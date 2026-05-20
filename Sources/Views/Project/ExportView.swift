import SwiftUI
import AppKit

// MARK: - Export intent + format (PR-25)

/// PR-25 §A1 — intent-first picker. Two intents:
///   - Review: PDF or Markdown
///   - Authorship Report: PDF only
/// "Bundle for Works" is no longer in the user-facing format picker (§B1);
/// the bundle code is invoked only by the "Promote to Works…" action.
enum ExportIntent: String, CaseIterable {
    case review
    case authorship

    var label: String {
        switch self {
        case .review:     return "Review"
        case .authorship: return "Authorship Report"
        }
    }

    var description: String {
        switch self {
        case .review:
            return "A printable or shareable summary of your project: description, check-ins, artifacts, and recent activity."
        case .authorship:
            return "A ledger-backed PDF report proving authorship and process history. Used for forensic, legal, or archival purposes."
        }
    }
}

enum ReviewFormat: String, CaseIterable {
    case pdf
    case markdown

    var label: String {
        switch self {
        case .pdf:      return "PDF"
        case .markdown: return "Markdown"
        }
    }
}

// MARK: - Export view

struct ExportView: View {
    @ObservedObject var state: ProjectState

    // PR-25 — intent-first state.
    @State private var selectedIntent: ExportIntent = .review
    @State private var reviewFormat: ReviewFormat = .pdf
    @State private var isExporting = false
    @State private var exportConfirmation: String? = nil
    @State private var exportError: String? = nil
    @State private var authorName: String = ""

    // Open-in-Works feedback (PR-26 §F)
    @State private var promoteConfirmation: String? = nil
    @State private var promoteError: String? = nil

