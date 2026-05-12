import SwiftUI

// MARK: - File Snapshot View
// Shows the full content of a single file at a specific snapshot.
// Toggle between Document view (clean render) and Diff view (inline changes).

struct FileSnapshotView: View {
    let relativePath: String
    let snapshot: Snapshot
    @ObservedObject var state: ProjectState

    @State private var mode: ViewMode = .document
    @State private var currentContent: String? = nil
    @State private var previousContent: String? = nil
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss

    enum ViewMode: String, CaseIterable {
        case document = "Document"
        case diff = "Changes"
    }

    private var filename: String { URL(fileURLWithPath: relativePath).lastPathComponent }
    private var isText: Bool {
        let textExts = ["txt","md","markdown","fountain","fdx","rtf","tex","json","yaml","yml",
                        "swift","py","js","ts","css","html","htm","xml","sh","csv","tsv"]
        return textExts.contains(URL(fileURLWithPath: relativePath).pathExtension.lowercased())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: CreativeFileRegistry.info(for: relativePath).category.systemIcon)
                            .font(.system(size: 12))
                            .foregroundColor(CreativeFileRegistry.info(for: relativePath).category.accentColor)
                        Text(filename)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Brand.textPrimary)
                    }
                    Text(snapshot.hash)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Brand.textMuted)
                }

                Spacer()

                // Mode toggle — only show if this is a text file
                if isText && previousContent != nil {
                    Picker("", selection: $mode) {
                        ForEach(ViewMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                }

                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .padding(.leading, Brand.spaceMD)
            }
            .padding(.horizontal, Brand.spaceLG)
            .padding(.vertical, Brand.spaceMD)
            .background(Brand.surfaceBase)

            Divider()

            // Stats bar (word count delta)
            if let curr = currentContent, let prev = previousContent {
                wordCountBar(current: curr, previous: prev)
                Divider()
            }

            // Content
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let content = currentContent {
                if !isText {
                    nonTextPlaceholder
                } else {
                    switch mode {
                    case .document:
                        documentView(content: content)
                    case .diff:
                        diffView(current: content, previous: previousContent)
                    }
                }
            } else {
                EmptyStateView(
                    message: "Could not load file content for this snapshot.",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .frame(width: 680, height: 580)
        .background(Brand.surfaceBase)
        .onAppear { load() }
    }

    // MARK: - Sub-views

    private var nonTextPlaceholder: some View {
        VStack(spacing: Brand.spaceMD) {
            Image(systemName: CreativeFileRegistry.info(for: relativePath).category.systemIcon)
                .font(.system(size: 40))
                .foregroundColor(Brand.textMuted)
            Text("Binary or non-text file — no preview available.")
                .foregroundColor(Brand.textSecondary)
                .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func wordCountBar(current: String, previous: String) -> some View {
        let currWords = wordCount(current)
        let prevWords = wordCount(previous)
        let delta = currWords - prevWords
        return HStack(spacing: Brand.spaceLG) {
            Label("\(currWords) words", systemImage: "text.word.spacing")
                .font(.system(size: 11))
                .foregroundColor(Brand.textMuted)
            if delta != 0 {
                HStack(spacing: 3) {
                    Image(systemName: delta > 0 ? "plus" : "minus")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(abs(delta)) words \(delta > 0 ? "added" : "removed")")
                        .font(.system(size: 11))
                }
                .foregroundColor(delta > 0 ? Brand.accent : Brand.statusStuck)
            }
            Spacer()
        }
        .padding(.horizontal, Brand.spaceLG)
        .padding(.vertical, 6)
        .background(Brand.surfaceSunken.opacity(0.5))
    }

    @ViewBuilder
    private func documentView(content: String) -> some View {
        ScrollView(.vertical) {
            DocumentRenderer(text: content)
                .padding(.horizontal, Brand.spaceXL)
                .padding(.vertical, Brand.spaceLG)
        }
    }

    private func diffLines(current: String, previous: String?) -> [InlineDiffLine] {
        if let prev = previous {
            return computeInlineDiff(old: prev, new: current)
        } else {
            return current.components(separatedBy: "\n").map {
                InlineDiffLine(text: $0, kind: .added)
            }
        }
    }

    @ViewBuilder
    private func diffView(current: String, previous: String?) -> some View {
        let lines = diffLines(current: current, previous: previous)
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    InlineDiffLineView(line: line)
                }
            }
            .padding(.horizontal, Brand.spaceLG)
            .padding(.vertical, Brand.spaceMD)
        }
    }

    // MARK: - Loading

    private func load() {
        isLoading = true
        let proj = state.project
        let hash = snapshot.hash
        let path = relativePath
        Task.detached(priority: .userInitiated) {
            let curr = GitService.fileContent(hash: hash, relativePath: path, project: proj)
            let prev = GitService.fileContentPrevious(hash: hash, relativePath: path, project: proj)
            await MainActor.run {
                currentContent = curr
                previousContent = prev
                // Default to diff view if there is a previous version to compare
                if prev != nil { mode = .diff }
                isLoading = false
            }
        }
    }

    // MARK: - Helpers

    private func wordCount(_ text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
    }
}

