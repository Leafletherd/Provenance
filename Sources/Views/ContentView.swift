import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .environmentObject(appState)
                // Apple-Mail-style sidebar width — ~200pt typical, 180 min, 320 max.
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
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
        // Title bar is transparent (set in ProvenanceWindowConfigurator below) so each
        // column's own background paints through it — body shows surfaceBase tan,
        // sidebar shows surfaceSidebar white. The previous `.toolbarBackground(surfaceBase)`
        // painted TAN over the entire title bar including the sidebar column, which is
        // why the sidebar's white kept appearing to start below the title bar.
        // App-level toolbar — always visible regardless of which pane is active.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                pill
            }
        }
        // Window-level config: hide the title-bar separator hairline (the "shadow"
        // visible at the top of the body) and let the body color show through.
        .background(
            ProvenanceWindowConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
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

    // MARK: - Floating pill (§5b — REV-7)
    //
    // Uses shared FloatingPill component from FloatingPill.swift.
    // Shape, shadow, padding, and fill are all handled by FloatingPill —
    // ContentView only composes the contents.

    private var pill: some View {
        FloatingPill {
            PillIconButton(systemImage: "house") {
                appState.isHomeSelected = true
                appState.selectedProjectID = nil
            }
            PillDivider()
            PillPrimaryAction(systemImage: "plus", label: "Connect Project") {
                NotificationCenter.default.post(name: .connectProjectRequested, object: nil)
            }
        }
        .help("Connect Project\u{2026}")
    }
}

// Makes the title bar transparent and sets the window background to surfaceBase
// so the body's color shows through the title bar over the body region. The
// sidebar column has its own .background(Brand.surfaceSidebar.ignoresSafeArea())
// which paints white through the title bar over the sidebar region.
private struct ProvenanceWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        if #available(macOS 12.0, *) { window.titlebarSeparatorStyle = .none }
        window.titlebarAppearsTransparent = true
        // Per spec § 00: titlebar = surfaceSidebar + 5% app-tint wash. The
        // sidebar column's own .background(surfaceSidebar.ignoresSafeArea())
        // paints through the transparent titlebar for the sidebar region;
        // the body region of the titlebar gets the tinted titlebarBg.
        window.backgroundColor = NSColor(Brand.titlebarBg)
    }
}
