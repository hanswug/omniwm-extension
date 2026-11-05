import Foundation
import Testing
@testable import Core

@Suite struct SettingsReaderTests {
    @Test func readsTheRealFixture() throws {
        let result = SettingsReader.read(try Fixture.settingsText)
        #expect(result.issues.isEmpty)
        let settings = try #require(result.settings)
        #expect(settings.bordersEnabled == true)
        #expect(settings.outerGaps == .init(top: 540, bottom: 8, left: 8, right: 8))
        #expect(settings.visibleContainerCount == 2)
        #expect(settings.hyperKeyModifiers == "Control+Option+Shift+Command")
        #expect(settings.hotkeys.count == 191)
        #expect(settings.hotkeys.contains(.init(id: "toggleQuakeTerminal", binding: "Hyper+G")))
        #expect(settings.hotkeys.filter { $0.binding != "Unassigned" }.count == 40)
        #expect(settings.workspaces.map(\.name) == ["1", "2", "3", "4"])
        #expect(settings.workspaces.allSatisfy { $0.displayName == nil })
        #expect(settings.monitorGapOverrides.isEmpty)
        #expect(settings.monitorNiriOverrides.isEmpty)
    }

    @Test func readsOverridesAndDisplayNames() throws {
        let text = """
        monitorGapOverrides = [{ monitorDisplayUUID = "ABC", monitorName = "LG" }]

        [[monitorNiriOverrides]]
        monitorDisplayId = 2
        monitorName = "Studio Display"
        visibleContainerCount = 3

        [[monitorNiriOverrides]]
        monitorDisplayUUID = "XYZ"

        [[workspaces]]
        name = "1"
        displayName = "Code"

        [[workspaces]]
        name = "2"
        displayName = ""
        """
        let settings = try #require(SettingsReader.read(text).settings)
        #expect(settings.monitorGapOverrides == [.init(displayUUID: "ABC", displayId: nil, name: "LG")])
        #expect(settings.monitorNiriOverrides == [
            .init(monitor: .init(displayUUID: nil, displayId: "2", name: "Studio Display"), visibleContainerCount: 3),
            .init(monitor: .init(displayUUID: "XYZ", displayId: nil, name: nil), visibleContainerCount: nil),
        ])
        #expect(settings.workspaces == [.init(name: "1", displayName: "Code"), .init(name: "2", displayName: nil)])
    }

    @Test func toleratesMissingSections() throws {
        let settings = try #require(SettingsReader.read("[general]\nipcEnabled = true\n").settings)
        #expect(settings.bordersEnabled == nil)
        #expect(settings.outerGaps == nil)
        #expect(settings.visibleContainerCount == nil)
        #expect(settings.hyperKeyModifiers == nil)
        #expect(settings.hotkeys.isEmpty)
    }

    @Test func integerGapsAreRead() throws {
        let settings = try #require(SettingsReader.read("[gaps.outer]\ntop = 1\nbottom = 2\nleft = 3\nright = 4.5\n").settings)
        #expect(settings.outerGaps == .init(top: 1, bottom: 2, left: 3, right: 4.5))
    }

    @Test func loadFromFile() throws {
        let file = try TempSettings()
        #expect(SettingsReader.load(from: file.url).settings?.visibleContainerCount == 2)
        try FileManager.default.removeItem(at: file.url)
        #expect(SettingsReader.load(from: file.url).issues == ["not found at \(file.url.path)"])
    }

    @Test func syntaxErrorIsReported() {
        let result = SettingsReader.read("[general]\nhyperKeyModifiers = \"Control\n")
        #expect(result.settings == nil)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].hasSuffix("(line 2)"))
    }
}

@Suite struct HyperModifiersTests {
    @Test(arguments: [
        ("Control+Option+Shift+Command", [KeyModifier.ctrl, .opt, .shift, .cmd]),
        ("Control+Option+Command", [.ctrl, .opt, .cmd]),
        ("Command", [.cmd]),
        (" shift + control ", [.shift, .ctrl]),
    ])
    func parsesValid(_ raw: String, _ expected: [KeyModifier]) throws {
        #expect(try HyperModifiers.parse(raw) == Set(expected))
    }

