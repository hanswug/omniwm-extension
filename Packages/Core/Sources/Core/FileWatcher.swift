import Dispatch
import Foundation

/// Watches one file for changes, including atomic-rename saves (PDR §3.2).
///
/// Editors and OmniWM save by writing a temp file and renaming it over the
/// original, which replaces the inode. So this watches the parent directory
/// (entry added/removed/renamed) *and* the file itself (in-place writes),
/// re-opening the file watch whenever the inode may have changed.
/// Events are debounced; `handler` runs on the watcher's private queue.
public final class FileWatcher: @unchecked Sendable {
    // @unchecked: all mutable state is confined to `queue`.
    private let url: URL
    private let debounce: DispatchTimeInterval
    private let handler: @Sendable () -> Void
    private let queue: DispatchQueue

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var running = false

    public init(url: URL, debounce: DispatchTimeInterval = .milliseconds(150), handler: @escaping @Sendable () -> Void) {
        self.url = url
        self.debounce = debounce
        self.handler = handler
        queue = DispatchQueue(label: "com.omniwm.extension.filewatcher.\(url.lastPathComponent)")
    }

    deinit {
        directorySource?.cancel()
        fileSource?.cancel()
        pending?.cancel()
    }

    public func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            openDirectorySource()
            openFileSource()
        }
    }

    public func stop() {
        queue.sync {
            running = false
            pending?.cancel()
            pending = nil
            directorySource?.cancel()
            directorySource = nil
            fileSource?.cancel()
            fileSource = nil
        }
    }

    // MARK: - Private (on `queue`)

    private func openDirectorySource() {
        let directory = url.deletingLastPathComponent()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.config.error("FileWatcher: can't watch \(directory.path, privacy: .public): errno \(errno)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in self?.scheduleFire() }
        source.setCancelHandler { close(fd) }
        source.resume()
        directorySource = source
    }

    private func openFileSource() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return } // missing for now; the directory watch sees it appear
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke], queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if !source.data.isDisjoint(with: [.delete, .rename, .revoke]) {
                // The inode went away; re-open after the debounce.
                source.cancel()
                if fileSource === source { fileSource = nil }
            }
            scheduleFire()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSource = source
    }

    private func scheduleFire() {
        guard running else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, running else { return }
            pending = nil
            openFileSource()
            handler()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
