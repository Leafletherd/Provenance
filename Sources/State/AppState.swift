import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var projectStates: [ProjectState] = []
    @Published var selectedProjectID: UUID? = nil

    private let store = ProjectStore()

    var selectedState: ProjectState? {
        projectStates.first { $0.project.id == selectedProjectID }
    }

    // MARK: - Launch

    func onLaunch() {
        for project in store.projects {
            let state = ProjectState(project: project)
            state.loadData()
            state.startWatching()
            // Refresh nested-repo excludes on every launch so repos cloned into the
            // project while Provenance was closed get excluded immediately.
            state.refreshNestedExcludes()
            projectStates.append(state)
            checkForFolderMove(state: state)
        }
        selectedProjectID = projectStates.first?.project.id

        // Start the global pasteboard observer if paste tracking is globally enabled.
        let globalTracking = UserDefaults.standard.object(forKey: "trackPasteSources") as? Bool ?? true
        if globalTracking {
            PasteboardObserver.shared.start()
        }
    }

    // MARK: - Connect Project

    func connectProject(at url: URL) {
        let fileCount = LedgerWriter.countProjectFiles(at: url)
        let folderName = url.lastPathComponent

        let project = Project(
            id: UUID(),
            name: folderName,
            folderURL: url,
            connectedAt: Date(),
            lastActivity: Date(),
            medium: nil,
            workingDescription: nil,
            intent: nil
        )

        // Ledger init is fast (just creating directories and files)
        do {
            try LedgerWriter.initializeLedger(for: project, fileCount: fileCount)
        } catch {
            print("Ledger init error: \(error)")
        }

        store.add(project)

        let state = ProjectState(project: project)
        state.loadData()
        state.startWatching()
        projectStates.append(state)
        selectedProjectID = project.id

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
            selectedProjectID = projectStates.first?.project.id
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

    // MARK: - Update Project in Store

    func updateProject(_ project: Project) {
        store.update(project)
        if let idx = projectStates.firstIndex(where: { $0.project.id == project.id }) {
            projectStates[idx].updateProject(project)
        }
    }
}
