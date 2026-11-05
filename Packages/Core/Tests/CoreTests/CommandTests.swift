import Foundation
import Testing
@testable import Core

private typealias Gaps = OmniWMSettings.OuterGaps
private let defaults = ExtConfig.builtInDefault.padding // Fullscreen, Wide, Single

private func preset(_ name: String, _ top: Double, _ bottom: Double, _ left: Double, _ right: Double) -> ExtConfig.PaddingPreset {
    .init(name: name, top: top, bottom: bottom, left: left, right: right, hotkey: nil)
}

@Suite struct PresetMatcherTests {
    @Test func exactMatch() {
        #expect(PresetMatcher.match(Gaps(top: 8, bottom: 8, left: 8, right: 8), presets: defaults) == .preset(0))
        #expect(PresetMatcher.match(Gaps(top: 540, bottom: 8, left: 8, right: 8), presets: defaults) == .preset(1))
        #expect(PresetMatcher.match(Gaps(top: 720, bottom: 8, left: 640, right: 640), presets: defaults) == .preset(2))
    }

    @Test(arguments: [0.0, 0.005, -0.005, 0.01, -0.01])
    func withinToleranceMatches(_ delta: Double) {
        #expect(PresetMatcher.match(Gaps(top: 540 + delta, bottom: 8, left: 8 - delta, right: 8), presets: defaults) == .preset(1))
    }

    @Test(arguments: [0.011, -0.02, 1.0])
    func outsideToleranceIsCustom(_ delta: Double) {
        #expect(PresetMatcher.match(Gaps(top: 540, bottom: 8 + delta, left: 8, right: 8), presets: defaults) == .custom)
    }

    @Test func noMatchIsCustom() {
        #expect(PresetMatcher.match(Gaps(top: 100, bottom: 8, left: 8, right: 8), presets: defaults) == .custom)
        #expect(PresetMatcher.match(Gaps(top: 8, bottom: 8, left: 8, right: 8), presets: []) == .custom)
    }

    @Test func eachEdgeMatters() {
        // Same top as Wide, but right differs → Custom.
        #expect(PresetMatcher.match(Gaps(top: 540, bottom: 8, left: 8, right: 9), presets: defaults) == .custom)
    }

    @Test func firstMatchWins() {
        let presets = [preset("A", 1, 2, 3, 4), preset("B", 1, 2, 3, 4), preset("C", 1, 2, 3, 4.005)]
        #expect(PresetMatcher.match(Gaps(top: 1, bottom: 2, left: 3, right: 4), presets: presets) == .preset(0))
        #expect(PresetMatcher.match(Gaps(top: 1, bottom: 2, left: 3, right: 4.005), presets: presets) == .preset(0))
    }

    @Test func cycleOrder() {
        #expect(PresetMatcher.next(after: .preset(0), count: 3) == 1)
        #expect(PresetMatcher.next(after: .preset(1), count: 3) == 2)
        #expect(PresetMatcher.next(after: .preset(2), count: 3) == 0) // wrap-around
        #expect(PresetMatcher.next(after: .custom, count: 3) == 0)    // from Custom → first
        #expect(PresetMatcher.next(after: .preset(0), count: 1) == 0) // single preset
        #expect(PresetMatcher.next(after: .custom, count: 0) == nil)
    }

    @Test func fullCycleVisitsEveryPresetAndWraps() {
        var selection = PaddingSelection.custom
        var visited: [String] = []
        for _ in 0..<4 {
            let index = PresetMatcher.next(after: selection, count: defaults.count) ?? -1
            visited.append(defaults[index].name)
            selection = .preset(index)
        }
        #expect(visited == ["Fullscreen", "Wide", "Single", "Fullscreen"])
    }
}

@Suite struct CommandPlannerTests {
    private func plan(_ command: Command, layout: WorkspaceLayout? = nil, text: String? = nil) throws -> (edits: [SettingsEdit], result: CommandResult) {
        try CommandPlanner.plan(command, presets: defaults, layout: layout, text: text ?? Fixture.settingsText)
    }

