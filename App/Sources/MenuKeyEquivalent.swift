import AppKit
import Core

/// Converts a registered chord into an `NSMenuItem` key-equivalent hint (PDR §5.2).
enum MenuKeyEquivalent {
    private static func functionKey(_ code: Int) -> String {
        String(utf16CodeUnits: [unichar(code)], count: 1)
    }

    private static let special: [String: String] = {
        var map: [String: String] = [
            "space": " ", "tab": "\t", "return": "\r", "escape": "\u{1b}",
            "left": functionKey(NSLeftArrowFunctionKey), "right": functionKey(NSRightArrowFunctionKey),
            "up": functionKey(NSUpArrowFunctionKey), "down": functionKey(NSDownArrowFunctionKey),
            "minus": "-", "equal": "=", "comma": ",", "period": ".", "slash": "/", "semicolon": ";",
            "quote": "'", "backslash": "\\", "leftbracket": "[", "rightbracket": "]", "grave": "`",
        ]
        for index in 1...20 { map["f\(index)"] = functionKey(NSF1FunctionKey + index - 1) }
        return map
    }()

    static func apply(_ chord: ResolvedHotkey?, to item: NSMenuItem) {
        guard let chord else { return }
        item.keyEquivalent = special[chord.key.name] ?? chord.key.name
        var mask: NSEvent.ModifierFlags = []
        for modifier in chord.modifiers {
            switch modifier {
            case .ctrl: mask.insert(.control)
            case .opt: mask.insert(.option)
            case .shift: mask.insert(.shift)
            case .cmd: mask.insert(.command)
            }
        }
        item.keyEquivalentModifierMask = mask
    }
}
