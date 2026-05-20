import SwiftUI
import AppKit

extension Notification.Name {
    static let connectProjectRequested = Notification.Name("connectProjectRequested")
}

// Walks up the view hierarchy and forces the sidebar's NSVisualEffectView
// (the translucent material macOS paints in the sidebar column) into an
// inactive .windowBackground state — letting SwiftUI's .background fill in.
private struct SidebarMaterialKiller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var v: NSView? = nsView
            while let current = v {
                if let effect = current as? NSVisualEffectView {
                    effect.material = .windowBackground
                    effect.state = .inactive
                    effect.blendingMode = .behindWindow
                }
                v = current.superview
            }
        }
    }
}

// MARK: - Sidebar selection model

enum SidebarItem: Hashable {
    case home
    case project(UUID)
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showRemoveAlert = false
    @State private var projectToRemove: UUID? = nil
    @State private var renameProjectID: UUID? = nil
    @State private var renameText: String = ""
    @State private var showNewFolderSheet = false

    // Computed binding that maps isHomeSelected + selectedProjectID → SidebarItem
    private var selectionBinding: Binding<SidebarItem?> {
        Binding(
            get: {
                if appState.isHomeSelected { return .home }
                if let id = appState.selectedProjectID { return .project(id) }
                return .home
            },
            set: { item in
                switch item {
                case .home, .none:
                    appState.isHomeSelected = true
                    appState.selectedProjectID = nil
                case .project(let id):
                    appState.isHomeSelected = false
                    appState.selectedProjectID = id
                }
            }
        )
    }

    var body: some View {
        // ZStack lets the surfaceSidebar color paint the ENTIRE sidebar column
        // (including under the title bar / traffic lights) regardless of the
        // safe-area constraints SwiftUI applies to NavigationSplitView columns.
        // Combined with SidebarMaterialKiller (defeats NSVisualEffectView).
        ZStack(alignment: .top) {
            Brand.surfaceSidebar
                .ignoresSafeArea()
            SidebarMaterialKiller()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
            // Explicit top spacer — pushes the List below the title-bar region
            // so the first row ("Home") doesn't sit underneath the traffic lights.
            Color.clear.frame(height: 28)

            List(selection: selectionBinding) {
                // Home row — PR-22: neutral-grey rounded rect (surfaceSelected),
                // dark text. No prov/accent on sidebar rows.
                Label {
                    Text("Home")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Brand.textPrimary)
                } icon: {
                    Image(systemName: "house")
                        .font(.system(size: 12))
                        .foregroundColor(Brand.textSecondary)
                }
                .tag(SidebarItem.home)
                .listRowBackground(
                    Group {
                        if appState.isHomeSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Brand.surfaceSelected)
                                .padding(.horizontal, 4)
                        } else {
                            Color.clear
                        }
                    }
                )

