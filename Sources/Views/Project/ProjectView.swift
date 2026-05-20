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
        // PR-30 — Three-tone chrome.
        // Header zone (tab bar + the title-bar strip above it via
        // ignoresSafeArea on its background) uses Brand.surfaceSunken — a
        // slightly darker cream than the body. The leading-edge gradient
        // here blends sidebar tan → surfaceSunken.
        // Body zone uses Brand.surfaceBase (lighter cream). Its leading-edge
        // gradient blends sidebar tan → surfaceBase.
        // Each zone is .clipped() so the gradient never bleeds out — that's
        // the Item B fix for the diagonal artifact previously visible
        // behind the Overview tab pill.
        VStack(spacing: 0) {
            // ── Header zone ───────────────────────────────────────────────
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [Brand.surfaceSidebar, Brand.surfaceSunken],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)

                // Tab bar (PR-26 §B: symmetric vertical padding).
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
                .padding(.vertical, Brand.spaceSM)
            }
            // Header bg extends UP through the title bar so the toolbar/pill
            // area also reads as surfaceSunken — the subtle horizontal shift
            // at the tab-bar's bottom edge IS the visible header→body divider
            // (no drawn line).
            .background(Brand.surfaceSunken.ignoresSafeArea(edges: .top))
            .clipped()

            // ── Body zone ─────────────────────────────────────────────────
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [Brand.surfaceSidebar, Brand.surfaceBase],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)

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
            .background(Brand.surfaceBase)
            .clipped()
        }
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
