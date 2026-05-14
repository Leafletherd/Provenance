import Foundation

enum LedgerEventType: String, Codable, CaseIterable {
    case projectConnected    = "project_connected"
    case fileSaved           = "file_saved"
    case snapshotAuto        = "snapshot_auto"
    case snapshotScheduled   = "snapshot_scheduled"
    case snapshotManual      = "snapshot_manual"
    case checkin             = "checkin"
    case sourceAdded         = "source_added"
    case artifactAdded       = "artifact_added"
    case folderMoved         = "folder_moved"
    case projectDisconnected = "project_disconnected"
    case githubSync          = "github_sync"
    case sceneBoardChange    = "sceneboard_change"
    case nestedRepoDetected  = "nested_repo_detected"
    case seedPromoted        = "seed_promoted"
    case paste               = "paste"
    case bundleExported      = "bundle_exported"
    case promotedToWorks     = "promoted_to_works"
    case chainStarted        = "chain_started"
    case chainReset          = "chain_reset"
    case manifestMigrated      = "manifest_migrated"
    case projectsDeduplicated  = "projects_deduplicated"
    case error               = "error"

    var displayName: String {
        switch self {
        case .projectConnected:    return "Project Connected"
        case .fileSaved:           return "File Saved"
        case .snapshotAuto:        return "Auto Snapshot"
        case .snapshotScheduled:   return "Scheduled Snapshot"
        case .snapshotManual:      return "Manual Snapshot"
        case .checkin:             return "Check-in"
        case .sourceAdded:         return "Source Added"
        case .artifactAdded:       return "Artifact Added"
        case .folderMoved:         return "Folder Moved"
        case .projectDisconnected: return "Disconnected"
        case .githubSync:          return "GitHub Sync"
        case .sceneBoardChange:    return "Scene Board"
        case .nestedRepoDetected:  return "Nested Repo"
        case .seedPromoted:        return "Seed Promoted"
        case .paste:               return "Paste Source"
        case .bundleExported:      return "Bundle Exported"
        case .promotedToWorks:     return "Promoted to Works"
        case .chainStarted:        return "Chain Started"
        case .chainReset:          return "Chain Reset"
        case .manifestMigrated:     return "Manifest Migrated"
        case .projectsDeduplicated: return "Projects Deduplicated"
        case .error:                return "Error"
        }
    }
}

struct LedgerEvent: Identifiable {
    let id: UUID
    let timestamp: Date
    let type: LedgerEventType
    let detail: String
    /// Side-stored structured payload — nil for events that pre-date metadata support.
    /// JSON-encoded; schema varies by type (SceneBoardChange, SeedTraceIngestor.SeedEntry, …).
    /// NOT written to ledger.md — persisted alongside it in .ledger/metadata/<id>.json.
    var metadata: Data?

    init(id: UUID = UUID(), timestamp: Date, type: LedgerEventType,
         detail: String, metadata: Data? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.detail = detail
        self.metadata = metadata
    }
}
