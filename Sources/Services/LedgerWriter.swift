import Foundation

struct Manifest: Codable {
    var projectName: String
    var createdAt: Date
    var originalPath: String
    var provenanceVersion: String
    var medium: String?
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

        // Write manifest
        let manifest = Manifest(
            projectName: project.name,
            createdAt: project.connectedAt,
            originalPath: project.folderURL.path,
            provenanceVersion: "1.0",
            medium: project.medium
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

    static func appendEvent(type: LedgerEventType, detail: String, to project: Project) {
        let timestamp = formatISO(Date())
        let line = "[\(timestamp)] \(type.rawValue) — \(detail)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = project.ledgerMDURL
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func readEvents(from project: Project) -> [LedgerEvent] {
        guard let content = try? String(contentsOf: project.ledgerMDURL, encoding: .utf8) else { return [] }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.compactMap { line -> LedgerEvent? in
            let s = String(line)
            // Format: [2025-04-12T14:32:01Z] event_type — detail
            guard s.hasPrefix("[") else { return nil }
            guard let closeBracket = s.firstIndex(of: "]") else { return nil }
            let tsString = String(s[s.index(after: s.startIndex)..<closeBracket])
            guard let timestamp = parseISO(tsString) else { return nil }
            let rest = String(s[s.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
            // rest is "event_type — detail"
            let parts = rest.components(separatedBy: " — ")
            guard parts.count >= 2 else { return nil }
            let typeRaw = parts[0].trimmingCharacters(in: .whitespaces)
            let detail = parts[1...].joined(separator: " — ").trimmingCharacters(in: .whitespaces)
            let eventType = LedgerEventType(rawValue: typeRaw) ?? .error
            return LedgerEvent(timestamp: timestamp, type: eventType, detail: detail)
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
}
