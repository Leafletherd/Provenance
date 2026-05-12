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

    var ledgerURL: URL { folderURL.appendingPathComponent(".ledger") }
    var snapshotsURL: URL { ledgerURL.appendingPathComponent("snapshots") }
    var attachmentsURL: URL { ledgerURL.appendingPathComponent("attachments") }
    var exportURL: URL { ledgerURL.appendingPathComponent("export") }
    var ledgerMDURL: URL { ledgerURL.appendingPathComponent("ledger.md") }
    var checkinsMDURL: URL { ledgerURL.appendingPathComponent("checkins.md") }
    var sourcesMDURL: URL { ledgerURL.appendingPathComponent("sources.md") }
    var artifactsMDURL: URL { ledgerURL.appendingPathComponent("artifacts.md") }
    var manifestURL: URL { ledgerURL.appendingPathComponent("manifest.json") }
}
