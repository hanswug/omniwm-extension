import Foundation

/// A long-lived child process whose stdout/stderr arrive line by line (for `omniwmctl subscribe`).
/// All callbacks run in order on a private serial queue, never the main thread.
/// `onExit` fires once, after the process exited *and* both pipes hit EOF, so no line is lost or reordered.
public final class LineStreamProcess: @unchecked Sendable {
    // @unchecked: `process` is configured before `start()`; every other mutable field is
    // touched only on `queue`.
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let queue = DispatchQueue(label: "com.omniwm.extension.linestream")

    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var stdoutEOF = false
    private var stderrEOF = false
    private var exitStatus: Int32?
    private var finished = false

    /// If a pipe never reaches EOF after exit (e.g. inherited by a grandchild), finish anyway.
    private static let eofGrace: DispatchTimeInterval = .seconds(1)

    private let onStdoutLine: @Sendable (String) -> Void
    private let onStderrLine: @Sendable (String) -> Void
    private let onExit: @Sendable (Int32) -> Void

    public init(
        executable: URL, arguments: [String], environment: [String: String]? = nil,
        onStdoutLine: @escaping @Sendable (String) -> Void,
        onStderrLine: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) {
        self.onStdoutLine = onStdoutLine
        self.onStderrLine = onStderrLine
        self.onExit = onExit
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice
    }

    public var processIdentifier: Int32 { process.processIdentifier }

    /// While the child runs, its handlers keep this object alive; they are cleared when it finishes.
    public func start() throws {
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            self.queue.async { self.receive(data, stderr: false) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            self.queue.async { self.receive(data, stderr: true) }
        }
        process.terminationHandler = { process in
            let status = process.terminationStatus
            self.queue.async {
                self.exitStatus = status
                self.finishIfDone()
                self.queue.asyncAfter(deadline: .now() + Self.eofGrace) { self.finish() }
            }
        }
        do {
            try process.run()
        } catch {
            clearHandlers()
            throw error
        }
    }

    /// Sends SIGTERM; `onExit` still fires.
    public func terminate() {
        if process.isRunning { process.terminate() }
    }

    // MARK: - On `queue`

    private func receive(_ data: Data, stderr: Bool) {
        guard !finished else { return }
        if data.isEmpty {
            if stderr {
                stderrEOF = true
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                stdoutEOF = true
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
            }
            finishIfDone()
            return
        }
        if stderr {
            stderrBuffer.append(data)
            deliverCompleteLines(from: &stderrBuffer, to: onStderrLine)
        } else {
            stdoutBuffer.append(data)
            deliverCompleteLines(from: &stdoutBuffer, to: onStdoutLine)
        }
    }

    private func deliverCompleteLines(from buffer: inout Data, to callback: @Sendable (String) -> Void) {
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            callback(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
    }

    private func finishIfDone() {
        if exitStatus != nil, stdoutEOF, stderrEOF { finish() }
    }

    private func finish() {
        guard !finished, let status = exitStatus else { return }
        finished = true
        clearHandlers()
        // A final line without a trailing newline.
        if !stdoutBuffer.isEmpty { onStdoutLine(String(decoding: stdoutBuffer, as: UTF8.self)) }
        if !stderrBuffer.isEmpty { onStderrLine(String(decoding: stderrBuffer, as: UTF8.self)) }
        stdoutBuffer = Data()
        stderrBuffer = Data()
        onExit(status)
    }

    private func clearHandlers() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
    }
}
