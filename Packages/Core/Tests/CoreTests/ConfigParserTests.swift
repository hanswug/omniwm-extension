import Testing
@testable import Core

/// One minimal valid preset, appended to snippets that test other sections.
private let onePreset = """

[[padding]]
name = "Only"
top = 1
bottom = 2
left = 3
right = 4
"""

private func parse(_ text: String) -> ConfigParseResult { ConfigParser.parse(text) }

private func onlyError(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> ConfigIssue {
    let result = parse(text)
    #expect(result.config == nil, sourceLocation: sourceLocation)
    #expect(result.errors.count == 1, "\(result.issues)", sourceLocation: sourceLocation)
    return try #require(result.errors.first, sourceLocation: sourceLocation)
}

@Suite struct ConfigDefaultsTests {
    @Test func defaultFileRoundTripsToBuiltInDefault() throws {
        let result = parse(ExtConfig.defaultFileContents)
        #expect(result.issues.isEmpty, "\(result.issues)")
        #expect(try #require(result.config) == ExtConfig.builtInDefault)
    }

    @Test func builtInDefaultMatchesPDR() throws {
        let config = ExtConfig.builtInDefault
        #expect(config.general.omniwmSettings == "")
        #expect(config.general.autoFullscreenOnBuiltin)
        #expect(config.general.balanceSizesDelayMs == 120)
        #expect(config.hud == .init(enabled: true, position: .center, durationMs: 900))
        #expect(config.padding.map(\.name) == ["Fullscreen", "Wide", "Single"])
        #expect(config.hotkeys.count == 6) // the six non-empty bindings all parsed
        #expect(config.hotkeys[.cyclePadding]?.description == "ctrl+opt+0")
        #expect(config.hotkeys[.toggleBorders]?.description == "ctrl+opt+b")
        #expect(config.hotkeys[.visibleContainers4]?.description == "hyper+4")
        #expect(config.hotkeys[.visibleContainers5] == nil)
        #expect(config.hotkeys[.visibleContainers6] == nil)
    }

    @Test func defaultFileStartsWithCommentHeader() {
        #expect(ExtConfig.defaultFileContents.hasPrefix("# OmniWM Extension config"))
        #expect(ExtConfig.defaultFileContents.hasSuffix("right = 640\n"))
    }
}

@Suite struct ConfigOmissionTests {
    @Test func onlyPaddingUsesDefaultsAndUnboundHotkeys() throws {
        let result = parse(onePreset)
        #expect(result.issues.isEmpty)
        let config = try #require(result.config)
        #expect(config.general == ExtConfig.builtInDefault.general)
        #expect(config.hud == ExtConfig.builtInDefault.hud)
        #expect(config.hotkeys.isEmpty)
        #expect(config.padding == [.init(name: "Only", top: 1, bottom: 2, left: 3, right: 4, hotkey: nil)])
    }

    @Test func omittedAndEmptyHotkeysAreUnbound() throws {
        let config = try #require(parse("""
        [hotkeys]
        toggle_borders = "ctrl+opt+b"
        cycle_padding = ""
        """ + onePreset).config)
        #expect(config.hotkeys == [.toggleBorders: try #require(try HotkeyParser.parse("ctrl+opt+b"))])
    }

    @Test func partialSectionsKeepOtherDefaults() throws {
        let config = try #require(parse("""
        [general]
        auto_fullscreen_on_builtin = false
        [hud]
        position = "TOP"
        """ + onePreset).config)
        #expect(config.general.omniwmSettings == "")
        #expect(!config.general.autoFullscreenOnBuiltin)
        #expect(config.hud == .init(enabled: true, position: .top, durationMs: 900))
    }
}

@Suite struct ConfigPaddingValidationTests {
    @Test func paddingMissingIsAnError() throws {
        let issue = try onlyError("[hud]\nenabled = true\n")
        #expect(issue.message.contains("at least one [[padding]]"))
    }

    @Test func paddingEmptyArrayIsAnError() throws {
        let issue = try onlyError("padding = []\n")
        #expect(issue.message.contains("at least one [[padding]]"))
        #expect(issue.line == 1)
    }

    @Test func paddingNotAnArrayIsAnError() throws {
        let issue = try onlyError("padding = 3\n")
        #expect(issue.message.contains("array of tables"))
    }

    @Test func nameMissing() throws {
        let issue = try onlyError("[[padding]]\ntop = 1\nbottom = 1\nleft = 1\nright = 1\n")
        #expect(issue.message == "[[padding]] #1: name is required")
        #expect(issue.line == 1)
    }

    @Test(arguments: ["\"\"", "\"   \"", "3"])
    func nameEmptyOrNotString(_ value: String) throws {
        let issue = try onlyError("[[padding]]\nname = \(value)\ntop = 1\nbottom = 1\nleft = 1\nright = 1\n")
        #expect(issue.message == "[[padding]] #1: name must be a non-empty string")
        #expect(issue.line == 2)
    }

    @Test func namesUniqueCaseInsensitive() throws {
        let issue = try onlyError(onePreset + "\n" + onePreset.replacingOccurrences(of: "\"Only\"", with: "\"ONLY\""))
        #expect(issue.message == "padding \"ONLY\": duplicate name (already used by \"Only\")")
        #expect(issue.line == 10)
    }

    @Test(arguments: ["-1", "-0.5", "\"8\"", "nan", "inf", "true"])
    func edgeMustBeNumberAtLeastZero(_ value: String) throws {
        let text = onePreset.replacingOccurrences(of: "left = 3", with: "left = \(value)")
        let issue = try onlyError(text)
        #expect(issue.message == "padding \"Only\": left must be a number ≥ 0")
        #expect(issue.line == 6)
    }

    @Test func edgeMissing() throws {
        let issue = try onlyError(onePreset.replacingOccurrences(of: "right = 4", with: ""))
        #expect(issue.message == "padding \"Only\": right is required")
    }

    @Test func zeroAndFloatsAreAccepted() throws {
        let text = onePreset.replacingOccurrences(of: "top = 1", with: "top = 0").replacingOccurrences(of: "left = 3", with: "left = 540.5")
        let preset = try #require(parse(text).config?.padding.first)
        #expect(preset.top == 0)
        #expect(preset.left == 540.5)
    }

    @Test func presetHotkeyIsOptionalAndParsed() throws {
        let bound = try #require(parse(onePreset + "\nhotkey = \"ctrl+opt+1\"\n").config)
        #expect(bound.padding[0].hotkey?.description == "ctrl+opt+1")
        let unbound = try #require(parse(onePreset + "\nhotkey = \"\"\n").config)
        #expect(unbound.padding[0].hotkey == nil)
    }

    @Test func presetHotkeyInvalid() throws {
        let issue = try onlyError(onePreset + "\nhotkey = \"ctrl+opt+11\"\n")
        #expect(issue.message == "padding \"Only\" hotkey: unknown token \"11\" in \"ctrl+opt+11\"")
        #expect(issue.line == 8)
    }

    @Test func presetEntryMustBeTable() throws {
        let issue = try onlyError("padding = [1]\n")
        #expect(issue.message == "[[padding]] #1 must be a table")
    }

    @Test func orderIsPreserved() throws {
        let config = try #require(parse(ExtConfig.defaultFileContents.replacingOccurrences(of: "\"Wide\"", with: "\"Zeta\"")).config)
        #expect(config.padding.map(\.name) == ["Fullscreen", "Zeta", "Single"])
    }
}

@Suite struct ConfigHUDValidationTests {
    @Test func positionMustBeKnown() throws {
        let issue = try onlyError("[hud]\nposition = \"left\"\n" + onePreset)
        #expect(issue.message == "hud.position must be center, top or bottom (got \"left\")")
        #expect(issue.line == 2)
    }

    @Test(arguments: [("center", ExtConfig.HUDPosition.center), ("Top", .top), ("BOTTOM", .bottom)])
    func positionIsCaseInsensitive(_ raw: String, _ expected: ExtConfig.HUDPosition) throws {
        #expect(parse("[hud]\nposition = \"\(raw)\"\n" + onePreset).config?.hud.position == expected)
    }

    @Test(arguments: [(100, 300), (300, 300), (900, 900), (5000, 5000), (9000, 5000)])
    func durationIsClamped(_ input: Int, _ expected: Int) throws {
        let result = parse("[hud]\nduration_ms = \(input)\n" + onePreset)
        #expect(result.config?.hud.durationMs == expected)
        #expect(result.errors.isEmpty)
        if input == expected {
            #expect(result.warnings.isEmpty)
        } else {
            #expect(result.warnings.map(\.message) == ["hud.duration_ms \(input) clamped to \(expected)"])
            #expect(result.warnings.first?.line == 2)
        }
    }

    @Test func durationMustBeNumber() throws {
        let issue = try onlyError("[hud]\nduration_ms = \"900\"\n" + onePreset)
        #expect(issue.message == "hud.duration_ms must be a number of milliseconds")
    }

    @Test(arguments: [(0, 0), (80, 80), (120, 120), (2000, 2000), (5000, 2000), (-5, 0)])
    func balanceSizesDelayIsClamped(_ input: Int, _ expected: Int) throws {
        let result = parse("[general]\nbalance_sizes_delay_ms = \(input)\n" + onePreset)
        #expect(result.config?.general.balanceSizesDelayMs == expected)
        #expect(result.errors.isEmpty)
        if input == expected {
            #expect(result.warnings.isEmpty)
        } else {
            #expect(result.warnings.map(\.message) == ["general.balance_sizes_delay_ms \(input) clamped to \(expected)"])
            #expect(result.warnings.first?.line == 2)
        }
    }

    @Test func balanceSizesDelayDefaultsWhenOmitted() throws {
        #expect(parse(onePreset).config?.general.balanceSizesDelayMs == 120)
    }

    @Test func balanceSizesDelayMustBeNumber() throws {
        let issue = try onlyError("[general]\nbalance_sizes_delay_ms = \"slow\"\n" + onePreset)
        #expect(issue.message == "general.balance_sizes_delay_ms must be a number of milliseconds")
    }

    @Test func enabledMustBeBool() throws {
        let issue = try onlyError("[hud]\nenabled = \"yes\"\n" + onePreset)
        #expect(issue.message == "hud.enabled must be true or false")
        #expect(issue.line == 2)
    }

    @Test func generalTypes() throws {
        let issue = try onlyError("[general]\nomniwm_settings = 3\n" + onePreset)
        #expect(issue.message == "general.omniwm_settings must be a string")
    }

    @Test(arguments: ["", "/abs/settings.toml", "~/dot/settings.toml"])
    func settingsPathAccepted(_ path: String) throws {
        #expect(parse("[general]\nomniwm_settings = \"\(path)\"\n" + onePreset).config?.general.omniwmSettings == path)
    }

    @Test func settingsPathMustNotBeRelative() throws {
        let issue = try onlyError("[general]\nomniwm_settings = \"dot/settings.toml\"\n" + onePreset)
        #expect(issue.message == "general.omniwm_settings must be empty, absolute, or start with ~/ (got \"dot/settings.toml\")")
        #expect(issue.line == 2)
    }

    @Test func sectionMustBeTable() throws {
        let issue = try onlyError("hud = 3\n" + onePreset)
        #expect(issue.message == "hud must be a table ([hud])")
        #expect(issue.line == 1)
    }
}

@Suite struct ConfigHotkeyValidationTests {
    @Test func unknownTokenNamesKeyAndToken() throws {
        let issue = try onlyError("[hotkeys]\ntoggle_borders = \"ctl+opt+b\"\n" + onePreset)
        #expect(issue.message == "hotkeys.toggle_borders: unknown token \"ctl\" in \"ctl+opt+b\"")
        #expect(issue.line == 2)
    }

    @Test(arguments: [
        ("ctrl+opt", "no key, only modifiers"),
        ("b", "needs at least one modifier"),
        ("ctrl+a+b", "more than one key (\"a\" and \"b\")"),
    ])
    func structuralErrors(_ chord: String, _ reason: String) throws {
        let issue = try onlyError("[hotkeys]\ncycle_padding = \"\(chord)\"\n" + onePreset)
        #expect(issue.message == "hotkeys.cycle_padding: \(reason) in \"\(chord)\"")
    }

    @Test func mustBeString() throws {
        let issue = try onlyError("[hotkeys]\ncycle_padding = 1\n" + onePreset)
        #expect(issue.message.hasPrefix("hotkeys.cycle_padding must be a string"))
    }

    @Test func sameChordTwiceInHotkeys() throws {
        let issue = try onlyError("[hotkeys]\ncycle_padding = \"ctrl+opt+b\"\ntoggle_borders = \"opt+CTRL+b\"\n" + onePreset)
        #expect(issue.message == "ctrl+opt+b is bound twice (hotkeys.cycle_padding and hotkeys.toggle_borders)")
        #expect(issue.line == 3)
    }

    @Test func sameChordInHotkeysAndPreset() throws {
        let issue = try onlyError("[hotkeys]\nvisible_containers_1 = \"hyper+1\"\n" + onePreset + "\nhotkey = \"hyper+1\"\n")
        #expect(issue.message == "hyper+1 is bound twice (hotkeys.visible_containers_1 and padding \"Only\" hotkey)")
    }

    @Test func distinctChordsAreFine() throws {
        #expect(parse(ExtConfig.defaultFileContents + "hotkey = \"ctrl+opt+9\"\n").errors.isEmpty)
    }
}

@Suite struct ConfigUnknownKeyAndSyntaxTests {
    @Test func unknownKeysAreWarningsNotErrors() throws {
        let text = """
        future_table_key = 1
        [general]
        mystery = true
        [hud]
        opacity = 0.5
        [hotkeys]
        toggle_gaps = "ctrl+opt+g"
        [telemetry]
        on = false
        """ + onePreset + "\ncolor = \"red\"\n"
        let result = parse(text)
        #expect(result.config != nil)
        #expect(result.errors.isEmpty)
        #expect(result.warnings.map(\.message) == [
            "unknown key \"future_table_key\"",
            "unknown key \"mystery\" in [general]",
            "unknown key \"opacity\" in [hud]",
            "unknown key \"toggle_gaps\" in [hotkeys]",
            "unknown key \"telemetry\"",
            "unknown key \"color\" in padding \"Only\"",
        ])
        #expect(result.warnings.map(\.line) == [1, 3, 5, 7, 8, 16])
    }

    @Test func syntaxErrorReportsLine() throws {
        let issue = try onlyError("[hud]\nenabled = true\nposition = \"center\n")
        #expect(issue.line == 3)
        #expect(!issue.message.isEmpty)
    }

    @Test func allErrorsAreReportedInLineOrder() {
        let result = parse("""
        [hud]
        position = "left"
        [hotkeys]
        cycle_padding = "nope+1"
        [[padding]]
        name = ""
        top = -1
        bottom = 0
        left = 0
        right = 0
        """)
        #expect(result.config == nil)
        #expect(result.errors.map(\.line) == [2, 4, 6, 7])
    }

    @Test func issueDescriptionFormat() {
        #expect(ConfigIssue(.error, "boom", line: 3).description == "Config error: boom (line 3)")
        #expect(ConfigIssue(.warning, "hm").description == "Config warning: hm")
    }
}

@Suite struct TOMLLineLocatorTests {
    @Test func locatesTablesKeysAndArrayEntries() {
        let locator = TOMLLineLocator("""
        top = 1
        # comment = 2
        [hud] # trailing
          "position" = "x"
        [[padding]]
        name = "a"
        [[padding]]
        text = \"\"\"
        fake = 1
        \"\"\"
        name = "b"
        """)
        #expect(locator.line(table: "", key: "top") == 1)
        #expect(locator.line(table: "", key: "comment") == nil)
        #expect(locator.line(table: "hud") == 3)
        #expect(locator.line(table: "hud", key: "position") == 4)
        #expect(locator.line(arrayTable: "padding", index: 0, key: "name") == 6)
        #expect(locator.line(arrayTable: "padding", index: 1) == 7)
        #expect(locator.line(arrayTable: "padding", index: 1, key: "fake") == nil)
        #expect(locator.line(arrayTable: "padding", index: 1, key: "name") == 11)
    }

    @Test func handlesCRLF() {
        let locator = TOMLLineLocator("[hud]\r\nposition = \"x\"\r\n[[padding]]\r\nname = \"a\"\r\n")
        #expect(locator.line(table: "hud") == 1)
        #expect(locator.line(table: "hud", key: "position") == 2)
        #expect(locator.line(arrayTable: "padding", index: 0, key: "name") == 4)
    }
}
