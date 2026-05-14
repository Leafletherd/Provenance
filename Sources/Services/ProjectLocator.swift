import Foundation

// MARK: - ProjectLocator

/// Resolves a project's folder after moves, renames, or external-drive disconnection.
///
/// Resolution order:
///   1. NSURL bookmark (handles renames + most moves transparently)
///   2. Stored path exists at the old location (covers no-bookmark legacy projects)
///   3. Volume-unmounted check (external drives, network volumes)
///   4. Local scan of ~/Documents/ up to depth 3 matching projectId
///   5. .notFound
enum ProjectLocator {

    // MARK: - Result

    enum ResolutionResult: Equatable {
        /// Folder found at expected location; no update needed.
        case found(URL)
        /// Folder found but at a new path; caller should persist `newBookmark` + update `folderURL`.
        case foundRelocated(URL, newBookmark: Data)
        /// The volume that holds this project is not currently mounted.
        case volumeUnmounted(volumeName: String)
        /// Could not locate the folder. Show Locate UI.
        case notFound

        static func == (lhs: ResolutionResult, rhs: ResolutionResult) -> Bool {
            switch (lhs, rhs) {
            case (.found(let a), .found(let b)):                 return a == b
            case (.foundRelocated(let a, _), .foundRelocated(let b, _)): return a == b
            case (.volumeUnmounted(let a), .volumeUnmounted(let b)):     return a == b
            case (.notFound, .notFound):                         return true
            default:                                             return false
            }
        }

        /// True when the folder is accessible and ProjectView should be shown.
        var isAccessible: Bool {
            switch self {
            case .found, .foundRelocated: return true
            case .volumeUnmounted, .notFound: return false
            }
        }
    }

    // MARK: - Primary resolution

    /// Synchronous — safe to call from a background queue.
    /// Do not call on the main actor during launch; run via Task.detached.
    static func resolve(_ project: Project) -> ResolutionResult {
        let fm = FileManager.default

        // ── Step 1: Bookmark resolution ────────────────────────────────────────
        if let bookmarkData = project.folderBookmark {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if isStale || url.path != project.folderURL.path {
                        // Bookmark resolved to a different (or stale) path — capture fresh one
                        let fresh = try? url.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                        return .foundRelocated(url, newBookmark: fresh ?? bookmarkData)
                    }
                    return .found(url)
                }
                // Bookmark resolved but directory doesn't exist — fall through.
            }
            // Bookmark resolution failed or folder gone.
        }

        // ── Step 2: Stored path (covers legacy no-bookmark projects) ──────────
        do {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: project.folderURL.path, isDirectory: &isDir), isDir.boolValue {
                return .found(project.folderURL)
            }
        }

        // ── Step 3: Volume-unmounted check ─────────────────────────────────────
        // If the path lives under /Volumes/<name>/ and that mount point is absent,
        // the drive is disconnected — don't waste time scanning.
        let (isUnmounted, volumeName) = volumeStatus(for: project.folderURL)
        if isUnmounted {
            return .volumeUnmounted(volumeName: volumeName)
        }

        // ── Step 4: Local scan ─────────────────────────────────────────────────
        if let found = scanForProjectId(project.projectId) {
            let fresh = try? found.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return .foundRelocated(found, newBookmark: fresh ?? Data())
        }

        return .notFound
    }

    // MARK: - Local scan

    /// Walks ~/Documents/ recursively up to depth 3, matching `.ledger/manifest.json`
    /// projectId entries. Hard deadline: 2.5 s.
    static func scanForProjectId(_ projectId: String) -> URL? {
        let fm = FileManager.default
        let docs = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        guard fm.fileExists(atPath: docs.path) else { return nil }
        let deadline = Date(timeIntervalSinceNow: 2.5)
        return scan(docs, projectId: projectId, depth: 0, deadline: deadline)
    }

    // MARK: - Private helpers

    private static let skipNames: Set<String> = [
        ".git", ".build", ".Trash", "node_modules", "Library",
        ".npm", ".cargo", "Pods", "DerivedData", ".DS_Store",
    ]

    private static func scan(
        _ dir: URL, projectId: String, depth: Int, deadline: Date
    ) -> URL? {
        guard depth <= 3, Date() < deadline else { return nil }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        for entry in entries {
            guard Date() < deadline else { return nil }
            guard !skipNames.contains(entry.lastPathComponent) else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }

            // Check if this folder is a Provenance project with a matching ID
            if let storedId = LedgerWriter.readProjectIdFromManifest(at: entry),
               storedId == projectId {
                return entry
            }

            // Recurse
            if depth < 3,
               let hit = scan(entry, projectId: projectId, depth: depth + 1, deadline: deadline) {
                return hit
            }
        }
        return nil
    }

    /// Checks whether the path lives on an external volume that is currently unmounted.
    /// Returns `(true, volumeName)` when the volume mount point doesn't exist.
    private static func volumeStatus(for url: URL) -> (isUnmounted: Bool, volumeName: String) {
        let components = url.pathComponents
        // External volumes appear as /Volumes/<name>/...
        guard components.count >= 3, components[1] == "Volumes" else {
            return (false, "")
        }
        let volumeName = components[2]
        let mountPoint = URL(fileURLWithPath: "/Volumes/\(volumeName)")
        let mounted = FileManager.default.fileExists(atPath: mountPoint.path)
        return (!mounted, volumeName)
    }
}
