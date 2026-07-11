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
    let limitID: String

    enum CodingKeys: String, CodingKey {
        case capturedAt
        case primary
        case secondary
        case planType
        case limitID
    }
}