                if !appState.projectStates.isEmpty {
                    Section("Projects") {
                        ForEach(appState.projectStates) { state in
                            ProjectRowView(state: state)
                                .tag(SidebarItem.project(state.project.id))
                                // PR-22: neutral-grey surfaceSelected rounded rect.
                                // Replaces REV-10 prov/accent fill — green accent
                                // is too vivid for sidebar selection in Provenance.
                                .listRowBackground(
                                    Group {
                                        let sel = !appState.isHomeSelected &&
                                                  appState.selectedProjectID == state.project.id
                                        if sel {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Brand.surfaceSelected)
                                                .padding(.horizontal, 4)
                                        } else {
                                            Color.clear
                                        }
                                    }
                                )
                                .contextMenu {
                                    // Missing-state actions at top
                                    if !state.resolutionStatus.isAccessible {
                                        Button("Locate Folder\u{2026}") {
                                            appState.selectedProjectID = state.project.id
                                            appState.isHomeSelected = false
                                        }
                                        Button("Disconnect Project", role: .destructive) {
                                            projectToRemove = state.project.id
                                            showRemoveAlert = true
                                        }
                                    } else {
                                        Button("Reveal in Finder") {
                                            NSWorkspace.shared.activateFileViewerSelecting(
                                                [state.project.folderURL]
                                            )
                                        }
                                        Button("Rename\u{2026}") {
                                            renameText = state.project.name
                                            renameProjectID = state.project.id
                                        }
                                        Button("Open in Works\u{2026}") {
                                            openInWorks(state: state)
                                        }
                                        Divider()
                                        Button("Disconnect Project", role: .destructive) {
                                            projectToRemove = state.project.id
                                            showRemoveAlert = true
                                        }
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            // PR-23 §D: press state must match the settled selection. The List's
            // press highlight uses the inherited .tint() — by default ContentView
            // sets .tint(Brand.accent) (teal-green), which flashes briefly under
            // a mouse-down before our surfaceSelected .listRowBackground paints.
            // Overriding the List's tint to surfaceSelected makes press and
            // settled paint identically — no flicker.
            .tint(Brand.surfaceSelected)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 2) {
                // §5c hover state via shared IconButton
                IconButton(systemImage: "plus", helpText: "Connect a project folder") {
                    openFolderPicker()
                }

                IconButton(
                    systemImage: "minus",
                    helpText: "Disconnect selected project"
                ) {
                    if let id = appState.selectedProjectID {
                        projectToRemove = id
                        showRemoveAlert = true
                    }
                }
                .disabled(appState.isHomeSelected || appState.selectedProjectID == nil)
                .opacity((appState.isHomeSelected || appState.selectedProjectID == nil) ? 0.35 : 1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Brand.surfaceSidebar)
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectProjectRequested)) { _ in
            openFolderPicker()
        }
        .alert("Disconnect Project?", isPresented: $showRemoveAlert) {
            Button("Disconnect", role: .destructive) {
                if let id = projectToRemove {
                    appState.removeProject(id: id)
                }
                projectToRemove = nil
            }
            Button("Cancel", role: .cancel) {
                projectToRemove = nil
            }
        } message: {
            Text("This will disconnect the project from Provenance. Your files and .ledger folder will not be deleted.")
        }
        .sheet(isPresented: Binding(
            get: { renameProjectID != nil },
            set: { if !$0 { renameProjectID = nil } }
        )) {
            RenameProjectSheet(text: $renameText) {
                if let id = renameProjectID {
                    if let state = appState.projectStates.first(where: { $0.project.id == id }) {
                        var updated = state.project
                        updated.name = renameText.trimmingCharacters(in: .whitespaces)
                        if !updated.name.isEmpty {
                            state.updateProject(updated)
                            appState.updateProject(updated)
                        }
                    }
                }
                renameProjectID = nil
            } onCancel: {
                renameProjectID = nil
            }
        }
        // New-folder sub-sheet — presented here so it persists even while the right pane
        // transitions from Home → ProjectView after connect.
        .sheet(isPresented: $showNewFolderSheet) {
            NewProjectFolderSheet { folderURL, displayName in
                showNewFolderSheet = false
                Task { @MainActor in
                    do {
                        // (g) Hand off to the normal connect flow
                        try appState.connectProject(at: folderURL, displayName: displayName)
                    } catch {
                        // (h) Ledger init failed — roll back the newly-created folder so we
                        // don't leave an empty shell on disk, then surface the error.
                        try? FileManager.default.removeItem(at: folderURL)
                        // Re-open the sub-sheet so the user sees what went wrong.
                        // (The sheet re-entry preserves the typed name / location.)
                        showNewFolderSheet = true
                    }
                }
            } onCancel: {
                showNewFolderSheet = false
            }
        }
    }

    // MARK: - Open in Works (PR-26 §F)

    /// Asks Works to open this project folder via the works:// URL scheme.
    /// No bundle is written — Works auto-detects `.ledger/`.
    private func openInWorks(state: ProjectState) {
        let path = state.project.folderURL.path
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        guard let url = URL(string: "works://add?path=\(encoded)") else { return }
        LedgerWriter.appendEvent(
            type: .promotedToWorks,
            detail: "Open in Works — \(state.project.name) (\(path))",
            to: state.project
        )
        state.reloadEvents()
        NSWorkspace.shared.open(url)
    }

    // MARK: - Folder picker

    private func openFolderPicker() {
        ConnectProjectFlow.openPanel(
            didRequestCreate: {
                // User wants to create a new folder — dismiss panel (already done) and
                // show the sub-sheet from this view, which is always in the hierarchy.
                showNewFolderSheet = true
            },
            onConnect: { url in
                Task { @MainActor in
                    try? appState.connectProject(at: url)
                }
            }
        )
    }
}

// MARK: - Project row

struct ProjectRowView: View {
    @ObservedObject var state: ProjectState
    @EnvironmentObject var appState: AppState

    private var isMissing: Bool { !state.resolutionStatus.isAccessible }
    private var isSelected: Bool {
        !appState.isHomeSelected && appState.selectedProjectID == state.project.id
    }

    private var missingSubtext: String? {
        switch state.resolutionStatus {
        case .volumeUnmounted(let vol): return "On \u{201C}\(vol)\u{201D} \u{2014} not connected."
        case .notFound:                 return "Folder couldn\u{2019}t be found."
        default:                        return nil
        }
    }

    var body: some View {
        // PR-22: selection bg is a neutral-grey surfaceSelected rounded rect (via
        // .listRowBackground in SidebarView). Text stays dark on the grey bg —
        // no cream flip needed. Status dot stays semantic (accent / muted).
        HStack(alignment: .center, spacing: 10) {
            if isMissing {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundColor(Brand.statusStuck)
            } else {
                Circle()
                    .fill(state.isWatching ? Brand.accent : Brand.textMuted)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(state.project.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(isMissing ? Brand.textMuted : Brand.textPrimary)

                Text(state.project.folderURL.lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundColor(Brand.textMuted)
                    .lineLimit(1)

                if let sub = missingSubtext {
                    Text(sub)
                        .font(.system(size: 10).italic())
                        .foregroundColor(Brand.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        // PR-22: selection background handled entirely by .listRowBackground in
        // SidebarView — neutral-grey surfaceSelected RoundedRectangle.
    }
}

// MARK: - Rename sheet

struct RenameProjectSheet: View {
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Project")
                .font(.system(size: 18, weight: .semibold))

            TextField("Display name", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { if !text.trimmingCharacters(in: .whitespaces).isEmpty { onSave() } }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { onSave() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear { focused = true }
    }
}
