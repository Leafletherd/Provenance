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
}
