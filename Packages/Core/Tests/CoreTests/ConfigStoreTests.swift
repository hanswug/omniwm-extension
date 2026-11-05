import Foundation
import Testing
@testable import Core

private let valid = ExtConfig.defaultFileContents
private let validWide = valid.replacingOccurrences(of: "\"Wide\"", with: "\"Wider\"")
private let invalid = valid.replacingOccurrences(of: "position = \"center\"", with: "position = \"left\"")

@Suite struct ConfigStoreTests {
    @Test func startsWithBuiltInDefaults() {
        let store = ConfigStore()
        #expect(store.config == .builtInDefault)
        #expect(!store.hasValidConfig)
        #expect(store.issues.isEmpty)
    }

    @Test func firstValidLoad() {
        var store = ConfigStore()
        #expect(store.apply(.read(text: validWide)) == .loaded)
        #expect(store.config.padding[1].name == "Wider")
        #expect(store.hasValidConfig)
    }

    @Test func invalidReloadKeepsLastGoodConfig() {
        var store = ConfigStore()
        store.apply(.read(text: validWide))
        #expect(store.apply(.read(text: invalid)) == .keptPrevious)
        #expect(store.config.padding[1].name == "Wider")          // last good still running
        #expect(store.issues.count == 1)
        #expect(store.issues.first?.severity == .error)
        #expect(store.issues.first?.line == 15)
    }

    @Test func fixingTheFileClearsTheError() {
        var store = ConfigStore()
        store.apply(.read(text: validWide))
        store.apply(.read(text: invalid))
        #expect(store.apply(.read(text: valid)) == .reloaded)
        #expect(store.issues.isEmpty)
        #expect(store.config == .builtInDefault)
    }

    @Test func invalidFirstLoadRunsBuiltInDefaults() {
        var store = ConfigStore()
        #expect(store.apply(.read(text: invalid)) == .usingDefaults)
        #expect(store.config == .builtInDefault)
        #expect(!store.hasValidConfig)
        #expect(store.issues.count == 1)
        // A later valid file is the first real load.
        #expect(store.apply(.read(text: validWide)) == .loaded)
    }

    @Test func unreadableFileKeepsLastGoodConfig() {
        var store = ConfigStore()
        store.apply(.read(text: validWide))
        let issue = ConfigIssue(.error, "config.toml not found")
        #expect(store.apply(.failed(issue)) == .keptPrevious)
        #expect(store.config.padding[1].name == "Wider")
        #expect(store.issues == [issue])
    }

    @Test func unchangedTextIsSkippedUnlessForced() {
        var store = ConfigStore()
        store.apply(.read(text: valid))
        #expect(store.apply(.read(text: valid)) == .unchanged)
        #expect(store.apply(.read(text: valid), force: true) == .reloaded)
        store.apply(.read(text: invalid))
        #expect(store.apply(.read(text: invalid)) == .unchanged)
        #expect(store.issues.count == 1) // the error stays visible
    }

    @Test func warningsAreKeptWithValidConfig() {
        var store = ConfigStore()
        #expect(store.apply(.read(text: valid + "\n[extra]\nx = 1\n")) == .loaded)
        #expect(store.issues.map(\.severity) == [.warning])
    }
}

@Suite struct ConfigFileTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ConfigFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @Test func writesDefaultWhenMissing() throws {
        let url = root.appending(path: "nested/dir/config.toml")
        #expect(try ConfigFile.writeDefaultIfMissing(at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == ExtConfig.defaultFileContents)
    }

    @Test(arguments: ["", "\n  \n\t"])
    func replacesBlankPlaceholder(_ blank: String) throws {
        let url = root.appending(path: "config.toml")
        try Data(blank.utf8).write(to: url)
        #expect(try ConfigFile.writeDefaultIfMissing(at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == ExtConfig.defaultFileContents)
    }

    @Test func neverTouchesAFileWithContent() throws {
        let url = root.appending(path: "config.toml")
        let mine = Data("# mine\n[[padding]]\n".utf8)
        try mine.write(to: url)
        #expect(try !ConfigFile.writeDefaultIfMissing(at: url))
        #expect(try Data(contentsOf: url) == mine)
    }

    @Test func failsWhenDirectoryCannotBeCreated() throws {
        let blocker = root.appending(path: "blocker")
        try Data("x".utf8).write(to: blocker)
        #expect(throws: ConfigFile.Failure.self) {
            try ConfigFile.writeDefaultIfMissing(at: blocker.appending(path: "config.toml"))
        }
    }

    @Test func loadReadsText() throws {
        let url = root.appending(path: "config.toml")
        try Data("a = 1\n".utf8).write(to: url)
        #expect(ConfigFile.load(from: url) == .read(text: "a = 1\n"))
    }

    @Test func loadMissingFile() {
        guard case let .failed(issue) = ConfigFile.load(from: root.appending(path: "nope.toml")) else {
            Issue.record("expected failure")
            return
        }
        #expect(issue.message.hasSuffix("nope.toml not found"))
    }

    @Test func loadRejectsInvalidUTF8() throws {
        let url = root.appending(path: "config.toml")
        try Data([0xFF, 0xFE, 0x00]).write(to: url)
        #expect(ConfigFile.load(from: url) == .failed(ConfigIssue(.error, "config.toml is not valid UTF-8")))
    }
}
