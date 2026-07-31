import Foundation

struct RadarResetEvent: Codable, Equatable, Sendable {
    let occurredAt: Date
    let title: String
    let sourceURL: URL
}

struct RadarStatusIncident: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let status: String
    let impact: String
    let createdAt: Date
    let resolvedAt: Date?

    var mostRecentDate: Date {
        resolvedAt ?? createdAt
    }
}

enum RadarForecastBasis: String, Equatable, Sendable {
    case cadenceOnly
    case cadenceAndIncidents
}

struct ResetRadarForecast: Equatable, Sendable {
    let center: Date
    let windowStart: Date
    let windowEnd: Date
    let confidencePercent: Int
    let basis: RadarForecastBasis
    let relevantIncidentCount: Int
    let latestVerifiedResetAt: Date
    let historyEventCount: Int
    let generatedAt: Date

    var confidenceLabel: String {
        switch confidencePercent {
        case 0..<35: return "низкая"
        case 35..<60: return "средняя"
        default: return "высокая"
        }
    }

    var basisText: String {
        switch basis {
        case .cadenceOnly:
            return "только ритм подтверждённой истории"
        case .cadenceAndIncidents:
            return "история + связанных инцидентов: \(relevantIncidentCount)"
        }
    }
}

enum RadarDateParser {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

struct ResetRadarEngine: Sendable {
    static let verifiedHistory: [RadarResetEvent] = [
        event(
            "2026-07-09T21:24:11.842Z",
            title: "A new researcher got credit for pressing the button",
            source: "https://x.com/thsottiaux/status/2075330198887940337"
        ),
        event(
            "2026-07-10T05:30:53.796Z",
            title: "GPT-5.6 Sol launch refill",
            source: "https://x.com/thsottiaux/status/2075452680760443190"
        ),
        event(
            "2026-07-13T18:29:31.013Z",
            title: "Seven million active users refill",
            source: "https://x.com/thsottiaux/status/2076735790567338203"
        ),
        event(
            "2026-07-14T19:34:54.638Z",
            title: "Eight million active users refill",
            source: "https://x.com/thsottiaux/status/2077114635308986427"
        ),
        event(
            "2026-07-18T03:28:22.589Z",
            title: "Paid-plan refill",
            source: "https://x.com/thsottiaux/status/2078320950488297917"
        ),
        event(
            "2026-07-21T16:47:15.178Z",
            title: "Ten million active users refill",
            source: "https://x.com/thsottiaux/status/2079609157934886975"
        )
    ]

    func forecast(
        now: Date = Date(),
        history: [RadarResetEvent] = Self.verifiedHistory,
        incidents: [RadarStatusIncident]
    ) -> ResetRadarForecast? {
        let orderedHistory = history.sorted { $0.occurredAt < $1.occurredAt }
        guard orderedHistory.count >= 2, let latest = orderedHistory.last else { return nil }

        let intervals = zip(orderedHistory, orderedHistory.dropFirst())
            .map { $1.occurredAt.timeIntervalSince($0.occurredAt) }
            .filter { $0 > 0 }
        guard let cadence = median(intervals), cadence > 0 else { return nil }

        var center = latest.occurredAt.addingTimeInterval(cadence)
        if center <= now {
            let missedCycles = floor(now.timeIntervalSince(center) / cadence) + 1
            center = center.addingTimeInterval(missedCycles * cadence)
        }

        let relevantIncidents = incidents.filter { incident in
            guard now.timeIntervalSince(incident.mostRecentDate) <= 7 * 24 * 60 * 60 else {
                return false
            }
            return isRelevant(incident.name)
        }
        let signalScore = relevantIncidents.reduce(0) { $0 + score(for: $1) }
        let earlierShift = min(8 * 60 * 60, TimeInterval(signalScore) * 60 * 60)
        center = max(now.addingTimeInterval(60 * 60), center.addingTimeInterval(-earlierShift))

        let deviations = intervals.map { abs($0 - cadence) }
        let medianDeviation = median(deviations) ?? 0
        let halfWindow = max(12 * 60 * 60, min(36 * 60 * 60, medianDeviation * 1.4826))

        var confidence = 20 + min(12, orderedHistory.count * 2)
        confidence += min(12, signalScore)
        let historyAge = now.timeIntervalSince(latest.occurredAt)
        if historyAge > 21 * 24 * 60 * 60 {
            confidence -= min(15, Int((historyAge / (24 * 60 * 60) - 21) / 2))
        }
        confidence = max(15, min(49, confidence))

        return ResetRadarForecast(
            center: center,
            windowStart: center.addingTimeInterval(-halfWindow),
            windowEnd: center.addingTimeInterval(halfWindow),
            confidencePercent: confidence,
            basis: relevantIncidents.isEmpty ? .cadenceOnly : .cadenceAndIncidents,
            relevantIncidentCount: relevantIncidents.count,
            latestVerifiedResetAt: latest.occurredAt,
            historyEventCount: orderedHistory.count,
            generatedAt: now
        )
    }

    private func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let ordered = values.sorted()
        let middle = ordered.count / 2
        if ordered.count.isMultiple(of: 2) {
            return (ordered[middle - 1] + ordered[middle]) / 2
        }
        return ordered[middle]
    }

    private func isRelevant(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return [
            "codex",
            "usage limit",
            "rate limit",
            "quota",
            "deplet"
        ].contains { normalized.contains($0) }
    }

    private func score(for incident: RadarStatusIncident) -> Int {
        var value: Int
        switch incident.impact.lowercased() {
        case "critical": value = 4
        case "major": value = 3
        case "minor": value = 2
        default: value = 1
        }
        if incident.resolvedAt == nil { value += 1 }
        return value
    }

    private static func event(_ date: String, title: String, source: String) -> RadarResetEvent {
        RadarResetEvent(
            occurredAt: RadarDateParser.parse(date) ?? .distantPast,
            title: title,
            sourceURL: URL(string: source)!
        )
    }
}
