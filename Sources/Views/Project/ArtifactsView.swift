import SwiftUI
import AppKit

// MARK: - Filter enum

private enum ArtifactFilter: String, CaseIterable {
    case all    = "All"
    case seeds  = "Seeds"
    case notes  = "Notes"
    case images = "Images"
    case audio  = "Audio"
    case other  = "Other"
}

// MARK: - Main view

struct ArtifactsView: View {
    @ObservedObject var state: ProjectState
    @State private var showAddSheet      = false
    @State private var editingArtifact:  Artifact? = nil
    @State private var seedDetailArtifact: Artifact? = nil
    @State private var activeFilter: ArtifactFilter = .all

    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var filtered: [Artifact] {
        switch activeFilter {
        case .all:    return state.artifacts
        case .seeds:  return state.artifacts.filter { $0.type == .seedHistory }
        case .notes:  return state.artifacts.filter { $0.type == .scannedNote }
        case .images: return state.artifacts.filter { $0.type == .image }
        case .audio:  return state.artifacts.filter { $0.type == .audio }
        case .other:  return state.artifacts.filter { $0.type == .oldDraft || $0.type == .other }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack {
                Text("Artifacts")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Artifact", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // ── Filter chips ─────────────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Brand.spaceSM) {
                    ForEach(ArtifactFilter.allCases, id: \.self) { filter in
                        ArtifactFilterChip(
                            label: filter.rawValue,
                            isActive: activeFilter == filter
                        ) {
                            activeFilter = filter
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            Divider()
                .overlay(Brand.border)

            // ── Grid ─────────────────────────────────────────────────────
            if filtered.isEmpty {
                let msg = activeFilter == .all
                    ? "No artifacts yet. Add scanned notes, images, audio, or old drafts."
                    : "No \(activeFilter.rawValue.lowercased()) yet."
                EmptyStateView(message: msg)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filtered) { artifact in
                            ArtifactCardView(artifact: artifact, state: state)
                                .onTapGesture {
                                    if artifact.type == .seedHistory {
                                        seedDetailArtifact = artifact
                                    }
                                }
                                .onTapGesture(count: 2) {
                                    if artifact.type != .seedHistory {
                                        editingArtifact = artifact
                                    }
                                }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddArtifactSheetView { artifact, fileURL in
                state.addArtifact(artifact, from: fileURL)
                showAddSheet = false
            } onCancel: {
                showAddSheet = false
            }
        }
        .sheet(item: $editingArtifact) { artifact in
            EditArtifactSheetView(artifact: artifact, attachmentsURL: state.project.attachmentsURL) { updated in
                state.updateArtifact(updated)
                editingArtifact = nil
            } onDelete: {
                state.deleteArtifact(id: artifact.id)
                editingArtifact = nil
            } onCancel: {
                editingArtifact = nil
            }
        }
        .sheet(item: $seedDetailArtifact) { artifact in
            SeedArtifactDetailSheet(artifact: artifact) {
                seedDetailArtifact = nil
            }
        }
        .background(Brand.surfaceBase)
    }
}

// MARK: - Filter chip

private struct ArtifactFilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? Brand.accent : Brand.textSecondary)
                .padding(.horizontal, Brand.spaceSM)
                .padding(.vertical, 4)
                .background(isActive ? Brand.accent.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.radiusMd)
                        .stroke(isActive ? Brand.accent.opacity(0.4) : Brand.border, lineWidth: 0.5)
                )
                .cornerRadius(Brand.radiusMd)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Artifact card

struct ArtifactCardView: View {
    var artifact: Artifact
    @ObservedObject var state: ProjectState

    private let displayFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt
    }()

    var thumbnail: NSImage? {
        guard let filename = artifact.attachmentFilename else { return nil }
        let url = state.project.attachmentsURL.appendingPathComponent(filename)
        return NSImage(contentsOf: url)
    }

    var systemIconName: String {
        switch artifact.type {
        case .scannedNote:  return "doc.text"
        case .image:        return "photo"
        case .audio:        return "waveform"
        case .oldDraft:     return "doc"
        case .seedHistory:  return "leaf"
        case .other:        return "paperclip"
        }
    }

    var iconColor: Color {
        artifact.type == .seedHistory ? Brand.textBrand : Brand.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Thumbnail or icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Brand.surfaceSunken)
                    .frame(height: 100)
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: systemIconName)
                        .font(.system(size: 32))
                        .foregroundColor(iconColor)
                }
            }

            // Title & type badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    TypeBadge(
                        label: artifact.type.rawValue,
                        color: artifact.type == .seedHistory ? Brand.textBrand : Brand.textMuted
                    )
                }
                Spacer()
                // Seed artifacts show a "tap to view" chevron hint
                if artifact.type == .seedHistory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(Brand.textMuted)
                        .padding(.top, 2)
                }
            }

            Text(displayFmt.string(from: artifact.timestamp))
                .font(.system(size: 10))
                .foregroundColor(Brand.textSecondary)

            if let caption = artifact.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundColor(Brand.textSecondary)
                    .lineLimit(2)
            }

            Toggle("Include in export", isOn: Binding(
                get: { artifact.exportIncluded },
                set: { newVal in
                    if let idx = state.artifacts.firstIndex(where: { $0.id == artifact.id }) {
                        state.artifacts[idx] = Artifact(
                            id: artifact.id, timestamp: artifact.timestamp, type: artifact.type,
                            title: artifact.title, attachmentFilename: artifact.attachmentFilename,
                            caption: artifact.caption, exportIncluded: newVal,
                            seedMetadata: artifact.seedMetadata
                        )
                        try? LedgerWriter.writeArtifacts(state.artifacts, to: state.project)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
        }
        .padding(Brand.spaceMD)
        // PR-22 §C4 (follow-up): surfaceSelected (warm beige) card background —
        // matches the sidebar selection treatment so cards read as distinct
        // surfaces against the surfaceBase body, not floating white patches.
        // Inner thumbnail area (surfaceSunken) stays as-is.
        .background(Brand.surfaceSelected)
        .overlay(
            RoundedRectangle(cornerRadius: Brand.radiusLg)
                .stroke(Brand.borderSubtle, lineWidth: 0.5)
        )
        .cornerRadius(Brand.radiusLg)
        .contextMenu {
            if artifact.type != .seedHistory {
                Button("Edit Artifact") { }
                Button("Delete Artifact", role: .destructive) {
                    state.deleteArtifact(id: artifact.id)
                }
            } else {
                Button("Delete Artifact", role: .destructive) {
                    state.deleteArtifact(id: artifact.id)
                }
            }
        }
    }
}

// MARK: - Seed artifact detail sheet

struct SeedArtifactDetailSheet: View {
    let artifact: Artifact
    let onClose: () -> Void

    private let relFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private var seedEntry: SeedTraceIngestor.SeedEntry? {
        guard let data = artifact.seedMetadata else { return nil }
        return try? JSONDecoder().decode(SeedTraceIngestor.SeedEntry.self, from: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Brand.textBrand)
                        Text(artifact.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Brand.textPrimary)
                    }
                    if let entry = seedEntry {
                        Text("From garden: \(URL(fileURLWithPath: entry.originalGardenPath).lastPathComponent)")
                            .font(.system(size: 12))
                            .foregroundColor(Brand.textMuted)
                        if let col = entry.destinationColumn {
                            Text("Transplanted to column: \"\(col)\"")
                                .font(.system(size: 12))
                                .foregroundColor(Brand.textMuted)
                        }
                    }
                }
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(24)

            Divider().overlay(Brand.border)

            // Timeline
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let entry = seedEntry, !entry.history.isEmpty {
                        ForEach(Array(entry.history.enumerated()), id: \.offset) { idx, histEntry in
                            TimelineRow(
                                entry: histEntry,
                                isLast: idx == entry.history.count - 1,
                                relFmt: relFmt
                            )
                        }
                    } else {
                        // Fallback: show caption
                        if let caption = artifact.caption {
                            Text(caption)
                                .font(.system(size: 13))
                                .foregroundColor(Brand.textSecondary)
                                .padding(24)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 460, height: 480)
        .background(Brand.surfaceBase)
    }
}

