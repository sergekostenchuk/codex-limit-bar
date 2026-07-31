import Foundation

final class SessionLimitReader: @unchecked Sendable {
    private let homeURL: URL
    private let maximumTailBytes = 1 * 1024 * 1024
    private let recentInterval: TimeInterval = 8 * 24 * 60 * 60
    private var cachedSnapshotsByLimitID: [String: LimitSnapshot] = [:]
    private var lastScanStartedAt: Date?

    init(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeURL = homeURL
    }

    func latestSnapshots() -> [String: LimitSnapshot] {
        let scanStartedAt = Date()
        let codex = homeURL.appendingPathComponent(".codex", isDirectory: true)
        let roots = [
            codex.appendingPathComponent("sessions", isDirectory: true),
            codex.appendingPathComponent("archived_sessions", isDirectory: true)
        ]

        let historyCutoff = scanStartedAt.addingTimeInterval(-recentInterval)
        let cutoff = lastScanStartedAt?.addingTimeInterval(-2) ?? historyCutoff
        let candidates = roots.flatMap { recentJSONLFiles(in: $0, modifiedAfter: cutoff) }
            .sorted { $0.modifiedAt > $1.modifiedAt }

        for candidate in candidates {
            let snapshots = latestSnapshots(in: candidate.url)
            for snapshot in snapshots.values {
                guard
                    let existing = cachedSnapshotsByLimitID[snapshot.limitID],
                    snapshot.capturedAt <= existing.capturedAt
                else {
                    cachedSnapshotsByLimitID[snapshot.limitID] = snapshot
                    continue
                }
            }
        }
        cachedSnapshotsByLimitID = cachedSnapshotsByLimitID.filter {
            $0.value.capturedAt >= historyCutoff
        }
        lastScanStartedAt = scanStartedAt
        return cachedSnapshotsByLimitID
    }

    private func recentJSONLFiles(in root: URL, modifiedAfter cutoff: Date) -> [(url: URL, modifiedAt: Date)] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= cutoff else { continue }
            result.append((url, modifiedAt))
        }
        return result
    }

    private func latestSnapshots(in url: URL) -> [String: LimitSnapshot] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maximumTailBytes) ? size - UInt64(maximumTailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [:] }

        var snapshots: [String: LimitSnapshot] = [:]
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        for line in lines.reversed() where line.containsASCII("\"rate_limits\"") {
            guard let snapshot = LimitEventParser.parse(line: Data(line)) else { continue }
            if let existing = snapshots[snapshot.limitID], existing.capturedAt >= snapshot.capturedAt {
                continue
            }
            snapshots[snapshot.limitID] = snapshot
        }
        return snapshots
    }
}

private extension Data.SubSequence {
    func containsASCII(_ needle: String) -> Bool {
        guard let bytes = needle.data(using: .utf8) else { return false }
        return range(of: bytes) != nil
    }
}
