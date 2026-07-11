import Foundation

struct SessionLimitReader: Sendable {
    private let homeURL: URL
    private let maximumTailBytes = 4 * 1024 * 1024
    private let recentInterval: TimeInterval = 2 * 24 * 60 * 60

    init(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeURL = homeURL
    }

    func latestSnapshot() -> LimitSnapshot? {
        let codex = homeURL.appendingPathComponent(".codex", isDirectory: true)
        let roots = [
            codex.appendingPathComponent("sessions", isDirectory: true),
            codex.appendingPathComponent("archived_sessions", isDirectory: true)
        ]

        let cutoff = Date().addingTimeInterval(-recentInterval)
        let candidates = roots.flatMap { recentJSONLFiles(in: $0, modifiedAfter: cutoff) }
            .sorted { $0.modifiedAt > $1.modifiedAt }

        var latest: LimitSnapshot?
        for candidate in candidates {
            if let snapshot = latestSnapshot(in: candidate.url),
               latest == nil || snapshot.capturedAt > latest!.capturedAt {
                latest = snapshot
            }
        }
        return latest
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

    private func latestSnapshot(in url: URL) -> LimitSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maximumTailBytes) ? size - UInt64(maximumTailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        for line in lines.reversed() where line.containsASCII("\"rate_limits\"") {
            if let snapshot = LimitEventParser.parse(line: Data(line)) {
                return snapshot
            }
        }
        return nil
    }
}

private extension Data.SubSequence {
    func containsASCII(_ needle: String) -> Bool {
        guard let bytes = needle.data(using: .utf8) else { return false }
        return range(of: bytes) != nil
    }
}

