import Foundation

/// Filesystem locations used by the app (PDR §2, §4, CLAUDE.md "Environment facts").
///
/// `XDG_CONFIG_HOME` is honoured only when it is an absolute path, matching OmniWM.
public struct AppPaths: Sendable, Equatable {
    public static let bundleIdentifier = "com.omniwm.extension"

    /// `${XDG_CONFIG_HOME:-~/.config}`
    public let configHome: URL
    /// `~/Library/Application Support/com.omniwm.extension`
    public let appSupportDirectory: URL

    public init(environment: [String: String], homeDirectory: URL) {
        if let xdg = environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            configHome = URL(filePath: xdg, directoryHint: .isDirectory)
        } else {
            configHome = homeDirectory.appending(path: ".config", directoryHint: .isDirectory)
        }
        appSupportDirectory = homeDirectory
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
            .appending(path: Self.bundleIdentifier, directoryHint: .isDirectory)
    }

    /// Paths for the current process.
    public static var current: AppPaths {
        AppPaths(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    /// `<configHome>/omniwm/settings.toml`
    public var omniwmSettingsURL: URL {
        configHome.appending(path: "omniwm/settings.toml", directoryHint: .notDirectory)
    }

    /// `<configHome>/omniwm-extension/`
    public var extensionConfigDirectory: URL {
        configHome.appending(path: "omniwm-extension", directoryHint: .isDirectory)
    }

    /// `<configHome>/omniwm-extension/config.toml`
    public var extensionConfigURL: URL {
        extensionConfigDirectory.appending(path: "config.toml", directoryHint: .notDirectory)
    }

    /// `~/Library/Application Support/com.omniwm.extension/state.json`
    public var stateURL: URL {
        appSupportDirectory.appending(path: "state.json", directoryHint: .notDirectory)
    }
}
