/// Holds the running config and applies reloads with last-good retention (PDR §4.2).
///
/// A value type with no I/O: the app reads the file off the main thread and
/// feeds the outcome in here.
public struct ConfigStore: Sendable, Equatable {
    /// What a load attempt produced.
    public enum Load: Sendable, Equatable {
        /// The file was read; `text` is its contents.
        case read(text: String)
        /// The file couldn't be read (missing, unreadable, not UTF-8).
        case failed(ConfigIssue)
    }

    public enum Outcome: Sendable, Equatable {
        /// First valid config.
        case loaded
        /// A new valid config replaced the previous one.
        case reloaded
        /// Invalid; the last good config keeps running.
        case keptPrevious
        /// Invalid and nothing valid was ever loaded: built-in defaults run.
        case usingDefaults
        /// The file content is identical to the last attempt (non-forced reload); nothing changed.
        case unchanged
    }

    /// The config in effect. Built-in defaults until a valid file loads.
    public private(set) var config: ExtConfig = .builtInDefault
    /// Issues of the latest attempt: errors (if rejected) and warnings.
    public private(set) var issues: [ConfigIssue] = []
    public private(set) var hasValidConfig = false
    private var lastText: String?

    public init() {}

    /// Applies a load attempt.
    /// - Parameter force: re-apply even if the text is unchanged ("Reload config").
    @discardableResult
    public mutating func apply(_ load: Load, force: Bool = false) -> Outcome {
        let parsed: ConfigParseResult
        switch load {
        case let .read(text):
            if !force, text == lastText { return .unchanged }
            lastText = text
            parsed = ConfigParser.parse(text)
        case let .failed(issue):
            lastText = nil
            parsed = ConfigParseResult(config: nil, issues: [issue])
        }

        issues = parsed.issues
        if let new = parsed.config {
            config = new
            defer { hasValidConfig = true }
            return hasValidConfig ? .reloaded : .loaded
        }
        return hasValidConfig ? .keptPrevious : .usingDefaults
    }
}
