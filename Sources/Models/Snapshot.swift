import Foundation

enum SnapshotTrigger: String, Codable {
    case auto, scheduled, manual
    var label: String { rawValue.capitalized }
}

struct Snapshot: Identifiable, Codable {
    let id: UUID
    let hash: String
    let timestamp: Date
    let trigger: SnapshotTrigger
    let filesChanged: Int
    var label: String?
    let changedFiles: [String]

    init(id: UUID = UUID(), hash: String, timestamp: Date, trigger: SnapshotTrigger,
         filesChanged: Int, label: String? = nil, changedFiles: [String] = []) {
        self.id = id
        self.hash = hash
        self.timestamp = timestamp
        self.trigger = trigger
        self.filesChanged = filesChanged
        self.label = label
        self.changedFiles = changedFiles
    }
}
