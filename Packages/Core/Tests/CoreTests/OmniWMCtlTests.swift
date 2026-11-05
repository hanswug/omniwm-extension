import Foundation
import Testing
@testable import Core

@Suite struct OmniWMCtlLocateTests {
    let home = URL(filePath: "/Users/test", directoryHint: .isDirectory)

    @Test func prefersBundledBinary() {
        let found = OmniWMCtl.locate(homeDirectory: home, environment: ["PATH": "/opt/bin"]) { _ in true }
        #expect(found?.path == OmniWMCtl.bundledPath)
    }

    @Test func fallsBackToUserApplications() {
        let found = OmniWMCtl.locate(homeDirectory: home, environment: ["PATH": "/opt/bin"]) { $0.hasPrefix("/Users/test/") }
        #expect(found?.path == "/Users/test/Applications/OmniWM.app/Contents/MacOS/omniwmctl")
    }

    @Test func fallsBackToPATHInOrder() {
        let found = OmniWMCtl.locate(homeDirectory: home, environment: ["PATH": "/a::/b:/c"]) { $0 == "/b/omniwmctl" || $0 == "/c/omniwmctl" }
        #expect(found?.path == "/b/omniwmctl")
    }

    @Test func missingEverywhere() {
        #expect(OmniWMCtl.locate(homeDirectory: home, environment: [:]) { _ in false } == nil)
    }
}

@Suite struct OmniWMCtlRunTests {
    @Test func capturesStatusAndOutput() async {
        let output = await OmniWMCtl.run(URL(filePath: "/bin/sh"), ["-c", "echo out; echo err >&2; exit 3"])
        #expect(output.status == 3)
        #expect(output.stdout == "out\n")
        #expect(output.stderr == "err\n")
        #expect(!output.timedOut)
        #expect(!output.succeeded)
    }

    @Test func success() async {
        #expect(await OmniWMCtl.run(URL(filePath: "/usr/bin/true"), []).succeeded)
    }

    @Test func largeOutputDoesNotDeadlock() async {
        // 1 MB, far beyond the 64 KB pipe buffer.
        let output = await OmniWMCtl.run(URL(filePath: "/bin/sh"), ["-c", "head -c 1048576 /dev/zero | tr '\\\\0' x"], timeout: .seconds(10))
        #expect(output.succeeded)
        #expect(output.stdout.count == 1_048_576)
    }

    @Test func timeoutTerminatesTheChild() async {
        let start = ContinuousClock.now
        let output = await OmniWMCtl.run(URL(filePath: "/bin/sleep"), ["10"], timeout: .milliseconds(200))
        #expect(output.timedOut)
        #expect(!output.succeeded)
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test func missingExecutable() async {
        let output = await OmniWMCtl.run(URL(filePath: "/nonexistent/omniwmctl"), [])
        #expect(output.status == -1)
        #expect(!output.succeeded)
    }
}
