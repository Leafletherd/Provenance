import Foundation
import AppKit
import CoreGraphics
import CoreText

struct ExportService {

    // MARK: - Bundle export models

    struct BundleResult {
        let url: URL
        let checkInCount: Int
        let sourceCount: Int
        let artifactCount: Int
    }

    private struct BundleManifest: Codable {
        let version: Int
        let schema: String
        let exportedAt: Date
        let provenanceVersion: String
        let projectName: String
    }

    private struct BundleProjectSummary: Codable {
        let name: String
        let medium: String?
        let workingDescription: String?
        let intent: String?
        let connectedAt: Date
        let lastActivity: Date
    }

    private struct BundleArtifactRecord: Codable {
        let id: UUID
        let timestamp: Date
        let type: ArtifactType
        let title: String
        /// Relative path inside the bundle (e.g., "artifacts/sketch.png") or nil.
        let attachmentFilename: String?
        let caption: String?
        let exportIncluded: Bool
    }

    private struct BundleProcess: Codable {
        let version: Int
        let exportedAt: Date
        let provenanceVersion: String
        let project: BundleProjectSummary
        let checkins: [CheckIn]
        let sources: [Source]
        let artifacts: [BundleArtifactRecord]
    }

    // MARK: - Bundle export

    /// Writes a `.provenance.bundle/` directory at the project root (outside .ledger/).
    /// Idempotent — writes to `.provenance.bundle.tmp` then atomically renames.
    /// Does NOT write ledger events; the caller is responsible for that.
    static func exportBundle(
        project: Project,
        checkIns: [CheckIn],
        sources: [Source],
        artifacts: [Artifact]
    ) throws -> BundleResult {
        let fm = FileManager.default
        let tmpURL    = project.folderURL.appendingPathComponent(".provenance.bundle.tmp")
        let bundleURL = project.bundleURL

        // Clean up any stale tmp from a crashed previous run.
        try? fm.removeItem(at: tmpURL)
        try fm.createDirectory(at: tmpURL, withIntermediateDirectories: true)

        let exportedAt     = Date()
        let exportCheckIns = checkIns.filter { $0.exportIncluded }
        let exportSources  = sources.filter  { $0.exportIncluded }
        let exportArtifacts = artifacts.filter { $0.exportIncluded }

        // ── JSON encoder (ISO 8601 dates) ─────────────────────────────────────
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // ── manifest.json ─────────────────────────────────────────────────────
        let manifest = BundleManifest(
            version: 1,
            schema: "provenance.bundle",
            exportedAt: exportedAt,
            provenanceVersion: "1.0",
            projectName: project.name
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: tmpURL.appendingPathComponent("manifest.json"), options: .atomic)

        // ── process.json ──────────────────────────────────────────────────────
        let projSummary = BundleProjectSummary(
            name: project.name,
            medium: project.medium,
            workingDescription: project.workingDescription,
            intent: project.intent,
            connectedAt: project.connectedAt,
            lastActivity: project.lastActivity
        )
        // Remap artifact attachmentFilename to bundle-relative path.
        let bundleArtifacts = exportArtifacts.map { a -> BundleArtifactRecord in
            BundleArtifactRecord(
                id: a.id,
                timestamp: a.timestamp,
                type: a.type,
                title: a.title,
                attachmentFilename: a.attachmentFilename.map { "artifacts/\($0)" },
                caption: a.caption,
                exportIncluded: a.exportIncluded
            )
        }
        let process = BundleProcess(
            version: 1,
            exportedAt: exportedAt,
            provenanceVersion: "1.0",
            project: projSummary,
            checkins: exportCheckIns,
            sources: exportSources,
            artifacts: bundleArtifacts
        )
        let processData = try encoder.encode(process)
        try processData.write(to: tmpURL.appendingPathComponent("process.json"), options: .atomic)

        // ── README.md ─────────────────────────────────────────────────────────
        let readmeData = Data(generateREADME(project: project, exportedAt: exportedAt,
                                              checkInCount: exportCheckIns.count,
                                              sourceCount: exportSources.count,
                                              artifactCount: exportArtifacts.count).utf8)
        try readmeData.write(to: tmpURL.appendingPathComponent("README.md"), options: .atomic)

        // ── checkins.md ───────────────────────────────────────────────────────
        let checkinsData = Data(generateCheckInsMarkdown(exportCheckIns).utf8)
        try checkinsData.write(to: tmpURL.appendingPathComponent("checkins.md"), options: .atomic)

        // ── sources.md ────────────────────────────────────────────────────────
        let sourcesData = Data(generateSourcesMarkdown(exportSources).utf8)
        try sourcesData.write(to: tmpURL.appendingPathComponent("sources.md"), options: .atomic)

        // ── artifacts.md ──────────────────────────────────────────────────────
        let artifactsData = Data(generateArtifactsMarkdown(exportArtifacts).utf8)
        try artifactsData.write(to: tmpURL.appendingPathComponent("artifacts.md"), options: .atomic)

        // ── artifacts/ (attachment copies) ────────────────────────────────────
        let artifactsDirURL = tmpURL.appendingPathComponent("artifacts")
        try fm.createDirectory(at: artifactsDirURL, withIntermediateDirectories: true)
        for artifact in exportArtifacts {
            guard let fn = artifact.attachmentFilename else { continue }
            let srcURL = project.attachmentsURL.appendingPathComponent(fn)
            let dstURL = artifactsDirURL.appendingPathComponent(fn)
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.copyItem(at: srcURL, to: dstURL)
            }
            // If missing: artifact remains in process.json with the relative path;
            // caller should check for completeness if needed.
        }

