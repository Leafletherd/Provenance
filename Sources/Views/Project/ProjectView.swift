import SwiftUI
import AppKit

enum ProjectTab: String, CaseIterable {
    case overview = "Overview"
    case sources = "Sources"
    case artifacts = "Artifacts"
    case versions = "Versions"
    case checkins = "Check-ins"
    case ledger = "Ledger"
}

struct ProjectView: View {
    @ObservedObject var state: ProjectState
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: ProjectTab = .overview
    @State private var isExporting = false
    @State private var exportError: String? = nil
    @State private var showExportError = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(ProjectTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundColor(selectedTab == tab ? Brand.accent : Brand.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedTab == tab
                                    ? Brand.accentDim
                                    : Color.clear
                            )
                            .cornerRadius(Brand.radiusMd)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                if isExporting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }

                Button {
                    exportProject()
                } label: {
                    Label("Export", systemImage: "arrow.up.doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isExporting)
                .padding(.trailing, 8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .overview:
                    OverviewView(state: state)
                        .environmentObject(appState)
                case .sources:
                    SourcesView(state: state)
                case .artifacts:
                    ArtifactsView(state: state)
                case .versions:
                    VersionsView(state: state)
                case .checkins:
                    CheckInsView(state: state)
                case .ledger:
                    LedgerView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    private func exportProject() {
        isExporting = true
        Task {
            do {
                let url = try state.export()
                await MainActor.run {
                    isExporting = false
                    NSWorkspace.shared.open(url)
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                    showExportError = true
                }
            }
        }
    }
}
