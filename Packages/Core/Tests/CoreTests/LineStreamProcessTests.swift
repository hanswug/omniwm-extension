import Foundation
import Synchronization
import Testing
@testable import Core

private final class Collected: Sendable {
    let stdout = Mutex<[String]>([])
    let stderr = Mutex<[String]>([])
    let status = Mutex<Int32?>(nil)

    func waitForExit(timeout: Duration = .seconds(5)) async -> Int32? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let status = status.withLock({ $0 }) { return status }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }
}

@Suite struct LineStreamProcessTests {
    private func run(_ script: String) throws -> (LineStreamProcess, Collected) {
        let collected = Collected()
        let process = LineStreamProcess(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", script],
            onStdoutLine: { line in collected.stdout.withLock { $0.append(line) } },
            onStderrLine: { line in collected.stderr.withLock { $0.append(line) } },
            onExit: { status in collected.status.withLock { $0 = status } }
        )
        try process.start()
        return (process, collected)
    }

    @Test func splitsLinesAcrossChunksInOrder() async throws {
        // Partial writes with pauses: lines must be reassembled across chunks.
        let (_, collected) = try run("printf 'one\\ntw'; sleep 0.1; printf 'o\\nthree\\n'; printf 'err1\\n' >&2; exit 4")
        #expect(await collected.waitForExit() == 4)
        #expect(collected.stdout.withLock { $0 } == ["one", "two", "three"])
        #expect(collected.stderr.withLock { $0 } == ["err1"])
    }

    @Test func flushesFinalLineWithoutNewline() async throws {
        let (_, collected) = try run("printf 'a\\nlast'")
        #expect(await collected.waitForExit() == 0)
        #expect(collected.stdout.withLock { $0 } == ["a", "last"])
    }

    @Test func terminateStopsALongRunningChild() async throws {
        let (process, collected) = try run("echo started; sleep 30")
        try await Task.sleep(for: .milliseconds(200))
        process.terminate()
        #expect(await collected.waitForExit() != nil)
        #expect(collected.stdout.withLock { $0 } == ["started"])
        #expect(kill(process.processIdentifier, 0) != 0) // gone
    }

    @Test func manyLines() async throws {
        let (_, collected) = try run("i=0; while [ $i -lt 2000 ]; do echo line$i; i=$((i+1)); done")
        #expect(await collected.waitForExit() == 0)
        let lines = collected.stdout.withLock { $0 }
        #expect(lines.count == 2000)
        #expect(lines.last == "line1999")
    }

    @Test func missingExecutableThrows() {
        let process = LineStreamProcess(
            executable: URL(filePath: "/nonexistent/omniwmctl"), arguments: [],
            onStdoutLine: { _ in }, onStderrLine: { _ in }, onExit: { _ in }
        )
        #expect(throws: (any Error).self) { try process.start() }
    }
}
