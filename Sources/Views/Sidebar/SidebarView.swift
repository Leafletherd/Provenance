import SwiftUI
import AppKit

extension Notification.Name {
    static let connectProjectRequested = Notification.Name("connectProjectRequested")
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showRemoveAlert = false
    @State private var projectToRemove: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            if appState.projectStates.isEmpty {
                emptyState
            } else {
                projectList
            }
        }
        .navigationTitle("Provenance")
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
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            VStack(spacing: 6) {
                Text("No Projects")
                    .font(.headline)
                Text("Connect a folder to start tracking its writing history.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Button("Connect Project Folder…") {
                openFolderPicker()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Project list

    private var projectList: some View {
        List(selection: Binding(
            get: { appState.selectedProjectID },
            set: { appState.selectedProjectID = $0 }
        )) {
            ForEach(appState.projectStates) { state in
                ProjectRowView(state: state)
                    .tag(state.project.id)
                    .contextMenu {
                        Button("Disconnect Project", role: .destructive) {
                            projectToRemove = state.project.id
                            showRemoveAlert = true
                        }
                    }
            }
        }
        .listStyle(.sidebar)
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
                .disabled(appState.selectedProjectID == nil)
                .help("Disconnect selected project")

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
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

// MARK: - Row

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
