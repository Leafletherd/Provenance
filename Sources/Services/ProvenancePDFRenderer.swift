import Foundation
import AppKit
import CoreGraphics
import CoreText
import SwiftUI

/// PR-25 — unified PDF renderer for both Provenance export intents
/// (Authorship Report and Review). Implements the spec in
/// `Procestra/Assets/Brand/provenance_export_layout_spec.md`.
///
/// Conventions:
/// - US Letter (612 × 792pt), 63pt L/R margins
/// - All colors come from `Brand.*` tokens (NSColor bridged) — no hex literals
/// - CoreGraphics y-up coordinate system; `currentY` decreases as content advances
/// - `CTFrameDraw` produces correctly oriented glyphs in y-up PDFs without a flip
struct ProvenancePDFRenderer {

    enum Intent {
        case authorship
        case review
    }

    // MARK: - Page geometry (spec §Page setup)
    private static let pageW: CGFloat = 612
    private static let pageH: CGFloat = 792
    private static let marginX: CGFloat = 63
    /// Top edge → first content baseline (header eyebrow row)
    private static let topContentY: CGFloat = pageH - 58
    /// Bottom edge → footer baseline
    private static let footerBaseY: CGFloat = 37
    /// Trigger a new page when currentY drops below this threshold.
    private static let pageBreakThreshold: CGFloat = 100  // ~1.4in from bottom
    /// Continuation-page top rule sits 0.9in (~65pt) from top.
    private static let continuationTopRuleY: CGFloat = pageH - 65
    private static var contentW: CGFloat { pageW - 2 * marginX }

    // MARK: - Public entry points

    static func renderAuthorship(
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
        try render(
            intent: .authorship,
            to: outputURL,
            project: project,
            authorName: authorName,
            checkIns: checkIns.filter { $0.exportIncluded },
            sources: sources.filter { $0.exportIncluded },
            artifacts: artifacts.filter { $0.exportIncluded },
            manuscripts: manuscripts,
            events: events,
            integrityStatus: integrityStatus,
            chain: chain
        )
    }

    static func renderReview(
        to outputURL: URL,
        project: Project,
        authorName: String,
        checkIns: [CheckIn],
        sources: [Source],
        artifacts: [Artifact],
        manuscripts: [Manuscript],
        events: [LedgerEvent]
    ) throws {
        try render(
            intent: .review,
            to: outputURL,
            project: project,
            authorName: authorName,
            checkIns: checkIns.filter { $0.exportIncluded },
            sources: sources.filter { $0.exportIncluded },
            artifacts: artifacts.filter { $0.exportIncluded },
            manuscripts: manuscripts,
            events: events,
            integrityStatus: .unchecked,
            chain: nil
        )
    }

    // MARK: - Core renderer

