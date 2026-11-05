/// What the menu bar shows about the focused window (PDR §5.1, §6.8).
public enum FocusIndicator: Sendable, Equatable {
    case none
    /// `F`
    case fullscreen
    /// `FC`
    case fullContainer
}

/// Live OmniWM state assembled from subscription events and queries (PDR §3.2, §6.7). Pure.
public struct OmniWMState: Sendable, Equatable {
    public var workspaces: [OmniWMWorkspace] = []
    public var displays: [OmniWMDisplay] = []
    public var activeWorkspace: OmniWMWorkspaceRef?
    public var focusedWindow: OmniWMWindow?
    /// Effective `visibleContainerCount` for the current display (from settings.toml, incl. overrides),
    /// stamped by the app. With 1, every column is full width, so "full container" means nothing.
    public var visibleContainerCount: Int?

    /// Tolerance when comparing the focused window's width to the usable width.
    public static let widthTolerance = 2.0

    public init() {}

    public mutating func apply(_ message: OmniWMMessage) {
        switch message {
        case let .focusedWindow(window):
            // `focus` events lack `mode`/`columnIndex`; keep what we knew about the same window.
            if var window, let id = window.id, id == focusedWindow?.id {
                window.mode = window.mode ?? focusedWindow?.mode
                window.columnIndex = window.columnIndex ?? focusedWindow?.columnIndex
                focusedWindow = window
            } else {
                focusedWindow = window
            }
        case let .activeWorkspace(active):
            activeWorkspace = active.workspace
        case let .workspaces(list):
            workspaces = list
        case let .displays(list):
            displays = list
        case let .windows(list):
            // `windows-changed` lists every window; `query windows --focused` just the one.
            if let focused = list.first(where: { $0.isFocused == true }) {
                focusedWindow = focused
            } else if list.count > 1 || list.isEmpty {
                focusedWindow = nil
            }
        case .subscribed, .failure, .ignored:
            break
        }
    }

    // MARK: - Derived

    /// The workspace the user is on: the focused one, else the active one, else the first current one.
    public var currentWorkspace: OmniWMWorkspace? {
        workspaces.first { $0.isFocused == true }
            ?? workspaces.first { $0.id != nil && $0.id == activeWorkspace?.id }
            ?? workspaces.first { $0.isCurrent == true }
    }

    public var currentLayout: WorkspaceLayout? { currentWorkspace?.workspaceLayout }

    /// Number and display name for the menu bar, from the current workspace or the active-workspace event.
    public var currentWorkspaceRef: OmniWMWorkspaceRef? {
        if let workspace = currentWorkspace {
            return OmniWMWorkspaceRef(id: workspace.id, number: workspace.number, displayName: workspace.displayName, rawName: workspace.rawName)
        }
        return activeWorkspace
    }

    /// The display showing the current workspace (for overrides and full-container width).
    public var currentDisplay: OmniWMDisplay? {
        let id = focusedWindow?.display?.id ?? currentWorkspace?.display?.id
        return displays.first { $0.id != nil && $0.id == id } ?? displays.first { $0.isCurrent == true }
    }

    public var isFullscreen: Bool { focusedWindow?.isFullscreen == true }

    /// The focused tiled window's column fills the usable width on a Niri workspace with ≥ 2 columns,
    /// while the visible container count is ≥ 2 (PDR §6.8). Unknown count → not excluded.
    public var isFullContainer: Bool {
        if let count = visibleContainerCount, count < 2 { return false }
        guard let window = focusedWindow, window.isFullscreen != true, window.mode == "tiling",
              let width = window.frame?.width,
              let workspace = currentWorkspace, workspace.workspaceLayout == .niri,
              (workspace.columns?.count ?? 0) >= 2,
              window.workspace?.id == nil || window.workspace?.id == workspace.id,
              let usable = usableWidth(of: displays.first { $0.id != nil && $0.id == window.display?.id } ?? currentDisplay)
        else { return false }
        return width >= usable - Self.widthTolerance
    }

    public var focusIndicator: FocusIndicator {
        if isFullscreen { return .fullscreen }
        if isFullContainer { return .fullContainer }
        return .none
    }

    private func usableWidth(of display: OmniWMDisplay?) -> Double? {
        guard let display, let visible = display.visibleFrame else { return nil }
        return visible.width - (display.outerGapLeft ?? 0) - (display.outerGapRight ?? 0)
    }
}

/// Detects OmniWM's own toggles as state transitions (PDR §6.8). IPC has no command events.
public enum OmniWMToggles {
    /// HUDs for what changed between two states. Fires only for the *same* workspace / focused
    /// window, so workspace switches, focus changes, snapshots and reconnects stay silent.
    public static func transitions(from old: OmniWMState, to new: OmniWMState) -> [HUDMessage] {
        var messages: [HUDMessage] = []

        let oldWorkspace = old.currentWorkspace
        let newWorkspace = new.currentWorkspace
        let sameWorkspace = oldWorkspace?.id != nil && oldWorkspace?.id == newWorkspace?.id
        let layoutChanged = sameWorkspace
            && oldWorkspace?.workspaceLayout != nil && newWorkspace?.workspaceLayout != nil
            && oldWorkspace?.workspaceLayout != newWorkspace?.workspaceLayout
        if layoutChanged, let layout = newWorkspace?.workspaceLayout {
            messages.append(layout == .niri ? .layoutNiri : .layoutDwindle)
        }

        let sameWindow = old.focusedWindow?.id != nil && old.focusedWindow?.id == new.focusedWindow?.id
        guard sameWindow else { return messages }

        let fullscreenChanged = old.isFullscreen != new.isFullscreen
        if fullscreenChanged {
            messages.append(new.isFullscreen ? .fullscreenOn : .fullscreenOff)
        }

        // Full container: same window, same workspace & column count, no fullscreen or layout change in play.
        let sameColumns = (oldWorkspace?.columns?.count ?? 0) == (newWorkspace?.columns?.count ?? 0)
        // A visible-containers change re-lays out every column; that's not the full-span toggle.
        let sameCount = old.visibleContainerCount == new.visibleContainerCount
        if !fullscreenChanged, !layoutChanged, sameWorkspace, sameColumns, sameCount,
           !old.isFullscreen, !new.isFullscreen, old.isFullContainer != new.isFullContainer {
            messages.append(new.isFullContainer ? .fullContainerOn : .fullContainerOff)
        }
        return messages
    }
}

public extension HUDMessage {
    static let fullscreenOn = HUDMessage(symbol: "arrow.up.left.and.arrow.down.right", text: "Fullscreen on")
    static let fullscreenOff = HUDMessage(symbol: "arrow.down.right.and.arrow.up.left", text: "Fullscreen off")
    static let layoutNiri = HUDMessage(symbol: "rectangle.split.3x1", text: "Niri")
    static let layoutDwindle = HUDMessage(symbol: "rectangle.split.2x2", text: "Dwindle")
    static let fullContainerOn = HUDMessage(symbol: "rectangle.fill", text: "Full container on")
    static let fullContainerOff = HUDMessage(symbol: "rectangle.split.3x1", text: "Full container off")
    static let maskedByOverride = HUDMessage(symbol: "exclamationmark.triangle", text: "Set, but this display overrides it")
}
