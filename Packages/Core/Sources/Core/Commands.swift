import Foundation

/// The current workspace's layout, from OmniWM IPC (0.6.0). `nil` = unknown.
public enum WorkspaceLayout: String, Sendable, Equatable {
    case niri, dwindle
}

/// A user command from a hotkey or the menu (PDR §6.2–§6.4).
public enum Command: Sendable, Equatable, CustomStringConvertible {
    case cyclePadding
    case selectPreset(String)
    /// 1…6.
    case visibleContainers(Int)
    case toggleBorders

    public init(_ action: HotkeyAction) {
        switch action {
        case .command(.cyclePadding): self = .cyclePadding
        case .command(.toggleBorders): self = .toggleBorders
        case .command(.visibleContainers1): self = .visibleContainers(1)
        case .command(.visibleContainers2): self = .visibleContainers(2)
        case .command(.visibleContainers3): self = .visibleContainers(3)
        case .command(.visibleContainers4): self = .visibleContainers(4)
        case .command(.visibleContainers5): self = .visibleContainers(5)
        case .command(.visibleContainers6): self = .visibleContainers(6)
        case let .selectPreset(name): self = .selectPreset(name)
        }
    }

    public var description: String {
        switch self {
        case .cyclePadding: "cycle padding"
        case let .selectPreset(name): "padding \"\(name)\""
        case let .visibleContainers(count): "\(count) visible containers"
        case .toggleBorders: "toggle borders"
        }
    }
}

/// What a command did, for the HUD (0.5.0) and logs.
public enum CommandResult: Sendable, Equatable {
    /// Padding is now this preset (also when it already was).
    case paddingSet(name: String)
    /// Visible container count is now N (also when it already was: PDR §6.3).
    case containersSet(Int)
    case bordersSet(enabled: Bool)
    /// Current workspace is Dwindle; nothing written (PDR §6.3).
    case skippedDwindle
}

/// A finished command: what it did, and whether `settings.toml` was written.
public struct CommandOutcome: Sendable, Equatable {
    public let result: CommandResult
    public let wroteSettings: Bool

    public init(result: CommandResult, wroteSettings: Bool) {
        self.result = result
        self.wroteSettings = wroteSettings
    }

    /// `omniwmctl` arguments to run after the write, if any.
    ///
    /// OmniWM reloads `visibleContainerCount` from the file but only re-lays out
    /// existing columns after a Balance Sizes, so a written count change is followed by one.
    public var followUp: [String]? {
        if case .containersSet = result, wroteSettings { return ["command", "balance-sizes"] }
        return nil
    }
}

public enum CommandError: Error, Sendable, Equatable, CustomStringConvertible {
    case noPresets
    case unknownPreset(String)
    case invalidContainerCount(Int)
    case settings(SettingsEditError)

    public var description: String {
        switch self {
        case .noPresets: "no padding presets configured"
        case let .unknownPreset(name): "no padding preset named \"\(name)\""
        case let .invalidContainerCount(count): "visible containers must be 1–6 (got \(count))"
        case let .settings(error): error.description
        }
    }
}

/// Decides and applies the `settings.toml` edits for a command (PDR §6).
public enum CommandPlanner {
    static let gapsTable = "gaps.outer"

    /// The edits for `command` given the file's current text. Pure.
    /// - Returns: `nil` edits mean "write nothing" (Dwindle skip).
    public static func plan(
        _ command: Command, presets: [ExtConfig.PaddingPreset], layout: WorkspaceLayout?, text: String
    ) throws(CommandError) -> (edits: [SettingsEdit], result: CommandResult) {
        // Never edit a file OmniWM itself couldn't load; also gives us current values.
        let read = SettingsReader.read(text)
        guard let settings = read.settings else {
            throw .settings(.unparseable(read.issues.first ?? "invalid TOML"))
        }

        switch command {
        case .cyclePadding:
            let current = settings.outerGaps.map { PresetMatcher.match($0, presets: presets) } ?? .custom
            guard let index = PresetMatcher.next(after: current, count: presets.count) else { throw .noPresets }
            return (gapEdits(presets[index]), .paddingSet(name: presets[index].name))

        case let .selectPreset(name):
            guard !presets.isEmpty else { throw .noPresets }
            guard let preset = presets.first(where: { $0.name.lowercased() == name.lowercased() }) else {
                throw .unknownPreset(name)
            }
            return (gapEdits(preset), .paddingSet(name: preset.name))

        case let .visibleContainers(count):
            guard (1...6).contains(count) else { throw .invalidContainerCount(count) }
            // Unknown layout (OmniWM unreachable) → apply (PDR §6.3).
            if layout == .dwindle { return ([], .skippedDwindle) }
            return ([SettingsEdit(table: "niri", key: "visibleContainerCount", value: .int(count))], .containersSet(count))

        case .toggleBorders:
            guard let enabled = settings.bordersEnabled else { throw .settings(.keyNotFound(table: "borders", key: "enabled")) }
            return ([SettingsEdit(table: "borders", key: "enabled", value: .bool(!enabled))], .bordersSet(enabled: !enabled))
        }
    }

    /// Plans against a fresh read of the file and applies the edits atomically.
    /// If the file changes underneath, the retry re-plans from the new content.
    public static func run(
        _ command: Command, presets: [ExtConfig.PaddingPreset], layout: WorkspaceLayout?, settingsURL: URL
    ) throws(CommandError) -> CommandOutcome {
        try validate(command, presets: presets)
        if case .visibleContainers = command, layout == .dwindle {
            return CommandOutcome(result: .skippedDwindle, wroteSettings: false) // nothing to write, so don't even read the file
        }

        var result: CommandResult?
        let edit: SettingsEditOutcome
        do throws(SettingsEditError) {
            edit = try SettingsEditor.edit(fileAt: settingsURL, computing: { text throws(SettingsEditError) in
                do throws(CommandError) {
                    let plan = try plan(command, presets: presets, layout: layout, text: text)
                    result = plan.result
                    return plan.edits
                } catch let .settings(inner) {
                    throw inner
                } catch {
                    throw .unparseable(error.description) // unreachable: validate() rejects the rest
                }
            })
        } catch {
            throw .settings(error)
        }
        guard let result else { throw .settings(.unparseable("no result")) }
        return CommandOutcome(result: result, wroteSettings: edit == .written)
    }

    /// Checks that don't depend on the file.
    static func validate(_ command: Command, presets: [ExtConfig.PaddingPreset]) throws(CommandError) {
        switch command {
        case .cyclePadding:
            if presets.isEmpty { throw .noPresets }
        case let .selectPreset(name):
            if presets.isEmpty { throw .noPresets }
            if !presets.contains(where: { $0.name.lowercased() == name.lowercased() }) { throw .unknownPreset(name) }
        case let .visibleContainers(count):
            if !(1...6).contains(count) { throw .invalidContainerCount(count) }
        case .toggleBorders:
            break
        }
    }

    private static func gapEdits(_ preset: ExtConfig.PaddingPreset) -> [SettingsEdit] {
        [
            SettingsEdit(table: gapsTable, key: "top", value: .float(preset.top)),
            SettingsEdit(table: gapsTable, key: "bottom", value: .float(preset.bottom)),
            SettingsEdit(table: gapsTable, key: "left", value: .float(preset.left)),
            SettingsEdit(table: gapsTable, key: "right", value: .float(preset.right)),
        ]
    }
}
