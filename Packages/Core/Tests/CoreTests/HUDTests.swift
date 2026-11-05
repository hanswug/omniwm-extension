import CoreGraphics
import Testing
@testable import Core

@Suite struct HUDMessageTests {
    @Test(arguments: [
        (CommandResult.paddingSet(name: "Wide"), "rectangle.inset.filled", "Wide"),
        (.containersSet(3), "rectangle.split.3x1", "3 containers"),
        (.containersSet(1), "rectangle.split.3x1", "1 container"),
        (.bordersSet(enabled: true), "square", "Borders on"),
        (.bordersSet(enabled: false), "square.dashed", "Borders off"),
        (.skippedDwindle, "exclamationmark.triangle", "Dwindle — skipped"),
    ])
    func commandMessages(_ result: CommandResult, _ symbol: String, _ text: String) {
        #expect(HUDMessage(result) == HUDMessage(symbol: symbol, text: text))
    }

    @Test func fixedMessagesMatchPDR() {
        #expect(HUDMessage.writeFailure == .init(symbol: "xmark.octagon", text: "Couldn't write OmniWM settings"))
        #expect(HUDMessage.configReloaded == .init(symbol: "checkmark.circle", text: "Config reloaded"))
        #expect(HUDMessage.configErrorKeptPrevious == .init(symbol: "xmark.octagon", text: "Config error — kept previous"))
    }

    @Test func displayMessagesMatchPDR() {
        #expect(HUDMessage.builtIn("Fullscreen") == .init(symbol: "laptopcomputer", text: "Fullscreen · built-in"))
        #expect(HUDMessage.restored("Wide") == .init(symbol: "display", text: "Wide · restored"))
        #expect(HUDMessage.restored("Custom") == .init(symbol: "display", text: "Custom · restored"))
    }

    @Test func configOutcomes() {
        #expect(HUDMessage.forConfig(.loaded) == nil)       // launch is silent
        #expect(HUDMessage.forConfig(.unchanged) == nil)
        #expect(HUDMessage.forConfig(.reloaded) == .configReloaded)
        #expect(HUDMessage.forConfig(.keptPrevious) == .configErrorKeptPrevious)
        #expect(HUDMessage.forConfig(.usingDefaults) == .configErrorUsingDefaults)
    }
}

@Suite struct HUDLayoutTests {
    // Built-in 1512×982 with a 37 pt menu bar, external 2560×1440 to its right.
    let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let builtInVisible = CGRect(x: 0, y: 0, width: 1512, height: 945)
    let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

    @Test func picksScreenWithCursor() {
        #expect(HUDLayout.screenIndex(containing: CGPoint(x: 100, y: 100), screens: [builtIn, external]) == 0)
        #expect(HUDLayout.screenIndex(containing: CGPoint(x: 2000, y: 1200), screens: [builtIn, external]) == 1)
    }

    @Test func edgesCountAsInside() {
        // Top edge of the built-in screen (mouse pinned at the very top).
        #expect(HUDLayout.screenIndex(containing: CGPoint(x: 10, y: 982), screens: [external, builtIn]) == 1)
    }

    @Test func fallsBackToFirstScreen() {
        #expect(HUDLayout.screenIndex(containing: CGPoint(x: -500, y: -500), screens: [builtIn, external]) == 0)
        #expect(HUDLayout.screenIndex(containing: .zero, screens: []) == nil)
    }

    @Test func centerPosition() {
        let origin = HUDLayout.origin(position: .center, frame: builtIn, visibleFrame: builtInVisible)
        #expect(origin == CGPoint(x: 656, y: 391))
    }

    @Test func topIsJustBelowMenuBar() {
        let origin = HUDLayout.origin(position: .top, frame: builtIn, visibleFrame: builtInVisible)
        #expect(origin == CGPoint(x: 656, y: 945 - 12 - 200))
    }

    @Test func bottomIs140AboveBottomEdge() {
        let origin = HUDLayout.origin(position: .bottom, frame: builtIn, visibleFrame: builtInVisible)
        #expect(origin == CGPoint(x: 656, y: 140))
    }

    @Test func secondaryScreenOffsetsAreRespected() {
        let origin = HUDLayout.origin(position: .center, frame: external, visibleFrame: external)
        #expect(origin == CGPoint(x: 1512 + 1280 - 100, y: 620))
    }
}
