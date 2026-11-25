import Foundation

enum QuotaPayload {
    static func jsonString(
        codex: QuotaState,
        codexFetchedAt: Date?,
        antigravity: QuotaState,
        antigravityFetchedAt: Date?,
        intervalSeconds: Int,
        currency: String = "USD"
    ) -> String? {
        guard let json = jsonData(
            codex: codex,
            codexFetchedAt: codexFetchedAt,
            antigravity: antigravity,
            antigravityFetchedAt: antigravityFetchedAt,
            intervalSeconds: intervalSeconds,
            currency: currency
        ) else { return nil }
        return String(data: json, encoding: .utf8)
    }

    static func data(
        codex: QuotaState,
        codexFetchedAt: Date?,
        antigravity: QuotaState,
        antigravityFetchedAt: Date?,
        intervalSeconds: Int,
        currency: String = "USD"
    ) -> Data? {
        guard let json = jsonData(
            codex: codex,
            codexFetchedAt: codexFetchedAt,
            antigravity: antigravity,
            antigravityFetchedAt: antigravityFetchedAt,
            intervalSeconds: intervalSeconds,
            currency: currency
        ) else { return nil }

        var output = Data("window.AGENT_QUOTA = ".utf8)
        output.append(json)
        output.append(Data(";\n".utf8))
        return output
    }

    private static func jsonData(
        codex: QuotaState,
        codexFetchedAt: Date?,
        antigravity: QuotaState,
        antigravityFetchedAt: Date?,
        intervalSeconds: Int,
        currency: String
    ) -> Data? {
        var root: [String: Any] = [
            "intervalSeconds": intervalSeconds,
            "currency": currency,
        ]
        if codex.hasReading {
            root["codex"] = encodeState(codex, fetchedAt: codexFetchedAt)
        }
        if antigravity.hasReading {
            root["antigravity"] = encodeState(antigravity, fetchedAt: antigravityFetchedAt)
        }

        guard JSONSerialization.isValidJSONObject(root) else { return nil }
        return try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func encodeState(_ state: QuotaState, fetchedAt: Date?) -> [String: Any] {
        var windows: [String: Any] = [:]
        if let reading = state.fiveHour { windows["session"] = encode(reading) }
        if let reading = state.weekly { windows["weekly"] = encode(reading) }
        var obj: [String: Any] = ["windows": windows]
        if let fetchedAt { obj["fetchedAt"] = isoString(fetchedAt) }
        return obj
    }

    private static func encode(_ reading: QuotaReading) -> [String: Any] {
        [
            "usedPercent": Int(reading.usedPercent.rounded()),
            "windowMinutes": Int(reading.windowMinutes.rounded()),
            "resetsAt": Int(reading.resetsAt.timeIntervalSince1970),
        ]
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
