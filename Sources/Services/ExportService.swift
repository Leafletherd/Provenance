import Foundation
import AppKit
import CoreGraphics
import CoreText

struct ExportService {

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
