import SwiftUI
import AppKit

struct OverviewView: View {
    @ObservedObject var state: ProjectState
    @EnvironmentObject var appState: AppState

    @State private var projectName: String = ""
    @State private var medium: String = ""
    @State private var workingDescription: String = ""
    @State private var intent: String = ""
    @State private var showContextSheet = false
    @State private var nameDebounceTask: Task<Void, Never>? = nil
    @State private var targetEditManuscript: Manuscript? = nil
    @State private var targetInputText: String = ""

    private let displayFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Display name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Display name", text: $projectName)
                        .font(.title2)
                        .textFieldStyle(.plain)
                        .onChange(of: projectName) { newValue in
                            nameDebounceTask?.cancel()
                            nameDebounceTask = Task {
                                try? await Task.sleep(nanoseconds: 800_000_000)
                                if !Task.isCancelled {
                                    var updated = state.project
                                    updated.name = newValue
                                    state.updateProject(updated)
                                    appState.updateProject(updated)
                                }
                            }
                        }
                    Text("Used everywhere this project appears, including when promoted to Works.")
                        .font(.system(size: 11))
                        .foregroundColor(Brand.textMuted)
                }

                Divider()

                // Folder path
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(state.project.folderURL.path)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.open(state.project.folderURL)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Divider()

                // Stats
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 16) {
                        StatBadge(count: state.snapshots.count, label: "versions")
                        StatBadge(count: state.checkIns.count, label: "check-ins")
                        StatBadge(count: state.sources.count, label: "sources")
                        StatBadge(count: state.artifacts.count, label: "artifacts")
                    }
                    Text("Connected \(displayFmt.string(from: state.project.connectedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    Text("Last activity \(displayFmt.string(from: state.project.lastActivity))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Paste tracking override
                VStack(alignment: .leading, spacing: 6) {
                    let globalOn = UserDefaults.standard.object(forKey: "trackPasteSources") as? Bool ?? true
                    let effectiveOn = state.project.trackPasteSources ?? globalOn

                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { state.project.trackPasteSources ?? globalOn },
                            set: { newValue in
                                var updated = state.project
                                // If the user is toggling back to the global default, clear the override.
                                updated.trackPasteSources = (newValue == globalOn) ? nil : newValue
                                state.updateProject(updated)
                                appState.updateProject(updated)
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Track paste sources")
                                    .font(.callout)
                                if state.project.trackPasteSources == nil {
                                    Text("global default")
                                        .font(.caption2)
                                        .foregroundColor(Brand.textMuted)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Brand.surfaceSunken)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(Brand.border, lineWidth: 0.5)
                                        )
                                        .cornerRadius(3)
                                }
                            }
                            Text(effectiveOn
                                 ? "Provenance will record where pasted text came from in this project."
                                 : "Paste-source recording is disabled for this project.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Editable context fields
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Project Context")
                            .font(.headline)
                        Spacer()
                        Button("Edit Context") {
                            medium = state.project.medium ?? ""
                            workingDescription = state.project.workingDescription ?? ""
                            intent = state.project.intent ?? ""
                            showContextSheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let m = state.project.medium, !m.isEmpty {
                        LabeledField(label: "Medium", value: m)
                    }
                    if let d = state.project.workingDescription, !d.isEmpty {
                        LabeledField(label: "Working Description", value: d)
                    }
                    if let i = state.project.intent, !i.isEmpty {
                        LabeledField(label: "Intent", value: i)
                    }
                    if (state.project.medium == nil || state.project.medium!.isEmpty) &&
                        (state.project.workingDescription == nil || state.project.workingDescription!.isEmpty) &&
                        (state.project.intent == nil || state.project.intent!.isEmpty) {
                        Text("No context added yet. Click \"Edit Context\" to add medium, description, and intent.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Manuscripts section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Manuscripts")
                            .font(.headline)
                        Spacer()
                        Button {
                            state.scanManuscripts()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if state.manuscripts.isEmpty {
                        EmptyStateView(message: "No text manuscripts found yet.")
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 6) {
                                ForEach(state.manuscripts) { ms in
                                    ManuscriptCard(manuscript: ms) { action in
                                        switch action {
                                        case .setTarget:
                                            targetInputText = ms.targetWordCount.map(String.init) ?? ""
                                            targetEditManuscript = ms
                                        case .clearTarget:
                                            state.setManuscriptTarget(nil, for: ms.id)
                                        case .revealInFinder:
                                            NSWorkspace.shared.activateFileViewerSelecting([ms.path])
                                        case .openInApp:
                                            NSWorkspace.shared.open(ms.path)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(maxHeight: 280)
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            projectName = state.project.name
        }
        .sheet(item: $targetEditManuscript) { ms in
            SetTargetSheet(
                title: ms.title,
                current: ms.targetWordCount,
                inputText: $targetInputText
            ) { newTarget in
                state.setManuscriptTarget(newTarget, for: ms.id)
                targetEditManuscript = nil
            } onCancel: {
                targetEditManuscript = nil
            }
        }
        .sheet(isPresented: $showContextSheet) {
            ContextSheetView(
                medium: $medium,
                workingDescription: $workingDescription,
                intent: $intent
            ) {
                var updated = state.project
                updated.medium = medium.isEmpty ? nil : medium
                updated.workingDescription = workingDescription.isEmpty ? nil : workingDescription
                updated.intent = intent.isEmpty ? nil : intent
                state.updateProject(updated)
                appState.updateProject(updated)
                showContextSheet = false
            } onCancel: {
                showContextSheet = false
            }
        }
    }
}

struct StatBadge: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundColor(Brand.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundColor(Brand.textMuted)
        }
        .padding(.horizontal, Brand.spaceMD)
        .padding(.vertical, Brand.spaceSM)
        .background(Brand.surfaceSunken)
        .overlay(
            RoundedRectangle(cornerRadius: Brand.radiusMd)
                .stroke(Brand.border, lineWidth: 0.5)
        )
        .cornerRadius(Brand.radiusMd)
    }
}

struct LabeledField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

struct ContextSheetView: View {
    @Binding var medium: String
    @Binding var workingDescription: String
    @Binding var intent: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Context")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Medium")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. Novel, Short Story, Screenplay", text: $medium)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Working Description")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $workingDescription)
                    .font(.body)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Intent")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $intent)
                    .font(.body)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// MARK: - Manuscript card

enum ManuscriptCardAction {
    case setTarget, clearTarget, revealInFinder, openInApp
}

struct ManuscriptCard: View {
    let manuscript: Manuscript
    let onAction: (ManuscriptCardAction) -> Void

    private let relFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var wordCountLabel: String {
        guard let wc = manuscript.wordCount else { return "Word count unavailable" }
        return "\(wc.formatted()) words"
    }

    private var pageCountLabel: String? {
        guard let pc = manuscript.pageCount else { return nil }
        return "\(pc) pages"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left column: metadata
            VStack(alignment: .leading, spacing: 3) {
                Text(manuscript.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Brand.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    TypeBadge(label: manuscript.kind.displayName, color: Brand.textMuted)
                    Text(relFmt.localizedString(for: manuscript.lastModified, relativeTo: Date()))
                        .font(.system(size: 10))
                        .foregroundColor(Brand.textMuted)
                }
            }

            Spacer()

            // Right column: counts + sparkline + progress
            VStack(alignment: .trailing, spacing: 4) {
                // Counts
                HStack(spacing: 6) {
                    if let pg = pageCountLabel {
                        Text(pg)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Brand.textSecondary)
                    }
                    Text(wordCountLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(manuscript.wordCount != nil ? Brand.textPrimary : Brand.textMuted)
                }

                // Sparkline (only when we have ≥2 history points)
                if manuscript.history.count >= 2 {
                    SparklineView(values: manuscript.history.map { $0.wordCount })
                }

                // Target progress bar
                if let target = manuscript.targetWordCount, let wc = manuscript.wordCount, target > 0 {
                    let pct = min(Double(wc) / Double(target), 1.0)
                    HStack(spacing: 5) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Brand.surfaceSunken)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(Brand.border, lineWidth: 0.5)
                                    )
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Brand.accent)
                                    .frame(width: geo.size.width * pct)
                            }
                        }
                        .frame(width: 60, height: 5)
                        Text("\(Int(pct * 100))%")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Brand.textMuted)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Brand.surfaceSunken)
        .overlay(
            RoundedRectangle(cornerRadius: Brand.radiusMd)
                .stroke(Brand.border, lineWidth: 0.5)
        )
        .cornerRadius(Brand.radiusMd)
        .contextMenu {
            Button("Set Target Word Count\u{2026}") { onAction(.setTarget) }
            if manuscript.targetWordCount != nil {
                Button("Clear Target") { onAction(.clearTarget) }
            }
            Divider()
            Button("Reveal in Finder") { onAction(.revealInFinder) }
            Button("Open in Default App") { onAction(.openInApp) }
        }
    }
}

