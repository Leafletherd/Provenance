import SwiftUI

// Read-only sheet — 480 wide — shown when the user clicks a seedPromoted ledger event.
// Decodes the SeedEntry from the event's metadata side-file and renders each history
// entry as a vertical timeline.

struct SeedTimelineView: View {
    let event: LedgerEvent
    @Environment(\.dismiss) var dismiss

    private var seed: SeedTraceIngestor.SeedEntry? {
        guard let data = event.metadata else { return nil }
        return try? JSONDecoder().decode(SeedTraceIngestor.SeedEntry.self, from: data)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Brand.textBrand)
                        Text(seed?.title ?? "Seed History")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Brand.textPrimary)
                    }
                    if let path = seed?.originalGardenPath {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundColor(Brand.textMuted)
                            .lineLimit(1)
                    }
                    if let col = seed?.destinationColumn {
                        TypeBadge(label: col, color: Brand.textBrand)
                    }
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, Brand.spaceLG)
            .padding(.vertical, Brand.spaceMD)
            .background(Brand.surfaceBase)

            Divider()

            if let seed, !seed.history.isEmpty {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(seed.history.enumerated()), id: \.offset) { idx, entry in
                            SeedTimelineRow(
                                entry: entry,
                                isLast: idx == seed.history.count - 1
                            )
                        }
                    }
                    .padding(.horizontal, Brand.spaceLG)
                    .padding(.vertical, Brand.spaceMD)
                }
            } else {
                EmptyStateView(
                    message: "No history recorded for this seed.",
                    systemImage: "clock.badge.questionmark"
                )
            }
        }
        .frame(width: 480, height: 440)
        .background(Brand.surfaceBase)
    }
}

// MARK: - Timeline row

private struct SeedTimelineRow: View {
    let entry: SeedTraceIngestor.HistoryEntry
    let isLast: Bool

    private var parsedDate: Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: entry.date) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: entry.date)
    }

    private let displayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var actionColor: Color {
        switch entry.action {
        case "plant":      return Brand.accent
        case "promote":    return Brand.statusBreakthrough
        case "transplant": return Brand.statusBreakthrough
        case "prune":      return Brand.statusStuck
        case "merge":      return Brand.statusDone
        case "split":      return Brand.statusStuck
        case "rename":     return Brand.textMuted
        case "auto":       return Brand.textMuted
        default:           return Brand.textMuted
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Spine
            VStack(spacing: 0) {
                Circle()
                    .fill(actionColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                if !isLast {
                    Rectangle()
                        .fill(Brand.border)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 3)
                }
            }
            .frame(width: 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TypeBadge(label: entry.action, color: actionColor)
                    Text(entry.hash)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Brand.textMuted)
                }
                Text(entry.message)
                    .font(.system(size: 13))
                    .foregroundColor(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = parsedDate {
                    Text(displayFmt.string(from: date))
                        .font(.system(size: 11))
                        .foregroundColor(Brand.textMuted)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }
}
