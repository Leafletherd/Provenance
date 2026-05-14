import Foundation

struct Manifest: Codable {
    var projectName: String
    var createdAt: Date
    var originalPath: String
    var provenanceVersion: String
    var medium: String?
    /// Stable cross-folder identity (Contract B). Nil in pre-PR-10 manifests;
    /// populated by migrateManifestProjectId() on first launch after PR-10.
    var projectId: String?
}

struct LedgerWriter {

    // MARK: - Timestamp helpers

    private static func isoFormatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        fmt.timeZone = TimeZone(abbreviation: "UTC")
        return fmt
    }

    private static func parseISO(_ string: String) -> Date? {
        return isoFormatter().date(from: string)
    }

    private static func formatISO(_ date: Date) -> String {
        return isoFormatter().string(from: date)
    }

    // MARK: - Initialization

    static func initializeLedger(for project: Project, fileCount: Int) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: project.ledgerURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: project.snapshotsURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: project.attachmentsURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: project.exportURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: project.metadataURL, withIntermediateDirectories: true)

        // Write manifest
        let manifest = Manifest(
            projectName: project.name,
            createdAt: project.connectedAt,
            originalPath: project.folderURL.path,
            provenanceVersion: "1.0",
            medium: project.medium,
            projectId: project.projectId
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: project.manifestURL, options: .atomic)

        // Create empty markdown files if not present
        for url in [project.ledgerMDURL, project.checkinsMDURL, project.sourcesMDURL, project.artifactsMDURL] {
            if !fm.fileExists(atPath: url.path) {
                try "".write(to: url, atomically: true, encoding: .utf8)
            }
        }

        // Log project_connected event
        let detail = "\"\(project.name)\" — \(fileCount) files found"
        appendEvent(type: .projectConnected, detail: detail, to: project)
    }

    // MARK: - Event log

    /// Appends a ledger event to ledger.md with an inline integrity hash suffix,
    /// then updates .ledger/ledger.chain.json.
    ///
    /// If `metadata` is provided, a stable UUID is generated, the metadata is written to
    /// .ledger/metadata/<uuid>.json, and the UUID is embedded in the ledger.md line as
    /// `<type>+<uuid>` so it can be retrieved on read-back.
    ///
    /// - Returns: The UUID assigned to this event.
    @discardableResult
    static func appendEvent(type: LedgerEventType, detail: String,
                            to project: Project, metadata: Data? = nil) -> UUID {
        let eventID = UUID()
        let timestamp = formatISO(Date())

        // Write metadata side-file before the ledger line so it's always present
        // by the time readEvents tries to load it.
        if let metadata {
            try? FileManager.default.createDirectory(
                at: project.metadataURL, withIntermediateDirectories: true)
            let sideURL = project.metadataURL.appendingPathComponent("\(eventID.uuidString).json")
            try? metadata.write(to: sideURL, options: .atomic)
        }

        // Build the line content (everything except the hash suffix).
        let typeField = metadata != nil
            ? "\(type.rawValue)+\(eventID.uuidString)"
            : type.rawValue
        let lineContent = "[\(timestamp)] \(typeField) — \(detail)"

        // Compute chain hash: SHA256(prevHead + lineContent).
        let prevHead  = LedgerIntegrity.currentHead(project: project)
        let newHash   = LedgerIntegrity.sha256hex(prevHead + lineContent)
        let prefix12  = String(newHash.prefix(12))

        // Full line written to ledger.md.
        let line = "\(lineContent)  ·h: \(prefix12)\n"
        guard let data = line.data(using: .utf8) else { return eventID }

        let url = project.ledgerMDURL
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }

        // Update the chain sidecar.
        LedgerIntegrity.appendHash(newHash, to: project)

        return eventID
    }

    static func readEvents(from project: Project) -> [LedgerEvent] {
        guard let content = try? String(contentsOf: project.ledgerMDURL, encoding: .utf8) else { return [] }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.compactMap { line -> LedgerEvent? in
            var s = String(line)
            // Strip inline chain hash suffix before parsing.
            let hashSep = "  ·h: "
            if let sepRange = s.range(of: hashSep) {
                s = String(s[..<sepRange.lowerBound])
            }
            // Format: [<timestamp>] <type>[+<uuid>] — <detail>
            guard s.hasPrefix("[") else { return nil }
            guard let closeBracket = s.firstIndex(of: "]") else { return nil }
            let tsString = String(s[s.index(after: s.startIndex)..<closeBracket])
            guard let timestamp = parseISO(tsString) else { return nil }
            let rest = String(s[s.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
            let parts = rest.components(separatedBy: " — ")
            guard parts.count >= 2 else { return nil }
            let typeField = parts[0].trimmingCharacters(in: .whitespaces)
            let detail = parts[1...].joined(separator: " — ").trimmingCharacters(in: .whitespaces)

            // Split <type>+<uuid> if a UUID suffix is present.
            var eventID = UUID()
            var cleanTypeRaw = typeField
            var metadata: Data? = nil
            if let plusIdx = typeField.lastIndex(of: "+") {
                let afterPlus = String(typeField[typeField.index(after: plusIdx)...])
                if let uuid = UUID(uuidString: afterPlus) {
                    eventID = uuid
                    cleanTypeRaw = String(typeField[..<plusIdx])
                    // Load side-file (gracefully absent for migrated/corrupted entries).
                    let sideURL = project.metadataURL
                        .appendingPathComponent("\(uuid.uuidString).json")
                    metadata = try? Data(contentsOf: sideURL)
                }
            }

            let eventType = LedgerEventType(rawValue: cleanTypeRaw) ?? .error
            return LedgerEvent(id: eventID, timestamp: timestamp,
                               type: eventType, detail: detail, metadata: metadata)
        }
    }

    // MARK: - Check-ins

    static func readCheckIns(from project: Project) -> [CheckIn] {
        guard let content = try? String(contentsOf: project.checkinsMDURL, encoding: .utf8) else { return [] }
        return parseCheckIns(from: content)
    }

    private static func parseCheckIns(from content: String) -> [CheckIn] {
        var result: [CheckIn] = []
        // Split on section headers (## )
        var blocks: [String] = []
        let lines = content.components(separatedBy: "\n")
        var currentBlock: [String] = []
        for line in lines {
            if line.hasPrefix("## ") && !currentBlock.isEmpty {
                blocks.append(currentBlock.joined(separator: "\n"))
                currentBlock = [line]
            } else {
                currentBlock.append(line)
            }
        }
        if !currentBlock.isEmpty {
            blocks.append(currentBlock.joined(separator: "\n"))
        }

        for block in blocks {
            guard block.contains("id:") else { continue }
            let blockLines = block.components(separatedBy: "\n")
            // First line: ## <timestamp>
            guard let firstLine = blockLines.first, firstLine.hasPrefix("## ") else { continue }
            let tsString = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            guard let timestamp = parseISO(tsString) else { continue }

            var id: UUID = UUID()
            var status: CheckInStatus = .working
            var exportIncluded: Bool = true
            var textLines: [String] = []
            var inBody = false
            var foundSeparator = false

            for blockLine in blockLines.dropFirst() {
                if blockLine == "---" {
                    foundSeparator = true
                    inBody = true
                    continue
                }
                if !foundSeparator {
                    // Parse key: value pairs
                    if blockLine.hasPrefix("id: "), let u = UUID(uuidString: String(blockLine.dropFirst(4)).trimmingCharacters(in: .whitespaces)) {
                        id = u
                    } else if blockLine.hasPrefix("status: ") {
                        let val = String(blockLine.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                        status = CheckInStatus(rawValue: val) ?? .working
                    }
                } else if inBody {
                    if blockLine.hasPrefix("export: ") {
                        let val = String(blockLine.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                        exportIncluded = val == "true"
                    } else {
                        textLines.append(blockLine)
                    }
                }
            }
            let text = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let checkIn = CheckIn(id: id, timestamp: timestamp, status: status, text: text, exportIncluded: exportIncluded)
            result.append(checkIn)
        }
        return result
    }

    static func writeCheckIns(_ checkIns: [CheckIn], to project: Project) throws {
        var output = ""
        let fmt = isoFormatter()
        for c in checkIns {
            output += "## \(fmt.string(from: c.timestamp))\n"
            output += "id: \(c.id.uuidString)\n"
            output += "status: \(c.status.rawValue)\n"
            output += "---\n"
            output += "\(c.text)\n"
            output += "export: \(c.exportIncluded ? "true" : "false")\n\n"
        }
        try output.write(to: project.checkinsMDURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Sources

    static func readSources(from project: Project) -> [Source] {
        guard let content = try? String(contentsOf: project.sourcesMDURL, encoding: .utf8) else { return [] }
        return parseSources(from: content)
    }

    private static func parseSources(from content: String) -> [Source] {
        var result: [Source] = []
        var blocks: [String] = []
        let lines = content.components(separatedBy: "\n")
        var currentBlock: [String] = []
        for line in lines {
            if line.hasPrefix("## ") && !currentBlock.isEmpty {
                blocks.append(currentBlock.joined(separator: "\n"))
                currentBlock = [line]
            } else {
                currentBlock.append(line)
            }
        }
        if !currentBlock.isEmpty {
            blocks.append(currentBlock.joined(separator: "\n"))
        }

        for block in blocks {
            guard block.contains("id:") else { continue }
            let blockLines = block.components(separatedBy: "\n")
            guard let firstLine = blockLines.first, firstLine.hasPrefix("## ") else { continue }
            // ## <timestamp> <title>
            let headerContent = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            // Try to split timestamp (ends at first space after the Z)
            var tsString = ""
            var title = ""
            let headerParts = headerContent.components(separatedBy: " ")
            if let first = headerParts.first {
                tsString = first
                title = headerParts.dropFirst().joined(separator: " ")
            }
            guard let timestamp = parseISO(tsString) else { continue }

            var id: UUID = UUID()
            var type: SourceType = .url
            var urlString: String? = nil
            var filePath: String? = nil
            var passage: String? = nil
            var annotation: String? = nil
            var exportIncluded: Bool = true

            for blockLine in blockLines.dropFirst() {
                if blockLine.hasPrefix("id: "), let u = UUID(uuidString: String(blockLine.dropFirst(4)).trimmingCharacters(in: .whitespaces)) {
                    id = u
                } else if blockLine.hasPrefix("type: ") {
                    let val = String(blockLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    type = SourceType(rawValue: val) ?? .url
                } else if blockLine.hasPrefix("url: ") {
                    urlString = String(blockLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                } else if blockLine.hasPrefix("file: ") {
                    filePath = String(blockLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if blockLine.hasPrefix("passage: ") {
                    passage = String(blockLine.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                } else if blockLine.hasPrefix("annotation: ") {
                    annotation = String(blockLine.dropFirst(12)).trimmingCharacters(in: .whitespaces)
                } else if blockLine.hasPrefix("export: ") {
                    let val = String(blockLine.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    exportIncluded = val == "true"
                }
            }
            let source = Source(id: id, timestamp: timestamp, type: type, title: title,
                                urlString: urlString, filePath: filePath, passage: passage,
                                annotation: annotation, exportIncluded: exportIncluded)
            result.append(source)
        }
        return result
    }

    static func writeSources(_ sources: [Source], to project: Project) throws {
        var output = ""
        let fmt = isoFormatter()
        for s in sources {
            output += "## \(fmt.string(from: s.timestamp)) \(s.title)\n"
            output += "id: \(s.id.uuidString)\n"
            output += "type: \(s.type.rawValue)\n"
            if let u = s.urlString { output += "url: \(u)\n" }
            if let f = s.filePath { output += "file: \(f)\n" }
            if let p = s.passage { output += "passage: \(p)\n" }
            if let a = s.annotation { output += "annotation: \(a)\n" }
            output += "export: \(s.exportIncluded ? "true" : "false")\n\n"
        }
        try output.write(to: project.sourcesMDURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Artifacts

    static func readArtifacts(from project: Project) -> [Artifact] {
        guard let content = try? String(contentsOf: project.artifactsMDURL, encoding: .utf8) else { return [] }
        return parseArtifacts(from: content)
    }

    private static func parseArtifacts(from content: String) -> [Artifact] {
        var result: [Artifact] = []
        var blocks: [String] = []
        let lines = content.components(separatedBy: "\n")
        var currentBlock: [String] = []
        for line in lines {
            if line.hasPrefix("## ") && !currentBlock.isEmpty {
                blocks.append(currentBlock.joined(separator: "\n"))
                currentBlock = [line]
            } else {
                currentBlock.append(line)
            }
        }
        if !currentBlock.isEmpty {
            blocks.append(currentBlock.joined(separator: "\n"))
        }

        for block in blocks {
            guard block.contains("id:") else { continue }
            let blockLines = block.components(separatedBy: "\n")
            guard let firstLine = blockLines.first, firstLine.hasPrefix("## ") else { continue }
            let headerContent = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            let headerParts = headerContent.components(separatedBy: " ")
            var tsString = ""
            var title = ""
            if let first = headerParts.first {
                tsString = first
                title = headerParts.dropFirst().joined(separator: " ")
            }
            guard let timestamp = parseISO(tsString) else { continue }

            var id: UUID = UUID()
            var type: ArtifactType = .other
            var attachmentFilename: String? = nil
            var caption: String? = nil
            var exportIncluded: Bool = true

            for blockLine in blockLines.dropFirst() {
                if blockLine.hasPrefix("id: "), let u = UUID(uuidString: String(blockLine.dropFirst(4)).trimmingCharacters(in: .whitespaces)) {
                    id = u
                } else if blockLine.hasPrefix("type: ") {
                    let val = String(blockLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    type = ArtifactType(rawValue: val) ?? .other
                } else if blockLine.hasPrefix("file: ") {
                    attachmentFilename = String(blockLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if blockLine.hasPrefix("caption: ") {
                    caption = String(blockLine.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                } else if blockLine.hasPrefix("export: ") {
                    let val = String(blockLine.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    exportIncluded = val == "true"
                }
            }
            let artifact = Artifact(id: id, timestamp: timestamp, type: type, title: title,
                                    attachmentFilename: attachmentFilename, caption: caption,
                                    exportIncluded: exportIncluded)
            result.append(artifact)
        }
        return result
    }

    static func writeArtifacts(_ artifacts: [Artifact], to project: Project) throws {
        var output = ""
        let fmt = isoFormatter()
        for a in artifacts {
            output += "## \(fmt.string(from: a.timestamp)) \(a.title)\n"
            output += "id: \(a.id.uuidString)\n"
            output += "type: \(a.type.rawValue)\n"
            if let f = a.attachmentFilename { output += "file: \(f)\n" }
            if let c = a.caption { output += "caption: \(c)\n" }
            output += "export: \(a.exportIncluded ? "true" : "false")\n\n"
        }
        try output.write(to: project.artifactsMDURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Utilities

    static func countProjectFiles(at url: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
        var count = 0
        for case let fileURL as URL in enumerator {
            // Skip .ledger directory
            if fileURL.path.contains("/.ledger/") { continue }
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
        return count
    }

    // MARK: - Manuscript persistence

    /// Loads the per-project target word counts from .ledger/manuscripts.json.
    /// Returns an empty dictionary if the file doesn't exist yet.
    static func readManuscriptTargets(from project: Project) -> [String: Int] {
        guard let data = try? Data(contentsOf: project.manuscriptsJSONURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    /// Writes the full targets dictionary atomically.
    static func writeManuscriptTargets(_ targets: [String: Int], to project: Project) {
        guard let data = try? JSONEncoder().encode(targets) else { return }
        try? data.write(to: project.manuscriptsJSONURL, options: .atomic)
    }

    /// Loads the sparkline history for one file (identified by its safeID).
    static func readManuscriptHistory(safeID: String, from project: Project) -> [Manuscript.HistoryPoint] {
        let url = project.manuscriptHistoryURL.appendingPathComponent("\(safeID).history.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Manuscript.HistoryPoint].self, from: data)) ?? []
    }

    /// Appends one history data point, capping at 365 entries using monthly decimation for older data.
    static func appendManuscriptHistoryPoint(_ point: Manuscript.HistoryPoint,
                                              safeID: String, to project: Project) {
        let fm = FileManager.default
        try? fm.createDirectory(at: project.manuscriptHistoryURL, withIntermediateDirectories: true)
        let url = project.manuscriptHistoryURL.appendingPathComponent("\(safeID).history.json")

        var history = readManuscriptHistory(safeID: safeID, from: project)
        history.append(point)

        // Decimate if over 365 entries: keep all entries from the last 365 days;
        // for older entries, keep only the last one per calendar month.
        if history.count > 365 {
            let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date.distantPast
            let recent = history.filter { $0.date >= cutoff }
            let older  = history.filter { $0.date < cutoff }

            var monthBuckets: [String: Manuscript.HistoryPoint] = [:]
            let cal = Calendar.current
            for entry in older {
                let comps = cal.dateComponents([.year, .month], from: entry.date)
                let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
                monthBuckets[key] = entry   // last entry in month wins
            }
            history = monthBuckets.values.sorted { $0.date < $1.date } + recent
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(history) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func checkPathMoved(project: Project) -> URL? {
        guard let data = try? Data(contentsOf: project.manifestURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: data) else { return nil }
        let originalPath = manifest.originalPath
        let currentPath = project.folderURL.path
        if originalPath != currentPath {
            return URL(fileURLWithPath: currentPath)
        }
        return nil
    }

    // MARK: - Manifest helpers (PR-10)

    static func readManifest(from project: Project) -> Manifest? {
        guard let data = try? Data(contentsOf: project.manifestURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Manifest.self, from: data)
    }

    static func writeManifest(_ manifest: Manifest, to project: Project) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(manifest) else { return }
        try? data.write(to: project.manifestURL, options: .atomic)
    }

    /// Reads the projectId from the manifest at the given folder URL (not project URL).
    /// Used by ProjectLocator.scanForProjectId and the Locate flow.
    static func readProjectIdFromManifest(at folderURL: URL) -> String? {
        let manifestURL = folderURL
            .appendingPathComponent(".ledger")
            .appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Manifest.self, from: data))?.projectId
    }

    /// Reads the project name from the manifest at the given folder URL.
    /// Used by the Locate flow when matching pre-PR-10 manifests.
    static func readProjectNameFromManifest(at folderURL: URL) -> String? {
        let manifestURL = folderURL
            .appendingPathComponent(".ledger")
            .appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Manifest.self, from: data))?.projectName
    }

    /// Writes a projectId into an existing manifest.json at the given folder URL.
    /// Used by the Locate flow to back-fill identity into pre-PR-10 manifests.
    static func writeProjectIdToManifest(projectId: String, to folderURL: URL) {
        let manifestURL = folderURL
            .appendingPathComponent(".ledger")
            .appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var manifest = try? decoder.decode(Manifest.self, from: data) else { return }
        manifest.projectId = projectId
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let updated = try? encoder.encode(manifest) else { return }
        try? updated.write(to: manifestURL, options: .atomic)
    }

    /// If the manifest lacks a projectId, assign the project's projectId, write it back
    /// atomically, and log a manifestMigrated event. Idempotent — no-op if already set.
    static func migrateManifestProjectId(project: Project) {
        guard var manifest = readManifest(from: project),
              manifest.projectId == nil else { return }
        manifest.projectId = project.projectId
        writeManifest(manifest, to: project)
        appendEvent(type: .manifestMigrated, detail: "Assigned projectId.", to: project)
    }
}
