import SwiftUI
import AppKit

enum ProjectTab: String, CaseIterable {
    case overview = "Overview"
    case sources = "Sources"
    case artifacts = "Artifacts"
    case versions = "Versions"
    case checkins = "Check-ins"
    case ledger = "Ledger"
    case export = "Export"
}

struct ProjectView: View {
    @ObservedObject var state: ProjectState
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: ProjectTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            // ── Tab bar (PR-24) ───────────────────────────────────────────
            // PR-24 §A: NO explicit .background on this row — the continuous
            // surfaceBase from ContentView's detail ZStack flows up under and
            // through the tab row, eliminating the visible "header band" the
            // old design produced.
            // PR-24 §B: each tab styled as a pill matching the ArtifactsView
            // filter chip ("All / Seeds / Notes / ..."). The 2pt accent
            // underline is gone — the filled chip is the selection indicator.
            HStack(spacing: Brand.spaceSM) {
                ForEach(ProjectTab.allCases, id: \.self) { tab in
                    TabButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
                Spacer()
            }
            .padding(.horizontal, Brand.spaceLG)
            .padding(.top, Brand.spaceMD)
            .padding(.bottom, Brand.spaceSM)
            // Bottom divider remains — separates the tab row from the body.
            .overlay(
                Rectangle()
                    .fill(Brand.borderSubtle)
                    .frame(height: 0.5),
                alignment: .bottom
            )

            // ── Content ───────────────────────────────────────────────────
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
                case .export:
                    ExportView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // PR-24 §A: no explicit .background on the root VStack either — the
        // ContentView detail ZStack paints surfaceBase up through the title bar
        // continuously, and this view sits transparently on top so there is no
        // band/seam at any column boundary.
        // provenance://reveal?path=…&tab=<tab> — switch to the requested tab.
        .onChange(of: appState.pendingDeepLink) { link in
            guard case let .selectTab(projectID, tab) = link,
                  projectID == state.project.id else { return }
            selectedTab = tab
            appState.pendingDeepLink = nil
        }
    }
}

// MARK: - Tab button — PR-24 chip-pill design

/// Individual tab pill for ProjectView's view-tab bar, matching the
/// `ArtifactFilterChip` ("All / Seeds / Notes / …") design exactly so the
/// two row treatments read as one unified system.
///
/// Styling values mirror ArtifactFilterChip in ArtifactsView.swift:
///   - font: 12pt system, semibold when active
///   - padding: Brand.spaceSM horizontal, 4 vertical
///   - active text: Brand.accent
///   - inactive text: Brand.textSecondary
///   - active bg: Brand.accent.opacity(0.1)
///   - border: 0.5pt — accent@0.4 when active, Brand.border when not
///   - corner radius: Brand.radiusMd (6pt)
private struct TabButton: View {
    let tab: ProjectTab
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Brand.accent : Brand.textSecondary)
                .padding(.horizontal, Brand.spaceSM)
                .padding(.vertical, 4)
                .background(
                    isSelected
                        ? Brand.accent.opacity(0.1)
                        : (hovering ? Brand.surfaceHover : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.radiusMd)
                        .stroke(
                            isSelected ? Brand.accent.opacity(0.4) : Brand.border,
                            lineWidth: 0.5
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: Brand.radiusMd))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