    private static func render(
        intent: Intent,
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
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let ctx = CGContext(outputURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "ProvenancePDFRenderer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context"])
        }

        let docType = (intent == .authorship) ? "Authorship Report" : "Review Export"
        let displayFmt = DateFormatter()
        displayFmt.dateStyle = .medium
        displayFmt.timeStyle = .none

        let dateRange = computeDateRange(events: events, project: project, fmt: displayFmt)

        var currentY: CGFloat = topContentY
        var isFirstPage = true

        func beginPage() {
            ctx.beginPDFPage(nil)
            currentY = topContentY
        }

        func endPage() {
            drawFooter(ctx: ctx,
                       docType: docType, title: project.name, author: authorName,
                       fmt: displayFmt)
            ctx.endPDFPage()
        }

        func newContinuationPage() {
            endPage()
            beginPage()
            // Continuation top rule: 1.2pt textPrimary at 0.9in from top
            currentY = continuationTopRuleY
            drawRule(ctx: ctx, y: currentY, weight: 1.2, color: nsColor(Brand.textPrimary))
            currentY -= 18  // begin content below rule
        }

        func ensureRoom(for needed: CGFloat) {
            if currentY - needed < pageBreakThreshold {
                newContinuationPage()
            }
        }

        // ── Page 1: begin ─────────────────────────────────────────────────────
        beginPage()
        isFirstPage = true
        _ = isFirstPage  // (currently unused — placeholder for potential gating)

        // Header block (spec §Header block, top of page 1)
        currentY = drawHeaderBlock(
            ctx: ctx,
            intent: intent,
            docType: docType,
            title: project.name,
            author: authorName,
            medium: project.medium ?? "",
            dateRange: dateRange,
            checkInCount: checkIns.count,
            artifactCount: artifacts.count,
            snapshotCount: snapshotsCount(events: events),
            integrityStatus: integrityStatus,
            chainedEventCount: chainedEventCount(events: events, chain: chain),
            connectedAt: project.connectedAt,
            fmt: displayFmt,
            startY: topContentY
        )

        // ── Sections ──────────────────────────────────────────────────────────
        switch intent {
        case .authorship:
            currentY = drawAuthorshipSummary(
                ctx: ctx, y: currentY,
                checkInCount: checkIns.count,
                artifactCount: artifacts.count,
                snapshotCount: snapshotsCount(events: events),
                sourceCount: sources.count
            )
            currentY = drawSectionRule(ctx: ctx, y: currentY)

            currentY = drawCheckInsSection(
                ctx: ctx, y: currentY, checkIns: checkIns,
                statusColor: nsColor(Brand.accentDark),
                fmt: displayFmt,
                ensureRoom: { needed in
                    if currentY - needed < pageBreakThreshold {
                        newContinuationPage(); return currentY
                    }
                    return currentY
                }
            )
            currentY = drawSectionRule(ctx: ctx, y: currentY)

            currentY = drawTimelineSection(
                ctx: ctx, y: currentY,
                events: events, checkIns: checkIns, artifacts: artifacts,
                connectedAt: project.connectedAt,
                projectName: project.name,
                keyDotColor: nsColor(Brand.accent),
                minorDotColor: nsColor(Brand.border),
                fmt: displayFmt,
                breakIfNeeded: {
                    if currentY < pageBreakThreshold { newContinuationPage() }
                    return currentY
                }
            )
            currentY = drawSectionRule(ctx: ctx, y: currentY)

            currentY = drawIntegritySection(
                ctx: ctx, y: currentY,
                integrityStatus: integrityStatus,
                chain: chain
            )

        case .review:
            currentY = drawDescriptionSection(
                ctx: ctx, y: currentY,
                medium: project.medium ?? "",
                workingDescription: project.workingDescription ?? "",
                intent: project.intent ?? ""
            )
            currentY = drawSectionRule(ctx: ctx, y: currentY)

            currentY = drawCheckInsSection(
                ctx: ctx, y: currentY, checkIns: checkIns,
                statusColor: nsColor(Brand.ochre600),
                fmt: displayFmt,
                ensureRoom: { needed in
                    if currentY - needed < pageBreakThreshold {
                        newContinuationPage(); return currentY
                    }
                    return currentY
                }
            )
            currentY = drawSectionRule(ctx: ctx, y: currentY)

            currentY = drawArtifactsSection(
                ctx: ctx, y: currentY, artifacts: artifacts,
                fmt: displayFmt,
                breakIfNeeded: {
                    if currentY < pageBreakThreshold { newContinuationPage() }
                    return currentY
                }
            )
            currentY = drawSectionRule(ctx: ctx, y: currentY)

            currentY = drawTimelineSection(
                ctx: ctx, y: currentY,
                events: events, checkIns: checkIns, artifacts: artifacts,
                connectedAt: project.connectedAt,
                projectName: project.name,
                keyDotColor: nsColor(Brand.tan400),
                minorDotColor: nsColor(Brand.border),
                fmt: displayFmt,
                breakIfNeeded: {
                    if currentY < pageBreakThreshold { newContinuationPage() }
                    return currentY
                }
            )
        }

        endPage()
        ctx.closePDF()
    }

    // MARK: - Header block (spec §Header block)

    private static func drawHeaderBlock(
        ctx: CGContext,
        intent: Intent,
        docType: String,
        title: String,
        author: String,
        medium: String,
        dateRange: String,
        checkInCount: Int,
        artifactCount: Int,
        snapshotCount: Int,
        integrityStatus: LedgerIntegrity.IntegrityStatus,
        chainedEventCount: Int,
        connectedAt: Date,
        fmt: DateFormatter,
        startY: CGFloat
    ) -> CGFloat {
        var y = startY

        // (1) Eyebrow row — System UI 7.5pt textMuted
        let eyebrowFont = NSFont.systemFont(ofSize: 7.5)
        let eyebrowColor = nsColor(Brand.textMuted)
        drawText(ctx: ctx, text: docType.uppercased(), x: marginX, y: y,
                 font: eyebrowFont, color: eyebrowColor, align: .left)
        drawText(ctx: ctx, text: "Provenance · Procestra",
                 x: pageW - marginX, y: y,
                 font: eyebrowFont, color: eyebrowColor, align: .right)
        y -= 8

        // (2) Heavy rule 1.2pt textPrimary, 8pt below eyebrow baseline
        drawRule(ctx: ctx, y: y, weight: 1.2, color: nsColor(Brand.textPrimary))
        y -= 22

        // (3) Title — New York bold 28pt
        let titleFont = serifFont(size: 28, bold: true)
        drawText(ctx: ctx, text: title, x: marginX, y: y,
                 font: titleFont, color: nsColor(Brand.textPrimary), align: .left)
        y -= 18

        // (4) Author left / Medium · DateRange right
        let metaFont = serifFont(size: 11, bold: false)
        drawText(ctx: ctx, text: author.isEmpty ? "—" : author, x: marginX, y: y,
                 font: metaFont, color: nsColor(Brand.textSecondary), align: .left)
        let right = [medium, dateRange].filter { !$0.isEmpty }.joined(separator: " · ")
        if !right.isEmpty {
            drawText(ctx: ctx, text: right, x: pageW - marginX, y: y,
                     font: metaFont, color: nsColor(Brand.textSecondary), align: .right)
        }
        y -= 18

        // (5) Document-specific line
        switch intent {
        case .authorship:
            drawVerifiedLine(ctx: ctx, x: marginX, y: y,
                             integrityStatus: integrityStatus,
                             chainedEventCount: chainedEventCount,
                             fmt: fmt)
        case .review:
            let activity = "\(snapshotCount) version\(snapshotCount == 1 ? "" : "s") · " +
                           "\(checkInCount) check-in\(checkInCount == 1 ? "" : "s") · " +
                           "\(artifactCount) artifact\(artifactCount == 1 ? "" : "s") · " +
                           "Connected \(fmt.string(from: connectedAt))"
            drawText(ctx: ctx, text: activity, x: marginX, y: y,
                     font: NSFont.systemFont(ofSize: 8.5),
                     color: nsColor(Brand.textMuted), align: .left)
        }
        y -= 18

        // (6) 0.5pt rule in borderUI
        drawRule(ctx: ctx, y: y, weight: 0.5, color: nsColor(Brand.border))
        y -= 14

        return y
    }

    private static func drawVerifiedLine(
        ctx: CGContext, x: CGFloat, y: CGFloat,
        integrityStatus: LedgerIntegrity.IntegrityStatus,
        chainedEventCount: Int,
        fmt: DateFormatter
    ) {
        // Teal filled circle (r=3.5pt), baseline +4
        ctx.saveGState()
        ctx.setFillColor(nsColor(Brand.accent).cgColor)
        ctx.fillEllipse(in: CGRect(x: x, y: y + 1, width: 7, height: 7))
        ctx.restoreGState()

        let labelFont = NSFont.boldSystemFont(ofSize: 8.5)
        let noteFont  = NSFont.systemFont(ofSize: 8.5)
        let mainText: String
        switch integrityStatus {
        case .intact(let since, _):
            mainText = "Ledger chain intact since \(fmt.string(from: since))"
        case .chainBroken:
            mainText = "Ledger chain broken — review before relying on this report"
        case .historyRewritten:
            mainText = "Git history rewritten — review before relying on this report"
        case .checking:
            mainText = "Ledger integrity: checking…"
        case .unchecked:
            mainText = "Pre-chain project — no ledger chain available"
        }
        let labelX = x + 12
        let labelEnd = drawText(ctx: ctx, text: mainText, x: labelX, y: y,
                                font: labelFont, color: nsColor(Brand.accentDark),
                                align: .left)
        let suffix = " · \(chainedEventCount) chained event\(chainedEventCount == 1 ? "" : "s")"
        drawText(ctx: ctx, text: suffix, x: labelEnd, y: y,
                 font: noteFont, color: nsColor(Brand.textMuted), align: .left)
    }

    // MARK: - Section primitives

    /// Draws the eyebrow + 14pt gap. Returns y after the gap.
    private static func drawSectionEyebrow(ctx: CGContext, y: CGFloat, label: String) -> CGFloat {
        let f = NSFont.systemFont(ofSize: 7)
        let kerned = label.uppercased()  // CoreText handles the kerning visually via attrs
        // Apply tracking for visual all-caps presence.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: f,
            .foregroundColor: nsColor(Brand.textMuted),
            .kern: 1.0
        ]
        let attrStr = NSAttributedString(string: kerned, attributes: attrs)
        drawAttrText(ctx: ctx, attrStr: attrStr, x: marginX, y: y, align: .left)
        return y - 14
    }

    /// Draws the 0.5pt rule + 14pt gap that separates sections.
    private static func drawSectionRule(ctx: CGContext, y: CGFloat) -> CGFloat {
        let yRule = y - 6
        drawRule(ctx: ctx, y: yRule, weight: 0.5, color: nsColor(Brand.border))
        return yRule - 14
    }

    // MARK: - Authorship summary

    private static func drawAuthorshipSummary(
        ctx: CGContext, y: CGFloat,
        checkInCount: Int, artifactCount: Int,
        snapshotCount: Int, sourceCount: Int
    ) -> CGFloat {
        var y = drawSectionEyebrow(ctx: ctx, y: y, label: "Summary")
        let colW = contentW / 4
        let numFont = serifFont(size: 20, bold: true)
        let labelFont = NSFont.systemFont(ofSize: 7.5)
        let entries: [(String, String)] = [
            ("\(checkInCount)", "Check-ins"),
            ("\(snapshotCount)", "Versions"),
            ("\(sourceCount)", "Sources"),
            ("\(artifactCount)", "Artifacts")
        ]
        for (i, entry) in entries.enumerated() {
            let cx = marginX + CGFloat(i) * colW
            drawText(ctx: ctx, text: entry.0, x: cx, y: y,
                     font: numFont, color: nsColor(Brand.textPrimary), align: .left)
            drawText(ctx: ctx, text: entry.1.uppercased(), x: cx, y: y - 22,
                     font: labelFont, color: nsColor(Brand.textMuted), align: .left)
        }
        y -= 44
        return y
    }

    // MARK: - Description (Review only)

    private static func drawDescriptionSection(
        ctx: CGContext, y: CGFloat,
        medium: String, workingDescription: String, intent: String
    ) -> CGFloat {
        var y = drawSectionEyebrow(ctx: ctx, y: y, label: "Description")
        let bodyFont = serifFont(size: 10, bold: false)
        let mLabelFont = NSFont.boldSystemFont(ofSize: 8.5)
        if !medium.isEmpty {
            let mLabel = "Medium  "
            let endX = drawText(ctx: ctx, text: mLabel, x: marginX, y: y,
                                font: mLabelFont, color: nsColor(Brand.textMuted),
                                align: .left)
            drawText(ctx: ctx, text: medium, x: endX, y: y,
                     font: bodyFont, color: nsColor(Brand.textPrimary), align: .left)
            y -= 16
        }
        if !workingDescription.isEmpty {
            y = drawWrappedText(ctx: ctx, text: workingDescription, x: marginX, y: y,
                                width: contentW, font: bodyFont,
                                color: nsColor(Brand.textPrimary), lineSpacing: 3)
            y -= 6
        }
        if !intent.isEmpty {
            y = drawWrappedText(ctx: ctx, text: intent, x: marginX, y: y,
                                width: contentW, font: bodyFont,
                                color: nsColor(Brand.textPrimary), lineSpacing: 3)
            y -= 4
        }
        return y
    }

    // MARK: - Check-ins (both intents; statusColor varies)

    private static func drawCheckInsSection(
        ctx: CGContext, y: CGFloat,
        checkIns: [CheckIn],
        statusColor: NSColor,
        fmt: DateFormatter,
        ensureRoom: (CGFloat) -> CGFloat
    ) -> CGFloat {
        var y = drawSectionEyebrow(ctx: ctx, y: y, label: "Check-ins")
        if checkIns.isEmpty {
            drawText(ctx: ctx, text: "No check-ins included.", x: marginX, y: y,
                     font: NSFont.systemFont(ofSize: 8.5),
                     color: nsColor(Brand.textMuted), align: .left)
            return y - 14
        }
        let bodyFont = serifFont(size: 10, bold: false)
        let dateFont = NSFont.systemFont(ofSize: 8.5)
        let statusFont = NSFont.boldSystemFont(ofSize: 8.5)
        for c in checkIns.reversed() {
            _ = ensureRoom(60)
            // Date left
            drawText(ctx: ctx, text: fmt.string(from: c.timestamp), x: marginX, y: y,
                     font: dateFont, color: nsColor(Brand.textMuted), align: .left)
            // [STATUS] right
            let statusLabel = "[\(c.status.label.uppercased())]"
            drawText(ctx: ctx, text: statusLabel, x: pageW - marginX, y: y,
                     font: statusFont, color: statusColor, align: .right)
            y -= 12
            // Body — wrapped New York roman 10pt
            let body = c.text.isEmpty ? "(no content)" : c.text
            y = drawWrappedText(ctx: ctx, text: body, x: marginX, y: y,
                                width: contentW, font: bodyFont,
                                color: nsColor(Brand.textPrimary), lineSpacing: 2)
            y -= 10
        }
        return y
    }

    // MARK: - Artifacts (Review only)

    private static func drawArtifactsSection(
        ctx: CGContext, y: CGFloat,
        artifacts: [Artifact],
        fmt: DateFormatter,
        breakIfNeeded: () -> CGFloat
    ) -> CGFloat {
        var y = drawSectionEyebrow(ctx: ctx, y: y, label: "Artifacts")
        if artifacts.isEmpty {
            drawText(ctx: ctx, text: "No artifacts included.", x: marginX, y: y,
                     font: NSFont.systemFont(ofSize: 8.5),
                     color: nsColor(Brand.textMuted), align: .left)
            return y - 14
        }
        let bodyFont = serifFont(size: 10, bold: false)
        let metaFont = NSFont.systemFont(ofSize: 7.5)
        for a in artifacts {
            if y < pageBreakThreshold + 30 { _ = breakIfNeeded() }
            drawText(ctx: ctx, text: a.title, x: marginX, y: y,
                     font: bodyFont, color: nsColor(Brand.textPrimary), align: .left)
            let right = "\(a.type.rawValue) · \(fmt.string(from: a.timestamp))"
            drawText(ctx: ctx, text: right, x: pageW - marginX, y: y,
                     font: metaFont, color: nsColor(Brand.textMuted), align: .right)
            y -= 12
            if let caption = a.caption, !caption.isEmpty {
                y = drawWrappedText(ctx: ctx, text: caption, x: marginX, y: y,
                                    width: contentW,
                                    font: NSFont.systemFont(ofSize: 8.5),
                                    color: nsColor(Brand.textMuted), lineSpacing: 2)
            }
            y -= 8
        }
        return y
    }

    // MARK: - Process timeline (both intents; dot color set by caller)

    private static func drawTimelineSection(
        ctx: CGContext, y: CGFloat,
        events: [LedgerEvent], checkIns: [CheckIn], artifacts: [Artifact],
        connectedAt: Date, projectName: String,
        keyDotColor: NSColor, minorDotColor: NSColor,
        fmt: DateFormatter,
        breakIfNeeded: () -> CGFloat
    ) -> CGFloat {
        var y = drawSectionEyebrow(ctx: ctx, y: y, label: "Process Timeline")

        // Build event list — mix of events + project connect.
        struct TLItem {
            let date: Date
            let title: String
            let detail: String
            let isKey: Bool  // key = teal/tan dot; minor = borderUI
        }
        var items: [TLItem] = []
        items.append(TLItem(date: connectedAt,
                            title: "Project connected",
                            detail: projectName, isKey: true))
        for e in events.suffix(40) {
            let isKey: Bool
            switch e.type {
            case .checkin, .projectConnected, .promotedToWorks, .bundleExported:
                isKey = true
            default:
                isKey = false
            }
            items.append(TLItem(date: e.timestamp,
                                title: e.type.displayName,
                                detail: e.detail, isKey: isKey))
        }
        for c in checkIns.suffix(12) {
            items.append(TLItem(date: c.timestamp,
                                title: "Check-in [\(c.status.label)]",
                                detail: String(c.text.prefix(120)),
                                isKey: true))
        }
        for a in artifacts.suffix(12) {
            items.append(TLItem(date: a.timestamp,
                                title: "Artifact added",
                                detail: a.title, isKey: false))
        }
        items.sort { $0.date < $1.date }

        // Vertical line down the left of the content area (5pt right of margin)
        let railX = marginX + 5
        let dotR: CGFloat = 2.5
        let titleFont = serifFont(size: 10, bold: false)
        let detailFont = NSFont.systemFont(ofSize: 8.5)
        let dateFont = NSFont.systemFont(ofSize: 7.5)

        let topY = y
        var bottomY = y
        for item in items {
            if y < pageBreakThreshold + 30 { _ = breakIfNeeded() }

            // Dot
            ctx.saveGState()
            ctx.setFillColor((item.isKey ? keyDotColor : minorDotColor).cgColor)
            ctx.fillEllipse(in: CGRect(x: railX - dotR, y: y + 1,
                                        width: dotR * 2, height: dotR * 2))
            ctx.restoreGState()

            // Title + date (right)
            let textX = railX + 12
            let textW = pageW - marginX - textX
            drawText(ctx: ctx, text: item.title, x: textX, y: y,
                     font: titleFont,
                     color: nsColor(Brand.textPrimary), align: .left)
            drawText(ctx: ctx, text: fmt.string(from: item.date),
                     x: pageW - marginX, y: y,
                     font: dateFont, color: nsColor(Brand.textMuted), align: .right)
            y -= 12
            if !item.detail.isEmpty {
                y = drawWrappedText(ctx: ctx, text: item.detail, x: textX, y: y,
                                    width: textW,
                                    font: detailFont,
                                    color: nsColor(Brand.textMuted), lineSpacing: 2)
            }
            y -= 8
            bottomY = y
        }

        // Draw the vertical rail behind all dots
        ctx.saveGState()
        ctx.setStrokeColor(nsColor(Brand.border).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: railX, y: topY + 4))
        ctx.addLine(to: CGPoint(x: railX, y: max(bottomY + 4, pageBreakThreshold)))
        ctx.strokePath()
        ctx.restoreGState()

        return y
    }

    // MARK: - Integrity (Authorship only)

    private static func drawIntegritySection(
        ctx: CGContext, y: CGFloat,
        integrityStatus: LedgerIntegrity.IntegrityStatus,
        chain: LedgerChain?
    ) -> CGFloat {
        var y = drawSectionEyebrow(ctx: ctx, y: y, label: "Integrity")
        let labelFont = NSFont.systemFont(ofSize: 8)
        let hashFont = NSFont(name: "Menlo", size: 8) ?? NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let noteFont = NSFont.systemFont(ofSize: 7.5)

        let genesis = chain?.genesisHash ?? "—"
        let head    = chain?.head ?? "—"

        drawText(ctx: ctx, text: "Genesis hash", x: marginX, y: y,
                 font: labelFont, color: nsColor(Brand.textMuted), align: .left)
        y -= 11
        drawText(ctx: ctx, text: genesis, x: marginX, y: y,
                 font: hashFont, color: nsColor(Brand.textPrimary), align: .left)
        y -= 14

        drawText(ctx: ctx, text: "Chain head", x: marginX, y: y,
                 font: labelFont, color: nsColor(Brand.textMuted), align: .left)
        y -= 11
        drawText(ctx: ctx, text: head, x: marginX, y: y,
                 font: hashFont, color: nsColor(Brand.textPrimary), align: .left)
        y -= 12

        let note: String
        switch integrityStatus {
        case .intact:
            note = "Chain verified — every link's SHA-256 was recomputed and matched on the date this report was generated."
        case .chainBroken(let at, _, _, _):
            note = "Chain broken at entry \(at). Treat downstream events as unverified."
        case .historyRewritten:
            note = "Git history was rewritten after this chain was built. Treat events as unverified."
        case .checking, .unchecked:
            note = "No chain available for this project (created before ledger chaining)."
        }
        y = drawWrappedText(ctx: ctx, text: note, x: marginX, y: y,
                            width: contentW, font: noteFont,
                            color: nsColor(Brand.textMuted), lineSpacing: 2)
        return y - 8
    }

    // MARK: - Footer (spec §Footer, all pages)

    private static func drawFooter(
        ctx: CGContext,
        docType: String, title: String, author: String,
        fmt: DateFormatter
    ) {
        let f = NSFont.systemFont(ofSize: 6.5)
        let c = nsColor(Brand.textMuted)
        // 0.4pt rule 11pt above baseline
        let ruleY = footerBaseY + 11
        drawRule(ctx: ctx, y: ruleY, weight: 0.4, color: nsColor(Brand.border))

        let left = "\(docType) · \(title)\(author.isEmpty ? "" : " · \(author)")"
        let right = "Generated by Provenance · \(fmt.string(from: Date()))"
        drawText(ctx: ctx, text: left, x: marginX, y: footerBaseY,
                 font: f, color: c, align: .left)
        drawText(ctx: ctx, text: right, x: pageW - marginX, y: footerBaseY,
                 font: f, color: c, align: .right)
    }

    // MARK: - Drawing primitives

    private enum HAlign { case left, right }

    /// Draws a single line of text at (x, y) in PDF y-up coords. Returns the
    /// x-end of the drawn run so callers can chain inline runs.
    @discardableResult
    private static func drawText(
        ctx: CGContext, text: String, x: CGFloat, y: CGFloat,
        font: NSFont, color: NSColor, align: HAlign
    ) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        return drawAttrText(ctx: ctx, attrStr: attrStr, x: x, y: y, align: align)
    }

    @discardableResult
    private static func drawAttrText(
        ctx: CGContext, attrStr: NSAttributedString,
        x: CGFloat, y: CGFloat, align: HAlign
    ) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attrStr as CFAttributedString)
        let bounds = CTLineGetImageBounds(line, ctx)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let startX: CGFloat
        switch align {
        case .left:  startX = x
        case .right: startX = x - CGFloat(width)
        }
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: startX, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        return startX + bounds.width
    }

    /// Lays out a paragraph in a fitted frame, returning the new y after drawing.
    @discardableResult
    private static func drawWrappedText(
        ctx: CGContext, text: String, x: CGFloat, y: CGFloat,
        width: CGFloat, font: NSFont, color: NSColor, lineSpacing: CGFloat
    ) -> CGFloat {
        guard !text.isEmpty else { return y }
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr as CFAttributedString)
        let fitSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRangeMake(0, attrStr.length),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        )
        let blockHeight = ceil(fitSize.height)
        let rect = CGRect(x: x, y: y - blockHeight, width: width, height: blockHeight)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, ctx)
        return y - blockHeight - 2
    }

    private static func drawRule(ctx: CGContext, y: CGFloat, weight: CGFloat, color: NSColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(weight)
        ctx.move(to: CGPoint(x: marginX, y: y))
        ctx.addLine(to: CGPoint(x: pageW - marginX, y: y))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Fonts

    /// Returns a New York serif font (or system serif fallback). Implementation
    /// note: macOS doesn't expose "NewYork" as a PostScript-named face the way
    /// it does on iOS — `NSFont(name:size:)` returns nil. We fall back to
    /// `Times-Roman/Times-Bold`, which IS the system serif on macOS and is
    /// metrically very close to New York. The spec explicitly endorses this
    /// fallback ("with fallback to .systemFont serif").
    private static func serifFont(size: CGFloat, bold: Bool) -> NSFont {
        let candidates = bold
            ? ["NewYork-Bold", "NewYorkBold", "Times-Bold"]
            : ["NewYork", "NewYorkRoman", "Times-Roman"]
        for name in candidates {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    // MARK: - Helpers

    private static func nsColor(_ swiftColor: Color) -> NSColor {
        NSColor(swiftColor)
    }

    private static func computeDateRange(
        events: [LedgerEvent], project: Project, fmt: DateFormatter
    ) -> String {
        let start: Date = events.first?.timestamp ?? project.connectedAt
        return "\(fmt.string(from: start)) – \(fmt.string(from: Date()))"
    }

    private static func snapshotsCount(events: [LedgerEvent]) -> Int {
        events.filter {
            $0.type == .snapshotAuto ||
            $0.type == .snapshotScheduled ||
            $0.type == .snapshotManual
        }.count
    }

    private static func chainedEventCount(events: [LedgerEvent], chain: LedgerChain?) -> Int {
        chain?.lineHashes.count ?? events.count
    }
}
