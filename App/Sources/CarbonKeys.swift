import Carbon.HIToolbox
import Core

/// Maps Core's key names and modifiers to Carbon virtual key codes / modifier flags.
/// Key codes are positional (ANSI layout), like every Carbon hotkey.
enum CarbonKeys {
    static let keyCodes: [String: Int] = {
        var codes: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "space": kVK_Space, "tab": kVK_Tab, "return": kVK_Return, "escape": kVK_Escape,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal, "comma": kVK_ANSI_Comma,
            "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash, "semicolon": kVK_ANSI_Semicolon,
            "quote": kVK_ANSI_Quote, "backslash": kVK_ANSI_Backslash,
            "leftbracket": kVK_ANSI_LeftBracket, "rightbracket": kVK_ANSI_RightBracket,
            "grave": kVK_ANSI_Grave,
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, code) in functionKeys.enumerated() { codes["f\(index + 1)"] = code }
        return codes
    }()

    static func keyCode(for key: HotkeyKey) -> UInt32? {
        keyCodes[key.name].map(UInt32.init)
    }

    static func modifierFlags(_ modifiers: Set<KeyModifier>) -> UInt32 {
        var flags = 0
        for modifier in modifiers {
            switch modifier {
            case .ctrl: flags |= controlKey
            case .opt: flags |= optionKey
            case .shift: flags |= shiftKey
            case .cmd: flags |= cmdKey
            }
        }
        return UInt32(flags)
    }

    /// Keys from Core's vocabulary without a Carbon code (should be none).
    static var unmappedKeys: Set<String> { HotkeyKey.allNames.subtracting(keyCodes.keys) }
}
