/// A problem found while loading `config.toml`, shown in the menu (PDR §4.1, §4.2).
public struct ConfigIssue: Sendable, Equatable, CustomStringConvertible {
    public enum Severity: Sendable, Equatable {
        /// The config is rejected; the last good config keeps running.
        case error
        /// Tolerated (e.g. unknown key, clamped value).
        case warning
    }

    public let severity: Severity
    public let message: String
    /// 1-based line in `config.toml`, if known.
    public let line: Int?

    public init(_ severity: Severity, _ message: String, line: Int? = nil) {
        self.severity = severity
        self.message = message
        self.line = line
    }

    /// Menu text, e.g. `Config error: hud.position … (line 12)`.
    public var description: String {
        let prefix = severity == .error ? "Config error" : "Config warning"
        let suffix = line.map { " (line \($0))" } ?? ""
        return "\(prefix): \(message)\(suffix)"
    }
}
