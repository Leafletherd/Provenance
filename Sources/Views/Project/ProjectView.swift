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
        ZStack(alignment: .leading) {
            // PR-27 §A — Seed bench chrome pattern. The title-bar area above
            // ProjectView already shows a HARD vertical seam (sidebar tan vs
            // detail-column cream painted via ignoresSafeArea in ContentView),
            // which is exactly what Seed's bench shows. Below the title bar
            // — where ProjectView lives — a narrow gradient strip at the
            // leading edge softens the seam between the sidebar tan and the
            // body cream. 24pt was tuned to match Seed's bench by eye.
            LinearGradient(
                colors: [Brand.surfaceSidebar, Brand.surfaceBase],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // ── Tab bar (PR-26 §B carried forward) ───────────────────
                // Vertical padding symmetric so the chip labels sit
                // equidistant from top/bottom; no background — the leading
                // gradient strip shows through behind the leftmost tabs.
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
        }   // close ZStack
    }       // close body
}           // close struct ProjectView

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
