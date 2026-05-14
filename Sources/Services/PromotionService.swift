import Foundation
import AppKit

/// Handles "Promote to Works" — writes the .provenance.bundle, appends a
/// ledger event, and fires the `works://add?path=` URL.
///
/// The URL dispatch is fire-and-forget. The bundle on disk is the durable
/// success criterion regardless of whether Works is installed.
struct PromotionService {

    struct PromotionResult {
        let bundleURL: URL
        let checkInCount: Int
        let sourceCount: Int
        let artifactCount: Int
    }

    /// Promote `state.project` to Works.
    /// Must be called on the main actor (reads @Published state).
    @MainActor
    static func promote(state: ProjectState) async throws -> PromotionResult {
        let proj  = state.project
        let cis   = state.checkIns
        let srcs  = state.sources
        let arts  = state.artifacts

        // Write / refresh the bundle on a background thread.
        let result = try await Task.detached(priority: .userInitiated) {
            try ExportService.exportBundle(project: proj, checkIns: cis,
                                           sources: srcs, artifacts: arts)
        }.value

        // Append ledger event on main actor.
        let detail = "Promoted to Works — \(result.checkInCount) check-in\(result.checkInCount == 1 ? "" : "s"), " +
                     "\(result.sourceCount) source\(result.sourceCount == 1 ? "" : "s"), " +
                     "\(result.artifactCount) artifact\(result.artifactCount == 1 ? "" : "s")."
        LedgerWriter.appendEvent(type: .promotedToWorks, detail: detail, to: proj)
        state.reloadEvents()

        // Dispatch works://add?path= (fire-and-forget).
        let encodedPath = proj.folderURL.path
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? proj.folderURL.path
        if let worksURL = URL(string: "works://add?path=\(encodedPath)") {
            NSWorkspace.shared.open(worksURL)
        }

        return PromotionResult(
            bundleURL: result.url,
            checkInCount: result.checkInCount,
            sourceCount: result.sourceCount,
            artifactCount: result.artifactCount
        )
    }
}
