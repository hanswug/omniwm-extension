import Foundation
import Testing
@testable import Core

/// Hans's real `settings.toml`, captured into the fixtures (never the live file).
enum Fixture {
    static var settingsURL: URL {
        get throws {
            try #require(Bundle.module.url(forResource: "settings", withExtension: "toml", subdirectory: "Fixtures"))
        }
    }

    static var settingsText: String {
        get throws { try String(contentsOf: settingsURL, encoding: .utf8) }
    }
}

/// A temp copy of the fixture for file-level tests.
struct TempSettings {
    let directory: URL
    let url: URL

    init(text: String? = nil) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "SettingsEditorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "settings.toml")
        try Data((text ?? Fixture.settingsText).utf8).write(to: url)
    }

    var text: String { get throws { try String(contentsOf: url, encoding: .utf8) } }
    var bytes: Data { get throws { try Data(contentsOf: url) } }

    /// Files in the directory other than settings.toml (leftover temp files).
    var strayFiles: [String] {
        get throws {
            try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "settings.toml" }
        }
    }
}

/// Line numbers (1-based) whose content differs; requires equal line counts.
private func changedLines(_ old: String, _ new: String, sourceLocation: SourceLocation = #_sourceLocation) -> [Int] {
    let a = old.split(separator: "\n", omittingEmptySubsequences: false)
    let b = new.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(a.count == b.count, "line count changed", sourceLocation: sourceLocation)
    return zip(a, b).enumerated().filter { $0.element.0 != $0.element.1 }.map { $0.offset + 1 }
}

private func line(_ text: String, _ number: Int) -> String {
    String(text.split(separator: "\n", omittingEmptySubsequences: false)[number - 1])
}

private func lineNumber(of needle: String, after header: String, in text: String) -> Int? {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard let start = lines.firstIndex(where: { $0 == header }) else { return nil }
    return lines[(start + 1)...].firstIndex(where: { $0.hasPrefix(needle) }).map { $0 + 1 }
}

// MARK: - Golden-file tests on the real fixture

@Suite struct SettingsEditorGoldenTests {
    @Test func fixtureLooksLikeTheRealFile() throws {
        let text = try Fixture.settingsText
        #expect(text.contains("[gaps.outer]\nbottom = 8.0\nleft = 8.0\nright = 8.0\ntop = 540.0\n"))
        #expect(text.contains("[borders]\nenabled = true\n"))
        #expect(text.contains("visibleContainerCount = 2\n"))
    }

    @Test func gapEditChangesOnlyTheTargetLine() throws {
        let original = try Fixture.settingsText
        let edited = try SettingsEditor.apply([.init(table: "gaps.outer", key: "top", value: .float(720))], to: original)
        let target = try #require(lineNumber(of: "top =", after: "[gaps.outer]", in: original))
        #expect(changedLines(original, edited) == [target])
        #expect(line(edited, target) == "top = 720.0")
    }

    @Test func fourGapEditsChangeExactlyFourLines() throws {
        let original = try Fixture.settingsText
        let edited = try SettingsEditor.apply([
            .init(table: "gaps.outer", key: "top", value: .float(720)),
            .init(table: "gaps.outer", key: "bottom", value: .float(8)),   // unchanged value
            .init(table: "gaps.outer", key: "left", value: .float(640)),
            .init(table: "gaps.outer", key: "right", value: .float(640.5)),
        ], to: original)
        let lines = try ["top =", "left =", "right ="].map { try #require(lineNumber(of: $0, after: "[gaps.outer]", in: original)) }
        #expect(changedLines(original, edited) == lines.sorted())
        #expect(edited.contains("[gaps.outer]\nbottom = 8.0\nleft = 640.0\nright = 640.5\ntop = 720.0\n"))
    }

    @Test func intEditInNiri() throws {
        let original = try Fixture.settingsText
        let edited = try SettingsEditor.apply([.init(table: "niri", key: "visibleContainerCount", value: .int(3))], to: original)
        let target = try #require(lineNumber(of: "visibleContainerCount", after: "[niri]", in: original))
        #expect(changedLines(original, edited) == [target])
        #expect(line(edited, target) == "visibleContainerCount = 3")
    }

    @Test func boolEditTouchesBordersNotGlow() throws {
        let original = try Fixture.settingsText
        let edited = try SettingsEditor.apply([.init(table: "borders", key: "enabled", value: .bool(false))], to: original)
        let target = try #require(lineNumber(of: "enabled", after: "[borders]", in: original))
        #expect(changedLines(original, edited) == [target])
        #expect(line(edited, target) == "enabled = false")
        #expect(edited.contains("[borders.glow]\nenabled = true\n")) // same key name in a sub-table is untouched
    }

    @Test func missingKeyIsInsertedAsFirstBodyLine() throws {
        let original = try Fixture.settingsText.replacingOccurrences(of: "visibleContainerCount = 2\n", with: "")
        let edited = try SettingsEditor.apply([.init(table: "niri", key: "visibleContainerCount", value: .int(4))], to: original)
        #expect(edited == original.replacingOccurrences(of: "[niri]\n", with: "[niri]\nvisibleContainerCount = 4\n"))
    }

    @Test func missingTableIsAnErrorAndNothingIsCreated() throws {
        let original = try Fixture.settingsText.replacingOccurrences(of: "[borders]\n", with: "[bordersX]\n")
        #expect(throws: SettingsEditError.tableNotFound("borders")) {
            try SettingsEditor.apply([.init(table: "borders", key: "enabled", value: .bool(false))], to: original)
        }
    }

