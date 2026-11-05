import Foundation
import Testing
@testable import Core

/// Captured `omniwmctl` output (see Fixtures/omniwm/README.md).
enum OmniWMFixture {
    static func url(_ name: String) throws -> URL {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        return try #require(Bundle.module.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Fixtures/omniwm"))
    }

    static func lines(_ name: String) throws -> [String] {
        try String(contentsOf: url(name), encoding: .utf8).components(separatedBy: "\n")
    }

    /// Every parseable message of an NDJSON fixture, in order.
    static func messages(_ name: String) throws -> [OmniWMMessage] {
        try lines(name).compactMap { try OmniWMParser.parseLine($0) }
    }

    static func query(_ name: String) throws -> OmniWMMessage {
        try OmniWMParser.parse(Data(contentsOf: url(name)))
    }

    /// State after the initial snapshot, with Safari focused (as during the toggle captures).
    static func baseline() throws -> OmniWMState {
        var state = OmniWMState()
        for message in try messages("subscribe-initial.ndjson") { state.apply(message) }
        state.apply(try query("query-windows-focused.json"))
        return state
    }
}

// MARK: - Parser

@Suite struct OmniWMParserTests {
    @Test func initialSnapshotParsesEveryChannel() throws {
        let messages = try OmniWMFixture.messages("subscribe-initial.ndjson")
        #expect(messages.count == 8)
        #expect(messages.first == .subscribed)

        guard case let .focusedWindow(window?) = messages[1] else { Issue.record("focus"); return }
        #expect(window.isFullscreen == false)
        #expect(window.frame?.width == 1931)
        #expect(window.workspace?.number == 1)

        #expect(messages.contains { if case .ignored("workspace-bar/workspace-bar") = $0 { true } else { false } })
        #expect(messages.contains { if case .ignored("focused-monitor/focused-monitor") = $0 { true } else { false } })

        guard case let .activeWorkspace(active) = messages[3] else { Issue.record("active"); return }
        #expect(active.workspace?.number == 1)
        #expect(active.display?.id == "display:2")

        guard case let .displays(displays) = messages[6] else { Issue.record("displays"); return }
        #expect(displays.first?.visibleFrame == OmniWMRect(x: 0, y: 58, width: 3840, height: 2072))
        #expect(displays.first?.outerGapLeft == 8)
        #expect(displays.first?.outerGapTop == 720)

        guard case let .workspaces(workspaces) = messages[7] else { Issue.record("workspaces"); return }
        #expect(workspaces.first?.workspaceLayout == .niri)
        #expect(workspaces.first?.columns?.count == 2)
        #expect(workspaces.first?.isCurrent == true)
    }

    @Test func windowsChangedHasModeAndColumns() throws {
        let messages = try OmniWMFixture.messages("subscribe-initial.ndjson")
        guard case let .windows(windows) = messages[5] else { Issue.record("windows"); return }
        let safari = try #require(windows.first { $0.columnIndex == 1 })
        #expect(safari.mode == "tiling")
        #expect(safari.isFullscreen == false)
        #expect(windows.contains { $0.mode == "floating" })
    }

    @Test func queriesParse() throws {
        guard case let .workspaces(workspaces) = try OmniWMFixture.query("query-workspaces.json") else { Issue.record("ws"); return }
        #expect(workspaces.map(\.number) == [1, 2, 3, 4])
        guard case let .displays(displays) = try OmniWMFixture.query("query-displays.json") else { Issue.record("d"); return }
        #expect(displays.first?.name == "Odyssey Ark")
        guard case let .windows(windows) = try OmniWMFixture.query("query-windows-focused-fullscreen.json") else { Issue.record("w"); return }
        #expect(windows.count == 1)
        #expect(windows.first?.isFullscreen == true)
        #expect(windows.first?.frame?.width == 3824)
        guard case .focusedWindow(_?) = try OmniWMFixture.query("query-focused-window.json") else { Issue.record("fw"); return }
    }

