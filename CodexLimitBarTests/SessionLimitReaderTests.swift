import XCTest
@testable import CodexLimitBar

final class SessionLimitReaderTests: XCTestCase {
    private var tempDirectory: URL!
    private var sessionsRoot: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sessionsRoot = tempDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    func testLatestSnapshotsReturnsNewestPerLimitID() throws {
        try write(line: generalEvent(limitID: "codex", timestamp: "2026-07-30T10:00:00.000Z", usedPercent: 55), to: "first.jsonl")
        try write(line: sparkEvent(limitID: "codex_bengalfox", timestamp: "2026-07-30T10:00:00.000Z", usedPercent: 25), to: "first.jsonl")
        try write(line: generalEvent(limitID: "codex", timestamp: "2026-07-30T11:00:00.000Z", usedPercent: 33), to: "second.jsonl")
        try write(line: sparkEvent(limitID: "codex_bengalfox", timestamp: "2026-07-30T10:30:00.000Z", usedPercent: 20), to: "second.jsonl")

        let reader = SessionLimitReader(homeURL: tempDirectory)
        let snapshots = reader.latestSnapshots()

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots["codex"]?.primary?.remainingPercent, 67)
        XCTAssertEqual(snapshots["codex_bengalfox"]?.primary?.remainingPercent, 80)
    }

    func testReaderKeepsIndependentPercentagesWithEqualValues() throws {
        try write(line: generalEvent(limitID: "codex", timestamp: "2026-07-30T12:00:00.000Z", usedPercent: 12), to: "rates.jsonl")
        try write(line: sparkEvent(limitID: "codex_bengalfox", timestamp: "2026-07-30T12:00:00.000Z", usedPercent: 12), to: "rates.jsonl")

        let reader = SessionLimitReader(homeURL: tempDirectory)
        let snapshots = reader.latestSnapshots()

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots["codex"]?.limitID, "codex")
        XCTAssertEqual(snapshots["codex_bengalfox"]?.limitID, "codex_bengalfox")
        XCTAssertEqual(
            snapshots["codex"]?.primary?.remainingPercent,
            snapshots["codex_bengalfox"]?.primary?.remainingPercent
        )
    }

    func testReaderRetainsCachedSparkWhileUpdatingGeneral() throws {
        try write(line: generalEvent(limitID: "codex", timestamp: "2026-07-28T00:00:00.000Z", usedPercent: 40), to: "rates.jsonl")
        try write(line: sparkEvent(limitID: "codex_bengalfox", timestamp: "2026-07-28T00:00:00.000Z", usedPercent: 10), to: "rates.jsonl")

        let reader = SessionLimitReader(homeURL: tempDirectory)
        XCTAssertEqual(reader.latestSnapshots()["codex_bengalfox"]?.primary?.remainingPercent, 90)

        try write(line: generalEvent(limitID: "codex", timestamp: "2026-07-28T00:01:00.000Z", usedPercent: 41), to: "rates.jsonl")
        let updated = reader.latestSnapshots()

        XCTAssertEqual(updated["codex"]?.primary?.remainingPercent, 59)
        XCTAssertEqual(updated["codex_bengalfox"]?.primary?.remainingPercent, 90)
    }

    private func write(line: String, to fileName: String) throws {
        let url = sessionsRoot.appendingPathComponent(fileName)
        let data = Data("\(line)\n".utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url)
        }
    }

    private func generalEvent(limitID: String, timestamp: String, usedPercent: Double) -> String {
        makeEvent(
            limitID: limitID,
            limitName: nil,
            timestamp: timestamp,
            usedPercent: usedPercent
        )
    }

    private func sparkEvent(limitID: String, timestamp: String, usedPercent: Double) -> String {
        makeEvent(
            limitID: limitID,
            limitName: "GPT-5.3-Codex-Spark",
            timestamp: timestamp,
            usedPercent: usedPercent
        )
    }

    private func makeEvent(limitID: String, limitName: String?, timestamp: String, usedPercent: Double) -> String {
        var rateLimits: [String: Any] = [
            "limit_id": limitID,
            "primary": [
                "used_percent": usedPercent,
                "window_minutes": 300,
                "resets_at": 1783787584
            ],
            "secondary": [
                "used_percent": 31.0,
                "window_minutes": 10080,
                "resets_at": 1784374384
            ],
            "plan_type": "pro"
        ]
        if let limitName { rateLimits["limit_name"] = limitName }

        let payload: [String: Any] = [
            "timestamp": timestamp,
            "payload": ["rate_limits": rateLimits] as [String: Any]
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            let line = String(data: data, encoding: .utf8)
        else { return "" }
        return line
    }
}
