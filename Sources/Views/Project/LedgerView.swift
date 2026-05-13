import SwiftUI

struct LedgerView: View {
    @ObservedObject var state: ProjectState
    @State private var selectedFilter: LedgerEventType? = nil
    @State private var selectedSeedEvent: LedgerEvent? = nil

    private let displayFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .medium
        return fmt
    }()

    var filteredEvents: [LedgerEvent] {
        if let filter = selectedFilter {
            return state.events.filter { $0.type == filter }
        }
        return state.events
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterButton(label: "All", isSelected: selectedFilter == nil) {
                        selectedFilter = nil
                    }
                    ForEach(LedgerEventType.allCases, id: \.self) { type in
                        FilterButton(label: type.displayName, isSelected: selectedFilter == type) {
                            selectedFilter = (selectedFilter == type) ? nil : type
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
                EmptyStateView(message: selectedFilter != nil
                    ? "No \(selectedFilter!.displayName) events."
                    : "No ledger events yet.")
            } else {
                List {
                    ForEach(filteredEvents) { event in
                        LedgerEventRowView(event: event, displayFmt: displayFmt)
                            .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                            // seedPromoted events with metadata open the timeline sheet.
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if event.type == .seedPromoted && event.metadata != nil {
                                    selectedSeedEvent = event
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
        case .error:               return Color.red
        }
    }

    /// seedPromoted events with metadata are tappable — show a chevron indicator.
    private var isTappable: Bool {
        event.type == .seedPromoted && event.metadata != nil
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
