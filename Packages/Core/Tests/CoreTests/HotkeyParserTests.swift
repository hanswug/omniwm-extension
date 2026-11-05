import Testing
@testable import Core

@Suite struct HotkeyParserTests {
    // MARK: valid

    @Test(arguments: [
        ("ctrl+opt+0", "ctrl+opt+0"),
        ("ctrl+opt+b", "ctrl+opt+b"),
        ("hyper+1", "hyper+1"),
        ("CTRL+Opt+B", "ctrl+opt+b"),            // case-insensitive
        ("alt+cmd+space", "opt+cmd+space"),      // alt = opt
        ("cmd+shift+ctrl+opt+f20", "ctrl+opt+shift+cmd+f20"),
        (" ctrl + opt + leftbracket ", "ctrl+opt+leftbracket"),
        ("b+ctrl", "ctrl+b"),                    // order-insensitive
        ("ctrl+ctrl+b", "ctrl+b"),               // repeated modifier is harmless
        ("shift+hyper+grave", "hyper+shift+grave"),
    ])
    func parsesValidChords(input: String, canonical: String) throws {
        let hotkey = try #require(try HotkeyParser.parse(input))
        #expect(hotkey.description == canonical)
    }

    @Test func everyDocumentedKeyIsAccepted() throws {
        for name in HotkeyKey.allNames {
            let hotkey = try #require(try HotkeyParser.parse("ctrl+\(name)"))
            #expect(hotkey.key.name == name)
        }
        #expect(HotkeyKey.allNames.count == 26 + 10 + 20 + 19)
    }

    @Test func equalityIgnoresTokenOrder() throws {
        #expect(try HotkeyParser.parse("opt+ctrl+b") == HotkeyParser.parse("ctrl+opt+b"))
    }

    // MARK: unbound

    @Test(arguments: ["", "   "])
    func emptyIsUnbound(input: String) throws {
        #expect(try HotkeyParser.parse(input) == nil)
    }

    // MARK: invalid

    @Test(arguments: [
        ("ctrl+opt", HotkeyParseError.noKey),
        ("b", .noModifier),
        ("f21", .unknownToken("f21")),
        ("ctl+b", .unknownToken("ctl")),
        ("ctrl+Enter", .unknownToken("Enter")),
        ("control+b", .unknownToken("control")),
        ("ctrl+a+b", .multipleKeys("a", "b")),
        ("ctrl++b", .emptyToken),
        ("ctrl+b+", .emptyToken),
        ("+b", .emptyToken),
    ])
    func rejectsInvalidChords(input: String, expected: HotkeyParseError) {
        #expect(throws: expected) { try HotkeyParser.parse(input) }
    }
}
