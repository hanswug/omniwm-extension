import Foundation

/// Which OmniWM app the extension talks to (PDR §6.7): the running one.
/// OmniWM Dev (`make run` in an OmniWM checkout) has its own `omniwmctl` and settings file.
public enum OmniWMBuild: Sendable, Equatable {
    case release
    case dev

    public static let devBundleIdentifier = "com.barut.OmniWM.dev"

    /// `.dev` while OmniWM Dev is running, otherwise `.release`.
    public static func running(bundleIdentifiers: some Sequence<String>) -> OmniWMBuild {
        bundleIdentifiers.contains(devBundleIdentifier) ? .dev : .release
    }

    public var displayName: String {
        switch self {
        case .release: "OmniWM"
        case .dev: "OmniWM Dev"
        }
    }
}
