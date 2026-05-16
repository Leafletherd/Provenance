import SwiftUI
import AppKit

extension Notification.Name {
    static let connectProjectRequested = Notification.Name("connectProjectRequested")
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
    @State private var promoteState: ProjectState? = nil
    @State private var isPromoting = false
    @State private var showPromoteSheet = false
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
        VStack(spacing: 0) {
            List(selection: selectionBinding) {
                // Home row
                Label {
                    Text("Home")
                        .font(.system(size: 15, weight: .medium))
                } icon: {
                    Image(systemName: "house")
                        .font(.system(size: 12))
                }
                .tag(SidebarItem.home)

                if !appState.projectStates.isEmpty {
                    Section("Projects") {
                        ForEach(appState.projectStates) { state in
                            ProjectRowView(state: state)
                                .tag(SidebarItem.project(state.project.id))
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
                                        Button("Promote to Works\u{2026}") {
                                            promoteState = state
                                            showPromoteSheet = true
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
        }
        .background(
            LinearGradient(
                colors: [Brand.surfaceRaised, Brand.surfaceBase],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationTitle("Provenance")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 4) {
                Button {
                    openFolderPicker()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Connect a project folder")

                Button {
                    if let id = appState.selectedProjectID {
                        projectToRemove = id
                        showRemoveAlert = true
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(appState.isHomeSelected || appState.selectedProjectID == nil)
                .help("Disconnect selected project")

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
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
        .sheet(isPresented: $showPromoteSheet) {
            if let ps = promoteState {
                PromoteConfirmSheet(
                    projectName: ps.project.name,
                    checkInCount: ps.checkIns.filter { $0.exportIncluded }.count,
                    sourceCount:  ps.sources.filter  { $0.exportIncluded }.count,
                    artifactCount: ps.artifacts.filter { $0.exportIncluded }.count
                ) {
                    showPromoteSheet = false
                    isPromoting = true
                    Task {
                        _ = try? await PromotionService.promote(state: ps)
                        await MainActor.run { isPromoting = false }
                    }
                } onCancel: {
                    showPromoteSheet = false
                }
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

    private var isMissing: Bool { !state.resolutionStatus.isAccessible }

    private var missingSubtext: String? {
        switch state.resolutionStatus {
        case .volumeUnmounted(let vol): return "On \u{201C}\(vol)\u{201D} \u{2014} not connected."
        case .notFound:                 return "Folder couldn\u{2019}t be found."
        default:                        return nil
        }
    }

    var body: some View {
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
        }
        .padding(.vertical, 4)
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
