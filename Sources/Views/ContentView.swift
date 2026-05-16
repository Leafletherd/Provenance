import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .environmentObject(appState)
        } detail: {
            ZStack {
                if appState.isHomeSelected || appState.selectedProjectID == nil {
                    HomeView()
                        .environmentObject(appState)
                } else if let state = appState.selectedState {
                    if state.resolutionStatus.isAccessible {
                        ProjectView(state: state)
                            .environmentObject(appState)
                            .id(state.project.id)
                    } else {
                        MissingProjectView(state: state)
                            .environmentObject(appState)
                            .id(state.project.id)
                    }
                } else {
                    HomeView()
                        .environmentObject(appState)
                }

                // Toast overlay — fires from AppState.showToast(_:)
                if let msg = appState.toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(8)
                            .padding(.bottom, 24)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    .animation(.easeInOut(duration: 0.25), value: appState.toastMessage)
                }
            }
        }
        // App-level toolbar — always visible regardless of which pane is active.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                toolbarGroup
            }
        }
        // provenance://open?path=… for a folder not yet connected
        .alert("Connect Project?", isPresented: Binding(
            get:  { appState.pendingConnectURL != nil },
            set:  { if !$0 { appState.pendingConnectURL = nil } }
        )) {
            Button("Connect") {
                if let url = appState.pendingConnectURL {
                    try? appState.connectProject(at: url)
                }
                appState.pendingConnectURL = nil
            }
            Button("Cancel", role: .cancel) {
                appState.pendingConnectURL = nil
            }
        } message: {
            if let url = appState.pendingConnectURL {
                Text("Connect \u{201C}\(url.lastPathComponent)\u{201D} to Provenance?\n\n\(url.path)")
            }
        }
    }

    // MARK: - Toolbar group
    //
    // House → Home | divider | + Connect Project
    // Mirrors Works' panel-toggle group pattern: HStack(spacing:0) with
    // 1pt Rectangle dividers and .plain button style throughout.

    private var toolbarGroup: some View {
        HStack(spacing: 0) {

            // House — navigate to Home view
            Button {
                appState.isHomeSelected = true
                appState.selectedProjectID = nil
            } label: {
                Image(systemName: "house")
                    .font(.system(size: 13))
                    .foregroundColor(Brand.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Go to Home")

            // Vertical divider
            Rectangle()
                .fill(Brand.border.opacity(0.5))
                .frame(width: 1, height: 16)
                .padding(.horizontal, Brand.spaceSM)

            // Connect Project
            Button {
                NotificationCenter.default.post(name: .connectProjectRequested, object: nil)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                    Text("Connect Project")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Brand.accent)
                .padding(.horizontal, Brand.spaceXS)
            }
            .buttonStyle(.plain)
            .help("Connect Project\u{2026}")
        }
        .padding(.horizontal, Brand.spaceSM)
    }
}
