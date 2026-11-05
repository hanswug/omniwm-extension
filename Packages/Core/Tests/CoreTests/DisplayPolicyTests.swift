import Foundation
import Testing
@testable import Core

private typealias Gaps = OmniWMSettings.OuterGaps
private let wide = Gaps(top: 540, bottom: 8, left: 8, right: 8)
private let custom = Gaps(top: 333.5, bottom: 12, left: 7.25, right: 99)

@Suite struct DisplayTopologyTests {
    @Test func classify() {
        #expect(DisplayTopology.classify(builtIn: [true]) == .builtInOnly)
        #expect(DisplayTopology.classify(builtIn: [true, false]) == .docked)
        #expect(DisplayTopology.classify(builtIn: [false]) == .docked) // clamshell
        #expect(DisplayTopology.classify(builtIn: []) == nil)
    }
}

@Suite struct DisplayPolicyTests {
    @Test func launchWithoutChangeDoesNothing() {
        for topology in [DisplayTopology.builtInOnly, .docked] {
            let state = DisplayState(lastTopology: topology, lastExternalGaps: wide)
            let decision = DisplayPolicy.decide(state: state, current: topology, currentGaps: custom, enabled: true)
            #expect(decision.action == .none)
            #expect(decision.state == state)
        }
    }

    @Test func firstRunOnlyRecords() {
        let decision = DisplayPolicy.decide(state: DisplayState(), current: .builtInOnly, currentGaps: wide, enabled: true)
        #expect(decision.action == .none)
        #expect(decision.state == DisplayState(lastTopology: .builtInOnly, lastExternalGaps: nil))
    }

    @Test func dockedToBuiltInSavesExactGapsAndAppliesFirstPreset() {
        let decision = DisplayPolicy.decide(state: DisplayState(lastTopology: .docked), current: .builtInOnly, currentGaps: wide, enabled: true)
        #expect(decision.action == .applyFirstPreset)
        #expect(decision.state == DisplayState(lastTopology: .builtInOnly, lastExternalGaps: wide))
    }

    @Test func customRoundTrips() {
        // Docked on Custom → laptop → re-dock: the exact Custom numbers come back.
        let undocked = DisplayPolicy.decide(state: DisplayState(lastTopology: .docked), current: .builtInOnly, currentGaps: custom, enabled: true)
        #expect(undocked.state.lastExternalGaps == custom)
        // Manual cycling on the laptop changes the live gaps but not the saved ones.
        let redocked = DisplayPolicy.decide(state: undocked.state, current: .docked, currentGaps: wide, enabled: true)
        #expect(redocked.action == .restore(custom))
        #expect(redocked.state.lastTopology == .docked)
    }

    @Test func builtInToDockedWithoutSavedGapsDoesNothing() {
        let decision = DisplayPolicy.decide(state: DisplayState(lastTopology: .builtInOnly), current: .docked, currentGaps: wide, enabled: true)
        #expect(decision.action == .none)
        #expect(decision.state.lastTopology == .docked)
    }

    @Test func disabledTracksTopologyOnly() {
        let state = DisplayState(lastTopology: .docked, lastExternalGaps: custom)
        let undocked = DisplayPolicy.decide(state: state, current: .builtInOnly, currentGaps: wide, enabled: false)
        #expect(undocked.action == .none)
        #expect(undocked.state == DisplayState(lastTopology: .builtInOnly, lastExternalGaps: custom))

        // Turning the setting on later (topology unchanged) doesn't fire.
        let enabledLater = DisplayPolicy.decide(state: undocked.state, current: .builtInOnly, currentGaps: wide, enabled: true)
        #expect(enabledLater.action == .none)

        let redockedDisabled = DisplayPolicy.decide(state: undocked.state, current: .docked, currentGaps: wide, enabled: false)
        #expect(redockedDisabled.action == .none)
    }

    @Test func unknownGapsForgetOldSavedValue() {
        let state = DisplayState(lastTopology: .docked, lastExternalGaps: custom)
        let decision = DisplayPolicy.decide(state: state, current: .builtInOnly, currentGaps: nil, enabled: true)
        #expect(decision.action == .applyFirstPreset)
        #expect(decision.state.lastExternalGaps == nil)
    }
}

@Suite struct DisplayStateStoreTests {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appending(path: "DisplayStateStoreTests-\(UUID().uuidString)/nested/state.json")
    }

    @Test func missingFileIsEmptyStateWithoutIssue() {
        let loaded = DisplayStateStore.load(from: url)
        #expect(loaded.state == DisplayState())
        #expect(loaded.issue == nil)
    }

    @Test func roundTrip() throws {
        let state = DisplayState(lastTopology: .builtInOnly, lastExternalGaps: custom)
        try DisplayStateStore.save(state, to: url)
        #expect(DisplayStateStore.load(from: url).state == state)
        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(json.contains("\"lastTopology\" : \"builtInOnly\""))
        #expect(json.contains("\"top\" : 333.5"))
    }

    @Test func corruptFileStartsFresh() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ nope".utf8).write(to: url)
        let loaded = DisplayStateStore.load(from: url)
        #expect(loaded.state == DisplayState())
        #expect(loaded.issue?.contains("corrupt") == true)
    }
}
