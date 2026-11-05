import Testing
@testable import Core

@Suite struct MenuBarFormatterTests {
    private func render(_ model: MenuBarModel) -> String {
        MenuBarFormatter.groups(model).map { group in
            group.map { piece in
                switch piece {
                case let .text(text): text
                case let .symbol(name): "<\(name)>"
                }
            }.joined()
        }.joined(separator: " | ")
    }

    @Test func fullNiriLabel() {
        let model = MenuBarModel(reachable: true, workspaceNumber: 1, displayName: "Code", bordersEnabled: true, layout: .niri, containerCount: 3)
        #expect(render(model) == "1 - Code | <square> | <rectangle.split.3x1> ●●●○")
    }

    @Test func noDisplayName() {
        #expect(render(MenuBarModel(reachable: true, workspaceNumber: 2, bordersEnabled: false, layout: .niri, containerCount: 2))
            == "2 | <square.dashed> | <rectangle.split.3x1> ●●○○")
    }

    @Test(arguments: [(1, "●○○○"), (2, "●●○○"), (3, "●●●○"), (4, "●●●●"), (5, "5/6"), (6, "6/6")])
    func niriCounts(_ count: Int, _ dots: String) {
        #expect(render(MenuBarModel(reachable: true, workspaceNumber: 1, layout: .niri, containerCount: count)) == "1 | <rectangle.split.3x1> \(dots)")
    }

    @Test func unknownCountShowsJustNiri() {
        #expect(render(MenuBarModel(reachable: true, workspaceNumber: 1, layout: .niri)) == "1 | <rectangle.split.3x1>")
    }

    @Test func dwindleHidesDots() {
        #expect(render(MenuBarModel(reachable: true, workspaceNumber: 3, bordersEnabled: true, layout: .dwindle, containerCount: 3))
            == "3 | <square> | <rectangle.split.2x2>")
    }

    @Test func unreachableKeepsBorders() {
        #expect(render(MenuBarModel(reachable: false, workspaceNumber: 1, bordersEnabled: true, layout: .niri, containerCount: 2, focus: .fullscreen))
            == "— | <square>")
        #expect(render(MenuBarModel(reachable: false)) == "—")
    }

    @Test func focusIndicators() {
        let base = MenuBarModel(reachable: true, workspaceNumber: 1, bordersEnabled: true, layout: .niri, containerCount: 2)
        var fullscreen = base
        fullscreen.focus = .fullscreen
        #expect(render(fullscreen) == "1 | <square> | <rectangle.split.3x1> ●●○○ | F")
        var full = base
        full.focus = .fullContainer
        #expect(render(full) == "1 | <square> | <rectangle.split.3x1> ●●○○ | FC")
        var dwindleFullscreen = base
        dwindleFullscreen.layout = .dwindle
        dwindleFullscreen.focus = .fullscreen
        #expect(render(dwindleFullscreen) == "1 | <square> | <rectangle.split.2x2> | F")
    }

    @Test func spokenDescription() {
        let niri = MenuBarModel(reachable: true, workspaceNumber: 1, displayName: "Code", bordersEnabled: true, layout: .niri, containerCount: 2, focus: .fullContainer)
        #expect(MenuBarFormatter.spokenDescription(niri) == "1 - Code, borders on, Niri ●●○○, FC")
        let dwindle = MenuBarModel(reachable: true, workspaceNumber: 3, bordersEnabled: false, layout: .dwindle)
        #expect(MenuBarFormatter.spokenDescription(dwindle) == "3, borders off, Dwindle")
    }

    @Test func customDisplayNameDetection() {
        // IPC reports displayName == rawName when no label is set.
        let plain = OmniWMWorkspaceRef(id: "a", number: 1, displayName: "1", rawName: "1")
        #expect(MenuBarFormatter.customDisplayName(plain, settings: nil) == nil)
        let named = OmniWMWorkspaceRef(id: "a", number: 1, displayName: "Code", rawName: "1")
        #expect(MenuBarFormatter.customDisplayName(named, settings: nil) == "Code")
        // settings.toml wins when it knows the workspace.
        var settings = OmniWMSettings()
        settings.workspaces = [.init(name: "1", displayName: "Mail")]
        #expect(MenuBarFormatter.customDisplayName(plain, settings: settings) == "Mail")
        settings.workspaces = [.init(name: "1", displayName: nil)]
        #expect(MenuBarFormatter.customDisplayName(named, settings: settings) == nil)
    }
}

@Suite struct BackoffTests {
    @Test func sequenceCapsAtTenSeconds() {
        var backoff = Backoff()
        let delays = (0..<6).map { _ in backoff.next() }
        #expect(delays == [.seconds(1), .seconds(2), .seconds(5), .seconds(10), .seconds(10), .seconds(10)])
    }

    @Test func resetStartsOver() {
        var backoff = Backoff()
        _ = backoff.next()
        _ = backoff.next()
        backoff.reset()
        #expect(backoff.next() == .seconds(1))
    }
}

@Suite struct DisplayOverridesTests {
    let display = DisplayIdentity(uuid: "AAAA-BBBB", id: "2", name: "Odyssey Ark")

    @Test func numericIDFromIPC() {
        #expect(DisplayIdentity.numericID(fromIPC: "display:2") == "2")
        #expect(DisplayIdentity.numericID(fromIPC: "7") == "7")
        #expect(DisplayIdentity.numericID(fromIPC: nil) == nil)
    }

    @Test func matchesByUUIDFirst() {
        #expect(DisplayOverrides.matches(.init(displayUUID: "aaaa-bbbb", displayId: "9", name: "Other"), display))
        #expect(!DisplayOverrides.matches(.init(displayUUID: "CCCC", displayId: "2", name: "Odyssey Ark"), display))
    }

    @Test func fallsBackToIdAndName() {
        #expect(DisplayOverrides.matches(.init(displayUUID: nil, displayId: "2", name: "Odyssey Ark"), display))
        #expect(!DisplayOverrides.matches(.init(displayUUID: nil, displayId: "2", name: "LG"), display))
        #expect(!DisplayOverrides.matches(.init(displayUUID: nil, displayId: "3", name: "Odyssey Ark"), display))
        #expect(DisplayOverrides.matches(.init(displayUUID: nil, displayId: "2", name: nil), display))
        #expect(!DisplayOverrides.matches(.init(displayUUID: nil, displayId: nil, name: "Odyssey Ark"), display))
    }

    @Test func effectiveContainerCount() {
        var settings = OmniWMSettings()
        settings.visibleContainerCount = 2
        #expect(DisplayOverrides.effectiveContainerCount(settings, on: display) == 2)
        settings.monitorNiriOverrides = [
            .init(monitor: .init(displayUUID: nil, displayId: "2", name: "Odyssey Ark"), visibleContainerCount: nil),
            .init(monitor: .init(displayUUID: "AAAA-BBBB", displayId: nil, name: nil), visibleContainerCount: 4),
        ]
        #expect(DisplayOverrides.effectiveContainerCount(settings, on: display) == 4)
        #expect(DisplayOverrides.effectiveContainerCount(settings, on: DisplayIdentity(uuid: "X", id: "5", name: "LG")) == 2)
        #expect(DisplayOverrides.effectiveContainerCount(nil, on: display) == nil)
    }

    @Test func gapOverrides() {
        var settings = OmniWMSettings()
        #expect(!DisplayOverrides.overridesGaps(settings, on: display))
        settings.monitorGapOverrides = [.init(displayUUID: nil, displayId: "2", name: "Odyssey Ark")]
        #expect(DisplayOverrides.overridesGaps(settings, on: display))
    }
}