private struct TimelineRow: View {
    let entry: SeedTraceIngestor.HistoryEntry
    let isLast: Bool
    let relFmt: RelativeDateTimeFormatter

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var parsedDate: Date? {
        if let d = Self.isoParser.date(from: entry.date) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: entry.date)
    }

    private var actionLabel: String {
        switch entry.action {
        case "plant":   return "Planted"
        case "edit":    return "Edited"
        case "merge":   return "Merged"
        case "split":   return "Split"
        case "promote": return "Transplanted"
        default:        return entry.action.capitalized
        }
    }

    private var actionIcon: String {
        switch entry.action {
        case "plant":   return "leaf.fill"
        case "edit":    return "pencil"
        case "merge":   return "arrow.triangle.merge"
        case "split":   return "arrow.branch"
        case "promote": return "arrow.up.forward.square"
        default:        return "circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon + connecting line
            VStack(spacing: 0) {
                Image(systemName: actionIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Brand.textBrand)
                    .frame(width: 22, height: 22)
                    .background(Brand.surfaceSunken)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Brand.border, lineWidth: 0.5))

                if !isLast {
                    Rectangle()
                        .fill(Brand.border)
                        .frame(width: 1)
                        .frame(minHeight: 20)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(actionLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Brand.textPrimary)
                    if let date = parsedDate {
                        Text(relFmt.localizedString(for: date, relativeTo: Date()))
                            .font(.system(size: 11))
                            .foregroundColor(Brand.textMuted)
                    } else {
                        Text(entry.date)
                            .font(.system(size: 11))
                            .foregroundColor(Brand.textMuted)
                    }
                }
                if !entry.message.isEmpty {
                    Text(entry.message)
                        .font(.system(size: 12))
                        .foregroundColor(Brand.textSecondary)
                        .lineLimit(3)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }
}

