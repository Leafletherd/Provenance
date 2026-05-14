import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var folderURL: URL
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
}
