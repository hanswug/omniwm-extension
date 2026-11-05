/// The extension's own configuration, `config.toml` (PDR §4).
public struct ExtConfig: Sendable, Equatable {
    public struct General: Sendable, Equatable {
        /// Path to OmniWM's settings. Empty = auto (see `AppPaths.omniwmSettingsURL`).
        public var omniwmSettings: String
        public var autoFullscreenOnBuiltin: Bool
    }

    public enum HUDPosition: String, Sendable, Equatable, CaseIterable {
        case center, top, bottom
    }

    public struct HUD: Sendable, Equatable {
        public static let durationRange = 300...5000
        public var enabled: Bool
        public var position: HUDPosition
        /// Always within `durationRange`.
        public var durationMs: Int
    }

    public struct PaddingPreset: Sendable, Equatable {
        public var name: String
        public var top: Double
        public var bottom: Double
        public var left: Double
        public var right: Double
        public var hotkey: Hotkey?
    }

    public var general: General
    public var hud: HUD
    /// Bound command hotkeys. A missing entry means unbound.
    public var hotkeys: [CommandHotkey: Hotkey]
    /// Non-empty, names unique case-insensitively. Order = cycle order.
    public var padding: [PaddingPreset]
}

/// The commands that have a hotkey in `[hotkeys]`. Raw value = config key.
public enum CommandHotkey: String, Sendable, Hashable, CaseIterable {
    case cyclePadding = "cycle_padding"
    case toggleBorders = "toggle_borders"
    case visibleContainers1 = "visible_containers_1"
    case visibleContainers2 = "visible_containers_2"
    case visibleContainers3 = "visible_containers_3"
    case visibleContainers4 = "visible_containers_4"
    case visibleContainers5 = "visible_containers_5"
    case visibleContainers6 = "visible_containers_6"
}

public extension ExtConfig {
    /// The values of `defaultFileContents`, used when the very first load is invalid (PDR §4.2).
    static let builtInDefault: ExtConfig = {
        func hotkey(_ string: String) -> Hotkey? {
            // The literals below are covered by tests; a typo would surface as an unbound key, never a crash.
            try? HotkeyParser.parse(string)
        }
        func preset(_ name: String, _ top: Double, _ bottom: Double, _ left: Double, _ right: Double) -> PaddingPreset {
            PaddingPreset(name: name, top: top, bottom: bottom, left: left, right: right, hotkey: nil)
        }
        var hotkeys: [CommandHotkey: Hotkey] = [:]
        hotkeys[.cyclePadding] = hotkey("ctrl+opt+0")
        hotkeys[.toggleBorders] = hotkey("ctrl+opt+b")
        hotkeys[.visibleContainers1] = hotkey("hyper+1")
        hotkeys[.visibleContainers2] = hotkey("hyper+2")
        hotkeys[.visibleContainers3] = hotkey("hyper+3")
        hotkeys[.visibleContainers4] = hotkey("hyper+4")
        return ExtConfig(
            general: General(omniwmSettings: "", autoFullscreenOnBuiltin: true),
            hud: HUD(enabled: true, position: .center, durationMs: 900),
            hotkeys: hotkeys,
            padding: [
                preset("Fullscreen", 8, 8, 8, 8),
                preset("Wide", 540, 8, 8, 8),
                preset("Single", 720, 8, 640, 640),
            ]
        )
    }()

    /// Written on first launch when `config.toml` is missing (PDR §4, verbatim).
    static let defaultFileContents = """
    # OmniWM Extension config — saved changes apply immediately.

    [general]
    # Path to OmniWM settings. Empty = auto (${XDG_CONFIG_HOME:-~/.config}/omniwm/settings.toml)
    omniwm_settings = ""
    # On the built-in display alone (no external), switch padding to the first preset.
    # When an external display returns, restore what it had before.
    auto_fullscreen_on_builtin = true

    [hud]
    enabled = true
    position = "center"      # center | top | bottom
    duration_ms = 900

    [hotkeys]
    # Modifiers: ctrl, opt (alt), cmd, shift, hyper (= OmniWM's general.hyperKeyModifiers)
    # Keys: a–z, 0–9, f1–f20, space, tab, return, escape, left, right, up, down,
    #       minus, equal, comma, period, slash, semicolon, quote, backslash,
    #       leftbracket, rightbracket, grave
    # "" (or omitting the key) = unbound
    cycle_padding        = "ctrl+opt+0"
    toggle_borders       = "ctrl+opt+b"
    visible_containers_1 = "hyper+1"
    visible_containers_2 = "hyper+2"
    visible_containers_3 = "hyper+3"
    visible_containers_4 = "hyper+4"
    visible_containers_5 = ""
    visible_containers_6 = ""

    # Padding presets. Order = cycle order. The FIRST preset is the one
    # auto_fullscreen_on_builtin applies. Add, remove, or rename freely.
    # Optional per preset: hotkey = "..."
    [[padding]]
    name = "Fullscreen"
    top = 8
    bottom = 8
    left = 8
    right = 8

    [[padding]]
    name = "Wide"
    top = 540
    bottom = 8
    left = 8
    right = 8

    [[padding]]
    name = "Single"
    top = 720
    bottom = 8
    left = 640
    right = 640

    """
}
