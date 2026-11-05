import Foundation

/// Identifies a physical display for matching OmniWM's per-monitor overrides (PDR §6.6).
public struct DisplayIdentity: Sendable, Equatable {
    /// `CGDisplayCreateUUIDFromDisplayID`, supplied by the app.
    public var uuid: String?
    /// Numeric display id, e.g. `2` from IPC's `display:2`.
    public var id: String?
    public var name: String?

    public init(uuid: String?, id: String?, name: String?) {
        self.uuid = uuid
        self.id = id
        self.name = name
    }

    /// `display:2` → `2`.
    public static func numericID(fromIPC id: String?) -> String? {
        guard let id else { return nil }
        if let colon = id.lastIndex(of: ":") { return String(id[id.index(after: colon)...]) }
        return id
    }
}

public enum DisplayOverrides {
    /// By `monitorDisplayUUID` when the row has one, else `monitorDisplayId` + `monitorName` (PDR §6.6).
    public static func matches(_ row: OmniWMSettings.MonitorMatch, _ display: DisplayIdentity) -> Bool {
        if let uuid = row.displayUUID {
            guard let displayUUID = display.uuid else { return false }
            return uuid.caseInsensitiveCompare(displayUUID) == .orderedSame
        }
        guard let rowID = row.displayId, rowID == display.id else { return false }
        if let rowName = row.name { return rowName == display.name }
        return true
    }

    /// A `[[monitorGapOverrides]]` row applies to this display.
    public static func overridesGaps(_ settings: OmniWMSettings, on display: DisplayIdentity) -> Bool {
        settings.monitorGapOverrides.contains { matches($0, display) }
    }

    /// The `visibleContainerCount` a `[[monitorNiriOverrides]]` row sets for this display, if any.
    public static func containerOverride(_ settings: OmniWMSettings, on display: DisplayIdentity) -> Int? {
        settings.monitorNiriOverrides.first { $0.visibleContainerCount != nil && matches($0.monitor, display) }?.visibleContainerCount
    }

    /// Override if present, else the global value (PDR §6.6: the dots show the effective count).
    public static func effectiveContainerCount(_ settings: OmniWMSettings?, on display: DisplayIdentity?) -> Int? {
        guard let settings else { return nil }
        if let display, let override = containerOverride(settings, on: display) { return override }
        return settings.visibleContainerCount
    }
}
