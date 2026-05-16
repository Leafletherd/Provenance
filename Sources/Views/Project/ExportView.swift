import SwiftUI
import AppKit

// MARK: - Export format

enum ExportFormat: String, CaseIterable {
    case pdf             = "pdf"
    case bundle          = "bundle"
    case markdown        = "markdown"
    case authorshipReport = "authorship_report"

    var label: String {
        switch self {
        case .pdf:             return "PDF Report"
        case .bundle:          return "Bundle for Works"
        case .markdown:        return "Markdown"
        case .authorshipReport: return "Authorship"
        }
    }

    var icon: String {
        switch self {
        case .pdf:             return "doc.richtext"
        case .bundle:          return "shippingbox"
        case .markdown:        return "doc.plaintext"
        case .authorshipReport: return "doc.badge.clock"
        }
    }

    /// One-line description shown under the picker.
    var shortDescription: String {
        switch self {
        case .pdf:
            return "A printable report of your project\u{2019}s check-ins, sources, artifacts, and recent snapshots."
        case .bundle:
            return "A structured handoff for Works. Writes .provenance.bundle/ at the project root."
        case .markdown:
            return "A single .md file containing the project\u{2019}s metadata, check-ins, sources, and artifact list."
        case .authorshipReport:
            return "A structured PDF designed for academic submission. Includes the full process timeline, sources, paste events, check-ins, and integrity chain status."
        }
    }
}

// MARK: - Export view

struct ExportView: View {
    @ObservedObject var state: ProjectState

    @State private var selectedFormat: ExportFormat = .pdf
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

                // ── Format ────────────────────────────────────────────────────
                sectionHeader("Format")

                VStack(alignment: .leading, spacing: Brand.spaceSM) {
                    Picker("", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { fmt in
                            Text(fmt.label).tag(fmt)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(selectedFormat.shortDescription)
                        .font(.system(size: 13))
                        .foregroundColor(Brand.textSecondary)

                    // Author name field — only for Authorship Report
                    if selectedFormat == .authorshipReport {
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

                    // Integrity indicator
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

    private func runExport() {
        isExporting = true
        exportConfirmation = nil
        exportError = nil

        let proj     = state.project
        let cis      = state.checkIns
        let srcs     = state.sources
        let arts     = state.artifacts
        let snaps    = state.snapshots
        let evs      = state.events
        let mss      = state.manuscripts
        let fmt      = selectedFormat
        let author   = authorName
        let iStatus  = state.integrityStatus
        let chain    = LedgerIntegrity.readChain(from: state.project)

        Task {
            do {
                switch fmt {

                case .pdf:
                    let url = try await Task.detached(priority: .userInitiated) {
                        try ExportService.export(project: proj, checkIns: cis, sources: srcs,
                                                  artifacts: arts, snapshots: snaps, events: evs)
                    }.value
                    await MainActor.run {
                        isExporting = false
                        let hint = "Exported to \(url.lastPathComponent)"
                        exportConfirmation = hint
                    }

                case .bundle:
                    let result = try await Task.detached(priority: .userInitiated) {
                        try ExportService.exportBundle(project: proj, checkIns: cis,
                                                       sources: srcs, artifacts: arts)
                    }.value
                    await MainActor.run {
                        let detail = "Bundle exported with \(result.checkInCount) check-in\(result.checkInCount == 1 ? "" : "s"), " +
                                     "\(result.sourceCount) source\(result.sourceCount == 1 ? "" : "s"), " +
                                     "\(result.artifactCount) artifact\(result.artifactCount == 1 ? "" : "s")."
                        LedgerWriter.appendEvent(type: .bundleExported, detail: detail, to: proj)
                        state.reloadEvents()
                        isExporting = false
                        exportConfirmation = "Exported to .provenance.bundle/"
                    }

                case .markdown:
                    let url = try await Task.detached(priority: .userInitiated) {
                        try ExportService.exportMarkdown(project: proj, checkIns: cis,
                                                         sources: srcs, artifacts: arts,
                                                         snapshots: snaps, events: evs)
                    }.value
                    await MainActor.run {
                        isExporting = false
                        exportConfirmation = "Exported to \(url.lastPathComponent)"
                    }

                case .authorshipReport:
                    let url = try await Task.detached(priority: .userInitiated) {
                        try ExportService.exportAuthorshipReport(
                            project: proj, authorName: author,
                            checkIns: cis, sources: srcs, artifacts: arts,
                            manuscripts: mss, events: evs,
                            integrityStatus: iStatus, chain: chain)
                    }.value
                    await MainActor.run {
                        isExporting = false
                        exportConfirmation = "Exported to \(url.lastPathComponent)"
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
