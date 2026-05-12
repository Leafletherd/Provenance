import Foundation
import SwiftUI

@MainActor
class ProjectState: ObservableObject, Identifiable {
    @Published var project: Project
    @Published var checkIns: [CheckIn] = []
    @Published var sources: [Source] = []
    @Published var artifacts: [Artifact] = []
    @Published var snapshots: [Snapshot] = []
    @Published var events: [LedgerEvent] = []
    @Published var isWatching: Bool = false
    @Published var pendingFilesChanged: Bool = false

    nonisolated let id: UUID

    private var watcher: FileWatcher?
    private var scheduledTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?
    // Cache of last-seen .sceneboard file contents, keyed by file URL path.
    // Used to diff SceneBoard changes when the file is modified.
    private var sceneBoardCache: [String: Data] = [:]

    init(project: Project) {
        self.id = project.id
        self.project = project
    }

    // MARK: - Data Loading

    func loadData() {
        // File reads are fast — fine on main thread
        checkIns = LedgerWriter.readCheckIns(from: project)
        sources = LedgerWriter.readSources(from: project)
        artifacts = LedgerWriter.readArtifacts(from: project)
        events = LedgerWriter.readEvents(from: project)
        // git log is a shell process — run off main thread
        let proj = project
        Task.detached(priority: .background) { [weak self] in
            let snaps = (try? GitService.log(project: proj)) ?? []
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.snapshots = snaps
            }
        }
    }

    // Called from AppState after background git init completes
    func reloadSnapshotsAsync() async {
        let proj = project
        let snaps = await Task.detached(priority: .background) {
            (try? GitService.log(project: proj)) ?? []
        }.value
        snapshots = snaps
    }

    // MARK: - Watching

    func startWatching() {
        guard !isWatching else { return }
        // Seed the SceneBoard cache before the watcher starts so the first
        // file-change event has a baseline to diff against.
        seedSceneBoardCache()
        let watcher = FileWatcher(url: project.folderURL) { [weak self] urls in
            self?.handleFileChanged(urls: urls)
        }
        self.watcher = watcher
        watcher.start()
        isWatching = true

        let timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.takeScheduledSnapshot() }
        }
        scheduledTimer = timer
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
        scheduledTimer?.invalidate()
        scheduledTimer = nil
        isWatching = false
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    // MARK: - File Change Handling

    func handleFileChanged(urls: [URL]) {
        debounceWorkItem?.cancel()
        pendingFilesChanged = true
        let changedFile = urls.first?.lastPathComponent ?? "unknown"

        // SceneBoard diff: for any .sceneboard file in the changed set,
        // compare against the cached previous version and log changes immediately.
        for url in urls where url.pathExtension.lowercased() == "sceneboard" {
            diffSceneBoard(at: url)
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.takeAutoSnapshot(changedFile: changedFile) }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    // MARK: - SceneBoard diff

    private func diffSceneBoard(at url: URL) {
        guard let newData = try? Data(contentsOf: url) else { return }
        let key = url.path
        defer { sceneBoardCache[key] = newData }

        guard let oldData = sceneBoardCache[key] else {
            // First time we've seen this file — seed the cache, no diff yet.
            return
        }

        let changes = SceneBoardDiffService.diff(old: oldData, new: newData)
        guard !changes.isEmpty else { return }

        let proj = project
        let filename = url.lastPathComponent
        for change in changes {
            LedgerWriter.appendEvent(
                type: .sceneBoardChange,
                detail: "\(filename): \(change.description)",
                to: proj
            )
        }
        reloadEvents()
    }

    // Seed the SceneBoard cache for all .sceneboard files currently in the
    // project folder so we have a baseline on first watch.
    func seedSceneBoardCache() {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: project.folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let fileURL as URL in enumerator
            where fileURL.pathExtension.lowercased() == "sceneboard" {
            if let data = try? Data(contentsOf: fileURL) {
                sceneBoardCache[fileURL.path] = data
            }
        }
    }

    // MARK: - Snapshots

    func takeAutoSnapshot(changedFile: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let message = "auto: file saved \(changedFile) \(fmt.string(from: Date()))"
        let proj = project
        Task.detached(priority: .background) { [weak self] in
            do {
                if let hash = try GitService.commit(message: message, project: proj) {
                    LedgerWriter.appendEvent(type: .snapshotAuto,
                        detail: "auto snapshot \(hash) — \(changedFile)", to: proj)
                    let snaps = (try? GitService.log(project: proj)) ?? []
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.pendingFilesChanged = false
                        self.snapshots = snaps
                        self.updateLastActivity()
                        self.reloadEvents()
                    }
                }
            } catch {
                LedgerWriter.appendEvent(type: .error,
                    detail: "auto snapshot failed: \(error.localizedDescription)", to: proj)
            }
        }
    }

    func takeScheduledSnapshot() {
        guard pendingFilesChanged else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let message = "scheduled: snapshot \(fmt.string(from: Date()))"
        let proj = project
        Task.detached(priority: .background) { [weak self] in
            do {
                if let hash = try GitService.commit(message: message, project: proj) {
                    LedgerWriter.appendEvent(type: .snapshotScheduled,
                        detail: "scheduled snapshot \(hash)", to: proj)
                    let snaps = (try? GitService.log(project: proj)) ?? []
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.pendingFilesChanged = false
                        self.snapshots = snaps
                        self.updateLastActivity()
                        self.reloadEvents()
                    }
                }
            } catch {
                LedgerWriter.appendEvent(type: .error,
                    detail: "scheduled snapshot failed: \(error.localizedDescription)", to: proj)
            }
        }
    }

    func takeManualSnapshot(label: String?) {
        let labelStr = label.flatMap { $0.isEmpty ? nil : $0 } ?? "manual snapshot"
        let message = "manual: \(labelStr)"
        let proj = project
        Task.detached(priority: .background) { [weak self] in
            do {
                if let hash = try GitService.commit(message: message, project: proj) {
                    LedgerWriter.appendEvent(type: .snapshotManual,
                        detail: "manual snapshot \(hash) — \(labelStr)", to: proj)
                    let snaps = (try? GitService.log(project: proj)) ?? []
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.snapshots = snaps
                        self.updateLastActivity()
                        self.reloadEvents()
                    }
                } else {
                    LedgerWriter.appendEvent(type: .snapshotManual,
                        detail: "snapshot requested — no changes to capture", to: proj)
                }
            } catch {
                LedgerWriter.appendEvent(type: .error,
                    detail: "manual snapshot failed: \(error.localizedDescription)", to: proj)
            }
        }
    }

    // MARK: - Check-ins

    func addCheckIn(_ checkIn: CheckIn) {
        checkIns.append(checkIn)
        try? LedgerWriter.writeCheckIns(checkIns, to: project)
        LedgerWriter.appendEvent(type: .checkin,
            detail: "[\(checkIn.status.label)] \(String(checkIn.text.prefix(60)))", to: project)
        updateLastActivity()
        reloadEvents()
    }

    func updateCheckIn(_ checkIn: CheckIn) {
        if let idx = checkIns.firstIndex(where: { $0.id == checkIn.id }) {
            checkIns[idx] = checkIn
            try? LedgerWriter.writeCheckIns(checkIns, to: project)
        }
    }

    func deleteCheckIn(id: UUID) {
        checkIns.removeAll { $0.id == id }
        try? LedgerWriter.writeCheckIns(checkIns, to: project)
    }

    // MARK: - Sources

    func addSource(_ source: Source) {
        sources.append(source)
        try? LedgerWriter.writeSources(sources, to: project)
        LedgerWriter.appendEvent(type: .sourceAdded,
            detail: "\(source.type.label): \(source.title)", to: project)
        updateLastActivity()
        reloadEvents()
    }

    func deleteSource(id: UUID) {
        sources.removeAll { $0.id == id }
        try? LedgerWriter.writeSources(sources, to: project)
        reloadEvents()
    }

    func updateSource(_ source: Source) {
        if let idx = sources.firstIndex(where: { $0.id == source.id }) {
            sources[idx] = source
            try? LedgerWriter.writeSources(sources, to: project)
        }
    }

    // MARK: - Artifacts

    func addArtifact(_ artifact: Artifact, from sourceURL: URL?) {
        var updatedArtifact = artifact
        if let sourceURL = sourceURL {
            let fm = FileManager.default
            try? fm.createDirectory(at: project.attachmentsURL, withIntermediateDirectories: true)
            let dest = project.attachmentsURL.appendingPathComponent(sourceURL.lastPathComponent)
            try? fm.copyItem(at: sourceURL, to: dest)
            updatedArtifact = Artifact(
                id: artifact.id,
                timestamp: artifact.timestamp,
                type: artifact.type,
                title: artifact.title,
                attachmentFilename: sourceURL.lastPathComponent,
                caption: artifact.caption,
                exportIncluded: artifact.exportIncluded
            )
        }
        artifacts.append(updatedArtifact)
        try? LedgerWriter.writeArtifacts(artifacts, to: project)
        LedgerWriter.appendEvent(type: .artifactAdded,
            detail: "\(updatedArtifact.type.rawValue): \(updatedArtifact.title)", to: project)
        updateLastActivity()
        reloadEvents()
    }

    func deleteArtifact(id: UUID) {
        artifacts.removeAll { $0.id == id }
        try? LedgerWriter.writeArtifacts(artifacts, to: project)
        reloadEvents()
    }

    func updateArtifact(_ artifact: Artifact) {
        if let idx = artifacts.firstIndex(where: { $0.id == artifact.id }) {
            artifacts[idx] = artifact
            try? LedgerWriter.writeArtifacts(artifacts, to: project)
        }
    }

    // MARK: - Project

    func updateProject(_ updated: Project) {
        project = updated
    }

    // MARK: - Events

    func reloadEvents() {
        events = LedgerWriter.readEvents(from: project)
    }

    // MARK: - Export

    func export() throws -> URL {
        return try ExportService.export(
            project: project,
            checkIns: checkIns,
            sources: sources,
            artifacts: artifacts,
            snapshots: snapshots,
            events: events
        )
    }

    // MARK: - Private

    private func updateLastActivity() {
        project.lastActivity = Date()
    }
}
