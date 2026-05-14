import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .environmentObject(appState)
        } detail: {
            if let state = appState.selectedState {
                ProjectView(state: state)
                    .environmentObject(appState)
                    .id(state.project.id)
            } else {
                EmptyStateView(message: "Select or connect a project")
            }
        }
        // provenance://open?path=… for a folder not yet connected
        .alert("Connect Project?", isPresented: Binding(
            get:  { appState.pendingConnectURL != nil },
            set:  { if !$0 { appState.pendingConnectURL = nil } }
        )) {
            Button("Connect") {
                if let url = appState.pendingConnectURL {
                    appState.connectProject(at: url)
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
