import Foundation
import SwiftUI

/// Deep-link actions dispatched by the `provenance://` URL scheme handler.
enum DeepLinkAction: Equatable {
    /// Select a named tab inside the project with the given ID.
    case selectTab(projectID: UUID, tab: ProjectTab)
}

@MainActor
class AppState: ObservableObject {
    @Published var projectStates: [ProjectState] = []
    @Published var selectedProjectID: UUID? = nil
    /// True when the Home row is selected in the sidebar (default at launch).
    @Published var isHomeSelected: Bool = true
    /// Set when `provenance://open?path=` points to an unconnected folder.
    /// The UI observes this and offers a "Connect" confirmation.
    @Published var pendingConnectURL: URL? = nil
    /// Set by the URL scheme handler; consumed by ProjectView to switch tabs.
    @Published var pendingDeepLink: DeepLinkAction? = nil
    /// Transient toast message (auto-clears after 2.5 s). Views show this as an overlay.
    @Published var toastMessage: String? = nil

    let store = ProjectStore()  // internal so MissingProjectView can call store.update

    var selectedState: ProjectState? {
        projectStates.first { $0.project.id == selectedProjectID }
    }

    // MARK: - Launch

    func onLaunch() {
        for project in store.projects {
            let state = ProjectState(project: project)
            projectStates.append(state)

            let fm = FileManager.default
            var isDir: ObjCBool = false
            let pathExists = fm.fileExists(atPath: project.folderURL.path, isDirectory: &isDir)
                          && isDir.boolValue

            if pathExists {
                // Fast path: folder present at the stored location.
                state.resolutionStatus = .found(project.folderURL)
                state.loadData()
                state.startWatching()
                state.refreshNestedExcludes()
                checkForFolderMove(state: state)
                // Manifest projectId migration (idempotent — fast JSON read/write)
                LedgerWriter.migrateManifestProjectId(project: project)
            } else {
                // Folder missing — resolve in background (may involve a directory scan).
                state.resolutionStatus = .notFound  // tentative until scan completes
                let proj = project
                Task.detached(priority: .background) { [weak self, weak state] in
                    guard let self, let state else { return }
                    let result = ProjectLocator.resolve(proj)
                    await MainActor.run { [weak self, weak state] in
                        guard let self, let state else { return }
                        state.resolutionStatus = result
                        if case .foundRelocated(let url, let bm) = result {
                            var updated = proj
                            updated.folderURL      = url
                            updated.folderBookmark = bm
                            state.updateProject(updated)
                            self.store.update(updated)
                            state.loadData()
                            state.startWatching()
                            LedgerWriter.migrateManifestProjectId(project: updated)
                        }
                    }
                }
            }
        }
        // Home is the default landing; no project pre-selected.
        selectedProjectID = nil
        isHomeSelected = true

        // Start the global pasteboard observer if paste tracking is globally enabled.
        let globalTracking = UserDefaults.standard.object(forKey: "trackPasteSources") as? Bool ?? true
        if globalTracking {
            PasteboardObserver.shared.start()
        }
    }

    // MARK: - Connect Project

    /// Connect a project folder. `displayName` is the human-readable name to show in the
    /// sidebar (e.g. the original typed name from NewProjectFolderSheet). Defaults to the
    /// folder's last path component when nil.
    ///
    /// Throws if ledger initialisation fails (e.g. disk full, permissions revoked). Callers
    /// that created the folder themselves should roll it back on error; callers connecting an
    /// existing folder can safely use `try?`.
    func connectProject(at url: URL, displayName: String? = nil) throws {
        let fileCount = LedgerWriter.countProjectFiles(at: url)
        let name = displayName ?? url.lastPathComponent

        // Capture NSURL bookmark for transparent relocation tracking.
        let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // Read any projectId already in the folder's manifest. An existing id means
        // this folder is a previously-tracked Provenance project.
        let manifestProjectId = LedgerWriter.readProjectIdFromManifest(at: url)

        // Section 9: duplicate-projectId guard — if this folder's projectId already
        // maps to an entry in our store, update the existing entry's path/bookmark
        // rather than creating a duplicate.
        if let existingId = manifestProjectId,
           let existingState = projectStates.first(where: { $0.project.projectId == existingId }) {
            var updated = existingState.project
            updated.folderURL      = url
            updated.folderBookmark = bookmark
            existingState.updateProject(updated)
            store.update(updated)
            selectedProjectID = updated.id
            isHomeSelected = false
            showToast("Updated location for \u{201C}\(updated.name)\u{201D}.")
            return
        }

        let project = Project(
            id: UUID(),
            projectId: manifestProjectId ?? UUID().uuidString,
            name: name,
            folderURL: url,
            folderBookmark: bookmark,
            connectedAt: Date(),
            lastActivity: Date()
        )

        // Ledger init is fast (just creating directories and files). Rethrow so callers
        // that created the folder can roll back on failure.
        try LedgerWriter.initializeLedger(for: project, fileCount: fileCount)

        store.add(project)

        let state = ProjectState(project: project)
        state.loadData()
        state.startWatching()
        projectStates.append(state)
        selectedProjectID = project.id
        isHomeSelected = false

        // Git init runs shell subprocesses — must be off the main thread
        Task.detached(priority: .background) { [state] in
            do {
                try GitService.initialize(project: project)
            } catch {
                LedgerWriter.appendEvent(
                    type: .error,
                    detail: "git init failed: \(error.localizedDescription)",
                    to: project
                )
            }
            // Reload snapshots on main after git is ready
            await state.reloadSnapshotsAsync()
        }
    }

