import Foundation

// MARK: - SceneBoard JSON model

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
}

// MARK: - Change kind

enum SceneBoardChangeKind: String, Codable {
    case cardAdded, cardRemoved, cardMoved, cardRenamed
    case columnAdded, columnRemoved, columnRenamed
    case boardRenamed
}

// MARK: - Change — flat struct, Codable for metadata side-storage

struct SceneBoardChange: Codable {
    let kind: SceneBoardChangeKind
    /// SceneBoard's card id — nil for column/board-level changes.
    let cardId: String?
    /// Card title after any rename; nil for column/board-level changes.
    let cardTitle: String?
    /// Target or current column for add/remove; nil for moves (use fromColumn/toColumn).
    let columnName: String?
    /// Source column for card moves.
    let fromColumn: String?
    /// Destination column for card moves.
    let toColumn: String?
    /// Previous name for renames (card title or column title).
    let oldValue: String?
    /// New name for renames.
    let newValue: String?
    /// Human-readable ledger string — kept for back-compat with the plain-text ledger.
    let description: String
}

// MARK: - Service

enum SceneBoardDiffService {

    /// Diff two raw JSON Data blobs from `.sceneboard` files.
    /// Returns an empty array if either blob can't be parsed.
    static func diff(old oldData: Data, new newData: Data) -> [SceneBoardChange] {
        guard let oldBoard = try? JSONDecoder().decode(SBBoard.self, from: oldData),
              let newBoard = try? JSONDecoder().decode(SBBoard.self, from: newData)
        else { return [] }

        var changes: [SceneBoardChange] = []

        // Board rename
        let oldTitle = oldBoard.title ?? ""
        let newTitle = newBoard.title ?? ""
        if oldTitle != newTitle && !oldTitle.isEmpty && !newTitle.isEmpty {
            changes.append(SceneBoardChange(
                kind: .boardRenamed, cardId: nil, cardTitle: nil,
                columnName: nil, fromColumn: nil, toColumn: nil,
                oldValue: oldTitle, newValue: newTitle,
                description: "Board renamed: \"\(oldTitle)\" \u{2192} \"\(newTitle)\""
            ))
        }

        // Column lookup by id
        let oldCols = Dictionary(uniqueKeysWithValues: oldBoard.cols.map { ($0.id, $0.title ?? $0.id) })
        let newCols = Dictionary(uniqueKeysWithValues: newBoard.cols.map { ($0.id, $0.title ?? $0.id) })

        // Column adds / renames
        for col in newBoard.cols {
            let colName = col.title ?? col.id
            if oldCols[col.id] == nil {
                changes.append(SceneBoardChange(
                    kind: .columnAdded, cardId: nil, cardTitle: nil,
                    columnName: colName, fromColumn: nil, toColumn: nil,
                    oldValue: nil, newValue: nil,
                    description: "Column added: \"\(colName)\""
                ))
            } else if let oldColName = oldCols[col.id], oldColName != colName {
                changes.append(SceneBoardChange(
                    kind: .columnRenamed, cardId: nil, cardTitle: nil,
                    columnName: colName, fromColumn: nil, toColumn: nil,
                    oldValue: oldColName, newValue: colName,
                    description: "Column renamed: \"\(oldColName)\" \u{2192} \"\(colName)\""
                ))
            }
        }

        // Column removes
        for col in oldBoard.cols where newCols[col.id] == nil {
            let colName = col.title ?? col.id
            changes.append(SceneBoardChange(
                kind: .columnRemoved, cardId: nil, cardTitle: nil,
                columnName: colName, fromColumn: nil, toColumn: nil,
                oldValue: nil, newValue: nil,
                description: "Column removed: \"\(colName)\""
            ))
        }

        // Card diffs by id
        let oldCards = Dictionary(uniqueKeysWithValues: oldBoard.cards.map { ($0.id, $0) })
        let newCards = Dictionary(uniqueKeysWithValues: newBoard.cards.map { ($0.id, $0) })

        // Added cards
        for card in newBoard.cards where oldCards[card.id] == nil {
            let title = card.title ?? card.id
            let col = card.col.flatMap { newCols[$0] }
            let desc = col.map { "Card added: \"\(title)\" \u{2192} \($0)" }
                ?? "Card added: \"\(title)\""
            changes.append(SceneBoardChange(
                kind: .cardAdded, cardId: card.id, cardTitle: title,
                columnName: col, fromColumn: nil, toColumn: nil,
                oldValue: nil, newValue: nil,
                description: desc
            ))
        }

        // Removed cards
        for card in oldBoard.cards where newCards[card.id] == nil {
            let title = card.title ?? card.id
            let col = card.col.flatMap { oldCols[$0] }
            let desc = col.map { "Card removed: \"\(title)\" from \($0)" }
                ?? "Card removed: \"\(title)\""
            changes.append(SceneBoardChange(
                kind: .cardRemoved, cardId: card.id, cardTitle: title,
                columnName: col, fromColumn: nil, toColumn: nil,
                oldValue: nil, newValue: nil,
                description: desc
            ))
        }

        // Moved / renamed cards
        for newCard in newBoard.cards {
            guard let oldCard = oldCards[newCard.id] else { continue }
            let newCardTitle = newCard.title ?? newCard.id

            // Rename
            if let oldT = oldCard.title, let newT = newCard.title, oldT != newT {
                changes.append(SceneBoardChange(
                    kind: .cardRenamed, cardId: newCard.id, cardTitle: newT,
                    columnName: newCard.col.flatMap { newCols[$0] },
                    fromColumn: nil, toColumn: nil,
                    oldValue: oldT, newValue: newT,
                    description: "Card renamed: \"\(oldT)\" \u{2192} \"\(newT)\""
                ))
            }

            // Move
            if oldCard.col != newCard.col {
                let fromCol = oldCard.col.flatMap { oldCols[$0] }
                let toCol   = newCard.col.flatMap { newCols[$0] }
                let f = fromCol ?? "?"; let t = toCol ?? "?"
                changes.append(SceneBoardChange(
                    kind: .cardMoved, cardId: newCard.id, cardTitle: newCardTitle,
                    columnName: nil, fromColumn: fromCol, toColumn: toCol,
                    oldValue: nil, newValue: nil,
                    description: "Card moved: \"\(newCardTitle)\" \(f) \u{2192} \(t)"
                ))
            }
        }

        return changes
    }

    static func diff(old oldURL: URL, new newURL: URL) -> [SceneBoardChange] {
        guard let oldData = try? Data(contentsOf: oldURL),
              let newData = try? Data(contentsOf: newURL)
        else { return [] }
        return diff(old: oldData, new: newData)
    }
}
