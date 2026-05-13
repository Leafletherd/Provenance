import Foundation

struct Manuscript: Identifiable {

    enum Kind: String, Codable {
        case prose      // .md, .txt, .markdown
        case screenplay // .fountain, .fdx
        case rtf        // .rtf
        case docx       // .docx
        case pages      // .pages

        var displayName: String {
            switch self {
            case .prose:      return "prose"
            case .screenplay: return "screenplay"
            case .rtf:        return "rtf"
            case .docx:       return "docx"
            case .pages:      return "pages"
            }
        }
    }

    /// A single word-count snapshot for sparkline data.
    struct HistoryPoint: Codable {
        let date: Date
        let wordCount: Int
        let pageCount: Int?
    }

    /// Stable identifier — the file's path relative to the project root.
    let id: String
    let path: URL
    /// Display-friendly filename (without path, without extension for long paths).
    let title: String
    /// `nil` when text extraction failed (binary or unsupported format).
    let wordCount: Int?
    /// Screenplays only: estimated pages = ⌈non-empty lines / 55⌉.
    let pageCount: Int?
    let lastModified: Date
    let kind: Kind
    /// Last ≤14 sparkline data points loaded from .ledger/manuscripts/<safeID>.history.json.
    let history: [HistoryPoint]
    /// User-set goal, persisted in .ledger/manuscripts.json. `nil` = no target.
    var targetWordCount: Int?
}
