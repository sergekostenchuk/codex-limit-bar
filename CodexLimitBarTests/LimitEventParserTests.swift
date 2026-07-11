import XCTest
@testable import CodexLimitBar

final class LimitEventParserTests: XCTestCase {
    func testParsesRateLimitEvent() throws {
        let line = #"{"timestamp":"2026-07-11T12:16:07.067Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":2.0,"window_minutes":300,"resets_at":1783787584},"secondary":{"used_percent":31.0,"window_minutes":10080,"resets_at":1784374384},"plan_type":"pro"}}}"#
        let snapshot = LimitEventParser.parse(line: Data(line.utf8))

        XCTAssertEqual(snapshot?.primary?.remainingPercent, 98)
        XCTAssertEqual(snapshot?.secondary?.remainingPercent, 69)
        XCTAssertEqual(snapshot?.planType, "pro")
    }
}

