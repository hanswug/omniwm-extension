import AppKit
import Core
import Observation
import SwiftUI

/// The confirmation HUD (PDR §5.3): never takes focus, never intercepts clicks,
/// appears on the screen with the cursor (also over full-screen apps), and a new
/// message replaces the current one immediately.
@MainActor
final class HUDController {
    private let panel = HUDPanel()
    private let model = HUDModel()
    /// Bumped on every show; stale hide timers and fade completions compare against it.
    private var generation = 0
    private var hideTask: Task<Void, Never>?

    init() {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: HUDLayout.size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: 18)

        let content = NSHostingView(rootView: HUDView(model: model))
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        panel.contentView = effect
    }

    func show(_ message: HUDMessage, position: ExtConfig.HUDPosition, durationMs: Int) {
        generation += 1
        let current = generation
        model.message = message
        place(position)

        hideTask?.cancel()
        if panel.isVisible {
            // Replace immediately: cut any running fade and stay fully opaque.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless() // shows without activating this app
            NSAnimationContext.runAnimationGroup { context in
                context.duration = HUDLayout.fadeIn
                panel.animator().alphaValue = 1
            }
        }

        let hold = Duration.milliseconds(Int(HUDLayout.fadeIn * 1000) + durationMs)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled, let self, current == generation else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = HUDLayout.fadeOut
                self.panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, current == self.generation else { return }
                    self.panel.orderOut(nil)
                }
            }
        }
    }

    private func place(_ position: ExtConfig.HUDPosition) {
        let screens = NSScreen.screens
        guard let index = HUDLayout.screenIndex(containing: NSEvent.mouseLocation, screens: screens.map(\.frame)) else { return }
        let screen = screens[index]
        let origin = HUDLayout.origin(position: position, frame: screen.frame, visibleFrame: screen.visibleFrame)
        panel.setFrame(NSRect(origin: origin, size: HUDLayout.size), display: false)
    }

    /// A stretchable rounded-rect mask, so the blur itself gets rounded corners.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Borderless, non-activating, click-through panel that can never become key or main.
private final class HUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: HUDLayout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
private final class HUDModel {
    var message = HUDMessage(symbol: "checkmark.circle", text: "")
}

private struct HUDView: View {
    let model: HUDModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: model.message.symbol)
                .font(.system(size: 64, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(height: 76)
            Text(model.message.text)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 14)
        }
        .foregroundStyle(.primary)
        .frame(width: HUDLayout.size.width, height: HUDLayout.size.height)
        .accessibilityElement(children: .combine)
    }
}
