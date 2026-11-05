import Foundation
import Synchronization
import Testing
@testable import Core

/// PDR §8 1.0.0: "100 rapid cycle presses → file valid, final state consistent;
/// settings.toml intact after the stress test (diff only in the 4 gap lines)".
@Suite(.serialized) struct StressTests {
    private let presets = ExtConfig.builtInDefault.padding // Fullscreen, Wide, Single; fixture is on Wide (index 1)

    /// Lines that differ between two texts (requires equal line counts).
    private func changedLines(_ old: String, _ new: String) -> [String] {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        #expect(a.count == b.count, "line count changed")
        return zip(a, b).filter { $0 != $1 }.map(\.1)
    }

    /// Every changed line starts with one of the allowed key prefixes.
    private func only(_ lines: [String], _ prefixes: [String]) -> Bool {
        lines.allSatisfy { line in prefixes.contains { line.hasPrefix($0) } }
    }

    private static let gapKeys = ["top =", "bottom =", "left =", "right ="]

    private func currentPreset(_ text: String) -> PaddingSelection? {
        SettingsReader.read(text).settings?.outerGaps.map { PresetMatcher.match($0, presets: presets) }
    }

    @Test func hundredRapidCyclesTouchOnlyTheGapLines() throws {
        let file = try TempSettings()
        let original = try file.text
        for _ in 0..<100 {
            _ = try CommandPlanner.run(.cyclePadding, presets: presets, layout: nil, settingsURL: file.url)
        }
        let final = try file.text
        #expect(SettingsReader.read(final).settings != nil) // still valid TOML
        // Wide + 100 steps → index (1 + 100) % 3 = 2 → Single.
        #expect(currentPreset(final) == .preset(2))
        let changed = changedLines(original, final)
        #expect(only(changed, Self.gapKeys), "\(changed)")
        #expect(changed.count <= 4)
        #expect(try file.strayFiles.isEmpty)
    }

    /// A simulated OmniWM rewrites another key every 20 ms (unguarded read-modify-write + atomic rename,
    /// far more often than the real one). Guarantees under test:
    /// - the file always parses and the gaps are never torn between presets;
    /// - only the gap lines (ours) and the margin line (theirs) change;
    /// - we never clobber their update: their last write survives;
    /// - a conflict we can't resolve is reported (`concurrentModification`), never silent.
    /// Not guaranteed: that *their* unguarded write can't clobber one of our cycles.
    @Test func hundredCyclesWhileOmniWMWritesConcurrently() async throws {
        let file = try TempSettings()
        let original = try file.text
        let url = file.url
        let stop = Mutex(false)
        let lastWritten = Mutex(0)

        let writer = Thread {
            var counter = 0
            while !stop.withLock({ $0 }) {
                counter += 1
                if let text = try? String(contentsOf: url, encoding: .utf8),
                   let range = text.range(of: #"\nmargin = \d+\n"#, options: .regularExpression) { // [mouseWarp]
                    let updated = text.replacingCharacters(in: range, with: "\nmargin = \(counter)\n")
                    if (try? Data(updated.utf8).write(to: url, options: .atomic)) != nil {
                        lastWritten.withLock { $0 = counter }
                    }
                }
                usleep(20_000)
            }
        }
        writer.start()

        var successes = 0
        var conflicts = 0
        for _ in 0..<100 {
            do {
                _ = try CommandPlanner.run(.cyclePadding, presets: presets, layout: nil, settingsURL: url)
                successes += 1
            } catch .settings(.concurrentModification) {
                conflicts += 1
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        stop.withLock { $0 = true }
        try await Task.sleep(for: .milliseconds(60)) // let the writer finish its last iteration

        let final = try file.text
        let theirs = lastWritten.withLock { $0 }
        #expect(theirs > 10, "the writer must actually have raced us")
        #expect(successes + conflicts == 100)
        #expect(successes > 50, "conflicts: \(conflicts)")
        #expect(SettingsReader.read(final).settings != nil)
        guard case .preset = currentPreset(final) else {
            Issue.record("gaps are torn")
            return
        }
        #expect(final.contains("\nmargin = \(theirs)\n"), "their last write must survive")
        let changed = changedLines(original, final)
        #expect(only(changed, Self.gapKeys + ["margin ="]), "\(changed)")
        #expect(try file.strayFiles.isEmpty)
    }

    @Test func unserializedConcurrentCyclesNeverTearTheGaps() async throws {
        let file = try TempSettings()
        let original = try file.text
        let url = file.url
        let presets = presets
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<25 {
                        _ = try? CommandPlanner.run(.cyclePadding, presets: presets, layout: nil, settingsURL: url)
                    }
                }
            }
        }
        let final = try file.text
        #expect(SettingsReader.read(final).settings != nil)
        // Whatever won, all four values belong to one preset (atomic rename, one edit per write).
        guard case .preset = currentPreset(final) else {
            Issue.record("gaps are torn: \(String(describing: SettingsReader.read(final).settings?.outerGaps))")
            return
        }
        let changed = changedLines(original, final)
        #expect(only(changed, Self.gapKeys), "\(changed)")
        #expect(try file.strayFiles.isEmpty)
    }
}
