import AppKit
import Core

/// Tracks which OmniWM is running (PDR §6.7): OmniWM Dev while it runs, otherwise the release.
@MainActor
final class OmniWMBuildMonitor {
    private(set) var build: OmniWMBuild
    var onChange: ((OmniWMBuild) -> Void)?
    private var observers: [NSObjectProtocol] = []

    init() {
        build = Self.current()
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        update()
    }

    private func update() {
        let next = Self.current()
        guard next != build else { return }
        build = next
        Log.app.info("Now talking to \(next.displayName, privacy: .public)")
        onChange?(next)
    }

    private static func current() -> OmniWMBuild {
        .running(bundleIdentifiers: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
