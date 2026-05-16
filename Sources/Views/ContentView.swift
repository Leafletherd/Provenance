import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    // Hover states for pill buttons (must live at View level — @State requires a View)
    @State private var homeHovering    = false
    @State private var connectHovering = false

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
        // §5b — toolbar background = surfaceBase so the floating pill reads as elevated over it.
        // .visible forces the background to render even when the toolbar has no title.
        // This also eliminates the old-chrome flash-back: the background is now always explicit.
        .toolbarBackground(Brand.surfaceBase, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        // App-level toolbar — always visible regardless of which pane is active.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                pill
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

    // MARK: - Floating pill (§5b)
    //
    // Capsule containing:   [house icon] | [Connect Project (accent label-action)]
    // Background: Brand.surfaceFloating (white / #3A352C dark).
    // Border: 0.5px Brand.border.
    // Icons get circular Brand.surfaceHover on hover (§5c).
    // Label-action gets capsule Brand.surfaceHover on hover (§5c).

    private var pill: some View {
        HStack(spacing: 6) {

            // Home icon — circular hover
            Button {
                appState.isHomeSelected = true
                appState.selectedProjectID = nil
            } label: {
                Image(systemName: "house")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Brand.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(homeHovering ? Brand.surfaceHover : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { homeHovering = $0 }
            .help("Go to Home")

            // Internal vertical divider
            Rectangle()
                .fill(Brand.border)
                .frame(width: 0.5, height: 16)

            // Connect Project — primary label-action in Brand.textBrand (§5b)
            Button {
                NotificationCenter.default.post(name: .connectProjectRequested, object: nil)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                    Text("Connect Project")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Brand.textBrand)
                .padding(.horizontal, Brand.spaceSM)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(connectHovering ? Brand.surfaceHover : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { connectHovering = $0 }
            .help("Connect Project\u{2026}")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Brand.surfaceFloating)
                .overlay(
                    Capsule().stroke(Brand.border, lineWidth: 0.5)
                )
        )
    }
}
