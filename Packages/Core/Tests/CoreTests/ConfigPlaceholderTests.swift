import Foundation
import Testing
@testable import Core

@Suite struct ConfigPlaceholderTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "ConfigPlaceholderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @Test func createsDirectoryAndEmptyFile() throws {
        let url = root.appending(path: "a/b/config.toml")
        let created = try ConfigPlaceholder.ensureExists(at: url)
        #expect(created)
        #expect(try Data(contentsOf: url).isEmpty)
    }

    @Test func leavesExistingFileUntouched() throws {
        let url = root.appending(path: "config.toml")
        let original = Data("[general]\nkeep = true\n".utf8)
        try original.write(to: url)
        let created = try ConfigPlaceholder.ensureExists(at: url)
        #expect(!created)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func failsWhenParentIsAFile() throws {
        let blocker = root.appending(path: "blocker")
        try Data().write(to: blocker)
        #expect(throws: ConfigPlaceholder.Failure.self) {
            try ConfigPlaceholder.ensureExists(at: blocker.appending(path: "config.toml"))
        }
    }
}
