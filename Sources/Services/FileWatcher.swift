import Foundation
import CoreServices

// Top-level C-compatible callback — runs on the background watcher queue.
//
// ROOT CAUSE of all previous crashes:
// Without kFSEventStreamCreateFlagUseCFTypes in the stream flags, FSEvents
// delivers eventPaths as a plain C array of C strings (const char **), NOT as
// a CFArray. Every prior attempt — unsafeBitCast → NSArray, and
// Unmanaged<CFArray> → CFArrayGetCount — crashed because both treat the pointer
// as a CFArray/NSArray and eventually call objc_msgSend (selector "count" or
// "_conditionallyBridgeFromObjectiveC") on memory that is not an ObjC object.
//
// FIX: read eventPaths directly as UnsafePointer<UnsafePointer<CChar>> and
// convert each element with String(cString:). This is pure C — no ObjC, no
// ARC, no Swift bridging machinery of any kind.
private func fileWatcherEventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()

    // eventPaths is const char ** — a plain C array of null-terminated path strings.
    // Bind directly and copy each string before returning from the callback.
    let rawPaths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    var urls: [URL] = []
    for i in 0..<numEvents {
        let path = String(cString: rawPaths[i])
        urls.append(URL(fileURLWithPath: path))
    }

    watcher.handleEvents(urls: urls)
}

final class FileWatcher {
    private let url: URL
    private let onChange: ([URL]) -> Void
    private var stream: FSEventStreamRef?
    private let watcherQueue = DispatchQueue(label: "com.provenance.filewatcher", qos: .utility)

    init(url: URL, onChange: @escaping ([URL]) -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        let pathsToWatch = [url.path] as CFArray
        let selfPtr = Unmanaged.passRetained(self)
        var context = FSEventStreamContext(
            version: 0,
            info: selfPtr.toOpaque(),
            // Properly retain/release the FileWatcher through the context so
            // FSEvents holds a valid reference for the lifetime of the stream.
            retain: { ptr -> UnsafeRawPointer? in
                guard let p = ptr else { return nil }
                _ = Unmanaged<FileWatcher>.fromOpaque(p).retain()
                return ptr
            },
            release: { ptr in
                guard let p = ptr else { return }
                Unmanaged<FileWatcher>.fromOpaque(p).release()
            },
            copyDescription: nil
        )
        // passRetained above gives one reference; the context retain callback
        // will add another when FSEvents stores the context — balance by
        // releasing our local passRetained reference now.
        selfPtr.release()

        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(
            nil,
            fileWatcherEventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else { return }

        stream = s
        FSEventStreamSetDispatchQueue(s, watcherQueue)
        FSEventStreamStart(s)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    // Called on the background watcher queue.
    // Filters out .ledger internal events, then dispatches to main for onChange.
    fileprivate func handleEvents(urls: [URL]) {
        let filtered = urls.filter { !$0.path.contains("/.ledger/") }
        guard !filtered.isEmpty else { return }
        DispatchQueue.main.async { [onChange = self.onChange] in
            onChange(filtered)
        }
    }

    deinit { stop() }
}
