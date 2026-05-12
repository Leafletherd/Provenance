import SwiftUI
import AppKit

struct CheckInsView: View {
    @ObservedObject var state: ProjectState
    @State private var showAddSheet = false
    @State private var editingCheckIn: CheckIn? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Check-ins")
                    .font(.headline)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("New Check-in", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if state.checkIns.isEmpty {
                EmptyStateView(message: "No check-ins yet. Record your working state, breakthroughs, and progress.")
            } else {
                List {
                    ForEach(state.checkIns.reversed()) { checkIn in
                        CheckInCardView(checkIn: checkIn, state: state)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                editingCheckIn = checkIn
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCheckInSheetView { checkIn in
                state.addCheckIn(checkIn)
                showAddSheet = false
            } onCancel: {
                showAddSheet = false
            }
        }
        .sheet(item: $editingCheckIn) { checkIn in
            EditCheckInSheetView(checkIn: checkIn) { updated in
                state.updateCheckIn(updated)
                editingCheckIn = nil
            } onDelete: {
                state.deleteCheckIn(id: checkIn.id)
                editingCheckIn = nil
            } onCancel: {
                editingCheckIn = nil
            }
        }
    }
}

struct CheckInCardView: View {
    var checkIn: CheckIn
    @ObservedObject var state: ProjectState

    private let displayFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(checkIn.status.label)
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(checkIn.status.swiftUIColor)
                    .cornerRadius(4)

                Spacer()

                Text(displayFmt.string(from: checkIn.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(checkIn.text)
                .font(.body)

            Toggle("Include in export", isOn: Binding(
                get: { checkIn.exportIncluded },
                set: { newVal in
                    if let idx = state.checkIns.firstIndex(where: { $0.id == checkIn.id }) {
                        state.checkIns[idx] = CheckIn(
                            id: checkIn.id,
                            timestamp: checkIn.timestamp,
                            status: checkIn.status,
                            text: checkIn.text,
                            exportIncluded: newVal
                        )
                        try? LedgerWriter.writeCheckIns(state.checkIns, to: state.project)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
        }
        .padding(Brand.spaceMD)
        .background(Brand.surfaceSunken.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: Brand.radiusMd)
                .stroke(Brand.border, lineWidth: 0.5)
        )
        .cornerRadius(Brand.radiusMd)
    }
}

struct AddCheckInSheetView: View {
    let onAdd: (CheckIn) -> Void
    let onCancel: () -> Void

    @State private var selectedStatus: CheckInStatus = .working
    @State private var text: String = ""
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Check-in")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("How's it going?")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ForEach(CheckInStatus.allCases, id: \.self) { status in
                        Button {
                            selectedStatus = status
                        } label: {
                            Text(status.label)
                                .font(.caption.bold())
                                .foregroundColor(selectedStatus == status ? .white : status.swiftUIColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    selectedStatus == status
                                        ? status.swiftUIColor
                                        : status.swiftUIColor.opacity(0.15)
                                )
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Entry")
                    .font(.caption).foregroundColor(.secondary)
                // TextEditor needs to be a direct child of the layout — no overlay
                // on top of it or it won't receive click events on macOS
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(textFocused ? Color.accentColor : Color.secondary.opacity(0.3))
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.05))
                        )
                    TextEditor(text: $text)
                        .font(.body)
                        .focused($textFocused)
                        .padding(6)
                        .scrollContentBackground(.hidden)
                }
                .frame(minHeight: 140)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Submit") {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onAdd(CheckIn(status: selectedStatus, text: text))
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            // Small delay so the sheet finishes its presentation animation
            // before we steal focus — otherwise the focus request is ignored.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                textFocused = true
            }
        }
    }
}

// MARK: - Edit Sheet

struct EditCheckInSheetView: View {
    let checkIn: CheckIn
    let onSave: (CheckIn) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var selectedStatus: CheckInStatus
    @State private var text: String
    @FocusState private var textFocused: Bool

    init(checkIn: CheckIn, onSave: @escaping (CheckIn) -> Void,
         onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.checkIn = checkIn
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _selectedStatus = State(initialValue: checkIn.status)
        _text = State(initialValue: checkIn.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Check-in")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ForEach(CheckInStatus.allCases, id: \.self) { status in
                        Button {
                            selectedStatus = status
                        } label: {
                            Text(status.label)
                                .font(.caption.bold())
                                .foregroundColor(selectedStatus == status ? .white : status.swiftUIColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    selectedStatus == status
                                        ? status.swiftUIColor
                                        : status.swiftUIColor.opacity(0.15)
                                )
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Entry")
                    .font(.caption).foregroundColor(.secondary)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(textFocused ? Color.accentColor : Color.secondary.opacity(0.3))
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.05))
                        )
                    TextEditor(text: $text)
                        .font(.body)
                        .focused($textFocused)
                        .padding(6)
                        .scrollContentBackground(.hidden)
                }
                .frame(minHeight: 180)
            }

            HStack {
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Save") {
                    var updated = checkIn
                    updated = CheckIn(id: checkIn.id, timestamp: checkIn.timestamp,
                                      status: selectedStatus, text: text,
                                      exportIncluded: checkIn.exportIncluded)
                    onSave(updated)
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { textFocused = true }
        }
    }
}

// MARK: - Color helpers

extension CheckInStatus {
    var swiftUIColor: Color {
        switch self {
        case .working:      return Brand.statusWorking        // archival teal
        case .stuck:        return Brand.statusStuck          // warm amber-orange
        case .breakthrough: return Brand.statusBreakthrough   // deep green
        case .paused:       return Brand.statusPaused         // slate-400
        case .done:         return Brand.statusDone           // dusty slate
        }
    }
}
