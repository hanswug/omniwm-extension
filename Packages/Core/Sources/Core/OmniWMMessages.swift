import Foundation

// Models and parser for `omniwmctl` output (PDR §6.7), written against the captured
// fixtures in Tests/CoreTests/Fixtures/omniwm/. Every field is optional on the wire;
// unknown fields are ignored.

public struct OmniWMRect: Sendable, Equatable, Decodable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        (self.x, self.y, self.width, self.height) = (x, y, width, height)
    }
}

/// `{id, number, displayName, rawName}` as embedded in other objects.
public struct OmniWMWorkspaceRef: Sendable, Equatable, Decodable {
    public var id: String?
    public var number: Int?
    public var displayName: String?
    public var rawName: String?
}

/// `{id, name, isMain}` as embedded in other objects. `id` looks like `display:2`.
public struct OmniWMDisplayRef: Sendable, Equatable, Decodable {
    public var id: String?
    public var name: String?
    public var isMain: Bool?
}

public struct OmniWMColumn: Sendable, Equatable, Decodable {
    public var index: Int?
    /// `intersecting`, `after`, `before`, …
    public var viewport: String?
}

/// A workspace from `layout-changed` / `query workspaces`.
public struct OmniWMWorkspace: Sendable, Equatable, Decodable {
    public var id: String?
    public var number: Int?
    public var displayName: String?
    public var rawName: String?
    /// `niri` / `dwindle`
    public var layout: String?
    public var isCurrent: Bool?
    public var isFocused: Bool?
    public var isVisible: Bool?
    /// Niri only; absent for Dwindle.
    public var columns: [OmniWMColumn]?
    public var focusedWindowId: String?
    public var display: OmniWMDisplayRef?

    public var workspaceLayout: WorkspaceLayout? { layout.flatMap { WorkspaceLayout(rawValue: $0.lowercased()) } }
}

/// A display from `display-changed` / `query displays`.
public struct OmniWMDisplay: Sendable, Equatable, Decodable {
    public var id: String?
    public var name: String?
    public var isMain: Bool?
    public var isCurrent: Bool?
    public var frame: OmniWMRect?
    public var visibleFrame: OmniWMRect?
    public var outerGapLeft: Double?
    public var outerGapRight: Double?
    public var outerGapTop: Double?
    public var outerGapBottom: Double?
    public var activeWorkspace: OmniWMWorkspaceRef?
}

/// A window from `focus` / `windows-changed` / `query windows`.
public struct OmniWMWindow: Sendable, Equatable, Decodable {
    public var id: String?
    public var isFocused: Bool?
    public var isFullscreen: Bool?
    /// `tiling` / `floating`. Absent in `focus` events.
    public var mode: String?
    public var columnIndex: Int?
    public var frame: OmniWMRect?
    public var workspace: OmniWMWorkspaceRef?
    public var display: OmniWMDisplayRef?
}

/// `active-workspace` payload.
public struct OmniWMActiveWorkspace: Sendable, Equatable, Decodable {
    public var workspace: OmniWMWorkspaceRef?
    public var display: OmniWMDisplayRef?
}

/// One decoded line or query response.
public enum OmniWMMessage: Sendable, Equatable {
    /// `subscribe` acknowledged.
    case subscribed
    /// `focus` / `query focused-window`. `nil` when nothing is focused (payload `{}`).
    case focusedWindow(OmniWMWindow?)
    case activeWorkspace(OmniWMActiveWorkspace)
    case workspaces([OmniWMWorkspace])
    case displays([OmniWMDisplay])
    case windows([OmniWMWindow])
    /// `ok: false` (e.g. `transport_failure`): OmniWM isn't reachable.
    case failure(code: String?, message: String?)
    /// A channel or result kind we don't use; ignore it.
    case ignored(String)
}

public enum OmniWMParseError: Error, Sendable, Equatable, CustomStringConvertible {
    case malformed(String)

    public var description: String {
        switch self {
        case let .malformed(detail): "malformed omniwmctl output: \(detail)"
        }
    }
}

public enum OmniWMParser {
    /// Parses one NDJSON line. Blank lines → `nil`.
    public static func parseLine(_ line: some StringProtocol) throws(OmniWMParseError) -> OmniWMMessage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return try parse(Data(trimmed.utf8))
    }

    /// Parses one JSON document (a subscription line or a `query --format json` response).
    public static func parse(_ data: Data) throws(OmniWMParseError) -> OmniWMMessage {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            let preview = String(decoding: data.prefix(80), as: UTF8.self)
            throw .malformed(preview)
        }
        if envelope.ok == false || envelope.status == "error" {
            return .failure(code: envelope.code, message: envelope.message)
        }
        if envelope.kind == "subscribe" { return .subscribed }
        guard let result = envelope.result, let kind = result.kind else {
            return .ignored(envelope.channel ?? envelope.kind ?? "?")
        }
        let payload = result.payload
        switch kind {
        case "focused-window": return .focusedWindow(payload?.window)
        case "active-workspace": return .activeWorkspace(OmniWMActiveWorkspace(workspace: payload?.workspace, display: payload?.display))
        case "workspaces": return .workspaces(payload?.workspaces ?? [])
        case "displays": return .displays(payload?.displays ?? [])
        case "windows": return .windows(payload?.windows ?? [])
        default: return .ignored(envelope.channel.map { "\($0)/\(kind)" } ?? kind)
        }
    }

    private struct Envelope: Decodable {
        var channel: String?
        var kind: String?
        var ok: Bool?
        var status: String?
        var code: String?
        var message: String?
        var result: Result?
    }

    private struct Result: Decodable {
        var kind: String?
        var payload: Payload?
    }

    /// Union of the payload shapes we use; each kind fills its own field.
    private struct Payload: Decodable {
        var window: OmniWMWindow?
        var workspace: OmniWMWorkspaceRef?
        var display: OmniWMDisplayRef?
        var workspaces: [OmniWMWorkspace]?
        var displays: [OmniWMDisplay]?
        var windows: [OmniWMWindow]?

        // A payload of an unexpected shape (e.g. `window` being a string) must not sink the
        // whole line: decode field by field and drop what doesn't fit.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            window = try? container.decodeIfPresent(OmniWMWindow.self, forKey: .window)
            workspace = try? container.decodeIfPresent(OmniWMWorkspaceRef.self, forKey: .workspace)
            display = try? container.decodeIfPresent(OmniWMDisplayRef.self, forKey: .display)
            workspaces = try? container.decodeIfPresent(LossyArray<OmniWMWorkspace>.self, forKey: .workspaces)?.elements
            displays = try? container.decodeIfPresent(LossyArray<OmniWMDisplay>.self, forKey: .displays)?.elements
            windows = try? container.decodeIfPresent(LossyArray<OmniWMWindow>.self, forKey: .windows)?.elements
        }

        enum CodingKeys: String, CodingKey {
            case window, workspace, display, workspaces, displays, windows
        }
    }
}

/// Decodes an array element by element, dropping elements that don't fit,
/// so one odd window can't blank the whole list.
private struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element] = []

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(Skip.self) // advance past the bad element
            }
        }
    }

    private struct Skip: Decodable {}
}
