/// Which padding preset the current `[gaps.outer]` corresponds to (PDR §6.2).
public enum PaddingSelection: Sendable, Equatable {
    /// Index into the config's `padding` array.
    case preset(Int)
    /// Matches no preset.
    case custom
}

public enum PresetMatcher {
    /// Two values match when they differ by at most this much.
    public static let tolerance = 0.01

    /// Compares all four edges to each preset in order; the first match wins.
    public static func match(_ gaps: OmniWMSettings.OuterGaps, presets: [ExtConfig.PaddingPreset]) -> PaddingSelection {
        for (index, preset) in presets.enumerated()
            where close(gaps.top, preset.top) && close(gaps.bottom, preset.bottom)
            && close(gaps.left, preset.left) && close(gaps.right, preset.right) {
            return .preset(index)
        }
        return .custom
    }

    /// The preset `cycle_padding` moves to: the next one, wrapping; from Custom, the first.
    /// - Returns: `nil` when there are no presets.
    public static func next(after selection: PaddingSelection, count: Int) -> Int? {
        guard count > 0 else { return nil }
        switch selection {
        case let .preset(index): return (index + 1) % count
        case .custom: return 0
        }
    }

    private static func close(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= tolerance
    }
}