    // Counts
    private var includedCheckIns: Int  { state.checkIns.filter  { $0.exportIncluded }.count }
    private var totalCheckIns: Int     { state.checkIns.count }
    private var includedSources: Int   { state.sources.filter   { $0.exportIncluded }.count }
    private var totalSources: Int      { state.sources.count }
    private var includedArtifacts: Int { state.artifacts.filter { $0.exportIncluded }.count }
    private var totalArtifacts: Int    { state.artifacts.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.spaceXL) {

                // ── Format (PR-25 §A1) ───────────────────────────────────────
                sectionHeader("Format")

                VStack(alignment: .leading, spacing: Brand.spaceMD) {
                    // Intent picker — Review / Authorship Report
                    Picker("", selection: $selectedIntent) {
                        ForEach(ExportIntent.allCases, id: \.self) { intent in
                            Text(intent.label).tag(intent)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    // PR-26 §D — same segmented control in both intents; in
                    // Authorship, Markdown is disabled rather than absent so
                    // the picker shape never changes between intents.
                    HStack(spacing: Brand.spaceSM) {
                        Text("Output:")
                            .font(.system(size: 12))
                            .foregroundColor(Brand.textSecondary)
                        UnifiedFormatPicker(
                            format: $reviewFormat,
                            markdownEnabled: selectedIntent == .review
                        )
                        .frame(width: 220)
                        Spacer()
                    }
                    .padding(.leading, 4)
                    .onChange(of: selectedIntent) { newIntent in
                        // Authorship forces PDF — Markdown is not a valid
                        // output for it, so reset the selection if the user
                        // had Markdown chosen on the Review intent.
                        if newIntent == .authorship && reviewFormat == .markdown {
                            reviewFormat = .pdf
                        }
                    }

                    // Intent-specific description (System UI 11pt, text/secondary).
                    Text(selectedIntent.description)
                        .font(.system(size: 11))
                        .foregroundColor(Brand.textSecondary)

                    // Author name field — required for Authorship, optional for Review.
                    HStack(spacing: Brand.spaceSM) {
                        Text("Author name:")
                            .font(.system(size: 13))
                            .foregroundColor(Brand.textSecondary)
                        TextField("Your name", text: $authorName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                    }
                    .padding(.top, 2)
                }

                // ── Will be included ──────────────────────────────────────────
                sectionHeader("Will be included")

                VStack(alignment: .leading, spacing: Brand.spaceSM) {
                    includedRow(label: "Check-ins",
                                included: includedCheckIns, total: totalCheckIns)
                    includedRow(label: "Sources",
                                included: includedSources,  total: totalSources)
                    includedRow(label: "Artifacts",
                                included: includedArtifacts, total: totalArtifacts)

                    Text("Toggle \u{201C}Include in export\u{201D} on individual items to change.")
                        .font(.system(size: 11))
                        .foregroundColor(Brand.textMuted)
                        .padding(.top, Brand.spaceXS)

                    // PR-26 §C — integrity status line shown for BOTH intents.
                    // The full Integrity SECTION (with hashes) remains
                    // Authorship-only in the PDF; this UI line is a trust
                    // signal that applies to either output type.
                    integrityLine
                }

                // ── Export action ─────────────────────────────────────────────
                VStack(alignment: .leading, spacing: Brand.spaceSM) {
                    HStack(spacing: Brand.spaceMD) {
                        Button {
                            runExport()
                        } label: {
                            if isExporting {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .controlSize(.small)
                                    Text("Exporting\u{2026}")
                                }
                            } else {
                                Text("Export")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.accent)
                        .keyboardShortcut("e", modifiers: .command)
                        .disabled(isExporting)
                    }

                    if let confirmation = exportConfirmation {
                        Label(confirmation, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Brand.accent)
                    }
                    if let err = exportError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Brand.statusStuck)
                    }
                }

                // ── Divider ───────────────────────────────────────────────────
                Divider()
                    .overlay(Brand.border)
                    .padding(.vertical, Brand.spaceSM)

                // ── Open in Works (PR-26 §F) ──────────────────────────────────
                // Replaces "Promote to Works" — no bundle is written. Works
                // receives the folder path via the works:// URL scheme and
                // auto-detects .ledger/ (WK-N follow-up).
                sectionHeader("Open in Works")

                VStack(alignment: .leading, spacing: Brand.spaceMD) {
                    Text("Open this project folder in the Works app to add it to a portfolio. Works will read your provenance data automatically.")
                        .font(.system(size: 13))
                        .foregroundColor(Brand.textSecondary)

                    Button("Open in Works\u{2026}") {
                        openInWorks()
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.textBrand)

                    if let confirmation = promoteConfirmation {
                        Text(confirmation)
                            .font(.system(size: 12))
                            .foregroundColor(Brand.accent)
                    }
                    if let err = promoteError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Brand.statusStuck)
                    }
                }
            }
            .padding(Brand.spaceXL)
        }
        .background(Brand.surfaceBase)
        .onAppear {
            // Default author name from git config
            Task.detached(priority: .background) {
                let name = await Self.gitAuthorName()
                await MainActor.run { if authorName.isEmpty { authorName = name } }
            }
        }
    }

    // MARK: - Integrity line

    private var integrityLine: some View {
        HStack(spacing: 6) {
            Image(systemName: integrityIcon)
                .font(.system(size: 11))
                .foregroundColor(integrityColor)
            Text(integrityText)
                .font(.system(size: 11))
                .foregroundColor(integrityColor)
        }
    }

    private var integrityIcon: String {
        switch state.integrityStatus {
        case .intact:            return "checkmark.shield.fill"
        case .chainBroken, .historyRewritten: return "exclamationmark.triangle.fill"
        default:                 return "shield.slash"
        }
    }

    private var integrityColor: Color {
        switch state.integrityStatus {
        case .intact:            return Brand.statusBreakthrough
        case .chainBroken, .historyRewritten: return Brand.statusStuck
        default:                 return Brand.textMuted
        }
    }

    private var integrityText: String {
        switch state.integrityStatus {
        case .intact(let since, _):
            let fmt = DateFormatter()
            fmt.dateStyle = .medium; fmt.timeStyle = .none
            return "Ledger integrity: \u{2713} intact (chain since \(fmt.string(from: since)))"
        case .chainBroken(let at, _, _, _):
            return "Ledger integrity: \u{26A0} chain broken at line \(at) — review before exporting"
        case .historyRewritten:
            return "Ledger integrity: \u{26A0} git history rewritten — review before exporting"
        case .checking:
            return "Ledger integrity: checking\u{2026}"
        case .unchecked:
            return "Ledger integrity: no chain (pre-chain project)"
        }
    }

    // MARK: - Sub-views

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Brand.textPrimary)
    }

    private func includedRow(label: String, included: Int, total: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Brand.textPrimary)
            Spacer()
            Text("\(included) of \(total)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Brand.textPrimary)
            if included < total {
                Text("\(total - included) hidden")
                    .font(.system(size: 11))
                    .foregroundColor(Brand.textMuted)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Export action

    /// PR-27 §B — dual-copy export.
    /// 1. ALWAYS write a timestamped backup to `<project>/.ledger/export/`.
    /// 2. Then present `NSSavePanel` so the user can save a copy anywhere.
    /// 3. Copy the backup bytes to the user's chosen location. If the user
    ///    cancels the panel, the backup is still written — the confirmation
    ///    message reflects that.
    private func runExport() {
        let proj    = state.project
        let cis     = state.checkIns
        let srcs    = state.sources
        let arts    = state.artifacts
        let evs     = state.events
        let mss     = state.manuscripts
        let author  = authorName
        let iStatus = state.integrityStatus
        let chain   = LedgerIntegrity.readChain(from: state.project)
        let intent  = selectedIntent
        let format  = reviewFormat

        // ── 1. Backup target (timestamped filename in .ledger/export/) ───
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]
        let timestamp = isoFmt.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let intentSlug: String
        let ext: String
        let userDefaultName: String
        switch intent {
        case .authorship:
            intentSlug = "authorship"
            ext = "pdf"
            userDefaultName = "\(proj.name)-authorship-report.pdf"
        case .review:
            intentSlug = "review"
            switch format {
            case .pdf:      ext = "pdf";  userDefaultName = "\(proj.name)-review.pdf"
            case .markdown: ext = "md";   userDefaultName = "\(proj.name)-review.md"
            }
        }
        let backupURL = proj.exportURL
            .appendingPathComponent("\(timestamp)_\(intentSlug).\(ext)")

        isExporting = true
        exportConfirmation = nil
        exportError = nil

        Task {
            do {
                // Ensure .ledger/export/ exists.
                try FileManager.default.createDirectory(
                    at: proj.exportURL,
                    withIntermediateDirectories: true
                )

                // ── 2. Generate the backup ───────────────────────────────
                switch intent {
                case .authorship:
                    _ = try await Task.detached(priority: .userInitiated) {
                        try ExportService.exportAuthorshipReport(
                            project: proj, authorName: author,
                            checkIns: cis, sources: srcs, artifacts: arts,
                            manuscripts: mss, events: evs,
                            integrityStatus: iStatus, chain: chain,
                            to: backupURL)
                    }.value
                case .review:
                    switch format {
                    case .pdf:
                        _ = try await Task.detached(priority: .userInitiated) {
                            try ExportService.exportReviewPDF(
                                project: proj, authorName: author,
                                checkIns: cis, sources: srcs, artifacts: arts,
                                manuscripts: mss, events: evs,
                                to: backupURL)
                        }.value
                    case .markdown:
                        _ = try await Task.detached(priority: .userInitiated) {
                            try ExportService.exportReviewMarkdown(
                                project: proj, authorName: author,
                                checkIns: cis, sources: srcs, artifacts: arts,
                                events: evs,
                                to: backupURL)
                        }.value
                    }
                }

                // ── 3. Present save panel for the user copy ──────────────
                await MainActor.run {
                    let panel = NSSavePanel()
                    panel.directoryURL = proj.folderURL
                    panel.title = "Save copy of \(proj.name) export"
                    panel.nameFieldStringValue = userDefaultName
                    switch ext {
                    case "pdf": panel.allowedContentTypes = [.pdf]
                    case "md":  panel.allowedContentTypes = [.plainText]
                    default: break
                    }

                    let backupRel = ".ledger/export/\(backupURL.lastPathComponent)"
                    let response = panel.runModal()
                    if response == .OK, let userURL = panel.url {
                        do {
                            // Overwrite if the user picked an existing path
                            // (NSSavePanel already warned them).
                            if FileManager.default.fileExists(atPath: userURL.path) {
                                try FileManager.default.removeItem(at: userURL)
                            }
                            try FileManager.default.copyItem(at: backupURL, to: userURL)
                            isExporting = false
                            exportConfirmation =
                                "Saved to \(userURL.lastPathComponent). Backup at \(backupRel)."
                        } catch {
                            isExporting = false
                            exportError =
                                "Backup saved at \(backupRel), but couldn't write the user copy: \(error.localizedDescription)"
                        }
                    } else {
                        // User cancelled — backup is still on disk.
                        isExporting = false
                        exportConfirmation = "Backup saved at \(backupRel)."
                    }
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Open in Works (PR-26 §F)

    /// Launches Works (or prompts the user to install it) pointed at this
    /// project's folder. NO bundle is written — Works auto-detects `.ledger/`
    /// via the WK-N follow-up.
    private func openInWorks() {
        promoteConfirmation = nil
        promoteError = nil

        let path = state.project.folderURL.path
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        guard let worksURL = URL(string: "works://add?path=\(encoded)") else {
            promoteError = "Could not construct works:// URL for \(path)."
            return
        }

        // Append a ledger event so the handoff is traceable.
        LedgerWriter.appendEvent(
            type: .promotedToWorks,
            detail: "Open in Works — \(state.project.name) (\(path))",
            to: state.project
        )
        state.reloadEvents()

        let launched = NSWorkspace.shared.open(worksURL)
        if launched {
            promoteConfirmation = "Works was asked to open this project."
        } else {
            promoteError = "Works isn't installed or didn't respond. Install Works and try again, or open the folder manually."
        }
    }

    // MARK: - Git author name

    private static func gitAuthorName() async -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["config", "user.name"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

}

// MARK: - Stat pill (kept for compatibility with ExportSheet usages)

struct ExportStatPill: View {
    let count: Int
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Brand.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Brand.textMuted)
        }
    }
}

// MARK: - PR-26 §D — UnifiedFormatPicker

/// Segmented PDF/Markdown selector used by both export intents. Authorship
/// passes `markdownEnabled: false` — same shape and position, reduced opacity
/// + `.disabled(true)` on the Markdown segment so the picker never changes
/// shape between intents.
struct UnifiedFormatPicker: View {
    @Binding var format: ReviewFormat
    let markdownEnabled: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment(format: .pdf, enabled: true)
            segment(format: .markdown, enabled: markdownEnabled)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Brand.radiusMd)
                .stroke(Brand.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Brand.radiusMd))
    }

    @ViewBuilder
    private func segment(format target: ReviewFormat, enabled: Bool) -> some View {
        let isSelected = (format == target)
        Button(action: { if enabled { format = target } }) {
            Text(target.label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Brand.accent : Brand.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(isSelected ? Brand.accent.opacity(0.1) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .help(enabled ? "" : "Authorship reports are PDF only.")
    }
}
