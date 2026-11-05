import Foundation
import TOMLKit

/// Result of parsing `config.toml`: a config when there are no errors, plus all issues.
public struct ConfigParseResult: Sendable, Equatable {
    /// `nil` iff `errors` is non-empty.
    public let config: ExtConfig?
    /// Errors and warnings, ordered by line.
    public let issues: [ConfigIssue]

    public var errors: [ConfigIssue] { issues.filter { $0.severity == .error } }
    public var warnings: [ConfigIssue] { issues.filter { $0.severity == .warning } }
}

/// Parses and validates `config.toml` (PDR §4, §4.1).
public enum ConfigParser {
    public static func parse(_ text: String) -> ConfigParseResult {
        let root: TOMLTable
        do {
            root = try TOMLTable(string: text)
        } catch let error as TOMLParseError {
            return ConfigParseResult(config: nil, issues: [ConfigIssue(.error, error.description, line: error.source.begin.line)])
        } catch {
            return ConfigParseResult(config: nil, issues: [ConfigIssue(.error, "\(error)")])
        }
        var validator = Validator(root: root, locator: TOMLLineLocator(text))
        return validator.run()
    }
}

// MARK: - Validation

private struct Validator {
    let root: TOMLTable
    let locator: TOMLLineLocator
    var issues: [ConfigIssue] = []

    private static let rootKeys: Set<String> = ["general", "hud", "hotkeys", "padding"]
    private static let generalKeys: Set<String> = ["omniwm_settings", "auto_fullscreen_on_builtin", "balance_sizes_delay_ms"]
    private static let hudKeys: Set<String> = ["enabled", "position", "duration_ms"]
    private static let retiredContainersKey = "visible_containers_6"
    private static let presetKeys: Set<String> = ["name", "top", "bottom", "left", "right", "hotkey"]

    /// A bound chord and where it came from, for duplicate detection.
    private struct Binding {
        let hotkey: Hotkey
        let label: String
        let line: Int?
    }

    private var bindings: [Binding] = []

    init(root: TOMLTable, locator: TOMLLineLocator) {
        self.root = root
        self.locator = locator
    }

    mutating func run() -> ConfigParseResult {
        let defaults = ExtConfig.builtInDefault
        let locator = self.locator // local copy: closures below must not capture `self` while it mutates

        warnUnknownKeys(in: root, known: Self.rootKeys, context: nil) { locator.line(table: "", key: $0) ?? locator.line(table: $0) }

        var general = defaults.general
        if let table = section("general") {
            warnUnknownKeys(in: table, known: Self.generalKeys, context: "[general]") { locator.line(table: "general", key: $0) }
            if let path = string(table, "general", "omniwm_settings") {
                let trimmed = path.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("/") || trimmed == "~" || trimmed.hasPrefix("~/") {
                    general.omniwmSettings = path
                } else {
                    error("general.omniwm_settings must be empty, absolute, or start with ~/ (got \"\(path)\")",
                          locator.line(table: "general", key: "omniwm_settings"))
                }
            }
            general.autoFullscreenOnBuiltin = bool(table, "general", "auto_fullscreen_on_builtin") ?? general.autoFullscreenOnBuiltin
            general.balanceSizesDelayMs = milliseconds(
                table, "general", "balance_sizes_delay_ms", range: ExtConfig.General.balanceSizesDelayRange
            ) ?? general.balanceSizesDelayMs
        }

        var hud = defaults.hud
        if let table = section("hud") {
            warnUnknownKeys(in: table, known: Self.hudKeys, context: "[hud]") { locator.line(table: "hud", key: $0) }
            hud.enabled = bool(table, "hud", "enabled") ?? hud.enabled
            hud.position = position(table) ?? hud.position
            hud.durationMs = milliseconds(table, "hud", "duration_ms", range: ExtConfig.HUD.durationRange) ?? hud.durationMs
        }

        // Omitting [hotkeys] or a key inside it = unbound.
        var hotkeys: [CommandHotkey: Hotkey] = [:]
        if let table = section("hotkeys") {
            let known = Set(CommandHotkey.allCases.map(\.rawValue)).union([Self.retiredContainersKey])
            warnUnknownKeys(in: table, known: known, context: "[hotkeys]") { locator.line(table: "hotkeys", key: $0) }
            // Written by older default configs; harmless when unbound, pointless when bound (OmniWM max is 5).
            if let value = table[Self.retiredContainersKey], value.string?.trimmingCharacters(in: .whitespaces).isEmpty != true {
                warning(
                    "hotkeys.\(Self.retiredContainersKey) is not supported (OmniWM allows at most 5 visible containers); remove it",
                    locator.line(table: "hotkeys", key: Self.retiredContainersKey)
                )
            }
            for command in CommandHotkey.allCases {
                let line = locator.line(table: "hotkeys", key: command.rawValue)
                guard let value = table[command.rawValue] else { continue }
                guard let raw = value.string else {
                    error("hotkeys.\(command.rawValue) must be a string like \"ctrl+opt+b\" or \"\"", line)
                    continue
                }
                if let hotkey = parseHotkey(raw, label: "hotkeys.\(command.rawValue)", line: line) {
                    hotkeys[command] = hotkey
                }
            }
        }

        let padding = presets()
        checkDuplicateChords()

        issues.sort { ($0.line ?? .max) < ($1.line ?? .max) }
        let hasErrors = issues.contains { $0.severity == .error }
        let config = hasErrors ? nil : ExtConfig(general: general, hud: hud, hotkeys: hotkeys, padding: padding)
        return ConfigParseResult(config: config, issues: issues)
    }

