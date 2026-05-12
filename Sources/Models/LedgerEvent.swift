import Foundation

enum LedgerEventType: String, Codable, CaseIterable {
    case projectConnected = "project_connected"
    case fileSaved = "file_saved"
    case snapshotAuto = "snapshot_auto"
    case snapshotScheduled = "snapshot_scheduled"
    case snapshotManual = "snapshot_manual"
    case checkin = "checkin"
    case sourceAdded = "source_added"
    case artifactAdded = "artifact_added"
    case folderMoved = "folder_moved"
    case projectDisconnected = "project_disconnected"
    case githubSync = "github_sync"
    case sceneBoardChange = "sceneboard_change"
    case error = "error"

    var displayName: String {
        switch self {
        case .projectConnected: return "Project Connected"
        case .fileSaved: return "File Saved"
        case .snapshotAuto: return "Auto Snapshot"
        case .snapshotScheduled: return "Scheduled Snapshot"
        case .snapshotManual: return "Manual Snapshot"
        case .checkin: return "Check-in"
        case .sourceAdded: return "Source Added"
        case .artifactAdded: return "Artifact Added"
        case .folderMoved: return "Folder Moved"
        case .projectDisconnected: return "Disconnected"
        case .githubSync: return "GitHub Sync"
        case .sceneBoardChange: return "Scene Board"
        case .error: return "Error"
        }
    }
}

struct LedgerEvent: Identifiable {
    let id: UUID
    let timestamp: Date
    let type: LedgerEventType
    let detail: String

    init(id: UUID = UUID(), timestamp: Date, type: LedgerEventType, detail: String) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.detail = detail
    }
}
