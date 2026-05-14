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
            .listStyle(.sidebar)
        }
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
    }

    // MARK: - Folder picker

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Connect Project Folder"
        panel.message = "Choose the folder you want to track with Provenance."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in
                    appState.connectProject(at: url)
                }
            }
        }
    }
}

// MARK: - Project row

struct ProjectRowView: View {
    @ObservedObject var state: ProjectState

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(state.isWatching ? Brand.accent : Brand.textMuted)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.project.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(state.project.folderURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(state.project.lastActivity, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
                .font(.headline)

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
