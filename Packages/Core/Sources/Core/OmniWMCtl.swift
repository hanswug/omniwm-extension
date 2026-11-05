import Foundation
import Synchronization

/// Locates and runs OmniWM's bundled `omniwmctl` (PDR §2, §6.7). Never speaks the wire protocol itself.
public enum OmniWMCtl {
    public static let bundledPath = "/Applications/OmniWM.app/Contents/MacOS/omniwmctl"

    /// `/Applications/…` → `~/Applications/…` → `PATH` (PDR §6.7).
    public static func locate(
        homeDirectory: URL,
        environment: [String: String],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        var candidates = [
            bundledPath,
            homeDirectory.appending(path: "Applications/OmniWM.app/Contents/MacOS/omniwmctl").path,
        ]
        for directory in (environment["PATH"] ?? "").split(separator: ":") where !directory.isEmpty {
            candidates.append("\(directory)/omniwmctl")
        }
        return candidates.first(where: isExecutable).map { URL(filePath: $0) }
    }

    public struct Output: Sendable, Equatable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
        public let timedOut: Bool

        public var succeeded: Bool { status == 0 && !timedOut }
    }

    /// Runs a one-shot command; terminates it after `timeout`. Pipes are drained while it runs,
    /// so large output can't block the child.
    public static func run(_ executable: URL, _ arguments: [String], timeout: Duration = .seconds(2)) async -> Output {
        let child = Child(executable: executable, arguments: arguments)
        let timer = Task.detached {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { child.terminateIfRunning() }
        }
        let status: Int32 = await withCheckedContinuation { continuation in
            child.start { continuation.resume(returning: $0) }
        }
        timer.cancel()
        return child.output(status: status)
    }
}

/// A child process plus its captured output. `@unchecked Sendable`: `Process` is
/// thread-safe for these calls, and the buffers are guarded by mutexes.
private final class Child: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdoutData = Mutex(Data())
    private let stderrData = Mutex(Data())
    private let timedOut = Mutex(false)
    /// False if `run()` failed: the pipes' write ends were never handed to a child, so reading would block forever.
    private let launched = Mutex(false)

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice
    }

    /// The handlers retain `self` until `stopReading()` clears them in `output(status:)`.
    func start(onExit: @escaping @Sendable (Int32) -> Void) {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            self.stdoutData.withLock { $0.append(chunk) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            self.stderrData.withLock { $0.append(chunk) }
        }
        process.terminationHandler = { finished in onExit(finished.terminationStatus) }
        // Set before run(): a fast child can exit (and output() run) before run() even returns.
        launched.withLock { $0 = true }
        do {
            try process.run()
        } catch {
            launched.withLock { $0 = false }
            process.terminationHandler = nil
            stopReading()
            onExit(-1)
        }
    }

    func terminateIfRunning() {
        guard process.isRunning else { return }
        timedOut.withLock { $0 = true }
        process.terminate()
    }

    func output(status: Int32) -> OmniWMCtl.Output {
        stopReading()
        guard launched.withLock({ $0 }) else {
            return OmniWMCtl.Output(status: status, stdout: "", stderr: "", timedOut: false)
        }
        // Whatever arrived after the last readability callback.
        let restOut = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? nil
        let restErr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? nil
        let out = stdoutData.withLock { $0 + (restOut ?? Data()) }
        let err = stderrData.withLock { $0 + (restErr ?? Data()) }
        return OmniWMCtl.Output(
            status: status,
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self),
            timedOut: timedOut.withLock { $0 }
        )
    }

    private func stopReading() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }
}
