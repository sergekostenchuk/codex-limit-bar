import Foundation

enum LimitEventParser {
    static func parse(line: Data) -> LimitSnapshot? {
        guard
            let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let payload = root["payload"] as? [String: Any],
            let limits = payload["rate_limits"] as? [String: Any],
            let limitID = limits["limit_id"] as? String
        else { return nil }

        let capturedAt = (root["timestamp"] as? String).flatMap(isoDate) ?? Date.distantPast
        let primary = parseWindow(limits["primary"])
        let secondary = parseWindow(limits["secondary"])

        return LimitSnapshot(
            capturedAt: capturedAt,
            primary: primary,
            secondary: secondary,
            planType: limits["plan_type"] as? String,
            limitID: limitID
        )
    }

    private static func parseWindow(_ value: Any?) -> LimitWindow? {
        guard
            let object = value as? [String: Any],
            let used = number(object["used_percent"]),
            let minutes = number(object["window_minutes"]),
            let reset = number(object["resets_at"])
        else { return nil }

        return LimitWindow(
            usedPercent: used,
            windowMinutes: Int(minutes),
            resetsAt: Date(timeIntervalSince1970: reset)
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func isoDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
