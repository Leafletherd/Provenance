import SwiftUI

struct LedgerView: View {
    @ObservedObject var state: ProjectState
    @State private var selectedFilter: LedgerEventType? = nil

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
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            state.reloadEvents()
        }
    }
}

struct LedgerEventRowView: View {
    let event: LedgerEvent
    let displayFmt: DateFormatter

    var eventColor: Color {
        switch event.type {
        case .projectConnected: return .green
        case .fileSaved: return .blue
        case .snapshotAuto: return .blue.opacity(0.7)
        case .snapshotScheduled: return .orange
        case .snapshotManual: return .green
        case .checkin: return .purple
        case .sourceAdded: return .teal
        case .artifactAdded: return .indigo
        case .folderMoved: return .yellow
        case .projectDisconnected: return .gray
        case .githubSync: return .mint
        case .sceneBoardChange: return Brand.accent.opacity(0.85)
        case .error: return .red
        }
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
                        .foregroundColor(.secondary)
                }
                Text(event.detail)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
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
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}
