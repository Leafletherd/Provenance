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
                // PR-28 §B — toolbar background applied at App/Scene root so
                // sidebar-toggle re-layouts don't flip the header chrome. The
                // band is TAN (surfaceSidebar) across the FULL window width;
                // the cream (surfaceBase) lives only in the body region below
                // the toolbar in the detail column.
                .toolbarBackground(Brand.surfaceSidebar, for: .windowToolbar)
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