    @Test func subTableHeaderDoesNotMatchParent() throws {
        // [gaps] exists; editing its body must stop at [gaps.outer].
        let original = try Fixture.settingsText
        let edited = try SettingsEditor.apply([.init(table: "gaps", key: "top", value: .float(1))], to: original)
        #expect(edited == original.replacingOccurrences(of: "[gaps]\n", with: "[gaps]\ntop = 1.0\n"))
    }

    @Test func noOpReturnsIdenticalText() throws {
        let original = try Fixture.settingsText
        let edited = try SettingsEditor.apply([
            .init(table: "gaps.outer", key: "top", value: .float(540)),
            .init(table: "niri", key: "visibleContainerCount", value: .int(2)),
            .init(table: "borders", key: "enabled", value: .bool(true)),
        ], to: original)
        #expect(edited == original)
    }
}

// MARK: - Formatting and line-level preservation

@Suite struct SettingsEditorFormattingTests {
    @Test(arguments: [
        (TOMLScalar.float(540), "540.0"),
        (.float(8), "8.0"),
        (.float(0), "0.0"),
        (.float(12.5), "12.5"),
        (.float(0.1983509958), "0.1983509958"),
        (.int(3), "3"),
        (.int(0), "0"),
        (.bool(true), "true"),
        (.bool(false), "false"),
    ])
    func formatting(_ value: TOMLScalar, _ expected: String) {
        #expect(value.description == expected)
    }

    @Test func preservesIndentSpacingCommentAndCRLF() throws {
        let text = "[gaps.outer]\r\n  top   =  540.0   # tall\r\nbottom = 8.0\r\n"
        let edited = try SettingsEditor.apply([.init(table: "gaps.outer", key: "top", value: .float(720))], to: text)
        #expect(edited == "[gaps.outer]\r\n  top   =  720.0   # tall\r\nbottom = 8.0\r\n")
    }

    @Test func insertKeepsCRLF() throws {
        let edited = try SettingsEditor.apply([.init(table: "niri", key: "visibleContainerCount", value: .int(1))], to: "[niri]\r\nx = 1\r\n")
        #expect(edited == "[niri]\r\nvisibleContainerCount = 1\r\nx = 1\r\n")
    }

    @Test func headerWithCommentAndSpaces() throws {
        let edited = try SettingsEditor.apply([.init(table: "niri", key: "a", value: .int(2))], to: "[ niri ]  # c\na = 1\n")
        #expect(edited == "[ niri ]  # c\na = 2\n")
    }

    @Test func intWrittenOverFloatTokenIsNoOpWhenEqual() throws {
        let text = "[gaps.outer]\ntop = 540\n"
        #expect(try SettingsEditor.apply([.init(table: "gaps.outer", key: "top", value: .float(540))], to: text) == text)
    }

    @Test func similarKeyPrefixIsNotMatched() throws {
        let edited = try SettingsEditor.apply([.init(table: "t", key: "top", value: .int(1))], to: "[t]\ntopX = 5\n")
        #expect(edited == "[t]\ntop = 1\ntopX = 5\n")
    }

    @Test func refusesToOverwriteNonScalar() throws {
        #expect(throws: SettingsEditError.unexpectedValue(table: "t", key: "k")) {
            try SettingsEditor.apply([.init(table: "t", key: "k", value: .int(1))], to: "[t]\nk = \"a b\"\n")
        }
    }

    @Test func rejectsNonFiniteFloat() throws {
        #expect(throws: SettingsEditError.self) {
            try SettingsEditor.apply([.init(table: "t", key: "k", value: .float(.infinity))], to: "[t]\nk = 1.0\n")
        }
    }

    @Test func arrayTableHeaderEndsBody() throws {
        let text = "[niri]\na = 1\n[[hotkeys]]\nvisibleContainerCount = 9\n"
        let edited = try SettingsEditor.apply([.init(table: "niri", key: "visibleContainerCount", value: .int(3))], to: text)
        #expect(edited == "[niri]\nvisibleContainerCount = 3\na = 1\n[[hotkeys]]\nvisibleContainerCount = 9\n")
    }
}

