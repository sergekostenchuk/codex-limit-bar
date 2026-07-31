import Foundation

struct LimitWindow: Codable, Equatable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date

    var remainingPercent: Int {
        max(0, min(100, Int((100 - usedPercent).rounded())))
    }

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

struct LimitSnapshot: Codable, Equatable {
    let capturedAt: Date
    let primary: LimitWindow?
    let secondary: LimitWindow?
    let planType: String?
    let limitName: String?
    let limitID: String

    static let generalLimitID = "codex"
    static let sparkLimitID = "codex_bengalfox"
    static let sparkDisplayName = "GPT-5.3-Codex-Spark"

    var sectionTitle: String {
        switch limitID {
        case Self.generalLimitID:
            return "General Codex"
        case Self.sparkLimitID:
            return Self.sparkDisplayName
        default:
            return limitName ?? limitID
        }
    }

    var isGeneral: Bool {
        limitID == Self.generalLimitID
    }

    var isSpark: Bool {
        limitID == Self.sparkLimitID
            || limitName?.localizedCaseInsensitiveContains("spark") == true
    }

    enum CodingKeys: String, CodingKey {
        case capturedAt
        case primary
        case secondary
        case planType
        case limitName
        case limitID
    }
}
