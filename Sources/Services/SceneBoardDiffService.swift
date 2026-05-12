import Foundation

// MARK: - Scene Board JSON model
// Matches the .sceneboard file format:
// { "title": "...", "cols": [{"id": "...", "title": "..."}],
//   "cards": [{"id": "...", "col": "...", "title": "...", "note": "...", "color": "...", "links": [...]}] }

private struct SBBoard: Decodable {
    let title: String?
    let cols: [SBCol]
    let cards: [SBCard]
}

private struct SBCol: Decodable {
    let id: String
    let title: String?
}

private struct SBCard: Decodable {
    let id: String
    let col: String?
    let title: String?
    let note: String?
    let color: String?
    // links can be an array of anything — we only care about presence/count
}

// MARK: - Diff result

struct SceneBoardChange {
    enum Kind {
        case cardAdded(title: String, column: String?)
        case cardRemoved(title: String, column: String?)
        case cardMoved(title: String, fromColumn: String?, toColumn: String?)
        case cardRenamed(from: String, to: String)
        case columnAdded(title: String)
        case columnRemoved(title: String)
        case columnRenamed(from: String, to: String)
        case boardRenamed(from: String, to: String)
    }
    let kind: Kind

    var description: String {
        switch kind {
        case .cardAdded(let title, let col):
            if let col { return "Card added: \"\(title)\" \u{2192} \(col)" }
            return "Card added: \"\(title)\""
        case .cardRemoved(let title, let col):
            if let col { return "Card removed: \"\(title)\" from \(col)" }
            return "Card removed: \"\(title)\""
        case .cardMoved(let title, let from, let to):
            let f = from ?? "?"
            let t = to ?? "?"
            return "Card moved: \"\(title)\" \(f) \u{2192} \(t)"
        case .cardRenamed(let from, let to):
            return "Card renamed: \"\(from)\" \u{2192} \"\(to)\""
        case .columnAdded(let title):
            return "Column added: \"\(title)\""
        case .columnRemoved(let title):
            return "Column removed: \"\(title)\""
        case .columnRenamed(let from, let to):
            return "Column renamed: \"\(from)\" \u{2192} \"\(to)\""
        case .boardRenamed(let from, let to):
            return "Board renamed: \"\(from)\" \u{2192} \"\(to)\""
        }
    }
}

// MARK: - Service

enum SceneBoardDiffService {

    // Diff two raw JSON Data blobs and return human-readable change descriptions.
    // Returns an empty array if either file can't be parsed.
    static func diff(old oldData: Data, new newData: Data) -> [SceneBoardChange] {
        guard let oldBoard = try? JSONDecoder().decode(SBBoard.self, from: oldData),
              let newBoard = try? JSONDecoder().decode(SBBoard.self, from: newData)
        else { return [] }

        var changes: [SceneBoardChange] = []

        // Board rename
        let oldTitle = oldBoard.title ?? ""
        let newTitle = newBoard.title ?? ""
        if oldTitle != newTitle && !oldTitle.isEmpty && !newTitle.isEmpty {
            changes.append(.init(kind: .boardRenamed(from: oldTitle, to: newTitle)))
        }

        // Build column lookup by id for both boards
        let oldCols = Dictionary(uniqueKeysWithValues: oldBoard.cols.map { ($0.id, $0.title ?? $0.id) })
        let newCols = Dictionary(uniqueKeysWithValues: newBoard.cols.map { ($0.id, $0.title ?? $0.id) })

        // Column adds / removes / renames (by id)
        for col in newBoard.cols {
            if oldCols[col.id] == nil {
                changes.append(.init(kind: .columnAdded(title: col.title ?? col.id)))
            } else if let oldTitle = oldCols[col.id], let newColTitle = col.title, oldTitle != newColTitle {
                changes.append(.init(kind: .columnRenamed(from: oldTitle, to: newColTitle)))
            }
        }
        for col in oldBoard.cols where newCols[col.id] == nil {
            changes.append(.init(kind: .columnRemoved(title: col.title ?? col.id)))
        }

        // Card diffs by id
        let oldCards = Dictionary(uniqueKeysWithValues: oldBoard.cards.map { ($0.id, $0) })
        let newCards = Dictionary(uniqueKeysWithValues: newBoard.cards.map { ($0.id, $0) })

        // Added cards
        for card in newBoard.cards where oldCards[card.id] == nil {
            let colName = card.col.flatMap { newCols[$0] }
            changes.append(.init(kind: .cardAdded(title: card.title ?? card.id, column: colName)))
        }

        // Removed cards
        for card in oldBoard.cards where newCards[card.id] == nil {
            let colName = card.col.flatMap { oldCols[$0] }
            changes.append(.init(kind: .cardRemoved(title: card.title ?? card.id, column: colName)))
        }

        // Moved / renamed cards
        for newCard in newBoard.cards {
            guard let oldCard = oldCards[newCard.id] else { continue }
            let displayName = newCard.title ?? newCard.id

            // Rename
            if let oldT = oldCard.title, let newT = newCard.title, oldT != newT {
                changes.append(.init(kind: .cardRenamed(from: oldT, to: newT)))
            }

            // Move (column changed)
            if oldCard.col != newCard.col {
                let fromCol = oldCard.col.flatMap { oldCols[$0] }
                let toCol   = newCard.col.flatMap { newCols[$0] }
                changes.append(.init(kind: .cardMoved(title: displayName, fromColumn: fromCol, toColumn: toCol)))
            }
        }

        return changes
    }

    // Convenience: read two files from disk and diff them.
    static func diff(old oldURL: URL, new newURL: URL) -> [SceneBoardChange] {
        guard let oldData = try? Data(contentsOf: oldURL),
              let newData = try? Data(contentsOf: newURL)
        else { return [] }
        return diff(old: oldData, new: newData)
    }
}
