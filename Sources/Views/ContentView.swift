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
    }
}
