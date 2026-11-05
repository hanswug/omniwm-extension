/// What a hotkey triggers.
public enum HotkeyAction: Sendable, Hashable, CustomStringConvertible {
    case command(CommandHotkey)
    /// Direct selection of a padding preset by name (per-preset `hotkey`).
    case selectPreset(String)

    public var description: String {
        switch self {
        case let .command(command): command.rawValue
        case let .selectPreset(name): "padding \"\(name)\""
        }
    }
}

/// One chord to register with the system.
public struct HotkeyRegistration: Sendable, Hashable {
    public let action: HotkeyAction
    /// As written in the config (may contain `hyper`), for display.
    public let hotkey: Hotkey
    /// Physical chord to register.
    public let resolved: ResolvedHotkey
}

/// A chord also bound in OmniWM (PDR §4.3). Still registered; the user decides.
public struct HotkeyConflict: Sendable, Equatable, CustomStringConvertible {
    public let hotkey: Hotkey
    public let omniwmIDs: [String]

    /// `ctrl+opt+b also bound in OmniWM (toggleX)`
    public var description: String {
        "\(hotkey) also bound in OmniWM (\(omniwmIDs.joined(separator: ", ")))"
    }
}

public struct HotkeyPlan: Sendable, Equatable {
    public let registrations: [HotkeyRegistration]
    public let conflicts: [HotkeyConflict]
    /// Chords that only collide after `hyper` is resolved; the later one is skipped.
    public let duplicateWarnings: [String]
}

/// Turns the config plus OmniWM's settings into registrations and warnings (PDR §4.3). Pure.
public enum HotkeyPlanner {
    public static func plan(config: ExtConfig, hyper: Set<KeyModifier>, omniwmHotkeys: [OmniWMSettings.HotkeyBinding]) -> HotkeyPlan {
        var wanted: [(HotkeyAction, Hotkey)] = CommandHotkey.allCases.compactMap { command in
            config.hotkeys[command].map { (.command(command), $0) }
        }
        wanted += config.padding.compactMap { preset in preset.hotkey.map { (.selectPreset(preset.name), $0) } }

        // OmniWM chord → ids, resolved with the same hyper.
        var omniwm: [ResolvedHotkey: [String]] = [:]
        for entry in omniwmHotkeys {
            if let chord = OmniWMBinding.parse(entry.binding, hyper: hyper) {
                omniwm[chord, default: []].append(entry.id)
            }
        }

        var registrations: [HotkeyRegistration] = []
        var conflicts: [HotkeyConflict] = []
        var duplicates: [String] = []
        var taken: [ResolvedHotkey: HotkeyRegistration] = [:]

        for (action, hotkey) in wanted {
            let resolved = hotkey.resolved(hyper: hyper)
            if let first = taken[resolved] {
                duplicates.append("\(hotkey) (\(action)) is the same chord as \(first.hotkey) (\(first.action)); not registered")
                continue
            }
            let registration = HotkeyRegistration(action: action, hotkey: hotkey, resolved: resolved)
            taken[resolved] = registration
            registrations.append(registration)
            if let ids = omniwm[resolved] {
                conflicts.append(HotkeyConflict(hotkey: hotkey, omniwmIDs: ids))
            }
        }
        return HotkeyPlan(registrations: registrations, conflicts: conflicts, duplicateWarnings: duplicates)
    }
}
