import Core
import Foundation

/// Live OmniWM state via `omniwmctl subscribe` (PDR §6.7, §6.8).
///
/// - Events update a working state and trigger a debounced `query windows --focused`,
///   which is authoritative for the focused window (events can carry stale frames, and
///   leaving OmniWM fullscreen emits no event at all).
/// - Toggle HUDs are computed only between *settled* states (after that query).
/// - While the focused window is fullscreen, it re-queries every 0.5 s to catch the exit.
/// - Child exit → unreachable, restart with backoff 1/2/5/10 s. stderr `connection lost` /
///   `reconnect failed` → unreachable; `reconnected` → re-sync.
@MainActor
final class OmniWMBridge {
    private(set) var reachable = false
    /// The state as of the last settle; what the UI shows.
    private(set) var state = OmniWMState()

    /// UI should refresh (reachability or state changed).
    var onChange: (() -> Void)?
    /// OmniWM toggles detected between settled states.
    var onToggles: (([HUDMessage]) -> Void)?
    /// Effective visible container count for the current display; stamped on every settled state.
    var containerCountProvider: (() -> Int?)?

    private let homeDirectory: URL
    private var working = OmniWMState()
    private var process: LineStreamProcess?
    private var ctl: URL?
    private var backoff = Backoff()
    private var restartTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshQueued = false
    private var pollTask: Task<Void, Never>?
    private var stopped = false
    /// No toggle HUDs until the first settle after (re)connecting.
    private var baselineSettled = false

    private static let channels = "active-workspace,layout-changed,display-changed,focus,windows-changed"
    private static let refreshDebounce: Duration = .milliseconds(40)
    /// OmniWM doesn't emit an event for every toggle (never for leaving fullscreen, sometimes not
    /// for others), so the focused window is also polled: fast while F/FC is shown, slower otherwise.
    private static let activePoll: Duration = .milliseconds(500)
    private static let idlePoll: Duration = .milliseconds(1500)

