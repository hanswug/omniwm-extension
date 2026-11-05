import CoreGraphics

/// One HUD: a large SF Symbol over one line of text (PDR §5.3).
public struct HUDMessage: Sendable, Equatable {
    public let symbol: String
    public let text: String

    public init(symbol: String, text: String) {
        self.symbol = symbol
        self.text = text
    }

    /// Messages for command results (PDR §5.3 table).
    public init(_ result: CommandResult) {
        switch result {
        case let .paddingSet(name):
            self.init(symbol: "rectangle.inset.filled", text: name)
        case let .containersSet(count):
            self.init(symbol: "rectangle.split.3x1", text: count == 1 ? "1 container" : "\(count) containers")
        case let .bordersSet(enabled):
            self.init(symbol: enabled ? "square" : "square.dashed", text: enabled ? "Borders on" : "Borders off")
        case .skippedDwindle:
            self.init(symbol: "exclamationmark.triangle", text: "Dwindle — skipped")
        }
    }

    /// Padding auto-applied because only the built-in display is left (PDR §6.5).
    public static func builtIn(_ name: String) -> HUDMessage {
        HUDMessage(symbol: "laptopcomputer", text: "\(name) · built-in")
    }

    /// Padding restored because an external display came back (PDR §6.5).
    public static func restored(_ name: String) -> HUDMessage {
        HUDMessage(symbol: "display", text: "\(name) · restored")
    }

    public static let writeFailure = HUDMessage(symbol: "xmark.octagon", text: "Couldn't write OmniWM settings")
    public static let configReloaded = HUDMessage(symbol: "checkmark.circle", text: "Config reloaded")
    public static let configErrorKeptPrevious = HUDMessage(symbol: "xmark.octagon", text: "Config error — kept previous")
    public static let configErrorUsingDefaults = HUDMessage(symbol: "xmark.octagon", text: "Config error — using defaults")

    /// The HUD for a config load, if any. The first successful load at launch is silent.
    public static func forConfig(_ outcome: ConfigStore.Outcome) -> HUDMessage? {
        switch outcome {
        case .loaded, .unchanged: nil
        case .reloaded: .configReloaded
        case .keptPrevious: .configErrorKeptPrevious
        case .usingDefaults: .configErrorUsingDefaults
        }
    }
}

/// Where the HUD goes (PDR §5.3). Pure geometry in AppKit's bottom-left coordinate space.
public enum HUDLayout {
    public static let size = CGSize(width: 200, height: 200)
    /// Gap below the menu bar for `top`.
    public static let topMargin: CGFloat = 12
    /// Distance above the screen's bottom edge for `bottom`.
    public static let bottomOffset: CGFloat = 140
    public static let fadeIn = 0.12
    public static let fadeOut = 0.25

    /// The screen whose frame contains `point` (the mouse); falls back to the first screen.
    /// - Returns: an index into `screens`, or `nil` if there are none.
    public static func screenIndex(containing point: CGPoint, screens: [CGRect]) -> Int? {
        if let index = screens.firstIndex(where: { contains($0, point) }) { return index }
        return screens.isEmpty ? nil : 0
    }

    /// Origin of the HUD on a screen.
    /// - Parameters:
    ///   - frame: the screen's full frame.
    ///   - visibleFrame: the frame minus menu bar and Dock.
    public static func origin(
        position: ExtConfig.HUDPosition, frame: CGRect, visibleFrame: CGRect, size: CGSize = size
    ) -> CGPoint {
        let x = (frame.midX - size.width / 2).rounded()
        let y: CGFloat
        switch position {
        case .center: y = frame.midY - size.height / 2
        case .top: y = visibleFrame.maxY - topMargin - size.height
        case .bottom: y = frame.minY + bottomOffset
        }
        return CGPoint(x: x, y: y.rounded())
    }

    /// `CGRect.contains` excludes the max edges; the mouse can sit exactly on a screen's top/right edge.
    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
