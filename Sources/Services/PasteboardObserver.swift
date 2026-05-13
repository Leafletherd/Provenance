import AppKit
import CryptoKit
import Foundation

/// Polls NSPasteboard at 4 Hz and maintains an in-memory ring buffer of the last 50 captures.
///
/// **Privacy contract:**
/// - No paste content is ever written to disk.
/// - Only a SHA256 hash and a 64-character preview are retained.
/// - The ring buffer lives entirely in memory and is cleared when the observer stops.
///
/// Ownership: one shared instance started by AppState on launch when paste tracking is enabled.
@MainActor
final class PasteboardObserver {

    static let shared = PasteboardObserver()
    private init() {}

    // MARK: - Ring buffer

    private(set) var ringBuffer: [PasteboardEvent] = []
    private let ringBufferCapacity = 50

    // MARK: - State

    private var timer: Timer?
    private var lastChangeCount: Int = -1

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        ringBuffer.removeAll()
    }

    // MARK: - Query

    /// Returns events from the ring buffer captured within the last `seconds` seconds.
    func recentEvents(within seconds: TimeInterval = 300) -> [PasteboardEvent] {
        let cutoff = Date().addingTimeInterval(-seconds)
        return ringBuffer.filter { $0.timestamp >= cutoff }
    }

    // MARK: - Polling

    private func poll() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if let event = capture(from: pb) {
            append(event)
        }
    }

    private func append(_ event: PasteboardEvent) {
        ringBuffer.append(event)
        if ringBuffer.count > ringBufferCapacity {
            ringBuffer.removeFirst(ringBuffer.count - ringBufferCapacity)
        }
    }

    // MARK: - Capture

    private func capture(from pb: NSPasteboard) -> PasteboardEvent? {
        let types = pb.types ?? []

        // ── Kind ──────────────────────────────────────────────────────────────
        let kind: PasteboardEvent.Kind
        if types.contains(.rtf) {
            kind = .rtf
        } else if types.contains(.string) {
            kind = .text
        } else if types.contains(.URL) {
            kind = .url
        } else if types.contains(.tiff) || types.contains(.png) {
            kind = .image
        } else {
            kind = .other
        }

        // ── String representation (for hashing & preview) ─────────────────────
        let rawString: String?
        switch kind {
        case .rtf:
            if let data = pb.data(forType: .rtf),
               let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
                rawString = attr.string
            } else {
                rawString = pb.string(forType: .string)
            }
        case .url:
            rawString = (NSURL(from: pb) as URL?)?.absoluteString
                ?? pb.string(forType: .string)
        case .image, .other:
            rawString = nil
        default:
            rawString = pb.string(forType: .string)
        }

        guard let text = rawString, !text.isEmpty else { return nil }

        let contentPreview = String(text.prefix(64))
        let contentLength  = text.utf8.count
        let contentHash    = sha256(text)

        // ── Source URL ────────────────────────────────────────────────────────
        let sourceURL: URL? = NSURL(from: pb) as URL?

        // ── Source bundle ID ──────────────────────────────────────────────────
        // First try the standard Cocoa pasteboard metadata type.
        var sourceBundleID: String? = nil
        let nspType = NSPasteboard.PasteboardType("org.nspasteboard.source")
        if let data = pb.data(forType: nspType),
           let str = String(data: data, encoding: .utf8), !str.isEmpty {
            sourceBundleID = str
        }
        // Fall back to the frontmost application.
        if sourceBundleID == nil {
            sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }

        let isAI = sourceURL.map { AISourceRegistry.isAISource($0) } ?? false

        return PasteboardEvent(
            id: UUID(),
            timestamp: Date(),
            contentHash: contentHash,
            contentPreview: contentPreview,
            contentLength: contentLength,
            kind: kind,
            sourceURL: sourceURL,
            sourceBundleID: sourceBundleID,
            isAI: isAI
        )
    }

    // MARK: - Hashing

    private func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
