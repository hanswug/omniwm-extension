import Foundation
import Testing
@testable import Core

/// `examples/config.toml` is meant for copy/paste; keep it valid and warning-free.
@Suite struct ExampleConfigTests {
    private var exampleURL: URL {
        // …/Packages/Core/Tests/CoreTests/ExampleConfigTests.swift → repo root
        URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "examples/config.toml")
    }

    @Test func parsesWithoutIssues() throws {
        let text = try String(contentsOf: exampleURL, encoding: .utf8)
        let result = ConfigParser.parse(text)
        #expect(result.issues.isEmpty, "\(result.issues)")
        let config = try #require(result.config)
        #expect(config.padding.map(\.name) == ["Fullscreen", "Wide", "Wide Comfort", "Single"])
        #expect(config.hotkeys[.cyclePadding]?.description == "ctrl+opt+0")
        #expect(config.general.balanceSizesDelayMs == 120)
    }

    @Test func coversEveryKeyOfTheDefaultFile() throws {
        // Every `key =` in the generated default also appears in the example, so it documents all options.
        func keys(_ text: String) -> Set<String> {
            Set(text.components(separatedBy: "\n").compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
                return trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            })
        }
        let example = try String(contentsOf: exampleURL, encoding: .utf8)
        #expect(keys(ExtConfig.defaultFileContents).isSubset(of: keys(example)))
    }
}
