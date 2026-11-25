import Foundation

enum CodexQuotaReaderError: LocalizedError {
    case executableUnavailable
    case launchFailed(String)
    case responseUnavailable(String?)

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            return "找不到 codex 命令"
        case let .launchFailed(detail):
            return "Codex 启动失败：\(detail)"
        case let .responseUnavailable(detail):
            guard let detail, !detail.isEmpty else { return "Codex 额度接口暂不可用" }
            return "Codex：\(detail)"
        }
    }
}

enum CodexQuotaReader {
    static let defaultTimeout: TimeInterval = 10

    static func readCurrent(
        now: Date = Date(),
        timeout: TimeInterval = defaultTimeout
    ) throws -> QuotaState {
        do {
            return try readAttempt(now: now, timeout: timeout, codexHome: nil)
        } catch let error as CodexQuotaReaderError {
            guard case let .responseUnavailable(detail) = error,
                  let detail,
                  detail.contains("sqlite state runtime"),
                  let temporaryHome = makeTemporaryCodexHome()
            else { throw error }
            defer { try? FileManager.default.removeItem(at: temporaryHome) }
            return try readAttempt(now: now, timeout: timeout, codexHome: temporaryHome)
        }
    }

    private static func readAttempt(
        now: Date,
        timeout: TimeInterval,
        codexHome: URL?
    ) throws -> QuotaState {
        guard let command = codexLaunchCommand() else {
            throw CodexQuotaReaderError.executableUnavailable
        }

        let process = Process()
        process.environment = environment(codexHome: codexHome)
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw CodexQuotaReaderError.launchFailed(error.localizedDescription)
        }

        let timeoutWork = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        defer {
            timeoutWork.cancel()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
        }

        try write(
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": ["name": "agent-quota-card", "title": "Agent 额度", "version": "1.0"],
                    "capabilities": ["experimentalApi": true],
                ],
            ],
            to: input.fileHandleForWriting
        )

        var buffer = Data()
        while process.isRunning {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard
                    let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                    let id = (object["id"] as? NSNumber)?.intValue
                else { continue }

                if id == 1, object["result"] != nil {
                    try write(["method": "initialized"], to: input.fileHandleForWriting)
                    try write(["id": 2, "method": "account/rateLimits/read", "params": NSNull()], to: input.fileHandleForWriting)
                } else if id == 2, let state = parseResponse(object, observedAt: now) {
                    try? input.fileHandleForWriting.close()
                    return state
                }
            }
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        let detail = String(decoding: stderr, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty }
        throw CodexQuotaReaderError.responseUnavailable(detail.map { String($0.prefix(200)) })
    }

    static func parseResponse(_ object: [String: Any], observedAt: Date) -> QuotaState? {
        guard
            let result = object["result"] as? [String: Any],
            let fallback = (result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any]
                ?? result["rateLimits"] as? [String: Any]
        else { return nil }

        var fiveHour: QuotaReading?
        var weekly: QuotaReading?
        for key in ["primary", "secondary"] {
            guard
                let values = fallback[key] as? [String: Any],
                let usedPercent = (values["usedPercent"] as? NSNumber)?.doubleValue,
                let resetsAt = (values["resetsAt"] as? NSNumber)?.doubleValue,
                let windowMinutes = (values["windowDurationMins"] as? NSNumber)?.doubleValue,
                let kind = QuotaWindowKind.resolve(windowMinutes: windowMinutes)
            else { continue }

            let reading = QuotaReading(
                kind: kind,
                observedAt: observedAt,
                usedPercent: usedPercent,
                resetsAt: Date(timeIntervalSince1970: resetsAt),
                windowMinutes: windowMinutes
            )
            if kind == .fiveHour { fiveHour = reading }
            if kind == .weekly { weekly = reading }
        }

        let state = QuotaState(fiveHour: fiveHour, weekly: weekly, extras: [])
        return state.hasReading ? state : nil
    }

    private static func codexLaunchCommand() -> (executableURL: URL, arguments: [String])? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".npm-global/bin/codex"),
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            let resolved = candidate.resolvingSymlinksInPath()
            if resolved.pathExtension.lowercased() == "js" {
                let packageRoot = resolved.deletingLastPathComponent().deletingLastPathComponent()
                #if arch(arm64)
                let native = packageRoot.appendingPathComponent("node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex")
                #else
                let native = packageRoot.appendingPathComponent("node_modules/@openai/codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex")
                #endif
                if FileManager.default.isExecutableFile(atPath: native.path) {
                    return (native, ["app-server", "--stdio"])
                }
                continue
            }
            if FileManager.default.isExecutableFile(atPath: resolved.path) {
                return (resolved, ["app-server", "--stdio"])
            }
        }
        return nil
    }

    private static func environment(codexHome: URL?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            NSHomeDirectory() + "/.npm-global/bin",
            "/usr/bin",
            "/bin",
        ].joined(separator: ":")
        if let codexHome { env["CODEX_HOME"] = codexHome.path }
        return env
    }

    private static func makeTemporaryCodexHome() -> URL? {
        let manager = FileManager.default
        let auth = manager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        guard manager.fileExists(atPath: auth.path) else { return nil }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("codex-quota-\(UUID().uuidString)", isDirectory: true)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let target = directory.appendingPathComponent("auth.json")
            try manager.copyItem(at: auth, to: target)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            return directory
        } catch {
            try? manager.removeItem(at: directory)
            return nil
        }
    }

    private static func write(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }
}