// MARK: - File operations

@Suite struct SettingsEditorFileTests {
    @Test func writesAtomicallyAndOnlyTargetBytesChange() throws {
        let file = try TempSettings()
        let original = try file.text
        let outcome = try SettingsEditor.edit(fileAt: file.url, [.init(table: "gaps.outer", key: "top", value: .float(720))])
        #expect(outcome == .written)
        #expect(try file.text == original.replacingOccurrences(of: "top = 540.0\n", with: "top = 720.0\n"))
        #expect(try file.strayFiles.isEmpty)
    }

    @Test func noOpDoesNotWrite() throws {
        let file = try TempSettings()
        let before = try FileManager.default.attributesOfItem(atPath: file.url.path)
        let outcome = try SettingsEditor.edit(fileAt: file.url, [.init(table: "borders", key: "enabled", value: .bool(true))])
        let after = try FileManager.default.attributesOfItem(atPath: file.url.path)
        #expect(outcome == .unchanged)
        #expect(before[.systemFileNumber] as? Int == after[.systemFileNumber] as? Int) // same inode: no rename
        #expect(before[.modificationDate] as? Date == after[.modificationDate] as? Date)
    }

    @Test func preservesPermissions() throws {
        let file = try TempSettings()
        chmod(file.url.path, 0o600)
        try SettingsEditor.edit(fileAt: file.url, [.init(table: "niri", key: "visibleContainerCount", value: .int(5))])
        let mode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func followsSymlinkAndKeepsIt() throws {
        let file = try TempSettings()
        let link = file.directory.appending(path: "link.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file.url)
        try SettingsEditor.edit(fileAt: link, [.init(table: "niri", key: "visibleContainerCount", value: .int(5))])
        let type = try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType
        #expect(type == .typeSymbolicLink)
        #expect(try file.text.contains("visibleContainerCount = 5\n"))
    }

    @Test func missingTableLeavesFileUntouched() throws {
        let text = try Fixture.settingsText.replacingOccurrences(of: "[niri]\n", with: "[niriX]\n")
        let file = try TempSettings(text: text)
        #expect(throws: SettingsEditError.tableNotFound("niri")) {
            try SettingsEditor.edit(fileAt: file.url, [.init(table: "niri", key: "visibleContainerCount", value: .int(3))])
        }
        #expect(try file.text == text)
        #expect(try file.strayFiles.isEmpty)
    }

    @Test func concurrentModificationRetriesOnceAndKeepsTheirChange() throws {
        let file = try TempSettings()
        var attempts: [Int] = []
        let outcome = try SettingsEditor.edit(fileAt: file.url, [.init(table: "gaps.outer", key: "top", value: .float(720))]) { attempt in
            attempts.append(attempt)
            if attempt == 0 {
                // OmniWM writes the file (atomic rename) between our read and our rename.
                let theirs = (try? file.text)?.replacingOccurrences(of: "visibleContainerCount = 2", with: "visibleContainerCount = 6")
                try? Data((theirs ?? "").utf8).write(to: file.url, options: .atomic)
            }
        }
        #expect(outcome == .written)
        #expect(attempts == [0, 1])
        let text = try file.text
        #expect(text.contains("top = 720.0\n"))                 // ours
        #expect(text.contains("visibleContainerCount = 6\n"))   // theirs survived
        #expect(try file.strayFiles.isEmpty)
    }

    @Test func persistentConcurrentModificationIsAnError() throws {
        let file = try TempSettings()
        var counter = 0
        #expect(throws: SettingsEditError.concurrentModification) {
            try SettingsEditor.edit(fileAt: file.url, [.init(table: "gaps.outer", key: "top", value: .float(720))]) { _ in
                counter += 1
                // Size changes every time, so the guard always trips.
                try? Data((try file.text + "# \(counter)\n").utf8).write(to: file.url)
            }
        }
        #expect(counter == 2)
        let text = try file.text
        #expect(text.contains("top = 540.0\n"))   // our edit never landed
        #expect(text.hasSuffix("# 2\n"))          // their last write is intact
        #expect(try file.strayFiles.isEmpty)
    }

    @Test func notUTF8IsAnError() throws {
        let file = try TempSettings()
        try Data([0x5B, 0xFF, 0x5D]).write(to: file.url)
        #expect(throws: SettingsEditError.notUTF8) {
            try SettingsEditor.edit(fileAt: file.url, [.init(table: "a", key: "b", value: .int(1))])
        }
    }

    @Test func missingFileIsAnIOError() throws {
        let file = try TempSettings()
        try FileManager.default.removeItem(at: file.url)
        #expect(throws: SettingsEditError.self) {
            try SettingsEditor.edit(fileAt: file.url, [.init(table: "a", key: "b", value: .int(1))])
        }
    }
}