    @Test func dwindleWorkspaceHasNoColumns() throws {
        let messages = try OmniWMFixture.messages("toggle-workspace-layout.ndjson")
        guard case let .workspaces(workspaces) = messages[1] else { Issue.record("ws"); return }
        let current = try #require(workspaces.first { $0.isCurrent == true })
        #expect(current.workspaceLayout == .dwindle)
        #expect(current.columns == nil)
    }

    @Test func emptyFocusPayloadMeansNoFocusedWindow() throws {
        let messages = try OmniWMFixture.messages("switch-workspace.ndjson")
        #expect(messages.contains(.focusedWindow(nil)))
    }

    @Test func edgeCases() throws {
        let lines = try OmniWMFixture.lines("edge-cases.ndjson")
        #expect(try OmniWMParser.parseLine(lines[0]) == .subscribed)
        #expect(throws: OmniWMParseError.self) { try OmniWMParser.parseLine(lines[2]) }   // truncated JSON
        #expect(throws: OmniWMParseError.self) { try OmniWMParser.parseLine(lines[3]) }   // garbage
        #expect(try OmniWMParser.parseLine(lines[4]) == .ignored("telemetry-v2/telemetry")) // unknown channel
        #expect(try OmniWMParser.parseLine(lines[5]) == .ignored("layout-changed/something-new")) // unknown kind
        #expect(try OmniWMParser.parseLine(lines[6]) == nil)                                // blank
        guard case .workspaces = try OmniWMParser.parseLine(lines[7]) else { Issue.record("real line after junk"); return }
    }

    @Test func oneBadWindowDoesNotDropTheList() throws {
        let line = #"{"channel":"windows-changed","kind":"event","ok":true,"result":{"kind":"windows","payload":{"windows":[{"id":"a","isFocused":true,"frame":{"x":"oops"}},{"id":"b","isFocused":false}]}},"status":"success"}"#
        guard case let .windows(windows) = try OmniWMParser.parseLine(line) else { Issue.record("windows"); return }
        #expect(windows.map(\.id) == ["b"])
    }

    @Test func transportFailure() throws {
        let message = try #require(try OmniWMFixture.messages("transport-failure.ndjson").first)
        guard case let .failure(code, message) = message else { Issue.record("failure"); return }
        #expect(code == "transport_failure")
        #expect(message?.contains("No such file") == true)
    }
}

// MARK: - State and toggles (replaying the real captures)

@Suite struct OmniWMStateTests {
    @Test func baselineIsNiriWithoutFocusState() throws {
        let state = try OmniWMFixture.baseline()
        #expect(state.currentLayout == .niri)
        #expect(state.currentWorkspaceRef?.number == 1)
        #expect(!state.isFullscreen)
        #expect(!state.isFullContainer)
        #expect(state.focusIndicator == .none)
    }

    @Test func fullscreenToggle() throws {
        let baseline = try OmniWMFixture.baseline()
        var on = baseline
        for message in try OmniWMFixture.messages("toggle-fullscreen.ndjson") { on.apply(message) }
        on.apply(try OmniWMFixture.query("query-windows-focused-fullscreen.json"))
        #expect(on.focusIndicator == .fullscreen)
        #expect(OmniWMToggles.transitions(from: baseline, to: on) == [.fullscreenOn])

        // Off emits no event; the app's poll query brings it back.
        var off = on
        off.apply(try OmniWMFixture.query("query-windows-focused.json"))
        #expect(off.focusIndicator == .none)
        #expect(OmniWMToggles.transitions(from: on, to: off) == [.fullscreenOff])
    }

    @Test func fullscreenEventAloneAlreadyCounts() throws {
        // The on-event carries isFullscreen=true with the old frame.
        let baseline = try OmniWMFixture.baseline()
        var state = baseline
        for message in try OmniWMFixture.messages("toggle-fullscreen.ndjson") { state.apply(message) }
        #expect(state.isFullscreen)
        #expect(OmniWMToggles.transitions(from: baseline, to: state) == [.fullscreenOn])
    }

