import Core
import Foundation

/// Wires config, OmniWM settings and hotkeys together; owns the menu's warnings.
@MainActor
final class AppController {
    let paths: AppPaths
    let config: ConfigController
    let settings = SettingsController()
    private let hotkeys = HotkeyManager()
    private let hud = HUDController()
    private var plan: HotkeyPlan?
    private var hyperIssue: String?
    /// Commands run one after another, so rapid presses each see the previous result.
    private var commandChain: Task<Void, Never>?
    /// Last command failure; shown in the menu only while the HUD is disabled (errors must surface somewhere).
    private var lastCommandError: String?

    init(paths: AppPaths) {
        self.paths = paths
        config = ConfigController(url: paths.extensionConfigURL)

        config.onChange = { [weak self] outcome in
            guard let self else { return }
            configChanged()
            if let message = HUDMessage.forConfig(outcome) { showHUD(message) }
        }
        settings.onChange = { [weak self] in self?.updateHotkeys() }
        hotkeys.onPress = { [weak self] registration in
            Log.hotkeys.info("Hotkey \(registration.hotkey.description, privacy: .public) → \(registration.action.description, privacy: .public)")
            self?.run(Command(registration.action))
        }
    }

    func start() {
        config.start()
    }

    /// Rows for the menu's warning section (PDR §5.2), without the ⚠ prefix.
    var warnings: [String] {
        var rows = config.issues.map(\.description)
        rows += settings.issues.map { "OmniWM settings: \($0)" }
        if let hyperIssue { rows.append("OmniWM settings: \(hyperIssue)") }
        if let plan {
            rows += plan.duplicateWarnings
            rows += plan.conflicts.map(\.description)
        }
        rows += hotkeys.failures.map { "Couldn't register \($0.hotkey)" }
        if let lastCommandError, !config.config.hud.enabled { rows.append(lastCommandError) }
        return rows
    }

    /// The physical chord registered for `action`, for menu key-equivalent hints.
    func registeredChord(for action: HotkeyAction) -> ResolvedHotkey? {
        plan?.registrations.first { $0.action == action && !hotkeys.failures.contains($0) }?.resolved
    }

    // MARK: - HUD

    /// Shows a HUD using the current config's `[hud]` settings (PDR §5.3).
    private func showHUD(_ message: HUDMessage) {
        let settings = config.config.hud
        guard settings.enabled else { return }
        hud.show(message, position: settings.position, durationMs: settings.durationMs)
    }

    // MARK: - Commands

    /// Runs a command against OmniWM's settings (PDR §6.2–§6.4). Never blocks the main thread.
    func run(_ command: Command) {
        guard let url = settings.url else {
            Log.settings.error("\(command.description, privacy: .public): OmniWM settings path not known yet")
            return
        }
        let presets = config.config.padding
        // Time for OmniWM to live-reload settings.toml before a follow-up (config: balance_sizes_delay_ms).
        // OmniWM 0.7.6 reloads 75–81 ms after our write.
        let reloadDelay = Duration.milliseconds(config.config.general.balanceSizesDelayMs)
        let layout: WorkspaceLayout? = nil // Unknown until the OmniWM bridge (0.6.0) → apply.
        let previous = commandChain
        commandChain = Task { [weak self] in
            await previous?.value
            let outcome = await Task.detached { () -> Result<CommandOutcome, CommandError> in
                do throws(CommandError) {
                    return .success(try CommandPlanner.run(command, presets: presets, layout: layout, settingsURL: url))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self else { return }
            switch outcome {
            case let .success(outcome):
                lastCommandError = nil
                Log.settings.info("\(command.description, privacy: .public) → \(String(describing: outcome.result), privacy: .public)")
                showHUD(HUDMessage(outcome.result))
                if let followUp = outcome.followUp {
                    await runFollowUp(followUp, after: reloadDelay)
                }
            case let .failure(error):
                lastCommandError = "Couldn't write OmniWM settings: \(error)"
                showHUD(.writeFailure)
                Log.settings.error("\(command.description, privacy: .public) failed: \(error.description, privacy: .public)")
            }
            settings.reload() // the watcher would catch it too; this keeps the menu state current sooner
        }
    }

    private func configChanged() {
        settings.watch(paths.omniwmSettingsURL(configured: config.config.general.omniwmSettings))
        updateHotkeys()
    }

    private func updateHotkeys() {
        let current = settings.settings
        let hyper = current?.resolvedHyper
        // Only report a hyper problem once we've actually read the settings.
        hyperIssue = hyper?.issue
        let plan = HotkeyPlanner.plan(
            config: config.config,
            hyper: hyper?.modifiers ?? HyperModifiers.fallback,
            omniwmHotkeys: current?.hotkeys ?? []
        )
        guard plan != self.plan else { return } // OmniWM rewrites settings.toml often; stay quiet if nothing changed
        self.plan = plan
        hotkeys.apply(plan.registrations)
        for conflict in plan.conflicts { Log.hotkeys.notice("\(conflict.description, privacy: .public)") }
        for warning in plan.duplicateWarnings { Log.hotkeys.notice("\(warning, privacy: .public)") }
    }

    /// Runs an `omniwmctl` follow-up (e.g. Balance Sizes after a visible-containers change).
    /// Failure is logged only: the settings write itself succeeded.
    private func runFollowUp(_ arguments: [String], after delay: Duration) async {
        let home = paths.homeDirectory
        let output = await Task.detached { () -> OmniWMCtl.Output? in
            try? await Task.sleep(for: delay)
            guard let ctl = OmniWMCtl.locate(homeDirectory: home, environment: ProcessInfo.processInfo.environment) else {
                return nil
            }
            return await OmniWMCtl.run(ctl, arguments)
        }.value
        let command = arguments.joined(separator: " ")
        guard let output else {
            Log.bridge.error("omniwmctl not found; skipped \(command, privacy: .public)")
            return
        }
        if output.succeeded {
            Log.bridge.info("omniwmctl \(command, privacy: .public) ok")
        } else {
            let reason = output.timedOut ? "timed out" : "exit \(output.status): \(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            Log.bridge.error("omniwmctl \(command, privacy: .public) failed (\(reason, privacy: .public))")
        }
    }
}
