import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    /// Stable cross-rename / cross-move identity. Assigned once at creation and
    /// written to .ledger/manifest.json as `projectId` (Contract B).
    var projectId: String
    var name: String
    var folderURL: URL
    /// NSURL security-scoped bookmark for transparent folder-relocation tracking.
    /// Nil for projects migrated from pre-PR-10 stores until the bookmark is created.
    var folderBookmark: Data?
    var connectedAt: Date
    var lastActivity: Date
    var medium: String?
    var workingDescription: String?
    var intent: String?
    /// Per-project paste-tracking override. `nil` defers to the global "Track paste sources"
    /// setting in Settings → Privacy. `true`/`false` forces tracking on/off for this project.
    var trackPasteSources: Bool?

    var ledgerURL: URL       { folderURL.appendingPathComponent(".ledger") }
    /// The .provenance.bundle directory written at the project root (outside .ledger/).
    /// Visible to git and to other tools like Works.
    var bundleURL: URL       { folderURL.appendingPathComponent(".provenance.bundle") }
    var snapshotsURL: URL  { ledgerURL.appendingPathComponent("snapshots") }
    var attachmentsURL: URL { ledgerURL.appendingPathComponent("attachments") }
    var exportURL: URL     { ledgerURL.appendingPathComponent("export") }
    /// Structured metadata side-files for ledger events, keyed by event UUID.
    var metadataURL: URL   { ledgerURL.appendingPathComponent("metadata") }
    /// manuscripts.json — maps relative path → target word count (user-set goals).
    var manuscriptsJSONURL: URL  { ledgerURL.appendingPathComponent("manuscripts.json") }
    /// Directory containing per-file sparkline history JSON files.
    var manuscriptHistoryURL: URL { ledgerURL.appendingPathComponent("manuscripts") }
    var ledgerMDURL: URL   { ledgerURL.appendingPathComponent("ledger.md") }
    /// Sidecar holding the integrity chain metadata (SHA256 hash per chained line).
    var chainURL: URL      { ledgerURL.appendingPathComponent("ledger.chain.json") }
    var checkinsMDURL: URL { ledgerURL.appendingPathComponent("checkins.md") }
    var sourcesMDURL: URL  { ledgerURL.appendingPathComponent("sources.md") }
    var artifactsMDURL: URL { ledgerURL.appendingPathComponent("artifacts.md") }
    var manifestURL: URL   { ledgerURL.appendingPathComponent("manifest.json") }

    // MARK: - Memberwise initialiser (with defaults for new fields)

    init(
        id: UUID = UUID(),
        projectId: String = UUID().uuidString,
        name: String,
        folderURL: URL,
        folderBookmark: Data? = nil,
        connectedAt: Date,
        lastActivity: Date,
        medium: String? = nil,
        workingDescription: String? = nil,
        intent: String? = nil,
        trackPasteSources: Bool? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.folderURL = folderURL
        self.folderBookmark = folderBookmark
        self.connectedAt = connectedAt
        self.lastActivity = lastActivity
        self.medium = medium
        self.workingDescription = workingDescription
        self.intent = intent
        self.trackPasteSources = trackPasteSources
    }

    // MARK: - Codable (backward-compatible with pre-PR-10 store entries)

    private enum CodingKeys: String, CodingKey {
        case id, projectId, name, folderURL, folderBookmark
        case connectedAt, lastActivity, medium, workingDescription, intent, trackPasteSources
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try  c.decode(UUID.self, forKey: .id)
        // Pre-PR-10 store entries lack projectId — generate a stable UUID on first decode.
        // ProjectStore.migrateLegacyFields() saves the result immediately so subsequent
        // loads read the persisted value instead of generating a new one each time.
        projectId        = (try? c.decodeIfPresent(String.self, forKey: .projectId)) ?? UUID().uuidString
        name             = try  c.decode(String.self, forKey: .name)
        folderURL        = try  c.decode(URL.self,    forKey: .folderURL)
        folderBookmark   = try? c.decodeIfPresent(Data.self,   forKey: .folderBookmark)
        connectedAt      = try  c.decode(Date.self,   forKey: .connectedAt)
        lastActivity     = try  c.decode(Date.self,   forKey: .lastActivity)
        medium           = try? c.decodeIfPresent(String.self, forKey: .medium)
        workingDescription = try? c.decodeIfPresent(String.self, forKey: .workingDescription)
        intent           = try? c.decodeIfPresent(String.self, forKey: .intent)
        trackPasteSources = try? c.decodeIfPresent(Bool.self,   forKey: .trackPasteSources)
    }
}
