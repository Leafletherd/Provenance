import Foundation
import AppKit
import CoreGraphics
import CoreText

/// Renders the Authorship Report PDF.
/// Uses the same Core Text / Core Graphics path as `ExportService.export()`.
struct AuthorshipReportRenderer {

    // MARK: - Entry point

    static func render(
        to outputURL: URL,
        project: Project,
        authorName: String,
        checkIns: [CheckIn],
        sources: [Source],
        artifacts: [Artifact],
        manuscripts: [Manuscript],
        events: [LedgerEvent],
        integrityStatus: LedgerIntegrity.IntegrityStatus,
        chain: LedgerChain?
    ) throws {
        let pageW: CGFloat = 612
        let pageH: CGFloat = 792
        let margin: CGFloat = 72
        let contentW = pageW - 2 * margin

        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let ctx = CGContext(outputURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "AuthorshipReportRenderer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context"])
        }

        // ── Drawing state ─────────────────────────────────────────────────────

        var currentY: CGFloat = pageH - margin
        var pageNumber = 0

        // ── Page helpers ──────────────────────────────────────────────────────

        func beginPage() {
            ctx.beginPDFPage(nil)
            pageNumber += 1
            currentY = pageH - margin
            // Header
            let hAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8),
                .foregroundColor: NSColor(white: 0.6, alpha: 1)
            ]
            let hStr = NSAttributedString(
                string: "Authorship Report — \(project.name)", attributes: hAttrs)
            drawAttributedString(hStr, x: margin, y: pageH - 20, width: contentW / 2, ctx: ctx)
            let pStr = NSAttributedString(
                string: "\(pageNumber)", attributes: hAttrs)
            drawAttributedString(pStr, x: pageW - margin - 20, y: pageH - 20, width: 20, ctx: ctx)
        }

        func endPage() { ctx.endPDFPage() }

        func ensureSpace(_ needed: CGFloat) {
            if currentY - needed < margin { endPage(); beginPage() }
        }

        // ── Text drawing (y-up PDF coordinates) ──────────────────────────────

        @discardableResult
        func drawText(_ text: String,
                      font: NSFont,
                      color: NSColor = NSColor(white: 0.15, alpha: 1),
                      x: CGFloat = margin,
                      width: CGFloat = contentW,
                      spacing: CGFloat = 4) -> CGFloat {
            guard !text.isEmpty else { return currentY }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let aStr = NSAttributedString(string: text, attributes: attrs)
            let fs = CTFramesetterCreateWithAttributedString(aStr as CFAttributedString)
            let sz = CTFramesetterSuggestFrameSizeWithConstraints(
                fs, CFRangeMake(0, aStr.length), nil,
                CGSize(width: width, height: .greatestFiniteMagnitude), nil)
            let blockH = ceil(sz.height) + spacing
            ensureSpace(blockH)
            let rect = CGRect(x: x, y: currentY - blockH, width: width, height: blockH)
            CTFrameDraw(CTFramesetterCreateFrame(fs, CFRangeMake(0, 0),
                                                 CGPath(rect: rect, transform: nil), nil), ctx)
            currentY -= blockH
            return currentY
        }

        func spacer(_ h: CGFloat = 8) { currentY -= h }

        func rule(color: NSColor = NSColor(white: 0.8, alpha: 1), w: CGFloat = 0.5) {
            ctx.saveGState()
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(w)
            ctx.move(to: CGPoint(x: margin, y: currentY))
            ctx.addLine(to: CGPoint(x: pageW - margin, y: currentY))
            ctx.strokePath()
            ctx.restoreGState()
            currentY -= 8
        }

        // ── Fonts ─────────────────────────────────────────────────────────────

        let displayFont: NSFont = {
            if let pf = NSFont(name: "PlayfairDisplay-Bold", size: 28) { return pf }
            return NSFont.boldSystemFont(ofSize: 28)
        }()
        let titleFont   = NSFont.boldSystemFont(ofSize: 22)
        let headFont    = NSFont.boldSystemFont(ofSize: 15)
        let subFont     = NSFont.boldSystemFont(ofSize: 11)
        let bodyFont    = NSFont.systemFont(ofSize: 10.5)
        let smallFont   = NSFont.systemFont(ofSize: 8.5)
        let monoFont    = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let captionClr  = NSColor(white: 0.45, alpha: 1)
        let dimClr      = NSColor(white: 0.3, alpha: 1)
        let accentClr   = NSColor(srgbRed: 0.114, green: 0.620, blue: 0.459, alpha: 1)

        let displayFmt = DateFormatter()
        displayFmt.dateStyle = .medium
        displayFmt.timeStyle = .short

        let shortFmt = DateFormatter()
        shortFmt.dateStyle = .medium
        shortFmt.timeStyle = .none

        // ── Integrity helpers ─────────────────────────────────────────────────

        let isIntact: Bool
        let integrityVerdictText: String
        let integrityVerdictColor: NSColor

        switch integrityStatus {
        case .intact(let since, _):
            isIntact = true
            integrityVerdictText = "\u{2713} Ledger chain intact since \(shortFmt.string(from: since))"
            integrityVerdictColor = NSColor(srgbRed: 0.17, green: 0.54, blue: 0.24, alpha: 1)
        case .chainBroken(let at, _, _, _):
            isIntact = false
            integrityVerdictText = "\u{26A0} Ledger chain broken at line \(at)"
            integrityVerdictColor = NSColor(srgbRed: 0.75, green: 0.47, blue: 0.23, alpha: 1)
        case .historyRewritten:
            isIntact = false
            integrityVerdictText = "\u{26A0} Git history rewritten"
            integrityVerdictColor = NSColor(srgbRed: 0.75, green: 0.47, blue: 0.23, alpha: 1)
        default:
            isIntact = true
            integrityVerdictText = "\u{25D0} Integrity chain not yet established"
            integrityVerdictColor = NSColor(white: 0.55, alpha: 1)
        }

        // Aggregate counts
        let totalFileSaves = events.filter { $0.type == .fileSaved }.count
        let exportCheckIns = checkIns.filter { $0.exportIncluded }
        let exportSources  = sources.filter  { $0.exportIncluded }
        let pasteEvents    = events.filter   { $0.type == .paste }
        let aiPasteCount   = pasteEvents.filter { event in
            guard let data = event.metadata,
                  let meta = try? JSONDecoder().decode(PasteMetadata.self, from: data)
            else { return false }
            return meta.isAI
        }.count

        // Date range
        let firstEvent = events.first?.timestamp ?? project.connectedAt
        let lastEvent  = events.last?.timestamp  ?? Date()

        // ── COVER PAGE ────────────────────────────────────────────────────────

        beginPage()
        currentY = pageH / 2 + 100

        drawText("Authorship Report", font: titleFont, color: captionClr)
        spacer(4)
        drawText(project.name, font: displayFont)
        spacer(8)
        if !authorName.isEmpty {
            drawText("Author: \(authorName)", font: subFont, color: dimClr)
            spacer(4)
        }
        drawText("\(shortFmt.string(from: firstEvent)) \u{2013} \(shortFmt.string(from: lastEvent))",
                 font: bodyFont, color: captionClr)
        spacer(4)
        drawText("A structured record of how this project was made \u{2014} every save, every source, every paste.",
                 font: smallFont, color: captionClr)
        spacer(16)

        // Integrity verdict — prominent on cover
        drawText(integrityVerdictText, font: subFont, color: integrityVerdictColor)
        spacer(16)
        rule()

        // Aggregate counts
        let countLines = [
            "\(totalFileSaves) file saves",
            "\(exportCheckIns.count) check-ins",
            "\(exportSources.count) sources",
            "\(artifacts.filter({ $0.exportIncluded }).count) artifacts",
            pasteEvents.isEmpty ? "no paste events recorded"
                : "\(pasteEvents.count) paste events (\(aiPasteCount) AI-classified)"
        ].joined(separator: "  ·  ")
        drawText(countLines, font: smallFont, color: captionClr)
        spacer(16)

        drawText("Generated by Provenance  ·  \(displayFmt.string(from: Date()))",
                 font: smallFont, color: captionClr)
        endPage()

        // ── INTEGRITY ISSUES page (only when broken) ─────────────────────────

        if !isIntact {
            beginPage()
            drawText("INTEGRITY ISSUES", font: headFont,
                     color: NSColor(srgbRed: 0.75, green: 0.47, blue: 0.23, alpha: 1))
            spacer(4)
            rule(color: NSColor(srgbRed: 0.75, green: 0.47, blue: 0.23, alpha: 1))

            switch integrityStatus {
            case .chainBroken(let at, let exp, let found, let content):
                drawText("The ledger's integrity chain is broken at line \(at). " +
                         "This may indicate that the ledger.md file was edited after the fact.",
                         font: bodyFont)
                spacer(6)
                drawText("Line: \(at)", font: subFont)
                drawText("Expected hash prefix: \(exp)", font: monoFont, color: dimClr)
                drawText("Found hash prefix:    \(found)", font: monoFont, color: dimClr)
                drawText("Content: \(content)", font: monoFont, color: dimClr)
            case .historyRewritten(let missing):
                drawText("The git snapshot history has been rewritten. " +
                         "\(missing.count) commit hash\(missing.count == 1 ? "" : "es") referenced " +
                         "in the ledger no longer exist in the snapshot repository.",
                         font: bodyFont)
                spacer(6)
                for m in missing {
                    drawText("\u{25AA} \(m.hash)  (\(displayFmt.string(from: m.date)))",
                             font: monoFont, color: dimClr)
                }
            default:
                break
            }
            endPage()
        }

        // ── PROCESS TIMELINE (day bar chart) ─────────────────────────────────

        beginPage()
        drawText("Process Timeline", font: headFont)
        spacer(4)
        rule()

        let fileSaveEvents = events.filter { $0.type == .fileSaved }
        if !fileSaveEvents.isEmpty {
            // Bucket by day
            var dayCounts: [String: Int] = [:]
            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "yyyy-MM-dd"
            for ev in fileSaveEvents {
                let key = dayFmt.string(from: ev.timestamp)
                dayCounts[key, default: 0] += 1
            }
            // Build sorted day array over the full date range
            var cal = Calendar.current
            cal.timeZone = TimeZone(abbreviation: "UTC")!
            var cursor = cal.startOfDay(for: firstEvent)
            let last   = cal.startOfDay(for: lastEvent)
            var dayValues: [Int] = []
            var activeDays = 0
            while cursor <= last {
                let key = dayFmt.string(from: cursor)
                let count = dayCounts[key] ?? 0
                dayValues.append(count)
                if count > 0 { activeDays += 1 }
                cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            }
            let totalDays = dayValues.count
            let maxCount  = dayValues.max() ?? 1

            // Draw bars
            let chartH: CGFloat = 90
            let barW = max(contentW / CGFloat(max(dayValues.count, 1)), 1)
            ensureSpace(chartH + 30)
            let chartBottom = currentY - chartH

            ctx.saveGState()
            ctx.setFillColor(accentClr.withAlphaComponent(0.7).cgColor)
            for (i, val) in dayValues.enumerated() {
                guard val > 0 else { continue }
                let barH = CGFloat(val) / CGFloat(maxCount) * chartH
                let x    = margin + CGFloat(i) * barW
                ctx.fill(CGRect(x: x, y: chartBottom, width: max(barW - 0.5, 0.5), height: barH))
            }
            ctx.restoreGState()
            currentY = chartBottom - 4

            let span = totalDays == 1 ? "1 day" : "\(totalDays) days"
            drawText("\(activeDays) active day\(activeDays == 1 ? "" : "s") over \(span).",
                     font: smallFont, color: captionClr)
        } else {
            drawText("No file save events recorded.", font: bodyFont, color: captionClr)
        }
        endPage()

        // ── WORD COUNT GROWTH ─────────────────────────────────────────────────

        let relevantMSS = manuscripts
            .filter { !$0.history.isEmpty }
            .sorted { ($0.history.last?.wordCount ?? 0) > ($1.history.last?.wordCount ?? 0) }
            .prefix(5)

        if !relevantMSS.isEmpty {
            beginPage()
            drawText("Word Count Growth", font: headFont)
            spacer(4)
            rule()

            for ms in relevantMSS {
                guard ms.history.count >= 2 else { continue }
                ensureSpace(120)
                drawText(ms.title, font: subFont)
                spacer(4)

                let points = ms.history
                let minT = points.first!.date.timeIntervalSince1970
                let maxT = points.last!.date.timeIntervalSince1970
                let tRange = max(maxT - minT, 1)
                let wMin = Double(points.map { $0.wordCount }.min() ?? 0)
                let wMax = Double(points.map { $0.wordCount }.max() ?? 1)
                let wRange = max(wMax - wMin, 1)

                let graphH: CGFloat = 70
                ensureSpace(graphH + 20)
                let graphBottom = currentY - graphH

                let mutablePath = CGMutablePath()
                for (i, pt) in points.enumerated() {
                    let x = margin + CGFloat((pt.date.timeIntervalSince1970 - minT) / tRange) * contentW
                    let y = graphBottom + CGFloat((Double(pt.wordCount) - wMin) / wRange) * graphH
                    if i == 0 { mutablePath.move(to: CGPoint(x: x, y: y)) }
                    else       { mutablePath.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.saveGState()
                ctx.setStrokeColor(accentClr.cgColor)
                ctx.setLineWidth(1.5)
                ctx.addPath(mutablePath)
                ctx.strokePath()
                ctx.restoreGState()
                currentY = graphBottom - 4

                let lastWC = points.last?.wordCount ?? 0
                drawText("\(lastWC) words  ·  \(points.count) data points",
                         font: smallFont, color: captionClr)
                spacer(12)
            }

            if manuscripts.count > 5 {
                drawText("And \(manuscripts.count - 5) more manuscript\(manuscripts.count - 5 == 1 ? "" : "s") not shown.",
                         font: smallFont, color: captionClr)
            }
            endPage()
        }

        // ── SOURCES ───────────────────────────────────────────────────────────

        if !exportSources.isEmpty {
            beginPage()
            drawText("Sources", font: headFont)
            spacer(4)
            rule()
            for s in exportSources {
                ensureSpace(50)
                drawText(s.title, font: subFont)
                drawText("Type: \(s.type.label)  ·  \(displayFmt.string(from: s.timestamp))",
                         font: smallFont, color: captionClr)
                if let u = s.urlString, !u.isEmpty {
                    drawText(u, font: monoFont, color: NSColor.blue)
                }
                if let f = s.filePath, !f.isEmpty {
                    drawText("File: \(f)", font: smallFont, color: dimClr)
                }
                if let p = s.passage, !p.isEmpty {
                    spacer(3)
                    drawText("\"\(String(p.prefix(200)))\"", font: bodyFont, color: dimClr)
                }
                if let a = s.annotation, !a.isEmpty {
                    drawText("Note: \(a)", font: smallFont, color: dimClr)
                }
                spacer(6)
                rule(color: NSColor(white: 0.9, alpha: 1))
            }
            endPage()
        }

        // ── PASTE EVENTS ──────────────────────────────────────────────────────

        beginPage()
        drawText("Paste Record", font: headFont)
        spacer(4)
        rule()
        drawText("Provenance records the source of pasted text where it can. " +
                 "This section makes any external sources used in this work explicit.",
                 font: smallFont, color: captionClr)
        spacer(8)

        if pasteEvents.isEmpty {
            drawText("No paste events recorded during this project.", font: bodyFont, color: captionClr)
        } else {
            let decoder = JSONDecoder()
            for event in pasteEvents {
                ensureSpace(40)
                var label = displayFmt.string(from: event.timestamp)
                var meta: PasteMetadata? = nil
                if let data = event.metadata {
                    meta = try? decoder.decode(PasteMetadata.self, from: data)
                }
                if let m = meta {
                    let aiTag  = m.isAI ? "  [AI]" : ""
                    let src    = m.sourceURL?.host ?? m.sourceBundleID ?? "unknown source"
                    let file   = m.matchedFile.isEmpty ? "" : "  ·  \(m.matchedFile)"
                    label += "  ·  \(m.contentLength) bytes  ·  \(src)\(file)\(aiTag)"
                }
                drawText(label, font: smallFont,
                         color: meta?.isAI == true
                             ? NSColor(srgbRed: 0.75, green: 0.47, blue: 0.23, alpha: 1)
                             : dimClr)
                if let m = meta, !m.contentPreview.isEmpty {
                    drawText("\u{201C}\(m.contentPreview)\u{2026}\u{201D}",
                             font: monoFont, color: captionClr)
                }
                spacer(4)
            }
        }
        endPage()

        // ── CHECK-INS ─────────────────────────────────────────────────────────

        if !exportCheckIns.isEmpty {
            beginPage()
            drawText("Check-ins", font: headFont)
            spacer(4)
            rule()
            for c in exportCheckIns {
                ensureSpace(60)
                drawText(displayFmt.string(from: c.timestamp), font: smallFont, color: captionClr)
                drawText("[\(c.status.label)]", font: subFont, color: dimClr)
                spacer(3)
                drawText(c.text.isEmpty ? "(no content)" : c.text, font: bodyFont)
                spacer(8)
                rule(color: NSColor(white: 0.9, alpha: 1))
            }
            endPage()
        }

        // ── INTEGRITY APPENDIX ────────────────────────────────────────────────

        beginPage()
        drawText("Integrity Appendix", font: headFont)
        spacer(4)
        rule()

        drawText(integrityVerdictText, font: subFont, color: integrityVerdictColor)
        spacer(8)

        if let chain {
            drawText("Total chained events: \(chain.lineHashes.count)", font: bodyFont)
            drawText("Pre-chain events:     \(chain.preChainEventCount)", font: bodyFont)
            spacer(6)
            drawText("Chain started: \(displayFmt.string(from: chain.chainStartedAt))", font: smallFont, color: captionClr)
            spacer(4)
            drawText("Genesis hash:", font: smallFont, color: captionClr)
            drawText(chain.genesisHash, font: monoFont, color: dimClr)
            spacer(4)
            drawText("Chain head hash:", font: smallFont, color: captionClr)
            drawText(chain.head, font: monoFont, color: dimClr)
        } else {
            drawText("No chain file present for this project.", font: bodyFont, color: captionClr)
        }

        spacer(16)
        rule()
        drawText("Verification",   font: subFont)
        drawText("To verify this report\u{2019}s source ledger, the chain head above must match the " +
                 "head computed by walking the project\u{2019}s .ledger/ledger.md from genesis. " +
                 "Provenance can verify this automatically under the Ledger tab.",
                 font: smallFont, color: captionClr)
        endPage()

        ctx.closePDF()
    }

    // MARK: - Private drawing helper (outside page scope)

    private static func drawAttributedString(
        _ str: NSAttributedString, x: CGFloat, y: CGFloat, width: CGFloat, ctx: CGContext
    ) {
        let fs   = CTFramesetterCreateWithAttributedString(str as CFAttributedString)
        let rect = CGRect(x: x, y: y, width: width, height: 14)
        CTFrameDraw(CTFramesetterCreateFrame(fs, CFRangeMake(0, 0),
                                             CGPath(rect: rect, transform: nil), nil), ctx)
    }
}
