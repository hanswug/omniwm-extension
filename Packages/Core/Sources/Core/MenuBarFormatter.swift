/// Everything the status item title shows (PDR §5.1).
public struct MenuBarModel: Sendable, Equatable {
    public var reachable: Bool
    public var workspaceNumber: Int?
    /// Custom display name; `nil` when the workspace has none.
    public var displayName: String?
    /// From `settings.toml`; shown even when OmniWM is unreachable.
    public var bordersEnabled: Bool?
    public var layout: WorkspaceLayout?
    /// Effective visible container count for the current display.
    public var containerCount: Int?
    public var focus: FocusIndicator

    public init(
        reachable: Bool, workspaceNumber: Int? = nil, displayName: String? = nil, bordersEnabled: Bool? = nil,
        layout: WorkspaceLayout? = nil, containerCount: Int? = nil, focus: FocusIndicator = .none
    ) {
        self.reachable = reachable
        self.workspaceNumber = workspaceNumber
        self.displayName = displayName
        self.bordersEnabled = bordersEnabled
        self.layout = layout
        self.containerCount = containerCount
        self.focus = focus
    }
}

public enum MenuBarPiece: Sendable, Equatable {
    case text(String)
    case symbol(String)
}

/// Turns the model into groups; the app joins groups with a secondary-colour `|`.
public enum MenuBarFormatter {
    public static func groups(_ model: MenuBarModel) -> [[MenuBarPiece]] {
        var groups: [[MenuBarPiece]] = []
        let borders = model.bordersEnabled.map { [MenuBarPiece.symbol($0 ? "square" : "square.dashed")] }

        guard model.reachable else {
            groups.append([.text("—")])
            if let borders { groups.append(borders) }
            return groups
        }

        groups.append([.text(workspaceLabel(number: model.workspaceNumber, displayName: model.displayName))])
        if let borders { groups.append(borders) }

        switch model.layout {
        case .niri:
            var text = "Niri"
            if let dots = containers(model.containerCount) { text += " \(dots)" }
            groups.append([.text(text)])
        case .dwindle:
            groups.append([.text("Dwindle")])
        case nil:
            break
        }

        switch model.focus {
        case .fullscreen: groups.append([.text("F")])
        case .fullContainer: groups.append([.text("FC")])
        case .none: break
        }
        return groups
    }

    /// `#`, or `# - displayName` when the workspace has one (PDR §5.1).
    public static func workspaceLabel(number: Int?, displayName: String?) -> String {
        let number = number.map(String.init) ?? "—"
        guard let name = displayName, !name.isEmpty else { return number }
        return "\(number) - \(name)"
    }

    /// `●●○○` for 1–4, `5/6` / `6/6` for 5–6; `nil` when unknown or out of range.
    public static func containers(_ count: Int?) -> String? {
        guard let count, count >= 1 else { return nil }
        if count <= 4 { return String(repeating: "●", count: count) + String(repeating: "○", count: 4 - count) }
        return "\(min(count, 6))/6"
    }

    /// IPC reports `displayName` = the raw name when no label is set; treat that as "no name".
    public static func customDisplayName(_ ref: OmniWMWorkspaceRef?, settings: OmniWMSettings?) -> String? {
        guard let ref else { return nil }
        // settings.toml is authoritative when it has the workspace.
        if let settings, let number = ref.number,
           let workspace = settings.workspaces.first(where: { $0.name == String(number) }) {
            return workspace.displayName
        }
        guard let name = ref.displayName, !name.isEmpty else { return nil }
        if name == ref.rawName || name == ref.number.map(String.init) { return nil }
        return name
    }
}
