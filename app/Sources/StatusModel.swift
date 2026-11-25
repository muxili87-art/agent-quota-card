import Combine
import Foundation

final class StatusModel: ObservableObject {
    @Published var codexState: QuotaState = .empty
    @Published var codexUpdatedAt: Date?
    @Published var codexError: String?
    @Published var codexRefreshing = false

    @Published var agyState: QuotaState = .empty
    @Published var agyUpdatedAt: Date?
    @Published var agyError: String?
    @Published var agyRefreshing = false

    @Published var alwaysOnTop = true
    @Published var cardVisible = true
    @Published var intervalSeconds: Int = 60
    @Published var currency: String = "USD"

    var isRefreshing: Bool { codexRefreshing || agyRefreshing }
}
