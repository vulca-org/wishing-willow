import Foundation
import CoreServices

/// Watches one directory with FSEvents.
///
/// Not `DispatchSource.makeFileSystemObjectSource`: the plugin writes each state
/// file to a temp name and `rename(2)`s it into place, which swaps the inode.
/// A vnode source holds a file descriptor on the *old* inode and goes quiet
/// after the first write — the failure looks exactly like "nothing is happening",
/// which is the one failure mode this project cannot afford anywhere.
///
/// `NoDefer` delivers the first event immediately instead of at the end of the
/// latency window, so a fresh turn shows up at once rather than a second later.
/// `WatchRoot` keeps the stream valid if the directory itself is moved or
/// recreated — the plugin recreates it whenever someone deletes it.
final class DirectoryWatcher: @unchecked Sendable {
    private let url: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "app.willow.watch", qos: .utility)
    private var stream: FSEventStreamRef?

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagWatchRoot
            | kFSEventStreamCreateFlagFileEvents
        )

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
            },
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}