        // ── Atomic rename ─────────────────────────────────────────────────────
        try? fm.removeItem(at: bundleURL)
        try fm.moveItem(at: tmpURL, to: bundleURL)

        return BundleResult(
            url: bundleURL,
            checkInCount: exportCheckIns.count,
            sourceCount: exportSources.count,
            artifactCount: exportArtifacts.count
        )
    }

    // MARK: - Markdown generators

    private static func isoString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private static func generateREADME(
        project: Project, exportedAt: Date,
        checkInCount: Int, sourceCount: Int, artifactCount: Int
    ) -> String {
        var md = "# \(project.name) \u{2014} Provenance Bundle\n\n"
        md += "Exported \(isoString(exportedAt)).\n\n"
        if let medium = project.medium, !medium.isEmpty {
            md += "**Medium:** \(medium)\n\n"
        }
        if let intent = project.intent, !intent.isEmpty {
            md += "**Intent:**\n\n\(intent)\n\n"
        }
        md += "## Highlights\n\n"
        md += "- \(checkInCount) check-in\(checkInCount == 1 ? "" : "s") included\n"
        md += "- \(sourceCount) source\(sourceCount == 1 ? "" : "s") included\n"
        md += "- \(artifactCount) artifact\(artifactCount == 1 ? "" : "s") included\n"
        return md
    }

    private static func generateCheckInsMarkdown(_ checkIns: [CheckIn]) -> String {
        guard !checkIns.isEmpty else { return "# Check-ins\n\n*None included.*\n" }
        var md = "# Check-ins\n\n"
        for c in checkIns.reversed() {
            md += "## \(isoString(c.timestamp)) \u{2014} \(c.status.label)\n\n"
            md += c.text.isEmpty ? "*(no content)*\n\n" : "\(c.text)\n\n"
            md += "---\n\n"
        }
        return md
    }

    private static func generateSourcesMarkdown(_ sources: [Source]) -> String {
        guard !sources.isEmpty else { return "# Sources\n\n*None included.*\n" }
        var md = "# Sources\n\n"
        for s in sources {
            md += "## \(s.title)\n\n"
            md += "- **Type:** \(s.type.label)\n"
            md += "- **Date:** \(isoString(s.timestamp))\n"
            if let u = s.urlString,  !u.isEmpty  { md += "- **URL:** \(u)\n" }
            if let f = s.filePath,   !f.isEmpty  { md += "- **File:** \(f)\n" }
            if let p = s.passage,    !p.isEmpty  { md += "\n> \(p)\n" }
            if let a = s.annotation, !a.isEmpty  { md += "\n**Note:** \(a)\n" }
            md += "\n---\n\n"
        }
        return md
    }

    private static func generateArtifactsMarkdown(_ artifacts: [Artifact]) -> String {
        guard !artifacts.isEmpty else { return "# Artifacts\n\n*None included.*\n" }
        var md = "# Artifacts\n\n"
        for a in artifacts {
            md += "## \(a.title)\n\n"
            md += "- **Type:** \(a.type.rawValue)\n"
            md += "- **Date:** \(isoString(a.timestamp))\n"
            if let fn = a.attachmentFilename {
                md += "- **Attachment:** artifacts/\(fn)\n"
            }
            if let c = a.caption, !c.isEmpty { md += "\n\(c)\n" }
            md += "\n---\n\n"
        }
        return md
    }

    // MARK: - Markdown export

    /// Renders the same content as the PDF report as a single .md file.
    /// Saved to .ledger/export/<project>-<date>.md.
    static func exportMarkdown(
        project: Project,
        checkIns: [CheckIn],
        sources: [Source],
        artifacts: [Artifact],
        snapshots: [Snapshot],
        events: [LedgerEvent]
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: project.exportURL, withIntermediateDirectories: true)

        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        let filename = "\(project.name)-provenance-\(dateStr).md"
            .replacingOccurrences(of: " ", with: "_")
        let outputURL = project.exportURL.appendingPathComponent(filename)

        let md = buildMarkdownReport(project: project, checkIns: checkIns, sources: sources,
                                     artifacts: artifacts, snapshots: snapshots, events: events)
        try Data(md.utf8).write(to: outputURL, options: .atomic)
        return outputURL
    }

    private static func buildMarkdownReport(
        project: Project,
        checkIns: [CheckIn],
        sources: [Source],
        artifacts: [Artifact],
        snapshots: [Snapshot],
        events: [LedgerEvent]
    ) -> String {
        let displayFmt = DateFormatter()
        displayFmt.dateStyle = .medium
        displayFmt.timeStyle = .short

        var md = ""

        // ── Cover ─────────────────────────────────────────────────────────────
        md += "# \(project.name)\n\n"
        if let medium = project.medium, !medium.isEmpty {
            md += "_\(medium)_\n\n"
        }
        if let earliest = events.first?.timestamp {
            md += "**Period:** \(displayFmt.string(from: earliest)) \u{2013} \(displayFmt.string(from: Date()))\n\n"
        } else {
            md += "**Connected:** \(displayFmt.string(from: project.connectedAt))\n\n"
        }
        md += "_Generated by Provenance_\n\n"
        md += "---\n\n"

        // ── Description / Intent ─────────────────────────────────────────────
        if let desc = project.workingDescription, !desc.isEmpty {
            md += "## Project Description\n\n\(desc)\n\n"
        }
        if let intent = project.intent, !intent.isEmpty {
            md += "## Project Intent\n\n\(intent)\n\n"
        }

        // ── Timeline ─────────────────────────────────────────────────────────
        md += "## Timeline\n\n"
        var timelineItems: [(Date, String)] = []
        timelineItems.append((project.connectedAt, "Project connected: \(project.name)"))
        for s in snapshots.suffix(20) {
            timelineItems.append((s.timestamp, "Snapshot [\(s.trigger.label)]: \(s.filesChanged) files \u{2014} `\(s.hash)`"))
        }
        for c in checkIns.filter({ $0.exportIncluded }).suffix(20) {
            timelineItems.append((c.timestamp, "Check-in [\(c.status.label)]: \(String(c.text.prefix(80)))"))
        }
        for src in sources.filter({ $0.exportIncluded }).suffix(10) {
            timelineItems.append((src.timestamp, "Source added: \(src.title)"))
        }
        timelineItems.sort { $0.0 < $1.0 }
        for (itemDate, itemText) in timelineItems {
            md += "- **\(displayFmt.string(from: itemDate))** \u{2014} \(itemText)\n"
        }
        md += "\n"

        // ── Check-ins ─────────────────────────────────────────────────────────
        let exportCheckIns = checkIns.filter { $0.exportIncluded }
        if !exportCheckIns.isEmpty {
            md += "## Check-ins\n\n"
            for c in exportCheckIns.reversed() {
                md += "### \(displayFmt.string(from: c.timestamp)) \u{2014} \(c.status.label)\n\n"
                md += c.text.isEmpty ? "_No content._\n\n" : "\(c.text)\n\n"
                md += "---\n\n"
            }
        }

        // ── Sources ───────────────────────────────────────────────────────────
        let exportSources = sources.filter { $0.exportIncluded }
        if !exportSources.isEmpty {
            md += "## Sources\n\n"
            for s in exportSources {
                md += "### \(s.title)\n\n"
                md += "- **Type:** \(s.type.label)\n"
                md += "- **Date:** \(displayFmt.string(from: s.timestamp))\n"
                if let u = s.urlString, !u.isEmpty { md += "- **URL:** [\(u)](\(u))\n" }
                if let f = s.filePath, !f.isEmpty  { md += "- **File:** `\(f)`\n" }
                if let p = s.passage, !p.isEmpty   { md += "\n> \(p)\n" }
                if let a = s.annotation, !a.isEmpty { md += "\n**Note:** \(a)\n" }
                md += "\n---\n\n"
            }
        }

        // ── Artifacts ─────────────────────────────────────────────────────────
        let exportArtifacts = artifacts.filter { $0.exportIncluded }
        if !exportArtifacts.isEmpty {
            md += "## Artifacts\n\n"
            for a in exportArtifacts {
                md += "### \(a.title)\n\n"
                md += "- **Type:** \(a.type.rawValue)\n"
                md += "- **Date:** \(displayFmt.string(from: a.timestamp))\n"
                if let fn = a.attachmentFilename { md += "- **Attachment:** `\(fn)`\n" }
                if let c = a.caption, !c.isEmpty { md += "\n\(c)\n" }
                md += "\n---\n\n"
            }
        }

        // ── Version Summary ───────────────────────────────────────────────────
        md += "## Version Summary\n\n"
        let autoCount   = snapshots.filter { $0.trigger == .auto }.count
        let schedCount  = snapshots.filter { $0.trigger == .scheduled }.count
        let manualCount = snapshots.filter { $0.trigger == .manual }.count
        md += "**Total:** \(snapshots.count) \u{b7} Auto: \(autoCount) \u{b7} Scheduled: \(schedCount) \u{b7} Manual: \(manualCount)\n\n"
        for s in snapshots.prefix(50) {
            let label = s.label.map { " \u{2014} \($0)" } ?? ""
            md += "- `\(s.hash)` \(displayFmt.string(from: s.timestamp)) [\(s.trigger.label)] \(s.filesChanged) files\(label)\n"
        }
        md += "\n"

        // ── Ledger Excerpt ────────────────────────────────────────────────────
        md += "## Ledger\n\n"
        md += "```\n"
        for ev in events {
            md += "\(displayFmt.string(from: ev.timestamp))  [\(ev.type.displayName)]  \(ev.detail)\n"
        }
        md += "```\n"

        return md
    }

    // MARK: - Authorship Report export

    /// Delegates to `AuthorshipReportRenderer`.
    static func exportAuthorshipReport(
        project: Project,
        authorName: String,
        checkIns: [CheckIn],
        sources: [Source],
        artifacts: [Artifact],
        manuscripts: [Manuscript],
        events: [LedgerEvent],
        integrityStatus: LedgerIntegrity.IntegrityStatus,
        chain: LedgerChain?
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: project.exportURL, withIntermediateDirectories: true)

        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        let filename = "\(project.name)-authorship-\(dateStr).pdf"
            .replacingOccurrences(of: " ", with: "_")
        let outputURL = project.exportURL.appendingPathComponent(filename)

        try AuthorshipReportRenderer.render(
            to: outputURL,
            project: project,
            authorName: authorName,
            checkIns: checkIns,
            sources: sources,
            artifacts: artifacts,
            manuscripts: manuscripts,
            events: events,
            integrityStatus: integrityStatus,
            chain: chain
        )
        return outputURL
    }

    // MARK: - PDF export (existing)

    static func export(
        project: Project,
        checkIns: [CheckIn],
        sources: [Source],
        artifacts: [Artifact],
        snapshots: [Snapshot],
        events: [LedgerEvent]
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: project.exportURL, withIntermediateDirectories: true)

        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        let filename = "\(project.name)-provenance-\(dateStr).pdf"
            .replacingOccurrences(of: " ", with: "_")
        let outputURL = project.exportURL.appendingPathComponent(filename)

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 72
        let contentWidth = pageWidth - 2 * margin

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(outputURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "ExportService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context"])
        }

        // currentY is in PDF coordinates: y=0 is bottom of page, y=pageHeight is top.
        // It starts near the top and decreases as content is added.
        var currentY: CGFloat = pageHeight - margin

        func beginPage() {
            ctx.beginPDFPage(nil)
            currentY = pageHeight - margin
        }

        func endPage() {
            ctx.endPDFPage()
        }

        func ensureSpace(_ needed: CGFloat) {
            if currentY - needed < margin {
                endPage()
                beginPage()
            }
        }

        // Draws text in the native PDF coordinate system (y-up).
        // CTFrameDraw is designed for this and produces correctly oriented output.
        // DO NOT apply a flip transform before calling — that mirrors glyphs.
        @discardableResult
        func drawText(
            _ text: String,
            font: NSFont,
            color: NSColor = .black,
            x: CGFloat = margin,
            maxWidth: CGFloat = contentWidth,
            lineSpacing: CGFloat = 4
        ) -> CGFloat {
            guard !text.isEmpty else { return currentY }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let framesetter = CTFramesetterCreateWithAttributedString(attrStr as CFAttributedString)
            let fitSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRangeMake(0, attrStr.length),
                nil,
                CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                nil
            )
            let blockHeight = ceil(fitSize.height) + lineSpacing
            ensureSpace(blockHeight)

            // Rect in PDF y-up coordinates:
            // top of text at currentY, bottom at currentY - blockHeight
            let rect = CGRect(x: x, y: currentY - blockHeight, width: maxWidth, height: blockHeight)
            let path = CGPath(rect: rect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
            CTFrameDraw(frame, ctx)

            currentY -= blockHeight
            return currentY
        }

        func drawSpacer(_ height: CGFloat = 10) {
            currentY -= height
        }

        func drawHRule(color: NSColor = .lightGray, weight: CGFloat = 0.5) {
            ctx.saveGState()
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(weight)
            ctx.move(to: CGPoint(x: margin, y: currentY))
            ctx.addLine(to: CGPoint(x: pageWidth - margin, y: currentY))
            ctx.strokePath()
            ctx.restoreGState()
            currentY -= 10
        }

        // Fonts
        let titleFont      = NSFont.boldSystemFont(ofSize: 26)
        let headingFont    = NSFont.boldSystemFont(ofSize: 15)
        let subheadFont    = NSFont.boldSystemFont(ofSize: 11)
        let bodyFont       = NSFont.systemFont(ofSize: 10.5)
        let smallFont      = NSFont.systemFont(ofSize: 8.5)
        let monoFont       = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let captionColor   = NSColor(white: 0.45, alpha: 1)
        let dimColor       = NSColor(white: 0.3, alpha: 1)

        let displayFmt = DateFormatter()
        displayFmt.dateStyle = .medium
        displayFmt.timeStyle = .short

        // MARK: — Cover

        beginPage()
        currentY = pageHeight / 2 + 60
        drawText(project.name, font: titleFont)
        drawSpacer(6)
        if let medium = project.medium, !medium.isEmpty {
            drawText(medium, font: subheadFont, color: captionColor)
            drawSpacer(4)
        }
        let dateRange: String
        if let earliest = events.first?.timestamp {
            dateRange = "\(displayFmt.string(from: earliest)) – \(displayFmt.string(from: Date()))"
        } else {
            dateRange = displayFmt.string(from: project.connectedAt)
        }
        drawText(dateRange, font: bodyFont, color: captionColor)
        drawSpacer(12)
        drawText("Generated by Provenance", font: smallFont, color: captionColor)
        endPage()

        // MARK: — Project Intent

        if let desc = project.workingDescription, !desc.isEmpty {
            beginPage()
            drawText("Project Description", font: headingFont)
            drawSpacer(4)
            drawHRule()
            drawText(desc, font: bodyFont)
            endPage()
        }

        if let intent = project.intent, !intent.isEmpty {
            beginPage()
            drawText("Project Intent", font: headingFont)
            drawSpacer(4)
            drawHRule()
            drawText(intent, font: bodyFont)
            endPage()
        }

        // MARK: — Timeline

        beginPage()
        drawText("Timeline", font: headingFont)
        drawSpacer(4)
        drawHRule()

        var timelineItems: [(Date, String)] = []
        timelineItems.append((project.connectedAt, "Project connected: \(project.name)"))
        for s in snapshots.suffix(20) {
            timelineItems.append((s.timestamp, "Snapshot [\(s.trigger.label)]: \(s.filesChanged) files — \(s.hash)"))
        }
        for c in checkIns.filter({ $0.exportIncluded }).suffix(20) {
            timelineItems.append((c.timestamp, "Check-in [\(c.status.label)]: \(String(c.text.prefix(80)))"))
        }
        for src in sources.filter({ $0.exportIncluded }).suffix(10) {
            timelineItems.append((src.timestamp, "Source added: \(src.title)"))
        }
        timelineItems.sort { $0.0 < $1.0 }

        for item in timelineItems {
            ensureSpace(20)
            drawText("\(displayFmt.string(from: item.0))  —  \(item.1)", font: bodyFont)
            drawSpacer(3)
        }
        endPage()

        // MARK: — Check-ins

        let exportCheckIns = checkIns.filter { $0.exportIncluded }
        if !exportCheckIns.isEmpty {
            beginPage()
            drawText("Check-ins", font: headingFont)
            drawSpacer(4)
            drawHRule()
            for c in exportCheckIns.reversed() {
                ensureSpace(60)
                drawText(displayFmt.string(from: c.timestamp), font: smallFont, color: captionColor)
                drawText("[\(c.status.label)]", font: subheadFont, color: dimColor)
                drawSpacer(3)
                drawText(c.text.isEmpty ? "(no content)" : c.text, font: bodyFont)
                drawSpacer(8)
                drawHRule()
            }
            endPage()
        }

        // MARK: — Sources

        let exportSources = sources.filter { $0.exportIncluded }
        if !exportSources.isEmpty {
            beginPage()
            drawText("Sources", font: headingFont)
            drawSpacer(4)
            drawHRule()
            for s in exportSources {
                ensureSpace(50)
                drawText(s.title, font: subheadFont)
                drawText("Type: \(s.type.label)  ·  \(displayFmt.string(from: s.timestamp))",
                         font: smallFont, color: captionColor)
                if let u = s.urlString, !u.isEmpty {
                    drawText(u, font: smallFont, color: .blue)
                }
                if let f = s.filePath, !f.isEmpty {
                    drawText("File: \(f)", font: smallFont, color: dimColor)
                }
                if let p = s.passage, !p.isEmpty {
                    drawSpacer(4)
                    drawText("\"\(String(p.prefix(300)))\"", font: bodyFont, color: dimColor)
                }
                if let a = s.annotation, !a.isEmpty {
                    drawText("Note: \(a)", font: bodyFont)
                }
                drawSpacer(8)
                drawHRule()
            }
            endPage()
        }

        // MARK: — Artifacts

        let exportArtifacts = artifacts.filter { $0.exportIncluded }
        if !exportArtifacts.isEmpty {
            beginPage()
            drawText("Artifacts", font: headingFont)
            drawSpacer(4)
            drawHRule()
            for a in exportArtifacts {
                ensureSpace(50)
                drawText(a.title, font: subheadFont)
                drawText("\(a.type.rawValue)  ·  \(displayFmt.string(from: a.timestamp))",
                         font: smallFont, color: captionColor)
                if let fn = a.attachmentFilename {
                    drawText("Attachment: \(fn)", font: smallFont, color: dimColor)
                }
                if let c = a.caption, !c.isEmpty {
                    drawText(c, font: bodyFont)
                }
                drawSpacer(8)
                drawHRule()
            }
            endPage()
        }

        // MARK: — Version Summary

        beginPage()
        drawText("Version Summary", font: headingFont)
        drawSpacer(4)
        drawHRule()
        let autoCount   = snapshots.filter { $0.trigger == .auto }.count
        let schedCount  = snapshots.filter { $0.trigger == .scheduled }.count
        let manualCount = snapshots.filter { $0.trigger == .manual }.count
        drawText("Total: \(snapshots.count)  ·  Auto: \(autoCount)  ·  Scheduled: \(schedCount)  ·  Manual: \(manualCount)",
                 font: bodyFont, color: dimColor)
        drawSpacer(8)
        for s in snapshots.prefix(50) {
            ensureSpace(16)
            let label = s.label.map { " — \($0)" } ?? ""
            drawText("\(displayFmt.string(from: s.timestamp))  [\(s.trigger.label)]  \(s.hash)  \(s.filesChanged) files\(label)",
                     font: smallFont)
            drawSpacer(2)
        }
        endPage()

        // MARK: — Ledger Excerpt

        beginPage()
        drawText("Ledger", font: headingFont)
        drawSpacer(4)
        drawHRule()
        for ev in events {
            ensureSpace(14)
            drawText("\(displayFmt.string(from: ev.timestamp))  [\(ev.type.displayName)]  \(ev.detail)",
                     font: monoFont)
            drawSpacer(1)
        }
        endPage()

        ctx.closePDF()
        return outputURL
    }
}