    @Test func workspaceLayoutToggle() throws {
        let baseline = try OmniWMFixture.baseline()
        let messages = try OmniWMFixture.messages("toggle-workspace-layout.ndjson")
        var dwindle = baseline
        for message in messages.prefix(3) { dwindle.apply(message) } // ack, layout(dwindle), windows
        #expect(dwindle.currentLayout == .dwindle)
        #expect(OmniWMToggles.transitions(from: baseline, to: dwindle) == [.layoutDwindle])

        var niri = dwindle
        for message in messages.dropFirst(3) { niri.apply(message) }
        #expect(niri.currentLayout == .niri)
        #expect(OmniWMToggles.transitions(from: dwindle, to: niri) == [.layoutNiri])
    }

    @Test func fullContainerToggle() throws {
        let baseline = try OmniWMFixture.baseline()
        let messages = try OmniWMFixture.messages("toggle-full-span.ndjson")
        var on = baseline
        on.apply(messages[1]) // layout-changed: other column pushed "after"
        on.apply(try OmniWMFixture.query("query-windows-focused-full-span.json"))
        #expect(on.focusIndicator == .fullContainer)
        #expect(OmniWMToggles.transitions(from: baseline, to: on) == [.fullContainerOn])

        var off = on
        off.apply(messages[2])
        off.apply(try OmniWMFixture.query("query-windows-focused.json"))
        #expect(off.focusIndicator == .none)
        #expect(OmniWMToggles.transitions(from: on, to: off) == [.fullContainerOff])
    }

    @Test func fullContainerNeedsTwoColumns() throws {
        var state = try OmniWMFixture.baseline()
        state.apply(try OmniWMFixture.query("query-windows-focused-full-span.json"))
        #expect(state.isFullContainer)
        state.workspaces = state.workspaces.map { workspace in
            var copy = workspace
            if copy.isCurrent == true { copy.columns = [OmniWMColumn(index: 1, viewport: "intersecting")] }
            return copy
        }
        #expect(!state.isFullContainer) // a lone full-width window isn't a "full container"
    }

    @Test func fullscreenWinsOverFullContainer() throws {
        var state = try OmniWMFixture.baseline()
        state.apply(try OmniWMFixture.query("query-windows-focused-fullscreen.json"))
        #expect(state.focusIndicator == .fullscreen) // width is full too, but F wins
    }

    @Test func workspaceSwitchFiresNothing() throws {
        var previous = try OmniWMFixture.baseline()
        for message in try OmniWMFixture.messages("switch-workspace.ndjson") {
            var next = previous
            next.apply(message)
            #expect(OmniWMToggles.transitions(from: previous, to: next).isEmpty, "\(message)")
            previous = next
        }
    }

    @Test func focusChangeFiresNothing() throws {
        let baseline = try OmniWMFixture.baseline()
        var other = baseline
        var window = try #require(baseline.focusedWindow)
        window.id = "another-window"
        window.isFullscreen = true
        other.focusedWindow = window
        #expect(OmniWMToggles.transitions(from: baseline, to: other).isEmpty)
    }

    @Test func initialSnapshotAndReconnectFireNothing() throws {
        let baseline = try OmniWMFixture.baseline()
        #expect(OmniWMToggles.transitions(from: OmniWMState(), to: baseline).isEmpty)
        var fullscreen = baseline
        fullscreen.apply(try OmniWMFixture.query("query-windows-focused-fullscreen.json"))
        #expect(OmniWMToggles.transitions(from: OmniWMState(), to: fullscreen).isEmpty)
    }

    @Test func focusEventKeepsModeOfSameWindow() throws {
        var state = try OmniWMFixture.baseline()
        let mode = state.focusedWindow?.mode
        var event = try #require(state.focusedWindow)
        event.mode = nil
        event.columnIndex = nil
        state.apply(.focusedWindow(event))
        #expect(state.focusedWindow?.mode == mode)
    }
}
