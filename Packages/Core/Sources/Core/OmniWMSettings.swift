import Foundation
import TOMLKit

/// The parts of OmniWM's `settings.toml` the extension reads (PDR §3.2, 0.3.0).
/// Every field is optional/tolerant: OmniWM owns the schema.
public struct OmniWMSettings: Sendable, Equatable {
    public struct OuterGaps: Sendable, Equatable {
        public var top: Double
        public var bottom: Double
        public var left: Double
        public var right: Double

        public init(top: Double, bottom: Double, left: Double, right: Double) {
            (self.top, self.bottom, self.left, self.right) = (top, bottom, left, right)
        }
    }

    /// A `[[hotkeys]]` entry.
    public struct HotkeyBinding: Sendable, Equatable {
        public var id: String
        public var binding: String
    }

    /// How an override row identifies its display (PDR §6.6).
    public struct MonitorMatch: Sendable, Equatable {
        public var displayUUID: String?
        /// Stored as text; OmniWM may write it as an integer.
        public var displayId: String?
        public var name: String?
    }

    public struct NiriOverride: Sendable, Equatable {
        public var monitor: MonitorMatch
        public var visibleContainerCount: Int?
    }

    public struct Workspace: Sendable, Equatable {
        /// The workspace number as text (`[[workspaces]] name`).
        public var name: String
        public var displayName: String?
    }

    public var bordersEnabled: Bool?
    public var outerGaps: OuterGaps?
    public var visibleContainerCount: Int?
    /// Raw `general.hyperKeyModifiers`.
    public var hyperKeyModifiers: String?
    public var hotkeys: [HotkeyBinding] = []
    public var monitorGapOverrides: [MonitorMatch] = []
    public var monitorNiriOverrides: [NiriOverride] = []
    public var workspaces: [Workspace] = []

    public init() {}
}

public struct SettingsReadResult: Sendable, Equatable {
    /// `nil` when the file couldn't be parsed at all.
    public let settings: OmniWMSettings?
    /// Human-readable problems, for logs and the menu.
    public let issues: [String]
}

/// Reads OmniWM's `settings.toml` with TOMLKit (reading only; writes go through `SettingsEditor`).
public enum SettingsReader {
    public static func read(_ text: String) -> SettingsReadResult {
        let root: TOMLTable
        do {
            root = try TOMLTable(string: text)
        } catch let error as TOMLParseError {
            return SettingsReadResult(settings: nil, issues: ["\(error.description) (line \(error.source.begin.line))"])
        } catch {
            return SettingsReadResult(settings: nil, issues: ["\(error)"])
        }

        var settings = OmniWMSettings()
        settings.bordersEnabled = root["borders"]?["enabled"]?.bool

        if let outer = root["gaps"]?["outer"]?.table,
           let top = number(outer["top"]), let bottom = number(outer["bottom"]),
           let left = number(outer["left"]), let right = number(outer["right"]) {
            settings.outerGaps = .init(top: top, bottom: bottom, left: left, right: right)
        }

        settings.visibleContainerCount = root["niri"]?["visibleContainerCount"]?.int
        settings.hyperKeyModifiers = root["general"]?["hyperKeyModifiers"]?.string

        settings.hotkeys = tables(root["hotkeys"]).compactMap { table in
            guard let id = table["id"]?.string, let binding = table["binding"]?.string else { return nil }
            return .init(id: id, binding: binding)
        }
        settings.monitorGapOverrides = tables(root["monitorGapOverrides"]).map(monitor)
        settings.monitorNiriOverrides = tables(root["monitorNiriOverrides"]).map {
            .init(monitor: monitor($0), visibleContainerCount: $0["visibleContainerCount"]?.int)
        }
        settings.workspaces = tables(root["workspaces"]).compactMap { table in
            guard let name = table["name"]?.string ?? table["name"]?.int.map(String.init) else { return nil }
            let displayName = table["displayName"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            return .init(name: name, displayName: displayName)
        }
        return SettingsReadResult(settings: settings, issues: [])
    }

    private static func number(_ value: TOMLValueConvertible?) -> Double? {
        guard let value else { return nil }
        return value.double ?? value.int.map(Double.init)
    }

    private static func tables(_ value: TOMLValueConvertible?) -> [TOMLTable] {
        guard let array = value?.array else { return [] }
        return array.compactMap(\.table)
    }

    private static func monitor(_ table: TOMLTable) -> OmniWMSettings.MonitorMatch {
        .init(
            displayUUID: table["monitorDisplayUUID"]?.string,
            displayId: table["monitorDisplayId"]?.string ?? table["monitorDisplayId"]?.int.map(String.init),
            name: table["monitorName"]?.string
        )
    }
}

public extension OmniWMSettings {
    /// Physical modifiers for `hyper`, plus a problem description when falling back (PDR §4.3).
    var resolvedHyper: (modifiers: Set<KeyModifier>, issue: String?) {
        guard let raw = hyperKeyModifiers else {
            return (HyperModifiers.fallback, "general.hyperKeyModifiers missing; hyper = ctrl+opt+shift+cmd")
        }
        do {
            return (try HyperModifiers.parse(raw), nil)
        } catch {
            return (HyperModifiers.fallback, "general.hyperKeyModifiers \"\(raw)\": \(error); hyper = ctrl+opt+shift+cmd")
        }
    }
}
