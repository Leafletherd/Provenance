import SwiftUI
import AppKit

// MARK: - Export format

enum ExportFormat: String, CaseIterable {
    case pdf    = "pdf"
    case bundle = "bundle"

    var label: String {
        switch self {
        case .pdf:    return "PDF Report"
        case .bundle: return "Bundle for Works"
        }
    }

    var icon: String {
        switch self {
        case .pdf:    return "doc.richtext"
        case .bundle: return "shippingbox"
        }
    }

    var heading: String {
        switch self {
        case .pdf:    return "PDF Report (.pdf)"
        case .bundle: return "Bundle for Works (.provenance.bundle/)"
        }
    }

    var detail: String {
        switch self {
        case .pdf:
            return "A formatted PDF document covering the full project timeline, check-ins, sources, artifacts, and version summary. Saved inside .ledger/export/."
        case .bundle:
            return "A structured directory at the project root that Works and other tools can detect and use to pre-fill metadata. Includes machine-readable process.json and human-readable markdown files. Re-running overwrites atomically."
        }
    }
}

// MARK: - Sheet

struct ExportSheet: View {
    @ObservedObject var state: ProjectState
    @Binding var isPresented: Bool

    @AppStorage("defaultExportFormat") private var defaultFormatRaw = "pdf"
    @State private var selectedFormat: ExportFormat = .pdf
    @State private var isExporting = false
    @State private var errorMessage: String? = nil
    @State private var showError = false

    private var exportCheckInCount: Int { state.checkIns.filter { $0.exportIncluded }.count }
    private var exportSourceCount: Int  { state.sources.filter  { $0.exportIncluded }.count }
    private var exportArtifactCount: Int { state.artifacts.filter { $0.exportIncluded }.count }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Export Project")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Brand.textPrimary)
                    Text(state.project.name)
                        .font(.system(size: 11))
                        .foregroundColor(Brand.textMuted)
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, Brand.spaceLG)
            .padding(.vertical, Brand.spaceMD)
            .background(Brand.surfaceBase)

            Divider()

            // ── Body ──────────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: Brand.spaceLG) {

                // Format picker row
                HStack(spacing: Brand.spaceMD) {
                    Text("Format")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Brand.textMuted)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { fmt in
                            Text(fmt.label).tag(fmt)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }

                // Format description card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selectedFormat.icon)
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Brand.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedFormat.heading)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Brand.textPrimary)
                            Text(selectedFormat.detail)
                                .font(.system(size: 11))
                                .foregroundColor(Brand.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider()

                    // Curated content counts
                    HStack(spacing: 14) {
                        ExportStatPill(count: exportCheckInCount, label: "check-ins")
                        ExportStatPill(count: exportSourceCount,  label: "sources")
                        ExportStatPill(count: exportArtifactCount, label: "artifacts")
                        Spacer()
                        Text("Only items marked \u{201C}Include in export\u{201D} are included.")
                            .font(.system(size: 10))
                            .foregroundColor(Brand.textMuted)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(Brand.spaceMD)
                .background(Brand.surfaceSunken)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.radiusMd)
                        .stroke(Brand.border, lineWidth: 0.5)
                )
                .cornerRadius(Brand.radiusMd)

                // Action row
                HStack {
                    Spacer()
                    if isExporting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    }
                    Button("Export") { runExport() }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.accent)
                        .disabled(isExporting)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(Brand.spaceLG)
        }
        .frame(width: 560)
        .background(Brand.surfaceBase)
        .onAppear {
            selectedFormat = ExportFormat(rawValue: defaultFormatRaw) ?? .pdf
        }
        .alert("Export Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Export action

    private func runExport() {
        isExporting = true

        // Capture all data on main actor before any background work.
        let proj  = state.project
        let cis   = state.checkIns
        let srcs  = state.sources
        let arts  = state.artifacts
        let snaps = state.snapshots
        let evs   = state.events
        let fmt   = selectedFormat

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
                        isPresented = false
                        defaultFormatRaw = fmt.rawValue
                        NSWorkspace.shared.open(url)
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
                        isPresented = false
                        defaultFormatRaw = fmt.rawValue
                        NSWorkspace.shared.activateFileViewerSelecting([result.url])
                    }
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Stat pill

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
