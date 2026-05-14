import SwiftUI
import AppKit

// MARK: - MissingProjectView

/// Full-pane view shown when a selected project's folder can't be located.
/// Handles both `.volumeUnmounted` and `.notFound` resolution states.
struct MissingProjectView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var state: ProjectState

    @State private var showMismatchSheet = false
    @State private var mismatchPickedURL: URL? = nil

    var body: some View {
        switch state.resolutionStatus {
        case .volumeUnmounted(let volumeName):
            unmountedView(volumeName: volumeName)
        case .notFound:
            notFoundView
        default:
            EmptyView()   // shouldn't reach here — ContentView guards this
        }
    }

    // MARK: - Volume unmounted

    private func unmountedView(volumeName: String) -> some View {
        VStack(spacing: Brand.spaceLG) {
            Spacer()
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(Brand.textMuted)
            VStack(spacing: Brand.spaceSM) {
                Text("This project lives on \u{201C}\(volumeName)\u{201D}.")
                    .font(.title2.bold())
                    .foregroundColor(Brand.textPrimary)
                Text("Connect the drive to continue working.")
                    .font(.body)
                    .foregroundColor(Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.surfaceBase)
        // Start/stop the 30-second retry when this view appears/disappears
        .onAppear  { state.startUnmountedRetry() }
        .onDisappear { state.stopUnmountedRetry() }
    }

    // MARK: - Not found

    private var notFoundView: some View {
        VStack(spacing: Brand.spaceLG) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 44))
                .foregroundColor(Brand.textMuted)
            VStack(spacing: Brand.spaceSM) {
                Text("This folder couldn\u{2019}t be found.")
                    .font(.title2.bold())
                    .foregroundColor(Brand.textPrimary)
                Text("Move it back, or relink it from here.")
                    .font(.body)
                    .foregroundColor(Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: Brand.spaceMD) {
                Button("Disconnect") {
                    appState.removeProject(id: state.project.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Locate Folder\u{2026}") {
                    openLocatePanel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.surfaceBase)
        .sheet(isPresented: $showMismatchSheet) {
            DifferentProjectSheet(
                missingName: state.project.name,
                pickedURL: mismatchPickedURL
            ) { pickedURL in
                // Connect as a separate project
                showMismatchSheet = false
                Task { @MainActor in
                    try? appState.connectProject(at: pickedURL)
                }
            } onKeepMissing: {
                showMismatchSheet = false
            }
        }
    }

    // MARK: - Locate panel

    private func openLocatePanel() {
        let panel = NSOpenPanel()
        panel.title = "Locate Project Folder"
        panel.message = "Find the folder for \u{201C}\(state.project.name)\u{201D}."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { self.handleLocatePick(url: url) }
        }
    }

    private func handleLocatePick(url: URL) {
        // Must contain .ledger/manifest.json
        let manifestPath = url.appendingPathComponent(".ledger/manifest.json").path
        guard FileManager.default.fileExists(atPath: manifestPath) else {
            showNotProvenance()
            return
        }

        let pickedId   = LedgerWriter.readProjectIdFromManifest(at: url)
        let myId       = state.project.projectId

        if let pickedId, pickedId == myId {
            // ✓ Exact match — relink
            relinkTo(url)

        } else if pickedId == nil {
            // Pre-PR-10 manifest — fall back to display-name match
            let manifestName = LedgerWriter.readProjectNameFromManifest(at: url)
            if manifestName == state.project.name {
                // Write our projectId into the old manifest, then relink
                LedgerWriter.writeProjectIdToManifest(projectId: myId, to: url)
                relinkTo(url)
            } else {
                mismatchPickedURL = url
                showMismatchSheet = true
            }

        } else {
            // Different projectId — show confirmation
            mismatchPickedURL = url
            showMismatchSheet = true
        }
    }

    private func relinkTo(_ url: URL) {
        let bm = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var updated = state.project
        updated.folderURL      = url
        updated.folderBookmark = bm
        state.updateProject(updated)
        appState.store.update(updated)
        state.resolutionStatus = .found(url)
        state.loadData()
        state.startWatching()
        appState.showToast("Reconnected \u{201C}\(state.project.name)\u{201D}.")
    }

    private func showNotProvenance() {
        let alert = NSAlert()
        alert.messageText    = "Not a Provenance Project"
        alert.informativeText = "This folder isn\u{2019}t a Provenance project. Choose a folder that contains a .ledger/manifest.json file."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - DifferentProjectSheet

private struct DifferentProjectSheet: View {
    let missingName: String
    let pickedURL: URL?
    let onConnect: (URL) -> Void
    let onKeepMissing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Different Project")
                .font(.headline)

            Text("""
                This folder has a Provenance ledger, but its project ID doesn\u{2019}t match \
                \u{201C}\(missingName)\u{201D}. Connect it as a separate project, or keep \
                \u{201C}\(missingName)\u{201D} marked as missing?
                """)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Keep As Missing", action: onKeepMissing)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect As Separate Project") {
                    if let url = pickedURL { onConnect(url) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
