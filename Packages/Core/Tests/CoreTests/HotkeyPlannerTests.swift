import Foundation
import Testing
@testable import Core

@Suite struct HotkeyPlannerTests {
    let hyper = HyperModifiers.fallback

    private func config(_ toml: String) throws -> ExtConfig {
        let result = ConfigParser.parse(toml)
        return try #require(result.config, "\(result.issues)")
    }

    private var fixtureHotkeys: [OmniWMSettings.HotkeyBinding] {
        get throws { try #require(SettingsReader.read(try Fixture.settingsText).settings).hotkeys }
    }

    @Test func defaultConfigAgainstRealOmniWMSettingsHasNoConflicts() throws {
        let plan = HotkeyPlanner.plan(config: .builtInDefault, hyper: hyper, omniwmHotkeys: try fixtureHotkeys)
        #expect(plan.conflicts.isEmpty)
        #expect(plan.duplicateWarnings.isEmpty)
        #expect(plan.registrations.map(\.action.description) == [
            "cycle_padding", "toggle_borders",
            "visible_containers_1", "visible_containers_2", "visible_containers_3", "visible_containers_4",
        ])
        #expect(plan.registrations[2].resolved.description == "ctrl+opt+shift+cmd+1")
    }

    @Test func detectsConflictWithRealOmniWMBinding() throws {
        let hotkeys = try fixtureHotkeys
        let omniwmID = try #require(hotkeys.first { $0.binding == "Control+Option+H" }?.id)
        let config = try config("[hotkeys]\ntoggle_borders = \"ctrl+opt+h\"\n" + "[[padding]]\nname = \"A\"\ntop = 0\nbottom = 0\nleft = 0\nright = 0\n")
        let plan = HotkeyPlanner.plan(config: config, hyper: hyper, omniwmHotkeys: hotkeys)
        #expect(plan.conflicts.map(\.description) == ["ctrl+opt+h also bound in OmniWM (\(omniwmID))"])
        #expect(plan.registrations.count == 1) // still registered
    }

    @Test func hyperConflictUsesResolvedModifiers() throws {
        let omniwm = [OmniWMSettings.HotkeyBinding(id: "toggleQuakeTerminal", binding: "Hyper+G")]
        let preset = "[[padding]]\nname = \"A\"\ntop = 0\nbottom = 0\nleft = 0\nright = 0\n"

        // Our explicit chord equals OmniWM's Hyper+G.
        let explicit = try config("[hotkeys]\ncycle_padding = \"ctrl+opt+shift+cmd+g\"\n" + preset)
        #expect(HotkeyPlanner.plan(config: explicit, hyper: hyper, omniwmHotkeys: omniwm).conflicts.map(\.description)
            == ["ctrl+opt+shift+cmd+g also bound in OmniWM (toggleQuakeTerminal)"])

        // Different hyper: no longer the same chord.
        #expect(HotkeyPlanner.plan(config: explicit, hyper: [.ctrl, .opt, .cmd], omniwmHotkeys: omniwm).conflicts.isEmpty)

        // Our hyper+g against OmniWM's Hyper+G always matches.
        let viaHyper = try config("[hotkeys]\ncycle_padding = \"hyper+g\"\n" + preset)
        #expect(HotkeyPlanner.plan(config: viaHyper, hyper: [.ctrl, .opt, .cmd], omniwmHotkeys: omniwm).conflicts.count == 1)
    }

    @Test func multipleOmniWMIDsAreListed() throws {
        let omniwm = [
            OmniWMSettings.HotkeyBinding(id: "a", binding: "Control+Option+B"),
            .init(id: "b", binding: "Option+Control+B"),
            .init(id: "c", binding: "Unassigned"),
        ]
        let plan = HotkeyPlanner.plan(config: .builtInDefault, hyper: hyper, omniwmHotkeys: omniwm)
        #expect(plan.conflicts.map(\.description) == ["ctrl+opt+b also bound in OmniWM (a, b)"])
    }

    @Test func unassignedNeverConflicts() throws {
        let omniwm = [OmniWMSettings.HotkeyBinding(id: "x", binding: "Unassigned")]
        #expect(HotkeyPlanner.plan(config: .builtInDefault, hyper: hyper, omniwmHotkeys: omniwm).conflicts.isEmpty)
    }

    @Test func presetHotkeysAreRegisteredAfterCommands() throws {
        let text = ExtConfig.defaultFileContents.replacingOccurrences(of: "name = \"Wide\"", with: "name = \"Wide\"\nhotkey = \"ctrl+opt+w\"")
        let plan = HotkeyPlanner.plan(config: try config(text), hyper: hyper, omniwmHotkeys: [])
        #expect(plan.registrations.last?.action == .selectPreset("Wide"))
        #expect(plan.registrations.last?.resolved.description == "ctrl+opt+w")
    }

    @Test func duplicateAfterHyperResolutionSkipsTheLaterOne() throws {
        let text = ExtConfig.defaultFileContents.replacingOccurrences(
            of: "visible_containers_5 = \"\"", with: "visible_containers_5 = \"ctrl+opt+shift+cmd+1\""
        )
        let plan = HotkeyPlanner.plan(config: try config(text), hyper: hyper, omniwmHotkeys: [])
        #expect(!plan.registrations.contains { $0.action == .command(.visibleContainers5) })
        #expect(plan.duplicateWarnings == [
            "ctrl+opt+shift+cmd+1 (visible_containers_5) is the same chord as hyper+1 (visible_containers_1); not registered",
        ])
    }

    @Test func unboundHotkeysAreNotRegistered() throws {
        let plan = HotkeyPlanner.plan(config: try config("[[padding]]\nname = \"A\"\ntop = 0\nbottom = 0\nleft = 0\nright = 0\n"), hyper: hyper, omniwmHotkeys: [])
        #expect(plan.registrations.isEmpty)
    }
}
