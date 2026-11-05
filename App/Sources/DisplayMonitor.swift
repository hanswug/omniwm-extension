import AppKit
import Core

/// Reports the display topology (built-in only vs. docked) on screen changes, debounced 1 s (PDR §6.5).
@MainActor
final class DisplayMonitor {
    private static let debounce: Duration = .seconds(1)

    /// Called with the topology after changes settle. Callers compare with what they recorded.
    var onChange: ((DisplayTopology) -> Void)?

    private var observer: (any NSObjectProtocol)?
    private var pending: Task<Void, Never>?

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    /// `nil` when no display is active (transient during sleep/wake).
    static func currentTopology() -> DisplayTopology? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        return DisplayTopology.classify(builtIn: ids.prefix(Int(count)).map { CGDisplayIsBuiltin($0) != 0 })
    }

    private func screensChanged() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            guard let topology = Self.currentTopology() else {
                Log.display.info("Screens changed: no active display; ignored")
                return
            }
            Log.display.info("Screens changed → \(topology.rawValue, privacy: .public)")
            onChange?(topology)
        }
    }
}
