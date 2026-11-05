import Foundation

/// A physical modifier key, after `hyper` is resolved (PDR §4.3).
public enum KeyModifier: String, Sendable, Hashable, CaseIterable, Comparable {
    case ctrl, opt, shift, cmd

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
    }
}

/// A chord with only physical modifiers, used for registration and conflict checks.
public struct ResolvedHotkey: Sendable, Hashable, CustomStringConvertible {
    public let modifiers: Set<KeyModifier>
    public let key: HotkeyKey

    public init(modifiers: Set<KeyModifier>, key: HotkeyKey) {
        self.modifiers = modifiers
        self.key = key
    }

    public var description: String {
        (modifiers.sorted().map(\.rawValue) + [key.name]).joined(separator: "+")
    }
}

public extension Hotkey {
    /// Replaces `hyper` with the given physical modifiers.
    func resolved(hyper: Set<KeyModifier>) -> ResolvedHotkey {
        var physical = Set<KeyModifier>()
        for modifier in modifiers {
            switch modifier {
            case .hyper: physical.formUnion(hyper)
            case .ctrl: physical.insert(.ctrl)
            case .opt: physical.insert(.opt)
            case .shift: physical.insert(.shift)
            case .cmd: physical.insert(.cmd)
            }
        }
        return ResolvedHotkey(modifiers: physical, key: key)
    }
}

// MARK: - Hyper

public enum HyperParseError: Error, Sendable, Equatable, CustomStringConvertible {
    case empty
    case unknownToken(String)

    public var description: String {
        switch self {
        case .empty: "no modifiers"
        case let .unknownToken(token): "unknown modifier \"\(token)\""
        }
    }
}

public enum HyperModifiers {
    /// OmniWM's factory value, used when `general.hyperKeyModifiers` is missing or invalid.
    public static let fallback: Set<KeyModifier> = [.ctrl, .opt, .shift, .cmd]

    /// Parses `general.hyperKeyModifiers`, e.g. `"Control+Option+Shift+Command"` (PDR §4.3).
    public static func parse(_ value: String) throws(HyperParseError) -> Set<KeyModifier> {
        var result = Set<KeyModifier>()
        for raw in value.split(separator: "+", omittingEmptySubsequences: false) {
            let token = raw.trimmingCharacters(in: .whitespaces)
            guard let modifier = OmniWMBinding.modifier(token) else {
                if token.isEmpty, value.trimmingCharacters(in: .whitespaces).isEmpty { throw .empty }
                throw .unknownToken(token)
            }
            switch modifier {
            case let .physical(physical): result.insert(physical)
            case .hyper: throw .unknownToken(token)
            }
        }
        if result.isEmpty { throw .empty }
        return result
    }
}

// MARK: - OmniWM bindings

/// Parses OmniWM `[[hotkeys]].binding` strings, e.g. `"Control+Option+H"`, `"Hyper+G"`, `"Control+Right Arrow"`.
///
/// Key names come from OmniWM's own key table. Keys we can't express
/// (Delete, Home, F21…) yield `nil`: they can't collide with our chords anyway.
public enum OmniWMBinding {
    enum Modifier {
        case physical(KeyModifier)
        case hyper
    }

    static func modifier(_ token: String) -> Modifier? {
        switch token.lowercased() {
        case "control": .physical(.ctrl)
        case "option": .physical(.opt)
        case "shift": .physical(.shift)
        case "command": .physical(.cmd)
        case "hyper": .hyper
        default: nil
        }
    }

    private static let namedKeys: [String: String] = [
        "space": "space", "tab": "tab", "return": "return", "enter": "return", "escape": "escape",
        "left arrow": "left", "right arrow": "right", "up arrow": "up", "down arrow": "down",
        "minus": "minus", "equal": "equal", "comma": "comma", "period": "period", "slash": "slash",
        "semicolon": "semicolon", "quote": "quote", "apostrophe": "quote", "backslash": "backslash",
        "grave": "grave", "left bracket": "leftbracket", "right bracket": "rightbracket",
    ]

    /// `nil` for `"Unassigned"`, unknown tokens, or keys outside our vocabulary.
    public static func parse(_ binding: String, hyper: Set<KeyModifier>) -> ResolvedHotkey? {
        let trimmed = binding.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != "unassigned" else { return nil }

        var modifiers = Set<KeyModifier>()
        var key: HotkeyKey?
        for raw in trimmed.split(separator: "+", omittingEmptySubsequences: false) {
            let token = raw.trimmingCharacters(in: .whitespaces)
            if let modifier = modifier(token) {
                switch modifier {
                case let .physical(physical): modifiers.insert(physical)
                case .hyper: modifiers.formUnion(hyper)
                }
                continue
            }
            let lower = token.lowercased()
            guard key == nil, let parsed = HotkeyKey(namedKeys[lower] ?? lower) else { return nil }
            key = parsed
        }
        guard let key, !modifiers.isEmpty else { return nil }
        return ResolvedHotkey(modifiers: modifiers, key: key)
    }
}
