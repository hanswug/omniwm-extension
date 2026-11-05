import Foundation

/// A modifier token in a hotkey string (PDR §4).
///
/// `hyper` stays symbolic here; it is resolved against OmniWM's
/// `general.hyperKeyModifiers` when hotkeys are registered (PDR §4.3).
public enum HotkeyModifier: String, CaseIterable, Sendable, Hashable, Comparable {
    case hyper, ctrl, opt, shift, cmd

    /// Accepted spellings (lower-cased) → modifier.
    static let tokens: [String: HotkeyModifier] = [
        "ctrl": .ctrl, "opt": .opt, "alt": .opt, "cmd": .cmd, "shift": .shift, "hyper": .hyper,
    ]

    /// Display order: hyper, then the macOS order ⌃⌥⇧⌘.
    private var order: Int {
        switch self {
        case .hyper: 0
        case .ctrl: 1
        case .opt: 2
        case .shift: 3
        case .cmd: 4
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

/// The single non-modifier key of a hotkey (PDR §4 key list).
public struct HotkeyKey: Sendable, Hashable, CustomStringConvertible {
    public let name: String

    /// Every accepted key name, lower-case.
    public static let allNames: Set<String> = {
        var names = Set("abcdefghijklmnopqrstuvwxyz".map(String.init))
        for digit in 0...9 { names.insert(String(digit)) }
        for function in 1...20 { names.insert("f\(function)") }
        names.formUnion([
            "space", "tab", "return", "escape", "left", "right", "up", "down",
            "minus", "equal", "comma", "period", "slash", "semicolon", "quote", "backslash",
            "leftbracket", "rightbracket", "grave",
        ])
        return names
    }()

    init?(_ token: String) {
        guard Self.allNames.contains(token) else { return nil }
        name = token
    }

    public var description: String { name }
}

/// A parsed chord such as `ctrl+opt+b`.
public struct Hotkey: Sendable, Hashable, CustomStringConvertible {
    public let modifiers: Set<HotkeyModifier>
    public let key: HotkeyKey

    /// Canonical form: modifiers in `HotkeyModifier` order, then the key, e.g. `hyper+1`, `ctrl+opt+b`.
    public var description: String {
        (modifiers.sorted().map(\.rawValue) + [key.name]).joined(separator: "+")
    }
}

public enum HotkeyParseError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyToken
    case unknownToken(String)
    case noKey
    case multipleKeys(String, String)
    case noModifier

    public var description: String {
        switch self {
        case .emptyToken: "empty token (stray \"+\")"
        case let .unknownToken(token): "unknown token \"\(token)\""
        case .noKey: "no key, only modifiers"
        case let .multipleKeys(first, second): "more than one key (\"\(first)\" and \"\(second)\")"
        case .noModifier: "needs at least one modifier"
        }
    }
}

public enum HotkeyParser {
    /// Parses a hotkey string (PDR §4.1).
    ///
    /// Case-insensitive, `+`-separated, whitespace around tokens ignored.
    /// Exactly one non-modifier key and at least one modifier.
    /// - Returns: `nil` for `""` (unbound).
    public static func parse(_ string: String) throws(HotkeyParseError) -> Hotkey? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }

        var modifiers = Set<HotkeyModifier>()
        var key: HotkeyKey?
        for rawToken in trimmed.split(separator: "+", omittingEmptySubsequences: false) {
            let token = rawToken.trimmingCharacters(in: .whitespaces).lowercased()
            if token.isEmpty { throw .emptyToken }
            if let modifier = HotkeyModifier.tokens[token] {
                modifiers.insert(modifier)
            } else if let parsed = HotkeyKey(token) {
                if let key { throw .multipleKeys(key.name, parsed.name) }
                key = parsed
            } else {
                throw .unknownToken(String(rawToken.trimmingCharacters(in: .whitespaces)))
            }
        }
        guard let key else { throw .noKey }
        guard !modifiers.isEmpty else { throw .noModifier }
        return Hotkey(modifiers: modifiers, key: key)
    }
}
