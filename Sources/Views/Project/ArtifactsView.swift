import SwiftUI
import AppKit

struct ArtifactsView: View {
    @ObservedObject var state: ProjectState
    @State private var showAddSheet = false
    @State private var editingArtifact: Artifact? = nil

    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
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

            if state.artifacts.isEmpty {
                EmptyStateView(message: "No artifacts yet. Add scanned notes, images, audio, or old drafts.")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(state.artifacts) { artifact in
                            ArtifactCardView(artifact: artifact, state: state)
                                .onTapGesture(count: 2) {
                                    editingArtifact = artifact
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
    }
}

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
        case .scannedNote: return "doc.text"
        case .image: return "photo"
        case .audio: return "waveform"
        case .oldDraft: return "doc"
        case .other: return "paperclip"
        }
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
                        .foregroundColor(Brand.textSecondary)
                }
            }

            // Title & type badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    TypeBadge(label: artifact.type.rawValue, color: Brand.textMuted)
                }
                Spacer()
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
                            caption: artifact.caption, exportIncluded: newVal
                        )
                        try? LedgerWriter.writeArtifacts(state.artifacts, to: state.project)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
        }
        .padding(Brand.spaceMD)
        .background(Brand.surfaceRaised)
        .overlay(
            RoundedRectangle(cornerRadius: Brand.radiusLg)
                .stroke(Brand.border, lineWidth: 0.5)
        )
        .cornerRadius(Brand.radiusLg)
        .contextMenu {
            Button("Edit Artifact") {
                // handled by double-click; also available via context menu
            }
            Button("Delete Artifact", role: .destructive) {
                state.deleteArtifact(id: artifact.id)
            }
        }
    }
}

struct AddArtifactSheetView: View {
    let onAdd: (Artifact, URL?) -> Void
    let onCancel: () -> Void

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
                    ForEach(ArtifactType.allCases, id: \.self) { t in
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
        _selectedType = State(initialValue: artifact.type)
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
                    ForEach(ArtifactType.allCases, id: \.self) { t in
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
                        exportIncluded: artifact.exportIncluded
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