// MARK: - Sparkline

struct SparklineView: View {
    let values: [Int]

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(Double(maxV - minV), 1.0)
            let count = values.count

            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) / CGFloat(count - 1) * size.width
                let y = size.height - CGFloat(Double(v - minV) / range) * size.height
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(Brand.accent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 60, height: 28)
    }
}

// MARK: - Set target sheet

struct SetTargetSheet: View {
    let title: String
    let current: Int?
    @Binding var inputText: String
    let onSave: (Int?) -> Void
    let onCancel: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Target Word Count")
                .font(.headline)
            Text(title)
                .font(.subheadline)
                .foregroundColor(Brand.textMuted)

            VStack(alignment: .leading, spacing: 4) {
                Text("Target (words)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. 80000", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { save() }
            }

            if let c = current {
                Text("Current target: \(c.formatted()) words")
                    .font(.caption)
                    .foregroundColor(Brand.textMuted)
            }

            HStack {
                if current != nil {
                    Button("Clear Target") { onSave(nil) }
                        .buttonStyle(.bordered)
                        .foregroundColor(Brand.statusStuck)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Set Target", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                    .disabled(parsedTarget == nil)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { fieldFocused = true }
    }

    private var parsedTarget: Int? {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed).flatMap { $0 > 0 ? $0 : nil }
    }

    private func save() {
        onSave(parsedTarget)
    }
}