    @Test func cycleFromWideGoesToSingle() throws {
        // The fixture is on Wide (top 540).
        let plan = try plan(.cyclePadding)
        #expect(plan.result == .paddingSet(name: "Single"))
        #expect(plan.edits == [
            .init(table: "gaps.outer", key: "top", value: .float(720)),
            .init(table: "gaps.outer", key: "bottom", value: .float(8)),
            .init(table: "gaps.outer", key: "left", value: .float(640)),
            .init(table: "gaps.outer", key: "right", value: .float(640)),
        ])
    }

    @Test func cycleFromCustomGoesToFirst() throws {
        let text = try Fixture.settingsText.replacingOccurrences(of: "top = 540.0", with: "top = 333.0")
        #expect(try plan(.cyclePadding, text: text).result == .paddingSet(name: "Fullscreen"))
    }

    @Test func cycleWrapsFromLast() throws {
        let text = try Fixture.settingsText
            .replacingOccurrences(of: "top = 540.0", with: "top = 720.0")
            .replacingOccurrences(of: "left = 8.0\nright = 8.0\ntop", with: "left = 640.0\nright = 640.0\ntop")
        #expect(try plan(.cyclePadding, text: text).result == .paddingSet(name: "Fullscreen"))
    }

    @Test func selectPresetIsCaseInsensitive() throws {
        let plan = try plan(.selectPreset("fullscreen"))
        #expect(plan.result == .paddingSet(name: "Fullscreen"))
        #expect(plan.edits.map(\.value) == [.float(8), .float(8), .float(8), .float(8)])
    }

    @Test func unknownPresetIsAnError() throws {
        #expect(throws: CommandError.unknownPreset("Nope")) { try plan(.selectPreset("Nope")) }
    }

    @Test func visibleContainers() throws {
        let plan = try plan(.visibleContainers(3))
        #expect(plan.result == .containersSet(3))
        #expect(plan.edits == [.init(table: "niri", key: "visibleContainerCount", value: .int(3))])
    }

    @Test func visibleContainersUnknownLayoutApplies() throws {
        #expect(try plan(.visibleContainers(4), layout: nil).result == .containersSet(4))
        #expect(try plan(.visibleContainers(4), layout: .niri).result == .containersSet(4))
    }

    @Test func visibleContainersOnDwindleIsSkipped() throws {
        let plan = try plan(.visibleContainers(4), layout: .dwindle)
        #expect(plan.result == .skippedDwindle)
        #expect(plan.edits.isEmpty)
    }

    @Test(arguments: [0, 7, -1])
    func visibleContainersOutOfRange(_ count: Int) throws {
        #expect(throws: CommandError.invalidContainerCount(count)) { try plan(.visibleContainers(count)) }
    }

    @Test func toggleBordersFlips() throws {
        let off = try plan(.toggleBorders)
        #expect(off.result == .bordersSet(enabled: false))
        #expect(off.edits == [.init(table: "borders", key: "enabled", value: .bool(false))])

        let text = try Fixture.settingsText.replacingOccurrences(of: "[borders]\nenabled = true", with: "[borders]\nenabled = false")
        #expect(try plan(.toggleBorders, text: text).result == .bordersSet(enabled: true))
    }

    @Test func toggleBordersWithoutKeyIsAnError() throws {
        let text = try Fixture.settingsText.replacingOccurrences(of: "[borders]\nenabled = true\n", with: "[borders]\n")
        #expect(throws: CommandError.settings(.keyNotFound(table: "borders", key: "enabled"))) {
            try plan(.toggleBorders, text: text)
        }
    }

    @Test func refusesToEditUnparseableFile() throws {
        let text = try Fixture.settingsText + "\nbroken = \n"
        #expect(throws: CommandError.self) { try plan(.visibleContainers(2), text: text) }
    }

    @Test func hotkeyActionsMapToCommands() {
        #expect(Command(.command(.cyclePadding)) == .cyclePadding)
        #expect(Command(.command(.toggleBorders)) == .toggleBorders)
        #expect(Command(.command(.visibleContainers1)) == .visibleContainers(1))
        #expect(Command(.command(.visibleContainers6)) == .visibleContainers(6))
        #expect(Command(.selectPreset("Wide")) == .selectPreset("Wide"))
    }
}

@Suite struct CommandRunTests {
    @Test func cyclingThroughAllPresetsRestoresTheFileByteForByte() throws {
        let file = try TempSettings()
        let original = try file.bytes
        var names: [String] = []
        for _ in 0..<3 {
            if case let .paddingSet(name) = try CommandPlanner.run(.cyclePadding, presets: defaults, layout: nil, settingsURL: file.url) {
                names.append(name)
            }
        }
        #expect(names == ["Single", "Fullscreen", "Wide"])
        #expect(try file.bytes == original)
        #expect(try file.strayFiles.isEmpty)
    }

    @Test func eachCycleStepChangesOnlyGapLines() throws {
        let file = try TempSettings()
        let original = try file.text
        _ = try CommandPlanner.run(.cyclePadding, presets: defaults, layout: nil, settingsURL: file.url)
        let a = original.components(separatedBy: "\n")
        let b = try file.text.components(separatedBy: "\n")
        #expect(a.count == b.count)
        let changed = zip(a, b).filter { $0 != $1 }.map(\.0)
        #expect(changed == ["left = 8.0", "right = 8.0", "top = 540.0"]) // bottom stays 8
    }

    @Test func visibleContainersSameValueDoesNotWrite() throws {
        let file = try TempSettings()
        let inode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.systemFileNumber] as? Int
        #expect(try CommandPlanner.run(.visibleContainers(2), presets: defaults, layout: nil, settingsURL: file.url) == .containersSet(2))
        #expect(try FileManager.default.attributesOfItem(atPath: file.url.path)[.systemFileNumber] as? Int == inode)
    }

    @Test func dwindleSkipDoesNotTouchTheFile() throws {
        let file = try TempSettings()
        try FileManager.default.removeItem(at: file.url) // would fail if read
        #expect(try CommandPlanner.run(.visibleContainers(3), presets: defaults, layout: .dwindle, settingsURL: file.url) == .skippedDwindle)
    }

    @Test func toggleBordersTwiceRestoresTheFile() throws {
        let file = try TempSettings()
        let original = try file.bytes
        #expect(try CommandPlanner.run(.toggleBorders, presets: defaults, layout: nil, settingsURL: file.url) == .bordersSet(enabled: false))
        #expect(try file.text.contains("[borders]\nenabled = false\n"))
        #expect(try CommandPlanner.run(.toggleBorders, presets: defaults, layout: nil, settingsURL: file.url) == .bordersSet(enabled: true))
        #expect(try file.bytes == original)
    }

    @Test func missingTableSurfacesAsSettingsError() throws {
        let file = try TempSettings(text: try Fixture.settingsText.replacingOccurrences(of: "[niri]\n", with: "[niriX]\n"))
        #expect(throws: CommandError.settings(.tableNotFound("niri"))) {
            try CommandPlanner.run(.visibleContainers(3), presets: defaults, layout: nil, settingsURL: file.url)
        }
    }

    @Test func emptyPresetsIsAnError() throws {
        let file = try TempSettings()
        #expect(throws: CommandError.noPresets) {
            try CommandPlanner.run(.cyclePadding, presets: [], layout: nil, settingsURL: file.url)
        }
    }
}
