import SwiftUI
import AppKit

struct SourcesView: View {
    @ObservedObject var state: ProjectState
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sources")
                    .font(.headline)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Source", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if state.sources.isEmpty {
                EmptyStateView(message: "No sources yet. Add a URL, local file, or quoted passage.")
            } else {
                List {
                    ForEach(state.sources) { source in
                        SourceCardView(source: source, state: state)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            state.deleteSource(id: state.sources[idx].id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSourceSheetView { source in
                state.addSource(source)
                showAddSheet = false
            } onCancel: {
                showAddSheet = false
            }
        }
    }
}

struct SourceCardView: View {
    var source: Source
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
                TypeBadge(label: source.type.label, color: typeColor(source.type))
                Text(source.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(displayFmt.string(from: source.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let u = source.urlString, !u.isEmpty {
                Text(u)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let f = source.filePath, !f.isEmpty {
                Text(f)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            if let p = source.passage, !p.isEmpty {
                Text("\"\(p)\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .italic()
            }
            if let a = source.annotation, !a.isEmpty {
                Text(a)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            Toggle("Include in export", isOn: Binding(
                get: { source.exportIncluded },
                set: { newVal in
                    var updated = source
                    updated = Source(
                        id: source.id, timestamp: source.timestamp, type: source.type,
                        title: source.title, urlString: source.urlString, filePath: source.filePath,
                        passage: source.passage, annotation: source.annotation, exportIncluded: newVal
                    )
                    state.updateSource(updated)
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
        .contextMenu {
            Button("Delete Source", role: .destructive) {
                state.deleteSource(id: source.id)
            }
        }
    }

    private func typeColor(_ type: SourceType) -> Color {
        switch type {
        case .url:           return Brand.accent
        case .localFile:     return Brand.statusStuck       // warm amber
        case .quotedPassage: return Brand.statusDone        // dusty slate
        }
    }
}

// TypeBadge is defined in BrandTokens.swift

struct AddSourceSheetView: View {
    let onAdd: (Source) -> Void
    let onCancel: () -> Void

    @State private var selectedType: SourceType = .url
    @State private var title: String = ""
    @State private var urlString: String = ""
    @State private var filePath: String = ""
    @State private var passage: String = ""
    @State private var annotation: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Source")
                .font(.headline)

            Picker("Type", selection: $selectedType) {
                ForEach(SourceType.allCases, id: \.self) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.caption).foregroundColor(.secondary)
                TextField("Source title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            switch selectedType {
            case .url:
                VStack(alignment: .leading, spacing: 4) {
                    Text("URL")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("https://...", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                }
            case .localFile:
                VStack(alignment: .leading, spacing: 4) {
                    Text("File Path")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        Text(filePath.isEmpty ? "No file selected" : filePath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose File") {
                            pickFile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            case .quotedPassage:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Passage")
                        .font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $passage)
                        .font(.body)
                        .frame(height: 100)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Annotation (optional)")
                    .font(.caption).foregroundColor(.secondary)
                TextField("Notes about this source", text: $annotation)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Add Source") {
                    guard !title.isEmpty else { return }
                    let source = Source(
                        type: selectedType,
                        title: title,
                        urlString: selectedType == .url ? urlString : nil,
                        filePath: selectedType == .localFile ? filePath : nil,
                        passage: selectedType == .quotedPassage ? passage : nil,
                        annotation: annotation.isEmpty ? nil : annotation
                    )
                    onAdd(source)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func pickFile() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    filePath = url.path
                    if title.isEmpty {
                        title = url.lastPathComponent
                    }
                }
            }
        }
    }
}
