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
                // PR-29 — sidebar tan extends up over its OWN column only;
                // the right column is cream from top to bottom. To achieve
                // per-column color in the title bar, the toolbar must NOT
                // paint a global background; transparent titlebar +
                // .ignoresSafeArea() on each column's background does the
                // work. Applied at Scene root so sidebar-toggle re-layouts
                // don't reintroduce a flip (cf. PR-28 §B diagnostic).
                .toolbarBackground(.hidden, for: .windowToolbar)
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
