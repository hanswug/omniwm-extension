import Foundation
import Testing
@testable import Core

/// OmniWM Dev (protocol 22) output must parse like 0.7.6's (see Fixtures/omniwm-dev/README.md).
@Suite struct OmniWMDevFixtureTests {
    private func url(_ name: String) throws -> URL {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        return try #require(Bundle.module.url(
            forResource: parts[0],
            withExtension: parts[1],
            subdirectory: "Fixtures/omniwm-dev"
        ))
    }

    private func messages(_ name: String) throws -> [OmniWMMessage] {
        try String(contentsOf: url(name), encoding: .utf8)
            .components(separatedBy: "\n")
            .compactMap { try OmniWMParser.parseLine($0) }
    }

    private func query(_ name: String) throws -> OmniWMMessage {
        try OmniWMParser.parse(Data(contentsOf: url(name)))
    }

    @Test func initialSnapshotParses() throws {
        let messages = try messages("subscribe-initial.ndjson")
        #expect(messages.first == .subscribed)
        #expect(messages.contains { if case .focusedWindow(.some) = $0 { true } else { false } })
        #expect(messages.contains { if case .activeWorkspace = $0 { true } else { false } })

        let displays = messages.compactMap { if case let .displays(displays) = $0 { displays } else { nil } }
        #expect(displays.first?.first?.outerGapLeft == 640)
        #expect(displays.first?.first?.outerGapTop == 720)

        let workspaces = messages.compactMap { if case let .workspaces(workspaces) = $0 { workspaces } else { nil } }
        let current = try #require(workspaces.first?.first { $0.isCurrent == true })
        #expect(current.workspaceLayout == .niri)
        #expect(current.columns?.isEmpty == false)

        let windows = messages.compactMap { if case let .windows(windows) = $0 { windows } else { nil } }
        #expect(windows.first?.contains { $0.mode == "tiling" && $0.columnIndex != nil } == true)
    }

    @Test func queriesParse() throws {
        guard case let .workspaces(workspaces) = try query("query-workspaces.json") else {
            Issue.record("workspaces")
            return
        }
        #expect(workspaces.contains { $0.number == 1 })
        guard case let .displays(displays) = try query("query-displays.json") else {
            Issue.record("displays")
            return
        }
        #expect(displays.first?.name == "Odyssey Ark")
        guard case let .windows(windows) = try query("query-windows-focused.json") else {
            Issue.record("windows")
            return
        }
        #expect(windows.count == 1)
        #expect(windows.first?.frame != nil)
    }

    @Test func stateSettlesFromDevSnapshot() throws {
        var state = OmniWMState()
        for message in try messages("subscribe-initial.ndjson") {
            state.apply(message)
        }
        state.apply(try query("query-windows-focused.json"))
        #expect(state.currentWorkspaceRef?.number == 1)
        #expect(state.currentLayout == .niri)
    }
}