// MARK: - Document renderer (clean text with basic markdown headings)

struct DocumentRenderer: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                renderedParagraph(para)
                    .padding(.bottom, para.kind == .heading1 ? 16 : para.kind == .heading2 ? 12 : 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paragraphs: [RenderedParagraph] { parseMarkdown(text) }

    @ViewBuilder
    private func renderedParagraph(_ para: RenderedParagraph) -> some View {
        switch para.kind {
        case .heading1:
            Text(para.text)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Brand.textPrimary)
        case .heading2:
            Text(para.text)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Brand.textPrimary)
        case .heading3:
            Text(para.text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Brand.textSecondary)
        case .blockquote:
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Brand.border)
                    .frame(width: 3)
                    .cornerRadius(2)
                Text(para.text)
                    .font(.system(size: 14))
                    .foregroundColor(Brand.textSecondary)
                    .italic()
            }
        case .body:
            Text(para.text)
                .font(.system(size: 14))
                .foregroundColor(Brand.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .empty:
            Color.clear.frame(height: 4)
        }
    }
}

enum ParagraphKind { case heading1, heading2, heading3, blockquote, body, empty }
struct RenderedParagraph { let text: String; let kind: ParagraphKind }

private func parseMarkdown(_ raw: String) -> [RenderedParagraph] {
    raw.components(separatedBy: "\n").map { line in
        if line.isEmpty { return RenderedParagraph(text: "", kind: .empty) }
        if line.hasPrefix("### ") { return RenderedParagraph(text: String(line.dropFirst(4)), kind: .heading3) }
        if line.hasPrefix("## ")  { return RenderedParagraph(text: String(line.dropFirst(3)), kind: .heading2) }
        if line.hasPrefix("# ")   { return RenderedParagraph(text: String(line.dropFirst(2)), kind: .heading1) }
        if line.hasPrefix("> ")   { return RenderedParagraph(text: String(line.dropFirst(2)), kind: .blockquote) }
        return RenderedParagraph(text: line, kind: .body)
    }
}

// MARK: - Inline diff

struct InlineDiffLine {
    let text: String
    enum Kind { case added, removed, context }
    let kind: Kind
}

struct InlineDiffLineView: View {
    let line: InlineDiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Gutter marker
            Text(line.kind == .added ? "+" : line.kind == .removed ? "−" : " ")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(gutterColor)
                .frame(width: 16, alignment: .leading)

            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 13))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .strikethrough(line.kind == .removed, color: Brand.statusStuck.opacity(0.6))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, Brand.spaceSM)
        .background(backgroundColor)
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .added:   return Brand.accent.opacity(0.08)
        case .removed: return Brand.statusStuck.opacity(0.07)
        case .context: return Color.clear
        }
    }
    private var textColor: Color {
        switch line.kind {
        case .added:   return Brand.textPrimary
        case .removed: return Brand.textSecondary
        case .context: return Brand.textPrimary
        }
    }
    private var gutterColor: Color {
        switch line.kind {
        case .added:   return Brand.accent
        case .removed: return Brand.statusStuck
        case .context: return Brand.textMuted
        }
    }
}

// MARK: - LCS-based line diff

private func computeInlineDiff(old: String, new: String) -> [InlineDiffLine] {
    let oldLines = old.components(separatedBy: "\n")
    let newLines = new.components(separatedBy: "\n")
    let edits = lcs(oldLines, newLines)
    return edits
}

// Myers-like LCS diff: returns InlineDiffLines
private func lcs(_ old: [String], _ new: [String]) -> [InlineDiffLine] {
    // Build LCS table
    let m = old.count, n = new.count
    var table = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in stride(from: m - 1, through: 0, by: -1) {
        for j in stride(from: n - 1, through: 0, by: -1) {
            if old[i] == new[j] {
                table[i][j] = 1 + table[i + 1][j + 1]
            } else {
                table[i][j] = max(table[i + 1][j], table[i][j + 1])
            }
        }
    }
    // Traceback
    var result: [InlineDiffLine] = []
    var i = 0, j = 0
    while i < m && j < n {
        if old[i] == new[j] {
            result.append(InlineDiffLine(text: old[i], kind: .context))
            i += 1; j += 1
        } else if table[i + 1][j] >= table[i][j + 1] {
            result.append(InlineDiffLine(text: old[i], kind: .removed))
            i += 1
        } else {
            result.append(InlineDiffLine(text: new[j], kind: .added))
            j += 1
        }
    }
    while i < m { result.append(InlineDiffLine(text: old[i], kind: .removed)); i += 1 }
    while j < n { result.append(InlineDiffLine(text: new[j], kind: .added));   j += 1 }
    return result
}
