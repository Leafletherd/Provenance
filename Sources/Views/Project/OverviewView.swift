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

    private let displayFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Project name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Project name", text: $projectName)
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
            }
            .padding(24)
        }
        .onAppear {
            projectName = state.project.name
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