    init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
    }

    func start() {
        stopped = false
        spawn()
    }

    /// Kills the child (PDR §5.2: Quit kills it too).
    func stop() {
        stopped = true
        restartTask?.cancel()
        refreshTask?.cancel()
        pollTask?.cancel()
        process?.terminate()
        process = nil
    }

    /// Re-query and re-settle now (e.g. settings.toml changed the container count).
    func refresh() {
        guard reachable else { return }
        scheduleRefresh(after: .zero)
    }

    // MARK: - Process lifecycle

    private func spawn() {
        guard !stopped, process == nil else { return }
        let home = homeDirectory
        Task { [weak self] in
            let located = await Task.detached {
                OmniWMCtl.locate(homeDirectory: home, environment: ProcessInfo.processInfo.environment)
            }.value
            guard let self, !stopped, process == nil else { return }
            guard let located else {
                Log.bridge.error("omniwmctl not found")
                markUnreachable()
                scheduleRestart()
                return
            }
            ctl = located
            let child = LineStreamProcess(
                executable: located,
                arguments: ["subscribe", Self.channels, "--reconnect", "--format", "ndjson"],
                onStdoutLine: { [weak self] line in
                    // Parse off the main thread; apply on it.
                    let parsed = Result { try OmniWMParser.parseLine(line) }
                    Task { @MainActor in self?.handle(parsed, raw: line) }
                },
                onStderrLine: { [weak self] line in
                    Task { @MainActor in self?.handleStderr(line) }
                },
                onExit: { [weak self] status in
                    Task { @MainActor in self?.childExited(status) }
                }
            )
            do {
                try child.start()
                process = child
                Log.bridge.info("Started \(located.path, privacy: .public) subscribe (pid \(child.processIdentifier))")
            } catch {
                Log.bridge.error("Couldn't start omniwmctl: \(error.localizedDescription, privacy: .public)")
                markUnreachable()
                scheduleRestart()
            }
        }
    }

    private func childExited(_ status: Int32) {
        process = nil
        guard !stopped else { return }
        Log.bridge.notice("omniwmctl subscribe exited (\(status))")
        markUnreachable()
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard !stopped else { return }
        let delay = backoff.next()
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.spawn()
        }
    }

    // MARK: - Input

    private func handle(_ parsed: Result<OmniWMMessage?, any Error>, raw: String) {
        let message: OmniWMMessage
        switch parsed {
        case let .success(value?): message = value
        case .success(nil): return
        case let .failure(error):
            Log.bridge.error("Skipped line: \(String(describing: error), privacy: .public)")
            return
        }
        switch message {
        case .subscribed:
            Log.bridge.info("Subscribed")
            backoff.reset()
            setReachable(true)
        case let .failure(code, text):
            Log.bridge.notice("OmniWM not reachable: \(code ?? "?", privacy: .public) \(text ?? "", privacy: .public)")
            markUnreachable()
        case let .ignored(what):
            Log.bridge.debug("Ignored \(what, privacy: .public)")
        default:
            working.apply(message)
            scheduleRefresh()
        }
    }

    private func handleStderr(_ line: String) {
        if line.contains("connection lost") || line.contains("reconnect failed") {
            Log.bridge.notice("\(line, privacy: .public)")
            markUnreachable()
        } else if line.contains("reconnected") {
            Log.bridge.info("\(line, privacy: .public)")
            backoff.reset()
            setReachable(true)
            resync()
        } else if !line.isEmpty {
            Log.bridge.debug("omniwmctl: \(line, privacy: .public)")
        }
    }

    private func setReachable(_ value: Bool) {
        guard reachable != value else { return }
        reachable = value
        onChange?()
    }

    private func markUnreachable() {
        working = OmniWMState()
        state = OmniWMState()
        baselineSettled = false
        pollTask?.cancel()
        setReachable(false)
        onChange?()
    }

    /// After a reconnect, rebuild everything from queries (snapshots may not be re-sent).
    private func resync() {
        guard let ctl else { return }
        working = OmniWMState()
        baselineSettled = false
        Task { [weak self] in
            for query in [["query", "workspaces"], ["query", "displays"]] {
                if let message = await Self.runQuery(ctl, query) { self?.working.apply(message) }
            }
            self?.scheduleRefresh()
        }
    }

    // MARK: - Refresh & settle

    /// Debounced `query windows --focused`, then settle. One in flight; extra requests queue one rerun.
    private func scheduleRefresh(after delay: Duration = refreshDebounce) {
        if refreshTask != nil {
            refreshQueued = true
            return
        }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            if let ctl, let message = await Self.runQuery(ctl, ["query", "windows", "--focused"]) {
                working.apply(message)
            }
            settle()
            refreshTask = nil
            if refreshQueued {
                refreshQueued = false
                scheduleRefresh()
            }
        }
    }

    private func settle() {
        let previous = state
        working.visibleContainerCount = containerCountProvider?()
        state = working
        let s = state
        Log.bridge.debug("Settled: ws=\(s.currentWorkspace?.number ?? -1) layout=\(s.currentLayout?.rawValue ?? "?", privacy: .public) focused=\(s.focusedWindow?.id.map { String($0.suffix(8)) } ?? "nil", privacy: .public) fs=\(s.isFullscreen) fc=\(s.isFullContainer) width=\(s.focusedWindow?.frame?.width ?? -1) mode=\(s.focusedWindow?.mode ?? "?", privacy: .public) cols=\(s.currentWorkspace?.columns?.count ?? -1)")
        if baselineSettled {
            let toggles = OmniWMToggles.transitions(from: previous, to: state)
            if !toggles.isEmpty {
                Log.bridge.info("Toggles: \(toggles.map(\.text).joined(separator: ", "), privacy: .public)")
                onToggles?(toggles)
            }
        }
        baselineSettled = true
        if previous != state { onChange?() }

        // Fallback poll (see `activePoll`); the next settle reschedules it.
        pollTask?.cancel()
        let interval = state.focusIndicator == .none ? Self.idlePoll : Self.activePoll
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let self, reachable else { return }
            scheduleRefresh(after: .zero)
        }
    }

    private nonisolated static func runQuery(_ ctl: URL, _ arguments: [String]) async -> OmniWMMessage? {
        let output = await OmniWMCtl.run(ctl, arguments + ["--format", "json"])
        guard output.succeeded else { return nil }
        return try? OmniWMParser.parse(Data(output.stdout.utf8))
    }
}
