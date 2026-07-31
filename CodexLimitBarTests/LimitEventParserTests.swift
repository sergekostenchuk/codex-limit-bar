import XCTest
@testable import CodexLimitBar

final class LimitEventParserTests: XCTestCase {
    func testParsesGeneralRateLimitEvent() throws {
        let line = #"{"timestamp":"2026-07-11T12:16:07.067Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":2.0,"window_minutes":300,"resets_at":1783787584},"secondary":{"used_percent":31.0,"window_minutes":10080,"resets_at":1784374384},"plan_type":"pro"}}}"#
        let snapshot = LimitEventParser.parse(line: Data(line.utf8))

        XCTAssertEqual(snapshot?.limitID, "codex")
        XCTAssertNil(snapshot?.limitName)
        XCTAssertEqual(snapshot?.primary?.remainingPercent, 98)
        XCTAssertEqual(snapshot?.secondary?.remainingPercent, 69)
        XCTAssertEqual(snapshot?.planType, "pro")
    }

    func testParsesSparkLimitEventWithName() throws {
        let line = #"{"timestamp":"2026-07-11T12:16:07.067Z","payload":{"rate_limits":{"limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":14.0,"window_minutes":300,"resets_at":1783787584},"secondary":{"used_percent":40.0,"window_minutes":10080,"resets_at":1784374384},"plan_type":"pro"}}}"#
        let snapshot = LimitEventParser.parse(line: Data(line.utf8))

        XCTAssertEqual(snapshot?.limitID, "codex_bengalfox")
        XCTAssertEqual(snapshot?.limitName, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(snapshot?.primary?.remainingPercent, 86)
        XCTAssertEqual(snapshot?.secondary?.remainingPercent, 60)
    }

    func testRecognizesSparkByNameWhenInternalIDChanges() throws {
        let line = #"{"timestamp":"2026-07-11T12:16:07.067Z","payload":{"rate_limits":{"limit_id":"future_spark_id","limit_name":"GPT-Codex-Spark","primary":{"used_percent":14.0,"window_minutes":300,"resets_at":1783787584}}}}"#
        let snapshot = LimitEventParser.parse(line: Data(line.utf8))

        XCTAssertEqual(snapshot?.limitID, "future_spark_id")
        XCTAssertEqual(snapshot?.isSpark, true)
    }
}
