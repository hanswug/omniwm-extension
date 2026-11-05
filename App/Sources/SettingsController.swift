import Core
import Foundation

/// Watches and parses OmniWM's `settings.toml` (PDR §3.2). Read-only here;
/// edits go through `SettingsEditor`. Parsing runs off the main thread.
@MainActor
final class SettingsController {
    private(set) var url: URL?
    /// Last successfully parsed settings; kept when a later read fails.
    private(set) var settings: OmniWMSettings?
    /// Problems from the latest read, for the menu.
    private(set) var issues: [String] = []

    private var watcher: FileWatcher?
    private var loadChain: Task<Void, Never>?

    /// Called on the main actor after every read.
    var onChange: (() -> Void)?

    /// Starts (or restarts) watching `url`. No-op if unchanged.
    func watch(_ url: URL) {
        guard url != self.url else { return }
        watcher?.stop()
        self.url = url
        settings = nil
        Log.settings.info("Watching OmniWM settings at \(url.path, privacy: .public)")

        let watcher = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        watcher.start()
        self.watcher = watcher
        reload()
    }

    func reload() {
        guard let url else { return }
        let previous = loadChain
        loadChain = Task { [weak self] in
            await previous?.value
            let result = await Task.detached { SettingsReader.load(from: url) }.value
            guard let self, url == self.url else { return }
            if let settings = result.settings { self.settings = settings }
            issues = result.issues
            for issue in issues { Log.settings.error("\(issue, privacy: .public)") }
            onChange?()
        }
    }
}
