import SwiftUI

@main
struct ProvenanceApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appState.onLaunch()
                }
                .onOpenURL { url in
                    appState.handleURL(url)
                }
                // PR-22 §B1 (follow-up): use surfaceBase (plain cream) here and
                // everywhere else so the toolbar, tab bar, and body all share one
                // continuous cream surface — no green-tinted titlebarBg band.
                .toolbarBackground(Brand.surfaceBase, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
        }
        // §5a: default 1100×720 on first launch; SwiftUI persists user-resize automatically
        .defaultSize(width: 1100, height: 720)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Connect Project Folder…") {
                    NotificationCenter.default.post(name: .connectProjectRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
