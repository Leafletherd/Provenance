import SwiftUI

struct VersionsView: View {
    @ObservedObject var state: ProjectState
    @State private var showSnapshotSheet = false
    @State private var snapshotLabel: String = ""
    @State private var selectedSnapshot: Snapshot? = nil

    private let displayFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Versions")
                    .font(.headline)
                Text("(\(state.snapshots.count))")
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    snapshotLabel = ""
                    showSnapshotSheet = true
                } label: {
                    Label("Take Snapshot", systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if state.snapshots.isEmpty {
                EmptyStateView(message: "No snapshots yet. Snapshots are created automatically when files change, or you can take one manually.")
            } else {
                List {
                    ForEach(state.snapshots) { snapshot in
                        SnapshotRowView(snapshot: snapshot, displayFmt: displayFmt)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSnapshot = snapshot
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showSnapshotSheet) {
            ManualSnapshotSheet(label: $snapshotLabel) {
                state.takeManualSnapshot(label: snapshotLabel.isEmpty ? nil : snapshotLabel)
                showSnapshotSheet = false
            } onCancel: {
                showSnapshotSheet = false
            }
        }
        .sheet(item: $selectedSnapshot) { snapshot in
            DiffView(snapshot: snapshot, state: state)
        }
    }
}

struct SnapshotRowView: View {
    let snapshot: Snapshot
    let displayFmt: DateFormatter

    var triggerColor: Color {
        switch snapshot.trigger {
        case .auto:      return Brand.accent        // teal — "alive / watching"
        case .scheduled: return Brand.statusStuck   // amber — "scheduled"
        case .manual:    return Brand.statusDone    // dusty slate — "deliberate"
        }
    }

    // Primary description: label (doc name for auto, user label for manual)
    var primaryTitle: String {
        if let label = snapshot.label, !label.isEmpty { return label }
        if !snapshot.changedFiles.isEmpty {
            return snapshot.changedFiles.prefix(2).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
        }
        return snapshot.hash
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    TypeBadge(label: snapshot.trigger.label, color: triggerColor)
                    Text(primaryTitle)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(displayFmt.string(from: snapshot.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if snapshot.filesChanged > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(snapshot.filesChanged) file\(snapshot.filesChanged == 1 ? "" : "s") changed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                // Show up to 3 changed file names with type badges
                if !snapshot.changedFiles.isEmpty {
                    let shown = Array(snapshot.changedFiles.prefix(3))
                    let extra = snapshot.changedFiles.count - shown.count
                    HStack(spacing: 4) {
                        ForEach(shown, id: \.self) { path in
                            ChangedFilePill(path: path)
                        }
                        if extra > 0 {
                            Text("+\(extra)")
                                .font(.system(size: 10))
                                .foregroundColor(Brand.textMuted)
                        }
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(snapshot.hash)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Changed File Pill

struct ChangedFilePill: View {
    let path: String

    private var filename: String { URL(fileURLWithPath: path).lastPathComponent }
    private var info: CreativeFileInfo { CreativeFileRegistry.info(for: path) }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: info.category.systemIcon)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(info.category.accentColor)
            Text(filename)
                .font(.system(size: 10))
                .foregroundColor(Brand.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(info.category.accentColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Brand.radiusSm)
                .stroke(info.category.accentColor.opacity(0.2), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Brand.radiusSm))
    }
}

struct ManualSnapshotSheet: View {
    @Binding var label: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Take Manual Snapshot")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Label (optional)")
                    .font(.caption).foregroundColor(.secondary)
                TextField("e.g. Before major revision", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            Text("A snapshot captures the current state of all files in your project folder.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Take Snapshot", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
