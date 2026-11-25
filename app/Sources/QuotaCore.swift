import Foundation

enum QuotaWindowKind: String, Equatable, Sendable {
    case fiveHour
    case weekly

    static let fiveHourMinutes = 300.0
    static let weeklyMinutes = 10_080.0
    static let classificationToleranceMinutes = 15.0

    static func resolve(windowMinutes: Double) -> Self? {
        if abs(windowMinutes - fiveHourMinutes) <= classificationToleranceMinutes {
            return .fiveHour
        }
        if abs(windowMinutes - weeklyMinutes) <= classificationToleranceMinutes {
            return .weekly
        }
        return nil
    }
}

struct QuotaReading: Equatable, Sendable {
    let kind: QuotaWindowKind
    let observedAt: Date
    let usedPercent: Double
    let resetsAt: Date
    let windowMinutes: Double

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct ExtraQuotaSummary: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let fiveHourRemain: Int?
    let weeklyRemain: Int?
}

struct QuotaState: Equatable, Sendable {
    let fiveHour: QuotaReading?
    let weekly: QuotaReading?
    let extras: [ExtraQuotaSummary]

    var hasReading: Bool {
        fiveHour != nil || weekly != nil
    }

    static let empty = QuotaState(fiveHour: nil, weekly: nil, extras: [])
}
