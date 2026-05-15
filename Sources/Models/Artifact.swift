import Foundation

enum ArtifactType: String, Codable, CaseIterable {
    case scannedNote  = "Scanned Note"
    case image        = "Image"
    case audio        = "Audio"
    case oldDraft     = "Old Draft"
    case seedHistory  = "Seed History"  // Auto-imported from *.seed-trace.json sidecars
    case other        = "Other"
}

struct Artifact: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var type: ArtifactType
    var title: String
    var attachmentFilename: String?
    var caption: String?
    var exportIncluded: Bool
    /// For `.seedHistory` artifacts: JSON-encoded `SeedTraceIngestor.SeedEntry`.
    /// Decoded in `SeedArtifactDetailSheet` to render the full pre-promotion timeline.
    var seedMetadata: Data?

    init(id: UUID = UUID(), timestamp: Date = Date(), type: ArtifactType, title: String,
         attachmentFilename: String? = nil, caption: String? = nil,
         exportIncluded: Bool = true, seedMetadata: Data? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.title = title
        self.attachmentFilename = attachmentFilename
        self.caption = caption
        self.exportIncluded = exportIncluded
        self.seedMetadata = seedMetadata
    }

    // Custom decoder so that Artifact files written before `seedMetadata` was added
    // still load without errors (decodeIfPresent returns nil for missing key).
    init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try  c.decode(UUID.self,         forKey: .id)
        timestamp      = try  c.decode(Date.self,         forKey: .timestamp)
        type           = try  c.decode(ArtifactType.self, forKey: .type)
        title          = try  c.decode(String.self,       forKey: .title)
        attachmentFilename = try? c.decodeIfPresent(String.self, forKey: .attachmentFilename)
        caption        = try? c.decodeIfPresent(String.self, forKey: .caption)
        exportIncluded = (try? c.decodeIfPresent(Bool.self,   forKey: .exportIncluded)) ?? true
        seedMetadata   = try? c.decodeIfPresent(Data.self,    forKey: .seedMetadata)
    }
}
