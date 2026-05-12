import Foundation

enum SourceType: String, Codable, CaseIterable {
    case url = "url"
    case localFile = "local_file"
    case quotedPassage = "passage"

    var label: String {
        switch self {
        case .url: return "URL"
        case .localFile: return "Local File"
        case .quotedPassage: return "Quoted Passage"
        }
    }
}

struct Source: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var type: SourceType
    var title: String
    var urlString: String?
    var filePath: String?
    var passage: String?
    var annotation: String?
    var exportIncluded: Bool

    init(id: UUID = UUID(), timestamp: Date = Date(), type: SourceType, title: String,
         urlString: String? = nil, filePath: String? = nil, passage: String? = nil,
         annotation: String? = nil, exportIncluded: Bool = true) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.title = title
        self.urlString = urlString
        self.filePath = filePath
        self.passage = passage
        self.annotation = annotation
        self.exportIncluded = exportIncluded
    }
}
