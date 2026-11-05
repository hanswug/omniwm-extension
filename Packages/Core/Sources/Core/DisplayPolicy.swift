import Foundation

/// Whether only the built-in display is active (PDR §6.5).
public enum DisplayTopology: String, Sendable, Equatable, Codable {
    /// Every active display is built in.
    case builtInOnly
    /// At least one non-built-in display (incl. clamshell with an external only).
    case docked

    /// From the `CGDisplayIsBuiltin` result of each active display. `nil` for no displays
    /// (transient during sleep/wake; ignore).
    public static func classify(builtIn displays: [Bool]) -> DisplayTopology? {
        guard !displays.isEmpty else { return nil }
        return displays.allSatisfy { $0 } ? .builtInOnly : .docked
    }
}

/// Persisted in `state.json` (PDR §6.5).
public struct DisplayState: Sendable, Equatable, Codable {
    public var lastTopology: DisplayTopology?
    /// Exact `[gaps.outer]` from before the last switch to built-in-only, so `Custom` round-trips.
    public var lastExternalGaps: OmniWMSettings.OuterGaps?

    public init(lastTopology: DisplayTopology? = nil, lastExternalGaps: OmniWMSettings.OuterGaps? = nil) {
        self.lastTopology = lastTopology
        self.lastExternalGaps = lastExternalGaps
    }
}

extension OmniWMSettings.OuterGaps: Codable {
    enum CodingKeys: String, CodingKey { case top, bottom, left, right }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            top: container.decode(Double.self, forKey: .top), bottom: container.decode(Double.self, forKey: .bottom),
            left: container.decode(Double.self, forKey: .left), right: container.decode(Double.self, forKey: .right)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(top, forKey: .top)
        try container.encode(bottom, forKey: .bottom)
        try container.encode(left, forKey: .left)
        try container.encode(right, forKey: .right)
    }
}

public enum DisplayAction: Sendable, Equatable {
    case none
    /// Docked → built-in-only: apply the first preset.
    case applyFirstPreset
    /// Built-in-only → docked: write these gaps back.
    case restore(OmniWMSettings.OuterGaps)
}

/// The auto-fullscreen rule as a pure function (PDR §6.5).
public enum DisplayPolicy {
    /// - Parameters:
    ///   - state: persisted state (its `lastTopology` is the previous topology).
    ///   - current: the topology now.
    ///   - currentGaps: `[gaps.outer]` read fresh from settings.toml; `nil` if unreadable.
    ///   - enabled: `general.auto_fullscreen_on_builtin`.
    /// - Returns: what to do, and the state to persist (always tracks the topology).
    public static func decide(
        state: DisplayState, current: DisplayTopology, currentGaps: OmniWMSettings.OuterGaps?, enabled: Bool
    ) -> (action: DisplayAction, state: DisplayState) {
        var next = state
        next.lastTopology = current

        // Same topology (incl. a relaunch without change): never override a manual choice.
        guard let previous = state.lastTopology, previous != current else {
            // First run ever (nothing recorded): just record.
            return (.none, next)
        }
        // Disabled: track the topology only, so enabling later doesn't fire spuriously.
        guard enabled else { return (.none, next) }

        switch (previous, current) {
        case (.docked, .builtInOnly):
            // Unknown gaps → forget any older value rather than restore something stale later.
            next.lastExternalGaps = currentGaps
            return (.applyFirstPreset, next)
        case (.builtInOnly, .docked):
            guard let saved = state.lastExternalGaps else { return (.none, next) }
            return (.restore(saved), next)
        default:
            return (.none, next)
        }
    }
}

/// Reads and writes `state.json`. Missing or unreadable → empty state (logged by the caller).
public enum DisplayStateStore {
    public static func load(from url: URL) -> (state: DisplayState, issue: String?) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return (DisplayState(), nil)
        } catch {
            return (DisplayState(), "couldn't read \(url.path): \(error.localizedDescription)")
        }
        do {
            return (try JSONDecoder().decode(DisplayState.self, from: data), nil)
        } catch {
            return (DisplayState(), "\(url.lastPathComponent) is corrupt; starting fresh")
        }
    }

    /// Atomic write; creates the directory.
    public static func save(_ state: DisplayState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