    // MARK: Sections

    private mutating func section(_ name: String) -> TOMLTable? {
        guard let value = root[name] else { return nil }
        guard let table = value.table else {
            error("\(name) must be a table ([\(name)])", locator.line(table: "", key: name))
            return nil
        }
        return table
    }

    private mutating func position(_ table: TOMLTable) -> ExtConfig.HUDPosition? {
        guard let raw = string(table, "hud", "position") else { return nil }
        guard let position = ExtConfig.HUDPosition(rawValue: raw.lowercased()) else {
            error("hud.position must be center, top or bottom (got \"\(raw)\")", locator.line(table: "hud", key: "position"))
            return nil
        }
        return position
    }

    /// A millisecond value: any number, rounded, clamped to `range` with a warning.
    private mutating func milliseconds(_ table: TOMLTable, _ tableName: String, _ key: String, range: ClosedRange<Int>) -> Int? {
        let line = locator.line(table: tableName, key: key)
        guard table[key] != nil else { return nil }
        guard let value = number(table[key]) else {
            error("\(tableName).\(key) must be a number of milliseconds", line)
            return nil
        }
        let rounded = value.rounded()
        let clamped = Int(min(max(rounded, Double(range.lowerBound)), Double(range.upperBound)))
        if Double(clamped) != rounded {
            warning("\(tableName).\(key) \(Self.format(value)) clamped to \(clamped)", line)
        }
        return clamped
    }

