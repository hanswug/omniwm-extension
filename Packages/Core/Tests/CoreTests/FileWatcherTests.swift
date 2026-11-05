import Foundation
import Synchronization
import Testing
@testable import Core

/// Thread-safe event counter for the watcher callback.
private final class Counter: Sendable {
    private let value = Mutex(0)
    func increment() { value.withLock { $0 += 1 } }
    var count: Int { value.withLock { $0 } }

    /// Polls until `count >= target` or the timeout passes.
    func wait(for target: Int, timeout: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if count >= target { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return count >= target
    }
}

/// Timing-based; serialized so parallel tests don't starve the debounce.
@Suite(.serialized) struct FileWatcherTests {
    let directory: URL
    let file: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "FileWatcherTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "config.toml")
        try Data("a = 1\n".utf8).write(to: file)
    }

    private func makeWatcher(_ counter: Counter) -> FileWatcher {
        let watcher = FileWatcher(url: file, debounce: .milliseconds(50)) { counter.increment() }
        watcher.start()
        return watcher
    }

    /// Lets `start()` (async on the watcher queue) open its sources.
    private func settle() async { try? await Task.sleep(for: .milliseconds(100)) }

    @Test func inPlaceWriteFires() async throws {
        let counter = Counter()
        let watcher = makeWatcher(counter)
        defer { watcher.stop() }
        await settle()

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("b = 2\n".utf8))
        try handle.close()

        #expect(await counter.wait(for: 1))
    }

    @Test func atomicRenameSaveFiresRepeatedly() async throws {
        let counter = Counter()
        let watcher = makeWatcher(counter)
        defer { watcher.stop() }
        await settle()

        try Data("a = 2\n".utf8).write(to: file, options: .atomic)
        #expect(await counter.wait(for: 1))
        let afterFirst = counter.count

        // The inode changed; a second save must still be seen.
        try await Task.sleep(for: .milliseconds(150))
        try Data("a = 3\n".utf8).write(to: file, options: .atomic)
        #expect(await counter.wait(for: afterFirst + 1))
    }

    @Test func inPlaceWriteAfterAtomicSaveFires() async throws {
        let counter = Counter()
        let watcher = makeWatcher(counter)
        defer { watcher.stop() }
        await settle()

        try Data("a = 2\n".utf8).write(to: file, options: .atomic)
        #expect(await counter.wait(for: 1))
        try await Task.sleep(for: .milliseconds(150))
        let before = counter.count

        // Proves the file source was re-opened on the new inode.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("b = 2\n".utf8))
        try handle.close()
        #expect(await counter.wait(for: before + 1))
    }

    @Test func burstIsDebouncedIntoOneCallback() async throws {
        let counter = Counter()
        let watcher = makeWatcher(counter)
        defer { watcher.stop() }
        await settle()

        for index in 0..<10 {
            try Data("a = \(index)\n".utf8).write(to: file)
        }
        #expect(await counter.wait(for: 1))
        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.count == 1)
    }

    @Test func deleteAndRecreateFires() async throws {
        let counter = Counter()
        let watcher = makeWatcher(counter)
        defer { watcher.stop() }
        await settle()

        try FileManager.default.removeItem(at: file)
        #expect(await counter.wait(for: 1))
        try await Task.sleep(for: .milliseconds(150))
        let before = counter.count
        try Data("a = 9\n".utf8).write(to: file)
        #expect(await counter.wait(for: before + 1))
    }

    @Test func stopSilencesEvents() async throws {
        let counter = Counter()
        let watcher = makeWatcher(counter)
        await settle()
        watcher.stop()

        try Data("a = 5\n".utf8).write(to: file, options: .atomic)
        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.count == 0)
    }
}
