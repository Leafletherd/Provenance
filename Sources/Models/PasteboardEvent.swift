import Foundation

/// A single clipboard capture — held in memory only, never written to disk.
/// Raw content is not kept: only a SHA256 hash and a 64-char preview.
struct PasteboardEvent: Identifiable {

    enum Kind: String, Codable {
        case text, rtf, url, image, other
    }

    let id: UUID
    let timestamp: Date
    /// SHA256 hex digest of the raw text content (UTF-8 bytes).
    let contentHash: String
    /// First 64 characters of the string representation.
    let contentPreview: String
    /// Byte length of the full string (UTF-8).
    let contentLength: Int
    let kind: Kind
    /// URL found on the pasteboard (public.url) — typically the page being copied from.
    let sourceURL: URL?
    /// Bundle ID of the app that put the content on the pasteboard, or the frontmost
    /// app at capture time if org.nspasteboard.source is absent.
    let sourceBundleID: String?
    /// True when `sourceURL` matches a known AI assistant host.
    let isAI: Bool
}

/// Persisted as the JSON metadata side-file for a `.paste` ledger event.
/// Does NOT contain full content — only the preview and provenance fields.
struct PasteMetadata: Codable {
    let contentPreview: String
    let contentLength: Int
    let kind: String
    let sourceURL: URL?
    let sourceBundleID: String?
    let isAI: Bool
    /// Project-relative path of the file where the paste was detected.
    let matchedFile: String
    /// Git commit hash of the auto-snapshot where the addition was detected.
    let snapshotHash: String?
}
