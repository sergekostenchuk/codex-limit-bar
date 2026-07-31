import XCTest
@testable import CodexLimitBar

final class ResetRadarTests: XCTestCase {
    func testForecastRollsCadenceForwardUntilItIsInTheFuture() throws {
        let day: TimeInterval = 24 * 60 * 60
        let start = try XCTUnwrap(RadarDateParser.parse("2026-07-01T00:00:00Z"))
        let history = [0, 3, 6].map { offset in
            RadarResetEvent(
                occurredAt: start.addingTimeInterval(TimeInterval(offset) * day),
                title: "Reset \(offset)",
                sourceURL: URL(string: "https://example.com/\(offset)")!
            )
        }
        let now = start.addingTimeInterval(7 * day)

        let forecast = try XCTUnwrap(
            ResetRadarEngine().forecast(now: now, history: history, incidents: [])
        )

        XCTAssertEqual(forecast.center, start.addingTimeInterval(9 * day))
        XCTAssertEqual(forecast.basis, .cadenceOnly)
        XCTAssertEqual(forecast.confidencePercent, 26)
    }

    func testRelevantIncidentRaisesConfidenceAndMovesCenterEarlier() throws {
        let now = try XCTUnwrap(RadarDateParser.parse("2026-07-31T00:00:00Z"))
        let engine = ResetRadarEngine()
        let baseline = try XCTUnwrap(engine.forecast(now: now, incidents: []))
        let incident = RadarStatusIncident(
            id: "incident-1",
            name: "Codex usage limits depleting faster than expected",
            status: "resolved",
            impact: "major",
            createdAt: now.addingTimeInterval(-2 * 60 * 60),
            resolvedAt: now.addingTimeInterval(-60 * 60)
        )

        let signaled = try XCTUnwrap(engine.forecast(now: now, incidents: [incident]))

        XCTAssertEqual(signaled.basis, .cadenceAndIncidents)
        XCTAssertEqual(signaled.relevantIncidentCount, 1)
        XCTAssertGreaterThan(signaled.confidencePercent, baseline.confidencePercent)
        XCTAssertLessThan(signaled.center, baseline.center)
        XCTAssertLessThanOrEqual(signaled.confidencePercent, 49)
    }

    func testUnrelatedIncidentDoesNotChangeForecast() throws {
        let now = try XCTUnwrap(RadarDateParser.parse("2026-07-31T00:00:00Z"))
        let incident = RadarStatusIncident(
            id: "incident-2",
            name: "Elevated image generation errors",
            status: "resolved",
            impact: "major",
            createdAt: now,
            resolvedAt: now
        )

        let forecast = try XCTUnwrap(ResetRadarEngine().forecast(now: now, incidents: [incident]))

        XCTAssertEqual(forecast.basis, .cadenceOnly)
        XCTAssertEqual(forecast.relevantIncidentCount, 0)
    }

    func testDecodesOpenAIStatusPayload() throws {
        let payload = """
        {
          "incidents": [
            {
              "id": "abc",
              "name": "Codex rate limits",
              "status": "resolved",
              "impact": "minor",
              "created_at": "2026-07-30T10:00:00.000Z",
              "resolved_at": "2026-07-30T11:00:00.000Z"
            }
          ]
        }
        """

        let incidents = try OpenAIStatusClient.decodeIncidents(from: Data(payload.utf8))

        XCTAssertEqual(incidents.count, 1)
        XCTAssertEqual(incidents.first?.id, "abc")
        XCTAssertNotNil(incidents.first?.resolvedAt)
    }
}
