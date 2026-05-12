import Foundation

enum ArtifactType: String, Codable, CaseIterable {
    case scannedNote = "Scanned Note"
    case image = "Image"
    case audio = "Audio"
    case oldDraft = "Old Draft"
    case other = "Other"
}

struct Artifact: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var type: ArtifactType
    var title: String
    var attachmentFilename: String?
    var caption: String?
    var exportIncluded: Bool

    init(id: UUID = UUID(), timestamp: Date = Date(), type: ArtifactType, title: String,
         attachmentFilename: String? = nil, caption: String? = nil, exportIncluded: Bool = true) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.title = title
        self.attachmentFilename = attachmentFilename
        self.caption = caption
        self.exportIncluded = exportIncluded
    }
}
