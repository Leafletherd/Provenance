import SwiftUI

// MARK: - Filter model

/// Logical filter groups shown in the LedgerView chip bar.
enum LedgerFilter: Hashable {
    case all
    case pastes
    case snapshots
    case checkIns
    case sources
    case other

    var label: String {
        switch self {
        case .all:       return "All"
        case .pastes:    return "Pastes"
        case .snapshots: return "Snapshots"
        case .checkIns:  return "Check-ins"
        case .sources:   return "Sources"
        case .other:     return "Other"
        }
    }

    func matches(_ type: LedgerEventType) -> Bool {
        switch self {
        case .all:       return true
        case .pastes:    return type == .paste
        case .snapshots: return [.snapshotAuto, .snapshotScheduled, .snapshotManual].contains(type)
        case .checkIns:  return type == .checkin
        case .sources:   return type == .sourceAdded
        case .other:     return ![.paste, .snapshotAuto, .snapshotScheduled, .snapshotManual,
                                   .checkin, .sourceAdded].contains(type)
        }
    }
}

// MARK: - LedgerView

struct LedgerView: View {
    @ObservedObject var state: ProjectState
    @State private var selectedFilter: LedgerFilter = .all
    @State private var selectedSeedEvent: LedgerEvent? = nil
    @State private var selectedPasteEvent: LedgerEvent? = nil

    private let displayFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .medium
        return fmt
    }()

    var filteredEvents: [LedgerEvent] {
        if selectedFilter == .all { return state.events }
        return state.events.filter { selectedFilter.matches($0.type) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([LedgerFilter.all, .pastes, .snapshots, .checkIns, .sources, .other],
                            id: \.self) { filter in
                        FilterButton(label: filter.label, isSelected: selectedFilter == filter) {
                            selectedFilter = (selectedFilter == filter && filter != .all) ? .all : filter
                        }
                    }
                    Spacer()
                    Button {
                        state.reloadEvents()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            if filteredEvents.isEmpty {
                EmptyStateView(message: selectedFilter == .all
                    ? "No ledger events yet."
                    : "No \(selectedFilter.label.lowercased()) events.")
            } else {
                List {
                    ForEach(filteredEvents) { event in
                        LedgerEventRowView(event: event, displayFmt: displayFmt)
                            .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if event.type == .seedPromoted && event.metadata != nil {
                                    selectedSeedEvent = event
                                } else if event.type == .paste && event.metadata != nil {
                                    selectedPasteEvent = event
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            state.reloadEvents()
        }
        .sheet(item: $selectedSeedEvent) { event in
            SeedTimelineView(event: event)
        }
        .sheet(item: $selectedPasteEvent) { event in
            PasteDetailView(event: event)
        }
    }
}

struct LedgerEventRowView: View {
    let event: LedgerEvent
    let displayFmt: DateFormatter

    var eventColor: Color {
        switch event.type {
        case .projectConnected:    return Brand.statusBreakthrough
        case .fileSaved:           return Brand.textMuted
        case .snapshotAuto:        return Brand.accent.opacity(0.8)
        case .snapshotScheduled:   return Brand.statusStuck
        case .snapshotManual:      return Brand.accent
        case .checkin:             return Color(hex: "5A6480")  // dusty slate
        case .sourceAdded:         return Brand.accent
        case .artifactAdded:       return Color(hex: "5A6480")
        case .folderMoved:         return Brand.statusStuck
        case .projectDisconnected: return Brand.textMuted
        case .githubSync:          return Brand.accent
        case .sceneBoardChange:    return Brand.accent.opacity(0.85)
        case .nestedRepoDetected:  return Brand.statusStuck
        case .seedPromoted:        return Brand.textBrand   // tan-600 — garden/seed themed
        case .paste:               return Color(hex: "7C6F9F")  // muted violet — provenance/origin
        case .bundleExported:      return Brand.accent
        case .error:               return Color.red
        }
    }

    /// seedPromoted and paste events with metadata are tappable — show a chevron indicator.
    private var isTappable: Bool {
        event.metadata != nil && (event.type == .seedPromoted || event.type == .paste)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(eventColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.type.displayName)
                        .font(.caption.bold())
                        .foregroundColor(eventColor)
                    Spacer()
                    Text(displayFmt.string(from: event.timestamp))
                        .font(.caption2)
                        .foregroundColor(Brand.textMuted)
                    if isTappable {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Brand.textMuted)
                    }
                }
                Text(event.detail)
                    .font(.caption)
                    .foregroundColor(Brand.textPrimary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
        .opacity(isTappable ? 1 : 1)   // reserved for future dimming
    }
}

struct FilterButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(isSelected ? .white : Brand.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Brand.accent : Brand.surfaceSunken)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Paste detail sheet

struct PasteDetailView: View {
    let event: LedgerEvent
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    private var meta: PasteMetadata? {
        guard let data = event.metadata else { return nil }
        return try? JSONDecoder().decode(PasteMetadata.self, from: data)
    }

    private let displayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "7C6F9F"))
                        Text("Paste Source")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Brand.textPrimary)
                        if meta?.isAI == true {
                            TypeBadge(label: "AI", color: Color(hex: "7C6F9F"))
                        }
                    }
                    Text(displayFmt.string(from: event.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(Brand.textMuted)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, Brand.spaceLG)
            .padding(.vertical, Brand.spaceMD)
            .background(Brand.surfaceBase)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Brand.spaceMD) {

                    // Source
                    if let meta {
                        PasteDetailRow(label: "Source") {
                            if let url = meta.sourceURL {
                                Button(url.host ?? url.absoluteString) {
                                    openURL(url)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundColor(Brand.accent)
                                .underline()
                            } else if let bundle = meta.sourceBundleID {
                                Text(bundle)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Brand.textPrimary)
                            } else {
                                Text("Unknown")
                                    .font(.system(size: 13))
                                    .foregroundColor(Brand.textMuted)
                            }
                        }

                        PasteDetailRow(label: "App") {
                            Text(meta.sourceBundleID ?? "—")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Brand.textSecondary)
                        }

                        PasteDetailRow(label: "File") {
                            Text(meta.matchedFile)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Brand.textPrimary)
                        }

                        PasteDetailRow(label: "Content") {
                            HStack(spacing: 8) {
                                TypeBadge(label: meta.kind, color: Brand.textMuted)
                                Text("\(meta.contentLength) bytes")
                                    .font(.system(size: 12))
                                    .foregroundColor(Brand.textMuted)
                            }
                        }

                        // Preview block
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preview")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Brand.textMuted)
                                .textCase(.uppercase)
                            Text("\u{201C}\(meta.contentPreview)\u{2026}\u{201D}")
                                .font(.system(size: 13))
                                .foregroundColor(Brand.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(Brand.spaceSM)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Brand.surfaceSunken)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Brand.radiusMd)
                                        .stroke(Brand.border, lineWidth: 0.5)
                                )
                                .cornerRadius(Brand.radiusMd)
                        }

                        if let hash = meta.snapshotHash {
                            PasteDetailRow(label: "Snapshot") {
                                Text(String(hash.prefix(7)))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(Brand.textMuted)
                            }
                        }
                    } else {
                        Text("Paste metadata unavailable.")
                            .font(.caption)
                            .foregroundColor(Brand.textMuted)
                    }
                }
                .padding(Brand.spaceLG)
            }
        }
        .frame(width: 480, height: 400)
        .background(Brand.surfaceBase)
    }
}

private struct PasteDetailRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Brand.textMuted)
                .textCase(.uppercase)
                .frame(width: 70, alignment: .leading)
            content()
        }
    }
}