    @Test(arguments: [
        ("", HyperParseError.empty),
        ("  ", .empty),
        ("Control+Ctrl", .unknownToken("Ctrl")),
        ("Control++Option", .unknownToken("")),
        ("Hyper", .unknownToken("Hyper")),
        ("None", .unknownToken("None")),
    ])
    func rejectsInvalid(_ raw: String, _ expected: HyperParseError) {
        #expect(throws: expected) { try HyperModifiers.parse(raw) }
    }

    @Test func resolvedHyperFromSettings() {
        var settings = OmniWMSettings()
        settings.hyperKeyModifiers = "Control+Option+Command"
        #expect(settings.resolvedHyper.modifiers == [.ctrl, .opt, .cmd])
        #expect(settings.resolvedHyper.issue == nil)

        settings.hyperKeyModifiers = "Banana"
        #expect(settings.resolvedHyper.modifiers == HyperModifiers.fallback)
        #expect(settings.resolvedHyper.issue?.contains("unknown modifier \"Banana\"") == true)

        settings.hyperKeyModifiers = nil
        #expect(settings.resolvedHyper.modifiers == HyperModifiers.fallback)
        #expect(settings.resolvedHyper.issue != nil)
    }

    @Test func hotkeyResolution() throws {
        let hotkey = try #require(try HotkeyParser.parse("hyper+shift+1"))
        #expect(hotkey.resolved(hyper: [.ctrl, .opt]).description == "ctrl+opt+shift+1")
        #expect(hotkey.resolved(hyper: HyperModifiers.fallback).description == "ctrl+opt+shift+cmd+1")
    }
}

@Suite struct OmniWMBindingTests {
    let hyper: Set<KeyModifier> = [.ctrl, .opt, .shift, .cmd]

    @Test(arguments: [
        ("Control+Option+H", "ctrl+opt+h"),
        ("Option+Command+Space", "opt+cmd+space"),
        ("Hyper+G", "ctrl+opt+shift+cmd+g"),
        ("Control+Right Arrow", "ctrl+right"),
        ("Control+Left Arrow", "ctrl+left"),
        ("Control+Option+Slash", "ctrl+opt+slash"),
        ("Control+Option+Minus", "ctrl+opt+minus"),
        ("Control+Option+Equal", "ctrl+opt+equal"),
        ("Control+Option+Comma", "ctrl+opt+comma"),
        ("Control+Option+Period", "ctrl+opt+period"),
        ("Control+Option+Command+4", "ctrl+opt+cmd+4"),
        ("Control+Left Bracket", "ctrl+leftbracket"),
        ("Control+Apostrophe", "ctrl+quote"),
        ("Control+Enter", "ctrl+return"),
        ("Shift+F12", "shift+f12"),
    ])
    func parsesOmniWMSyntax(_ binding: String, _ expected: String) throws {
        #expect(OmniWMBinding.parse(binding, hyper: hyper)?.description == expected)
    }

    @Test(arguments: ["Unassigned", "", "Control+Delete", "Control+F21", "H", "Control+A+B", "Ctrl+H"])
    func unparseableIsNil(_ binding: String) {
        #expect(OmniWMBinding.parse(binding, hyper: hyper) == nil)
    }

    @Test func everyBoundEntryInTheFixtureParses() throws {
        let settings = try #require(SettingsReader.read(try Fixture.settingsText).settings)
        let bound = settings.hotkeys.filter { $0.binding != "Unassigned" }
        #expect(!bound.isEmpty)
        for entry in bound {
            #expect(OmniWMBinding.parse(entry.binding, hyper: hyper) != nil, "\(entry.id): \(entry.binding)")
        }
    }
}
