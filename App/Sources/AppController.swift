import Core
import Foundation

/// Wires config, OmniWM settings and hotkeys together; owns the menu's warnings.
@MainActor
final class AppController {
    let paths: AppPaths
    let config: ConfigController
    let settings = SettingsController()
    private let hotkeys = HotkeyManager()
    private var plan: HotkeyPlan?
    private var hyperIssue: String?
    /// Commands run one after another, so rapid presses each see the previous result.
    private var commandChain: Task<Void, Never>?
    /// Shown in the menu until the next command succeeds (the HUD takes over in 0.5.0).
    private var lastCommandError: String?

    init(paths: AppPaths) {
        self.paths = paths
        config = ConfigController(url: paths.extensionConfigURL)

        config.onChange = { [weak self] _ in self?.configChanged() }
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
        if let lastCommandError { rows.append(lastCommandError) }
        return rows
    }

    /// The physical chord registered for `action`, for menu key-equivalent hints.
    func registeredChord(for action: HotkeyAction) -> ResolvedHotkey? {
        plan?.registrations.first { $0.action == action && !hotkeys.failures.contains($0) }?.resolved
    }

    // MARK: - Commands

    /// Runs a command against OmniWM's settings (PDR §6.2–§6.4). Never blocks the main thread.
    func run(_ command: Command) {
        guard let url = settings.url else {
            Log.settings.error("\(command.description, privacy: .public): OmniWM settings path not known yet")
            return
        }
        let presets = config.config.padding
        let layout: WorkspaceLayout? = nil // Unknown until the OmniWM bridge (0.6.0) → apply.
        let previous = commandChain
        commandChain = Task { [weak self] in
            await previous?.value
            let outcome = await Task.detached { () -> Result<CommandResult, CommandError> in
                do throws(CommandError) {
                    return .success(try CommandPlanner.run(command, presets: presets, layout: layout, settingsURL: url))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self else { return }
            switch outcome {
            case let .success(result):
                lastCommandError = nil
                Log.settings.info("\(command.description, privacy: .public) → \(String(describing: result), privacy: .public)")
            case let .failure(error):
                lastCommandError = "Couldn't write OmniWM settings: \(error)"
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
}