    // MARK: - Remove Project

    func removeProject(id: UUID) {
        if let state = projectStates.first(where: { $0.project.id == id }) {
            state.stopWatching()
            LedgerWriter.appendEvent(type: .projectDisconnected, detail: "project disconnected", to: state.project)
        }
        projectStates.removeAll { $0.project.id == id }
        store.remove(id: id)
        if selectedProjectID == id {
            if let next = projectStates.first?.project.id {
                selectedProjectID = next
                isHomeSelected = false
            } else {
                selectedProjectID = nil
                isHomeSelected = true
            }
        }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { [weak self] in
                self?.toastMessage = nil
            }
        }
    }

    // MARK: - Folder Move Check

    func checkForFolderMove(state: ProjectState) {
        if let newURL = LedgerWriter.checkPathMoved(project: state.project) {
            let oldPath = state.project.folderURL.path
            LedgerWriter.appendEvent(
                type: .folderMoved,
                detail: "folder moved from \(oldPath) to \(newURL.path)",
                to: state.project
            )
            var updated = state.project
            updated.folderURL = newURL
            state.updateProject(updated)
            store.update(updated)
        }
    }

    // MARK: - URL scheme (provenance://)

    /// Handles incoming `provenance://` URLs.
    ///
    /// - `provenance://open?path=<encoded-folder-path>`
    ///   Selects the matching project, or sets `pendingConnectURL` so the UI
    ///   can offer a "Connect" confirmation.
    ///
    /// - `provenance://reveal?path=<encoded-file-path>&tab=<tab>`
    ///   Selects the project that contains the file and requests a tab switch.
    func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "provenance",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return }

        let host = url.host?.lowercased() ?? ""
        let queryPath = components.queryItems?.first(where: { $0.name == "path" })?.value

        switch host {

        case "open":
            guard let pathStr = queryPath, !pathStr.isEmpty else { return }
            let folderURL = URL(fileURLWithPath: pathStr)
            if let existing = projectStates.first(where: { $0.project.folderURL == folderURL }) {
                selectedProjectID = existing.project.id
                isHomeSelected = false
                NSApp.activate(ignoringOtherApps: true)
            } else {
                pendingConnectURL = folderURL
                NSApp.activate(ignoringOtherApps: true)
            }

        case "reveal":
            guard let pathStr = queryPath, !pathStr.isEmpty else { return }
            let fileURL    = URL(fileURLWithPath: pathStr)
            let tabStr     = components.queryItems?.first(where: { $0.name == "tab" })?.value ?? "overview"
            let tab        = ProjectTab.allCases.first {
                $0.rawValue.lowercased() == tabStr.lowercased()
            } ?? .overview

            if let state = projectStates.first(where: {
                fileURL.path.hasPrefix($0.project.folderURL.path + "/") ||
                fileURL.path == $0.project.folderURL.path
            }) {
                selectedProjectID = state.project.id
                isHomeSelected    = false
                pendingDeepLink   = .selectTab(projectID: state.project.id, tab: tab)
                NSApp.activate(ignoringOtherApps: true)
            }

        default:
            break
        }
    }

    // MARK: - Update Project in Store

    func updateProject(_ project: Project) {
        store.update(project)
        if let idx = projectStates.firstIndex(where: { $0.project.id == project.id }) {
            projectStates[idx].updateProject(project)
        }
    }
}
