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
            // ── Tab bar (§6a) ─────────────────────────────────────────────
            // Sits on Brand.surfaceBase (via outer VStack background) so there
            // is no separate white-strip chrome above the body — the tab row
            // blends into the same tan surface as the content panels (§3a.ii).
            // Tab bar — per user directive: titlebar accent wash treatment.
            // Background = titlebarBg (surfaceSidebar + 5% prov-tint per spec § 00).
            // Bottom = 0.5px borderUI hairline to separate from content body.
            HStack(spacing: 0) {
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
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Brand.surfaceBase)
            .overlay(
                Rectangle()
                    .fill(Brand.border)
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
        // §3a.ii — entire VStack (including the tab bar row) sits on surfaceBase
        // so no white strip appears between the toolbar and the tan content body.
        .background(Brand.surfaceBase)
        // provenance://reveal?path=…&tab=<tab> — switch to the requested tab.
        .onChange(of: appState.pendingDeepLink) { link in
            guard case let .selectTab(projectID, tab) = link,
                  projectID == state.project.id else { return }
            selectedTab = tab
            appState.pendingDeepLink = nil
        }
    }
}

// MARK: - Tab button with hover (§5c)

/// Individual tab button for ProjectView's §6a view-tab bar.
/// Gets a RoundedRectangle surfaceHover background on cursor hover (§5c).
private struct TabButton: View {
    let tab: ProjectTab
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(tab.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                // B1 — PR-21: selected tab text uses textPrimary (near-black), not accent green.
                .foregroundColor(isSelected ? Brand.textPrimary : Brand.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Brand.radiusMd)
                        .fill(
                            isSelected
                                // PR-22 §C3: neutral surfaceSelected replaces accentDim
                                // (light green tint) for the selected tab background.
                                ? Brand.surfaceSelected
                                : (hovering ? Brand.surfaceHover : Color.clear)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
