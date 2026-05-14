import SwiftUI
import AppKit

// MARK: - NewProjectFolderSheet

/// Sub-sheet presented when the user clicks "Create New Project Folder…" in the
/// connect-project panel's accessory view.
///
/// On successful creation the sheet calls `onConnect(folderURL, displayName)`.
/// `folderURL` is the newly-created directory; `displayName` is the original
/// (un-sanitized) typed name — used as the project's Display Name in Provenance.
struct NewProjectFolderSheet: View {
    /// Called on success. folderURL = the created directory; displayName = raw typed name.
    let onConnect: (URL, String) -> Void
    let onCancel: () -> Void

    @State private var projectName: String = ""
    @State private var location: URL = NewProjectFolderSheet.resolveDefaultLocation()
    @State private var createManuscript: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isCreating: Bool = false

    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Title
            Text("Create a new project folder")
                .font(.headline)
                .padding(.bottom, 20)

            // Project name
            VStack(alignment: .leading, spacing: 6) {
                Text("Project name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("The Mythos of Aria", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
                    .onSubmit { tryCreate() }
                    .onChange(of: projectName) { _ in errorMessage = nil }

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 16)

            // Location
            VStack(alignment: .leading, spacing: 6) {
                Text("Location")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text(friendlyPath(location))
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Change\u{2026}") { pickLocation() }
                        .controlSize(.small)
                }
            }
            .padding(.bottom, 16)

            // Optional manuscript.md
            Toggle(isOn: $createManuscript) {
                Text("Start with a blank manuscript.md file")
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            .padding(.bottom, 24)

            // Actions
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") { tryCreate() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            // Re-resolve on each appearance so the UserDefaults key is fresh
            location = NewProjectFolderSheet.resolveDefaultLocation()
            nameFieldFocused = true
        }
    }

    // MARK: - Create logic

    private func tryCreate() {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let sanitized = sanitizeFolderName(trimmed)
        let destination = location.appendingPathComponent(sanitized)

        // (c) Collision check
        if FileManager.default.fileExists(atPath: destination.path) {
            errorMessage = "A folder named \u{201C}\(sanitized)\u{201D} already exists here. Choose a different name or location."
            return
        }

        // (c-ext) Writability check (surfaces read-only volumes)
        guard FileManager.default.isWritableFile(atPath: location.path) else {
            errorMessage = "This location can\u{2019}t be written to."
            return
        }

        isCreating = true

        // (d) Create directory
        do {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: false,
                attributes: nil
            )
        } catch {
            errorMessage = "Couldn\u{2019}t create the folder. \(error.localizedDescription)"
            isCreating = false
            return
        }

        // (e) Optional manuscript.md — non-fatal if it fails
        if createManuscript {
            let manuscriptURL = destination.appendingPathComponent("manuscript.md")
            do {
                try "".write(to: manuscriptURL, atomically: true, encoding: .utf8)
            } catch {
                fputs("Provenance: manuscript.md creation failed: \(error)\n", stderr)
            }
        }

        // (f) Persist the chosen location for next time
        UserDefaults.standard.set(location.path, forKey: "provLastCreateProjectLocation")

        isCreating = false

        // (g) Hand off — display name = original typed text
        onConnect(destination, trimmed)
    }

    // MARK: - Location picker (plain panel, no accessory view)

    private func pickLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose Location"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = location
        // No accessory view — spec §6: only the connect-project flow gets the accessory

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { self.location = url }
        }
    }

    // MARK: - Helpers

    /// Sanitize for use as a filesystem folder name.
    /// Trims whitespace, replaces / and : with -, collapses internal whitespace.
    /// Returns the sanitized string; if unchanged the folder name equals the display name.
    private func sanitizeFolderName(_ name: String) -> String {
        var result = name
        result = result.replacingOccurrences(of: "/", with: "-")
        result = result.replacingOccurrences(of: ":", with: "-")
        let parts = result.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    private func friendlyPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    /// Resolves the default location: UserDefaults → ~/Documents/ → ~/
    static func resolveDefaultLocation() -> URL {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // 1. Saved from a previous Create
        if let saved = UserDefaults.standard.string(forKey: "provLastCreateProjectLocation") {
            let url = URL(fileURLWithPath: saved)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: saved, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }

        // 2. ~/Documents/
        let docs = home.appendingPathComponent("Documents")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: docs.path, isDirectory: &isDir), isDir.boolValue {
            return docs
        }

        // 3. ~/
        return home
    }
}
