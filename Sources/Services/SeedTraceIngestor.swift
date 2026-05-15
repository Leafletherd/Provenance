import Foundation

// MARK: - Seed-trace ingestor
//
// Consumes *.seed-trace.json sidecars written by Seed at promote/transplant time.
// Contract: Procestra/Assets/Brand/SUITE_FORMAT_CONTRACTS.md — Contract A.
//
// Per-call behaviour:
//   • Parses the sidecar defensively (unknown fields ignored, missing optionals tolerated).
//   • De-dups by (boardPath, originalGardenPath, promotedAt) so re-emitted sidecars
//     do not produce duplicate ledger entries or artifacts.
//   • Returns an IngestResult with events and artifacts to append — callers own writing.

enum SeedTraceIngestor {

    // MARK: - JSON models (Contract A schema v1)

    struct SeedTrace: Decodable {
        let version: Int
        let promotedAt: String
        let boardPath: String
        let promotedBy: String?
        let seeds: [SeedEntry]
    }

    /// Codable so it can be stored as the metadata side-file on a `seedPromoted` event.
    struct SeedEntry: Codable {
        let title: String
        let destinationColumn: String?
        let destinationCardId: String?
        let originalGardenPath: String
        let history: [HistoryEntry]
    }

    struct HistoryEntry: Codable {
        let date: String
        let action: String
        let hash: String
        let message: String
    }

    // MARK: - Result

    struct IngestResult {
        var parseError: String? = nil
        /// (detail string, JSON-encoded SeedEntry for metadata side-file)
        var events: [(detail: String, metadata: Data)] = []
        var artifacts: [Artifact] = []
    }

    // MARK: - Folder scan

    /// Walk `root` for `*.seed-trace.json` files, skipping `.ledger`, `.git`,
    /// hidden files, and package descendants.
    static func scanFolder(at root: URL) -> [URL] {
        var found: [URL] = []
        let skipDirs: Set<String> = [".ledger", ".git", ".build", "node_modules", ".Trash"]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDir {
                if skipDirs.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.lastPathComponent.hasSuffix(".seed-trace.json") {
                found.append(url)
            }
        }
        return found
    }

    // MARK: - Ingest

    /// Parse a seed-trace sidecar and return events + artifacts to add.
    /// Does NOT write to the ledger or artifact store — that's the caller's job.
    static func ingest(fileURL: URL, project: Project) -> IngestResult {
        guard let data = try? Data(contentsOf: fileURL) else {
            return IngestResult(parseError: "Could not read \(fileURL.lastPathComponent)")
        }
        guard let trace = try? JSONDecoder().decode(SeedTrace.self, from: data) else {
            return IngestResult(parseError: "Invalid seed-trace JSON in \(fileURL.lastPathComponent)")
        }
        guard trace.version >= 1 else {
            return IngestResult(parseError: "Unsupported seed-trace version \(trace.version)")
        }

        var seen = loadSeen(project: project)
        var result = IngestResult()

        for seed in trace.seeds {
            // De-dup key: (boardPath, originalGardenPath, promotedAt)
            let key = "\(trace.boardPath)|\(seed.originalGardenPath)|\(trace.promotedAt)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            // Build compact detail string:
            // Seed "Opening image" → Act 1.sceneboard (history: 4 entries, planted 3d ago)
            let histCount = seed.history.count
            let plantEntry = seed.history.first(where: { $0.action == "plant" })
            let plantDate  = plantEntry.flatMap { isoDate($0.date) }
            let agoStr     = plantDate.map { daysAgoString(from: $0) } ?? "unknown date"
            let entryWord  = histCount == 1 ? "entry" : "entries"
            let detail = "Seed \"\(seed.title)\" \u{2192} \(trace.boardPath) " +
                         "(history: \(histCount) \(entryWord), planted \(agoStr))"

            // JSON-encode the SeedEntry for the metadata side-file + artifact store.
            let seedData = try? JSONEncoder().encode(seed)
            if let metadata = seedData {
                result.events.append((detail: detail, metadata: metadata))
            }

            // Artifact: one per seed, type seedHistory, metadata carries full SeedEntry.
            let duration: String
            if let pd = plantDate {
                let days = Int(-pd.timeIntervalSinceNow / 86400)
                duration = days <= 1 ? "1 day" : "\(days) days"
            } else {
                duration = "unknown duration"
            }
            let histStr = histCount == 1 ? "1 event" : "\(histCount) events"
            let caption = "Promoted from garden. Pre-promotion history: \(histStr) over \(duration)."
            result.artifacts.append(Artifact(
                type: .seedHistory,
                title: "Seed: \(seed.title)",
                attachmentFilename: nil,
                caption: caption,
                exportIncluded: true,
                seedMetadata: seedData
            ))
        }

        saveSeen(seen, project: project)
        return result
    }

    // MARK: - Seen-set persistence

    private static func seenURL(project: Project) -> URL {
        project.ledgerURL.appendingPathComponent("seed-trace-seen.json")
    }

    private static func loadSeen(project: Project) -> Set<String> {
        guard let data = try? Data(contentsOf: seenURL(project: project)),
              let arr  = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }

    private static func saveSeen(_ seen: Set<String>, project: Project) {
        if let data = try? JSONEncoder().encode(Array(seen)) {
            try? data.write(to: seenURL(project: project), options: .atomic)
        }
    }

    // MARK: - Date helpers

    private static func isoDate(_ string: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: string) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: string)
    }

    private static func daysAgoString(from date: Date) -> String {
        let days = Int(-date.timeIntervalSinceNow / 86400)
        if days <= 0 { return "today" }
        if days == 1 { return "1d ago" }
        return "\(days)d ago"
    }
}
