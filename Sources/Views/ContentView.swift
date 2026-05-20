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
                // PR-23 §A: paint surfaceBase up through the title bar in the
                // body column — mirrors the sidebar column's surfaceSidebar
                // ignoresSafeArea, so the two columns meet at the column boundary
                // with no white toolbar band on top.
                Brand.surfaceBase
                    .ignoresSafeArea()

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
        // PR-20 §B — prov/accent tint propagates to all .borderedProminent buttons and
        // system UI tint throughout the app, replacing system blue.
        .tint(Brand.accent)
        // PR-23 §A: no global .toolbarBackground — that would override the
        // per-column surfaceSidebar / surfaceBase backgrounds painted up through
        // the title bar by .ignoresSafeArea() on each column, producing a seam
        // between the title bar and the sidebar tan. NSWindow.titlebarAppearsTransparent
        // = true (set in ProvenanceWindowConfigurator) lets each column show through.
        // Title bar is transparent (set in ProvenanceWindowConfigurator below) so each
        // column's own background paints through it — body shows surfaceBase tan,
        // sidebar shows surfaceSidebar white.
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
        // PR-22 follow-up: window background = surfaceBase (cream) so toolbar,
        // tab bar, and body all share one continuous surface — no green-tinted band.
        window.backgroundColor = NSColor(Brand.surfaceBase)

        // PR-22 §B2: remove the baseline separator the NSToolbar draws under
        // itself. showsBaselineSeparator is deprecated on macOS 15 but still
        // the correct call on 13–14. titlebarSeparatorStyle = .none covers 12+.
        window.toolbar?.showsBaselineSeparator = false

        // PR-22 §B3: force a toolbar layout pass on the next tick so the
        // toolbarBackground applied at App level propagates before the first
        // frame is drawn. Prevents the white-band flash seen on initial mount.
        DispatchQueue.main.async {
            window.toolbar?.validateVisibleItems()
            window.layoutIfNeeded()
        }
    }
}
