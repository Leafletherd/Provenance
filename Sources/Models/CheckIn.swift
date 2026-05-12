import Foundation
import AppKit

enum CheckInStatus: String, Codable, CaseIterable {
    case working, stuck, breakthrough, paused, done

    var label: String {
        rawValue.capitalized
    }

    var color: NSColor {
        switch self {
        case .working: return .systemBlue
        case .stuck: return .systemOrange
        case .breakthrough: return .systemGreen
        case .paused: return .systemGray
        case .done: return .systemPurple
        }
    }
}

struct CheckIn: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var status: CheckInStatus
    var text: String
    var exportIncluded: Bool

    init(id: UUID = UUID(), timestamp: Date = Date(), status: CheckInStatus, text: String, exportIncluded: Bool = true) {
        self.id = id
        self.timestamp = timestamp
        self.status = status
        self.text = text
        self.exportIncluded = exportIncluded
    }
}