    private mutating func presets() -> [ExtConfig.PaddingPreset] {
        let missing = "at least one [[padding]] preset is required"
        guard let value = root["padding"] else {
            error(missing, nil)
            return []
        }
        guard let array = value.array else {
            error("padding must be an array of tables ([[padding]])", locator.line(table: "", key: "padding"))
            return []
        }
        if array.isEmpty {
            error(missing, locator.line(table: "", key: "padding"))
            return []
        }

        let locator = self.locator
        var presets: [ExtConfig.PaddingPreset] = []
        var seenNames: [String: String] = [:] // lower-cased → as written
        for (index, element) in array.enumerated() {
            let headerLine = locator.line(arrayTable: "padding", index: index)
            func line(_ key: String) -> Int? { locator.line(arrayTable: "padding", index: index, key: key) ?? headerLine }

            guard let table = element.table else {
                error("[[padding]] #\(index + 1) must be a table", headerLine)
                continue
            }

            // Name first, so later messages can use it.
            var label = "[[padding]] #\(index + 1)"
            var name: String?
            if let value = table["name"] {
                if let raw = value.string?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
                    name = raw
                    label = "padding \"\(raw)\""
                    if let previous = seenNames[raw.lowercased()] {
                        error("\(label): duplicate name (already used by \"\(previous)\")", line("name"))
                    } else {
                        seenNames[raw.lowercased()] = raw
                    }
                } else {
                    error("\(label): name must be a non-empty string", line("name"))
                }
            } else {
                error("\(label): name is required", headerLine)
            }

            warnUnknownKeys(in: table, known: Self.presetKeys, context: label) { line($0) }

            var edges: [String: Double] = [:]
            for edge in ["top", "bottom", "left", "right"] {
                guard let value = table[edge] else {
                    error("\(label): \(edge) is required", headerLine)
                    continue
                }
                guard let number = number(value), number >= 0 else {
                    error("\(label): \(edge) must be a number ≥ 0", line(edge))
                    continue
                }
                edges[edge] = number
            }

            var hotkey: Hotkey?
            if let value = table["hotkey"] {
                if let raw = value.string {
                    hotkey = parseHotkey(raw, label: "\(label) hotkey", line: line("hotkey"))
                } else {
                    error("\(label): hotkey must be a string like \"ctrl+opt+1\" or \"\"", line("hotkey"))
                }
            }

            if let name, let top = edges["top"], let bottom = edges["bottom"], let left = edges["left"], let right = edges["right"] {
                presets.append(.init(name: name, top: top, bottom: bottom, left: left, right: right, hotkey: hotkey))
            }
        }
        return presets
    }

    // MARK: Hotkeys

    private mutating func parseHotkey(_ raw: String, label: String, line: Int?) -> Hotkey? {
        do {
            guard let hotkey = try HotkeyParser.parse(raw) else { return nil }
            bindings.append(Binding(hotkey: hotkey, label: label, line: line))
            return hotkey
        } catch {
            self.error("\(label): \(error) in \"\(raw)\"", line)
            return nil
        }
    }

    /// The same chord bound twice within our config is an error (PDR §4.1).
    private mutating func checkDuplicateChords() {
        var first: [Hotkey: Binding] = [:]
        for binding in bindings {
            if let previous = first[binding.hotkey] {
                error("\(binding.hotkey) is bound twice (\(previous.label) and \(binding.label))", binding.line)
            } else {
                first[binding.hotkey] = binding
            }
        }
    }

    // MARK: Typed accessors

    private mutating func string(_ table: TOMLTable, _ tableName: String, _ key: String) -> String? {
        guard let value = table[key] else { return nil }
        guard let string = value.string else {
            error("\(tableName).\(key) must be a string", locator.line(table: tableName, key: key))
            return nil
        }
        return string
    }

    private mutating func bool(_ table: TOMLTable, _ tableName: String, _ key: String) -> Bool? {
        guard let value = table[key] else { return nil }
        guard let bool = value.bool else {
            error("\(tableName).\(key) must be true or false", locator.line(table: tableName, key: key))
            return nil
        }
        return bool
    }

    /// Integers and finite floats.
    private func number(_ value: TOMLValueConvertible?) -> Double? {
        guard let value else { return nil }
        if let int = value.int { return Double(int) }
        if let double = value.double, double.isFinite { return double }
        return nil
    }

    // MARK: Issues

    private mutating func warnUnknownKeys(in table: TOMLTable, known: Set<String>, context: String?, line: (String) -> Int?) {
        for key in table.keys.sorted() where !known.contains(key) {
            let location = context.map { " in \($0)" } ?? ""
            warning("unknown key \"\(key)\"\(location)", line(key))
        }
    }

    private mutating func error(_ message: String, _ line: Int?) {
        issues.append(ConfigIssue(.error, message, line: line))
    }

    private mutating func warning(_ message: String, _ line: Int?) {
        issues.append(ConfigIssue(.warning, message, line: line))
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
