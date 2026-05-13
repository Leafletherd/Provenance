import AppKit
import Foundation

/// Scans a connected project for writable text files and computes word counts.
/// All methods are blocking — always call from a background thread / Task.detached.
enum ManuscriptScanner {

    static let supportedExtensions: Set<String> = [
        "md", "txt", "markdown",
        "fountain", "fdx",
        "rtf",
        "docx",
        "pages",
    ]

    // MARK: - Full project scan

    /// Enumerates the project folder and returns a Manuscript for every supported file.
    static func scan(project: Project) -> [Manuscript] {
        let fm = FileManager.default
        let targets = LedgerWriter.readManuscriptTargets(from: project)

        guard let enumerator = fm.enumerator(
            at: project.folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey,
                                         .isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [Manuscript] = []

        for case let url as URL in enumerator {
            let path = url.path
            // Skip anything inside .ledger/
            if path.contains("/.ledger/") { continue }
            // Skip nested .git/ directories
            if path.contains("/.git/") { continue }

            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

            // .pages files can be packages (directories). Allow them but handle them specially.
            // For plain directory nodes that aren't .pages, skip.
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir && ext != "pages" { continue }

            let relPath = relativePath(url: url, project: project)
            let targets_ = targets
            let history = LedgerWriter.readManuscriptHistory(safeID: safeID(relPath), from: project)
            if let ms = buildManuscript(at: url, relativePath: relPath,
                                         targets: targets_, history: history, project: project) {
                results.append(ms)
            }
        }

        return results.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Single-file rescan

    /// Re-scans one file and returns an updated Manuscript, or nil if the file
    /// is no longer present or no longer supported.
    static func rescan(url: URL, existing: Manuscript?, project: Project) -> Manuscript? {
        let relPath = relativePath(url: url, project: project)
        let targets = LedgerWriter.readManuscriptTargets(from: project)
        let history = LedgerWriter.readManuscriptHistory(safeID: safeID(relPath), from: project)
        return buildManuscript(at: url, relativePath: relPath,
                               targets: targets, history: history, project: project)
    }

    // MARK: - History append

    /// Appends a single word-count data point for a manuscript, capping at 365 entries.
    static func appendHistory(url: URL, project: Project) {
        let relPath = relativePath(url: url, project: project)
        let kind = manuscriptKind(ext: url.pathExtension.lowercased())
        guard let text = extractText(from: url, kind: kind) else { return }
        let wc = wordCount(from: text)
        let pc = kind == .screenplay ? estimatedPages(from: text) : nil
        let point = Manuscript.HistoryPoint(date: Date(), wordCount: wc, pageCount: pc)
        LedgerWriter.appendManuscriptHistoryPoint(point, safeID: safeID(relPath), to: project)
    }

    // MARK: - Internal helpers

    private static func buildManuscript(
        at url: URL,
        relativePath relPath: String,
        targets: [String: Int],
        history: [Manuscript.HistoryPoint],
        project: Project
    ) -> Manuscript? {
        let ext = url.pathExtension.lowercased()
        let kind = manuscriptKind(ext: ext)

        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? Date.distantPast

        let text = extractText(from: url, kind: kind)
        let wc: Int? = text.map { wordCount(from: $0) }
        let pc: Int? = (kind == .screenplay && text != nil)
            ? estimatedPages(from: text!)
            : nil

        // Last 14 history points for sparkline
        let sparkline = Array(history.suffix(14))

        return Manuscript(
            id: relPath,
            path: url,
            title: url.lastPathComponent,
            wordCount: wc,
            pageCount: pc,
            lastModified: modDate,
            kind: kind,
            history: sparkline,
            targetWordCount: targets[relPath]
        )
    }

    // MARK: - Kind detection

    static func manuscriptKind(ext: String) -> Manuscript.Kind {
        switch ext {
        case "fountain", "fdx": return .screenplay
        case "rtf":             return .rtf
        case "docx":            return .docx
        case "pages":           return .pages
        default:                return .prose
        }
    }

    // MARK: - Text extraction

    /// Returns the plain-text content of the file, or nil if extraction failed.
    static func extractText(from url: URL, kind: Manuscript.Kind) -> String? {
        switch kind {
        case .prose, .screenplay:
            return try? String(contentsOf: url, encoding: .utf8)

        case .rtf:
            guard let data = try? Data(contentsOf: url) else { return nil }
            let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.rtf
            ]
            var docAttrs: NSDictionary? = nil
            return (try? NSAttributedString(data: data, options: opts,
                                             documentAttributes: &docAttrs))?.string

        case .docx:
            return extractDocxText(at: url)

        case .pages:
            return extractPagesText(at: url)
        }
    }

    // MARK: - Word / page counts

    static func wordCount(from text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    /// Estimated screenplay pages: non-empty line count / 55, rounded up.
    static func estimatedPages(from text: String) -> Int {
        let nonEmpty = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Int(ceil(Double(nonEmpty.count) / 55.0))
    }

    // MARK: - .docx extraction

    private static func extractDocxText(at url: URL) -> String? {
        // .docx is a zip archive; extract word/document.xml via shell unzip.
        let pipe = Pipe()
        let errPipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-p", url.path, "word/document.xml"]
        proc.standardOutput = pipe
        proc.standardError = errPipe
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        // Strip XML tags; collapse whitespace.
        let stripped = xml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return stripped.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - .pages extraction

    private static func extractPagesText(at url: URL) -> String? {
        let fm = FileManager.default
        // Modern .pages files are packages (directories).
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists else { return nil }

        if isDir.boolValue {
            // Package format: look for index.xml (legacy) inside the bundle.
            let legacyXML = url.appendingPathComponent("index.xml")
            if fm.fileExists(atPath: legacyXML.path),
               let xml = try? String(contentsOf: legacyXML, encoding: .utf8) {
                let stripped = xml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                return stripped.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }.joined(separator: " ")
            }
            // Modern .iwa binary inside Index/ — cannot parse; signal unavailable.
            return nil
        }

        // Single-file (zipped) .pages: try index.xml inside the zip.
        let pipe = Pipe()
        let errPipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-p", url.path, "index.xml"]
        proc.standardOutput = pipe
        proc.standardError = errPipe
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        let stripped = xml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return stripped.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Path utilities

    static func relativePath(url: URL, project: Project) -> String {
        var rel = url.path
        let root = project.folderURL.path
        if rel.hasPrefix(root) {
            rel = String(rel.dropFirst(root.count))
        }
        if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
        return rel
    }

    /// Returns a filesystem-safe identifier for a relative path, used in history filenames.
    static func safeID(_ relativePath: String) -> String {
        relativePath
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
