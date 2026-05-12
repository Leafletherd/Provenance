import SwiftUI

// Small Identifiable wrapper so we can use .sheet(item:) with a plain file path string.
private struct FileTarget: Identifiable {
    let path: String
    var id: String { path }
}

struct DiffLine: Identifiable {
    let id = UUID()
    let text: String
    let kind: DiffLineKind
}

enum DiffLineKind {
    case added, removed, hunk, context
}

struct DiffView: View {
    let snapshot: Snapshot
    @ObservedObject var state: ProjectState

    @State private var diffLines: [DiffLine] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var selectedFile: String? = nil
    @Environment(\.dismiss) var dismiss

    private let displayFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(snapshot.hash)
                            .font(.system(.headline, design: .monospaced))
                            .foregroundColor(Brand.textPrimary)
                        TypeBadge(label: snapshot.trigger.label, color: triggerColor)
                    }
                    Text(displayFmt.string(from: snapshot.timestamp))
                        .font(.system(size: 12))
                        .foregroundColor(Brand.textMuted)
                    // Changed files — tappable to open per-file document view
                    if !snapshot.changedFiles.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(snapshot.changedFiles, id: \.self) { path in
                                    Button { selectedFile = path } label: {
                                        ChangedFilePill(path: path)
                                    }
                                    .buttonStyle(.plain)
                                    .help("View \(URL(fileURLWithPath: path).lastPathComponent) at this snapshot")
                                }
                            }
                        }
                    }
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(Brand.spaceLG)
            .background(Brand.surfaceBase)

            Divider()

            if isLoading {
                ProgressView("Loading diff…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: Brand.spaceSM) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(Brand.statusStuck)
                    Text(error)
                        .foregroundColor(Brand.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diffLines.isEmpty {
                EmptyStateView(message: "No changes recorded in this snapshot.")
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffLines) { line in
                            DiffLineView(line: line)
                        }
                    }
                    .padding(.horizontal, Brand.spaceSM)
                }
            }
        }
        .frame(width: 740, height: 520)
        .background(Brand.surfaceBase)
        .onAppear { loadDiff() }
        .sheet(item: Binding(
            get: { selectedFile.map { FileTarget(path: $0) } },
            set: { selectedFile = $0?.path }
        )) { target in
            FileSnapshotView(
                relativePath: target.path,
                snapshot: snapshot,
                state: state
            )
        }
    }

    private var triggerColor: Color {
        switch snapshot.trigger {
        case .auto:      return Brand.accent
        case .scheduled: return Brand.statusStuck
        case .manual:    return Brand.statusDone
        }
    }

    private func loadDiff() {
        isLoading = true
        errorMessage = nil
        let proj = state.project
        let hash = snapshot.hash
        Task.detached(priority: .userInitiated) {
            // Try parent diff first; fall back to empty-tree SHA for the first commit
            let raw: String
            if let parentDiff = try? GitService.diff(hash1: hash + "^", hash2: hash, project: proj),
               !parentDiff.isEmpty {
                raw = parentDiff
            } else if let treeDiff = try? GitService.diff(
                hash1: "4b825dc642cb6eb9a060e54bf8d69288fbee4904",
                hash2: hash, project: proj) {
                raw = treeDiff
            } else {
                raw = ""
            }
            let parsed = parseDiffLines(raw)
            await MainActor.run {
                diffLines = parsed
                isLoading = false
            }
        }
    }
}

// Free function — no actor isolation, safe to call from Task.detached
private func parseDiffLines(_ raw: String) -> [DiffLine] {
    raw.components(separatedBy: "\n").compactMap { line -> DiffLine? in
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return DiffLine(text: line, kind: .context)
        } else if line.hasPrefix("+") {
            return DiffLine(text: line, kind: .added)
        } else if line.hasPrefix("-") {
            return DiffLine(text: line, kind: .removed)
        } else if line.hasPrefix("@@") {
            return DiffLine(text: line, kind: .hunk)
        } else if line.isEmpty {
            return nil
        } else {
            return DiffLine(text: line, kind: .context)
        }
    }
}

struct DiffLineView: View {
    let line: DiffLine

    var backgroundColor: Color {
        switch line.kind {
        case .added:   return Brand.accent.opacity(0.12)
        case .removed: return Brand.statusStuck.opacity(0.12)
        case .hunk:    return Brand.surfaceSunken.opacity(0.6)
        case .context: return Color.clear
        }
    }

    var textColor: Color {
        switch line.kind {
        case .added:   return Brand.accentDark
        case .removed: return Brand.statusStuck
        case .hunk:    return Brand.textMuted
        case .context: return Brand.textPrimary
        }
    }

    var body: some View {
        Text(line.text.isEmpty ? " " : line.text)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .padding(.vertical, 1)
    }
}
