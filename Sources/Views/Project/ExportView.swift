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

    // Promotion
    @State private var showPromoteSheet = false
    @State private var isPromoting = false
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

                    // Nested format toggle under the selected intent.
                    HStack(spacing: Brand.spaceSM) {
                        Text("Output:")
                            .font(.system(size: 12))
                            .foregroundColor(Brand.textSecondary)
                        switch selectedIntent {
                        case .review:
                            Picker("", selection: $reviewFormat) {
                                ForEach(ReviewFormat.allCases, id: \.self) { f in
                                    Text(f.label).tag(f)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 200)
                        case .authorship:
                            // PDF-only pill (non-interactive, with tooltip).
                            Text("PDF")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Brand.accent)
                                .padding(.horizontal, Brand.spaceSM)
                                .padding(.vertical, 3)
                                .background(Brand.accent.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Brand.radiusMd)
                                        .stroke(Brand.accent.opacity(0.4), lineWidth: 0.5)
                                )
                                .cornerRadius(Brand.radiusMd)
                                .help("Authorship reports are PDF only.")
                        }
                        Spacer()
                    }
                    .padding(.leading, 4)

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

                    // PR-25 §A3 — integrity line only relevant for Authorship Report.
                    if selectedIntent == .authorship {
                        integrityLine
                    }
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

                // ── Promote to Works ──────────────────────────────────────────
                sectionHeader("Promote to Works")

                VStack(alignment: .leading, spacing: Brand.spaceMD) {
                    Text("When this project is ready to enter a Works library, promote it here. A bundle will be written and Works will be asked to open with the project pre-filled.")
                        .font(.system(size: 13))
                        .foregroundColor(Brand.textSecondary)

                    Button("Promote to Works\u{2026}") {
                        showPromoteSheet = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPromoting)

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
        .sheet(isPresented: $showPromoteSheet) {
            PromoteConfirmSheet(
                projectName: state.project.name,
                checkInCount: includedCheckIns,
                sourceCount: includedSources,
                artifactCount: includedArtifacts
            ) {
                showPromoteSheet = false
                runPromote()
            } onCancel: {
                showPromoteSheet = false
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

    // PR-25 — intent-first export dispatch.
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

        let savePanel = NSSavePanel()
        savePanel.directoryURL = proj.folderURL
        savePanel.title = "Export \(proj.name)"

        switch intent {
        case .authorship:
            savePanel.allowedContentTypes = [.pdf]
            savePanel.nameFieldStringValue = "\(proj.name)-authorship-report.pdf"
        case .review:
            switch format {
            case .pdf:
                savePanel.allowedContentTypes = [.pdf]
                savePanel.nameFieldStringValue = "\(proj.name)-review.pdf"
            case .markdown:
                savePanel.allowedContentTypes = [.plainText]
                savePanel.nameFieldStringValue = "\(proj.name)-review.md"
            }
        }

        guard savePanel.runModal() == .OK, let destURL = savePanel.url else { return }

        isExporting = true
        exportConfirmation = nil
        exportError = nil

        Task {
            do {
                let outURL: URL
                switch intent {
                case .authorship:
                    outURL = try await Task.detached(priority: .userInitiated) {
                        try ExportService.exportAuthorshipReport(
                            project: proj, authorName: author,
                            checkIns: cis, sources: srcs, artifacts: arts,
                            manuscripts: mss, events: evs,
                            integrityStatus: iStatus, chain: chain,
                            to: destURL)
                    }.value
                case .review:
                    switch format {
                    case .pdf:
                        outURL = try await Task.detached(priority: .userInitiated) {
                            try ExportService.exportReviewPDF(
                                project: proj, authorName: author,
                                checkIns: cis, sources: srcs, artifacts: arts,
                                manuscripts: mss, events: evs,
                                to: destURL)
                        }.value
                    case .markdown:
                        outURL = try await Task.detached(priority: .userInitiated) {
                            try ExportService.exportReviewMarkdown(
                                project: proj, authorName: author,
                                checkIns: cis, sources: srcs, artifacts: arts,
                                events: evs,
                                to: destURL)
                        }.value
                    }
                }
                await MainActor.run {
                    isExporting = false
                    exportConfirmation = "Exported to \(outURL.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Promote action

    private func runPromote() {
        isPromoting = true
        promoteConfirmation = nil
        promoteError = nil

        Task {
            do {
                _ = try await PromotionService.promote(state: state)
                await MainActor.run {
                    isPromoting = false
                    promoteConfirmation = "Bundle ready. Works will open if installed; otherwise open it manually and add this folder."
                }
            } catch {
                await MainActor.run {
                    isPromoting = false
                    promoteError = error.localizedDescription
                }
            }
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

// MARK: - Promote confirmation sheet

struct PromoteConfirmSheet: View {
    let projectName: String
    let checkInCount: Int
    let sourceCount: Int
    let artifactCount: Int
    let onPromote: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.spaceLG) {
            Text("Promote to Works")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Brand.textPrimary)

            Text("A Provenance bundle will be written to this project\u{2019}s folder. Works will open with this project ready to add to a library.")
                .font(.system(size: 13))
                .foregroundColor(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Will include \(checkInCount) check-in\(checkInCount == 1 ? "" : "s"), \(sourceCount) source\(sourceCount == 1 ? "" : "s"), \(artifactCount) artifact\(artifactCount == 1 ? "" : "s").")
                .font(.system(size: 13))
                .foregroundColor(Brand.textPrimary)
                .padding(Brand.spaceSM)
                .background(Brand.surfaceSunken)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.radiusMd)
                        .stroke(Brand.border, lineWidth: 0.5)
                )
                .cornerRadius(Brand.radiusMd)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Promote") { onPromote() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Brand.spaceXL)
        .frame(width: 480)
        .background(Brand.surfaceBase)
    }
}
