import os

/// Loggers for subsystem `com.omniwm.extension` (PDR §3.1).
///
/// Debug with: `log stream --predicate 'subsystem == "com.omniwm.extension"'`
public enum Log {
    public static let subsystem = AppPaths.bundleIdentifier

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let bridge = Logger(subsystem: subsystem, category: "bridge")
    public static let settings = Logger(subsystem: subsystem, category: "settings")
    public static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    public static let display = Logger(subsystem: subsystem, category: "display")
    public static let config = Logger(subsystem: subsystem, category: "config")
}