// MARK: - Add Artifact Sheet

struct AddArtifactSheetView: View {
    let onAdd: (Artifact, URL?) -> Void
    let onCancel: () -> Void

    // Exclude .seedHistory from user-facing picker — seeds are auto-imported
    private let manualTypes = ArtifactType.allCases.filter { $0 != .seedHistory }

    @State private var selectedType: ArtifactType = .scannedNote
    @State private var title: String = ""
    @State private var caption: String = ""
    @State private var selectedFileURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Artifact")
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Type")
                    .font(.system(size: 12)).foregroundColor(Brand.textSecondary)
                Picker("Type", selection: $selectedType) {
                    ForEach(manualTypes, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.system(size: 12)).foregroundColor(Brand.textSecondary)
                TextField("Artifact title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Attachment (optional)")
                    .font(.system(size: 12)).foregroundColor(Brand.textSecondary)
                HStack {
                    if let url = selectedFileURL {
                        Text(url.lastPathComponent)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundColor(Brand.textSecondary)
                    } else {
                        Text("No file attached")
                            .font(.system(size: 13))
                            .foregroundColor(Brand.textMuted)
                    }
                    Spacer()
                    Button("Attach File") {
                        pickFile()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Brand.surfaceSunken)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.radiusMd)
                        .stroke(Brand.border, lineWidth: 0.5)
                )
                .cornerRadius(Brand.radiusMd)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Caption (optional)")
                    .font(.system(size: 12)).foregroundColor(Brand.textSecondary)
                TextField("Describe this artifact", text: $caption)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Add Artifact") {
                    guard !title.isEmpty else { return }
                    let artifact = Artifact(
                        type: selectedType,
                        title: title,
                        attachmentFilename: selectedFileURL?.lastPathComponent,
                        caption: caption.isEmpty ? nil : caption
                    )
                    onAdd(artifact, selectedFileURL)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func pickFile() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    selectedFileURL = url
                    if title.isEmpty {
                        title = url.deletingPathExtension().lastPathComponent
                    }
                }
            }
        }
    }
}

// MARK: - Edit Artifact Sheet

struct EditArtifactSheetView: View {
    let artifact: Artifact
    let attachmentsURL: URL
    let onSave: (Artifact) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    private let manualTypes = ArtifactType.allCases.filter { $0 != .seedHistory }

    @State private var selectedType: ArtifactType
    @State private var title: String
    @State private var caption: String

    init(artifact: Artifact, attachmentsURL: URL,
         onSave: @escaping (Artifact) -> Void,
         onDelete: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.artifact = artifact
        self.attachmentsURL = attachmentsURL
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _selectedType = State(initialValue: artifact.type == .seedHistory ? .oldDraft : artifact.type)
        _title = State(initialValue: artifact.title)
        _caption = State(initialValue: artifact.caption ?? "")
    }

    var thumbnail: NSImage? {
        guard let filename = artifact.attachmentFilename else { return nil }
        return NSImage(contentsOf: attachmentsURL.appendingPathComponent(filename))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Artifact")
                .font(.system(size: 18, weight: .semibold))

            // Preview
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Category")
                    .font(.system(size: 12)).foregroundColor(Brand.textSecondary)
                Picker("Category", selection: $selectedType) {
                    ForEach(manualTypes, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.system(size: 12)).foregroundColor(Brand.textSecondary)
                TextField("Artifact title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Caption")
                    .font(.system(size: 12)).foregroundColor(Brand.textSecondary)
                TextField("Describe this artifact", text: $caption)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }

            if let filename = artifact.attachmentFilename {
                HStack(spacing: 4) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12))
                        .foregroundColor(Brand.textSecondary)
                    Text(filename)
                        .font(.system(size: 12))
                        .foregroundColor(Brand.textSecondary)
                        .lineLimit(1)
                }
            }

            HStack {
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Save") {
                    let updated = Artifact(
                        id: artifact.id, timestamp: artifact.timestamp,
                        type: selectedType, title: title,
                        attachmentFilename: artifact.attachmentFilename,
                        caption: caption.isEmpty ? nil : caption,
                        exportIncluded: artifact.exportIncluded,
                        seedMetadata: artifact.seedMetadata
                    )
                    onSave(updated)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
