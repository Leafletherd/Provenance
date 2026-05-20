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
                // PR-22 §B1: apply toolbar background at the App/Scene root so
                // it takes effect on the FIRST layout pass — not just after a
                // NavigationSplitView re-render triggers re-application. Without
                // this, macOS can display a white toolbar band on initial launch
                // before ContentView's .toolbarBackground fires.
                .toolbarBackground(Brand.titlebarBg, for: .windowToolbar)
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
