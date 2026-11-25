import Foundation
import CFNetwork

enum AntigravityQuotaReaderError: LocalizedError {
    case executableUnavailable
    case launchFailed(String)
    case responseUnavailable(String?)

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            return "找不到 agy 命令"
        case let .launchFailed(detail):
            return "Antigravity 启动失败：\(detail)"
        case let .responseUnavailable(detail):
            guard let detail, !detail.isEmpty else { return "Antigravity 额度接口暂不可用" }
            return "Antigravity：\(detail)"
        }
    }
}

enum AntigravityQuotaReader {
    static let defaultTimeout: TimeInterval = 40

    static func readCurrent(
        now: Date = Date(),
        timeout: TimeInterval = defaultTimeout
    ) throws -> QuotaState {
        guard let executableURL = findAgyExecutable() else {
            throw AntigravityQuotaReaderError.executableUnavailable
        }

        // 先探测 oauth2.googleapis.com 连通性，避免断网/刚唤醒时 agy 误判并拉起网页登录
        guard canReachGoogleAuth() else {
            throw AntigravityQuotaReaderError.responseUnavailable("网络暂未就绪")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-p", "/usage", "--output-format", "json", "--print-timeout", "35s"]
        process.environment = processEnvironment()
        process.standardInput = FileHandle.nullDevice

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw AntigravityQuotaReaderError.launchFailed(error.localizedDescription)
        }

        let timeoutWork = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        defer { timeoutWork.cancel() }

        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AntigravityQuotaReaderError.responseUnavailable(errText)
        }

        return try parseUsageJSON(outData, now: now)
    }

    static func parseUsageJSON(_ data: Data, now: Date = Date()) throws -> QuotaState {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let command = root["command"] as? [String: Any],
            let payload = command["data"] as? [String: Any],
            let groups = payload["groups"] as? [[String: Any]]
        else {
            throw AntigravityQuotaReaderError.responseUnavailable("返回格式异常")
        }

        let primaryGroup = groups.first { ($0["name"] as? String) == "Gemini Models" } ?? groups.first
        var fiveHour: QuotaReading?
        var weekly: QuotaReading?

        if let buckets = primaryGroup?["buckets"] as? [[String: Any]] {
            for bucket in buckets {
                guard let reading = parseBucket(bucket, now: now) else { continue }
                switch reading.kind {
                case .fiveHour: fiveHour = reading
                case .weekly: weekly = reading
                }
            }
        }

        var extras: [ExtraQuotaSummary] = []
        for group in groups {
            let name = (group["name"] as? String) ?? ""
            if name == (primaryGroup?["name"] as? String) || name.isEmpty { continue }
            let buckets = (group["buckets"] as? [[String: Any]]) ?? []
            var r5h: Int?
            var rWeek: Int?
            for bucket in buckets {
                guard let reading = parseBucket(bucket, now: now) else { continue }
                let rem = Int(reading.remainingPercent.rounded())
                if reading.kind == .fiveHour { r5h = rem }
                if reading.kind == .weekly { rWeek = rem }
            }
            if r5h != nil || rWeek != nil {
                let shortName = name
                    .replacingOccurrences(of: "Claude and GPT models", with: "Claude / GPT")
                    .replacingOccurrences(of: "Gemini 4 ", with: "")
                extras.append(ExtraQuotaSummary(id: name, name: shortName, fiveHourRemain: r5h, weeklyRemain: rWeek))
            }
        }

        return QuotaState(fiveHour: fiveHour, weekly: weekly, extras: extras)
    }

    private static func parseBucket(_ bucket: [String: Any], now: Date) -> QuotaReading? {
        guard
            let window = bucket["window"] as? String,
            let remainingFraction = bucket["remaining_fraction"] as? Double,
            let resetStr = bucket["reset_time"] as? String,
            let resetDate = parseISODate(resetStr)
        else { return nil }

        let kind: QuotaWindowKind
        let windowMinutes: Double
        switch window {
        case "5h":
            kind = .fiveHour
            windowMinutes = QuotaWindowKind.fiveHourMinutes
        case "weekly":
            kind = .weekly
            windowMinutes = QuotaWindowKind.weeklyMinutes
        default:
            return nil
        }

        let usedPercent = max(0, min(100, (1.0 - remainingFraction) * 100.0))
        return QuotaReading(
            kind: kind,
            observedAt: now,
            usedPercent: usedPercent,
            resetsAt: resetDate,
            windowMinutes: windowMinutes
        )
    }

    private static func parseISODate(_ value: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: value) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: value)
    }

    private static func findAgyExecutable() -> URL? {
        let home = NSHomeDirectory()
        for path in ["\(home)/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        let current = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extra + [current]).joined(separator: ":")
        // 防止后台轮询在凭证过期时反复拉起浏览器登录页
        env["BROWSER"] = "/usr/bin/true"
        env["NO_BROWSER"] = "1"
        injectSystemProxy(into: &env)
        return env
    }

    private static func canReachGoogleAuth() -> Bool {
        guard let url = URL(string: "https://oauth2.googleapis.com/generate_204") else { return true }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)
        let semaphore = DispatchSemaphore(value: 0)
        var reachable = false
        let task = session.dataTask(with: url) { _, response, error in
            if error == nil, response is HTTPURLResponse {
                reachable = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3.5)
        session.invalidateAndCancel()
        return reachable
    }

    private static func injectSystemProxy(into env: inout [String: String]) {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return }
        if (settings[kCFNetworkProxiesHTTPEnable as String] as? Int) == 1,
           let host = settings[kCFNetworkProxiesHTTPProxy as String] as? String,
           let port = settings[kCFNetworkProxiesHTTPPort as String] as? Int,
           env["HTTP_PROXY"] == nil {
            env["HTTP_PROXY"] = "http://\(host):\(port)"
        }
        if (settings[kCFNetworkProxiesHTTPSEnable as String] as? Int) == 1,
           let host = settings[kCFNetworkProxiesHTTPSProxy as String] as? String,
           let port = settings[kCFNetworkProxiesHTTPSPort as String] as? Int,
           env["HTTPS_PROXY"] == nil {
            env["HTTPS_PROXY"] = "http://\(host):\(port)"
        }
        if (settings[kCFNetworkProxiesSOCKSEnable as String] as? Int) == 1,
           let host = settings[kCFNetworkProxiesSOCKSProxy as String] as? String,
           let port = settings[kCFNetworkProxiesSOCKSPort as String] as? Int,
           env["ALL_PROXY"] == nil {
            env["ALL_PROXY"] = "socks5://\(host):\(port)"
        }
    }
}
