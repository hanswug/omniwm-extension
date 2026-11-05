import Core
import Foundation

/// Loads `config.toml`, watches it and keeps the last good config (PDR §4, §4.2).
/// File I/O runs off the main thread; state lives on the main actor.
@MainActor
final class ConfigController {
    let url: URL
    private(set) var store = ConfigStore()
    /// Set when the default file couldn't be written on launch.
    private var bootstrapIssue: ConfigIssue?
    private var watcher: FileWatcher?
    /// Reloads run one after another, in order.
    private var reloadChain: Task<Void, Never>?

    /// Called on the main actor after every applied change (not for `.unchanged`).
    var onChange: ((ConfigStore.Outcome) -> Void)?

    init(url: URL) {
        self.url = url
    }

    var config: ExtConfig { store.config }

    /// Rows for the menu's warning section.
    var issues: [ConfigIssue] { (bootstrapIssue.map { [$0] } ?? []) + store.issues }

    /// First launch: write the default if missing, load it, then watch for saves.
    func start() {
        let url = url
        enqueue { controller in
            do {
                if try await Task.detached(operation: { try ConfigFile.writeDefaultIfMissing(at: url) }).value {
                    Log.config.info("Wrote default config to \(url.path, privacy: .public)")
                }
                controller.bootstrapIssue = nil
            } catch {
                Log.config.error("\(String(describing: error), privacy: .public)")
                controller.bootstrapIssue = ConfigIssue(.error, String(describing: error))
            }
            await controller.load(force: true)

            let watcher = FileWatcher(url: url) { [weak controller] in
                Task { @MainActor in controller?.reload() }
            }
            watcher.start()
            controller.watcher = watcher
        }
    }

    /// Re-reads the file. `force` re-applies identical content ("Reload config").
    func reload(force: Bool = false) {
        enqueue { controller in await controller.load(force: force) }
    }

    /// Ensures the file exists (writing the default if missing or blank), for "Edit config file".
    func ensureFileExists() async throws {
        let url = url
        if try await Task.detached(operation: { try ConfigFile.writeDefaultIfMissing(at: url) }).value {
            Log.config.info("Wrote default config to \(url.path, privacy: .public)")
            bootstrapIssue = nil
        }
    }

    // MARK: - Private

    private func enqueue(_ work: @escaping @MainActor (ConfigController) async -> Void) {
        let previous = reloadChain
        reloadChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
        }
    }

    private func load(force: Bool) async {
        let url = url
        let load = await Task.detached { ConfigFile.load(from: url) }.value
        let outcome = store.apply(load, force: force)

        switch outcome {
        case .unchanged:
            return
        case .loaded:
            Log.config.info("Config loaded")
        case .reloaded:
            Log.config.info("Config reloaded")
        case .keptPrevious:
            Log.config.error("Config error — kept previous")
        case .usingDefaults:
            Log.config.error("Config error — running built-in defaults")
        }
        for issue in store.issues {
            if issue.severity == .error {
                Log.config.error("\(issue.description, privacy: .public)")
            } else {
                Log.config.notice("\(issue.description, privacy: .public)")
            }
        }
        onChange?(outcome)
    }
}
