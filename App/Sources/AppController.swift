import ColorSync // CGDisplayCreateUUIDFromDisplayID
import Core
import CoreGraphics
import Foundation

/// Wires config, OmniWM settings and hotkeys together; owns the menu's warnings.
@MainActor
final class AppController {
    let paths: AppPaths
    let config: ConfigController
    let settings = SettingsController()
    private let hotkeys = HotkeyManager()
    private let hud = HUDController()
    private let displays = DisplayMonitor()
    private let omniwmBuild = OmniWMBuildMonitor()
    let bridge: OmniWMBridge
    /// The status item title should be redrawn (OmniWM state, borders, config).
    var onStatusChange: (() -> Void)?
    private var plan: HotkeyPlan?
    private var hyperIssue: String?
    /// Commands run one after another, so rapid presses each see the previous result.
    private var commandChain: Task<Void, Never>?
    /// Last command failure; shown in the menu only while the HUD is disabled (errors must surface somewhere).
    private var lastCommandError: String?

    init(paths: AppPaths) {
        self.paths = paths
        config = ConfigController(url: paths.extensionConfigURL)
        bridge = OmniWMBridge(homeDirectory: paths.homeDirectory, build: omniwmBuild.build)

        config.onChange = { [weak self] outcome in
            guard let self else { return }
            configChanged()
            if let message = HUDMessage.forConfig(outcome) { showHUD(message) }
            // Launch check (PDR §6.5): once config and the settings path are known.
            if !checkedTopologyAtLaunch {
                checkedTopologyAtLaunch = true
                if let topology = DisplayMonitor.currentTopology() { topologyChanged(topology) }
            }
        }
        displays.onChange = { [weak self] topology in self?.topologyChanged(topology) }
        settings.onChange = { [weak self] in
            self?.updateHotkeys()
            self?.onStatusChange?()
            self?.bridge.refresh() // the container count feeds FC (PDR §6.8)
        }
        bridge.containerCountProvider = { [weak self] in
            guard let self else { return nil }
            return DisplayOverrides.effectiveContainerCount(settings.settings, on: currentDisplayIdentity)
        }
        bridge.onChange = { [weak self] in self?.onStatusChange?() }
        bridge.onToggles = { [weak self] toggles in
            // Several at once (rare): the last one wins, like rapid presses.
            if let last = toggles.last { self?.showHUD(last) }
        }
        hotkeys.onPress = { [weak self] registration in
            Log.hotkeys.info("Hotkey \(registration.hotkey.description, privacy: .public) → \(registration.action.description, privacy: .public)")
            self?.run(Command(registration.action))
        }
        omniwmBuild.onChange = { [weak self] build in
            guard let self else { return }
            bridge.retarget(build)
            configChanged()
        }
    }

    func start() {
        omniwmBuild.start()
        config.start()
        bridge.start()
        displays.start()
    }

    /// Kills the `omniwmctl` child (PDR §5.2).
    func stop() {
        bridge.stop()
    }

    // MARK: - Menu bar (PDR §5.1)

    var menuBarModel: MenuBarModel {
        let state = bridge.state
        let omniwm = settings.settings
        let ref = state.currentWorkspaceRef
        return MenuBarModel(
            reachable: bridge.reachable,
            workspaceNumber: ref?.number,
            displayName: MenuBarFormatter.customDisplayName(ref, settings: omniwm),
            bordersEnabled: omniwm?.bordersEnabled,
            layout: state.currentLayout,
            containerCount: DisplayOverrides.effectiveContainerCount(omniwm, on: currentDisplayIdentity),
            focus: state.focusIndicator
        )
    }

    /// ⓘ rows: the current display overrides a global value we write (PDR §6.6).
    var notices: [String] {
        guard let omniwm = settings.settings, let display = currentDisplayIdentity else { return [] }
        var rows: [String] = []
        if DisplayOverrides.overridesGaps(omniwm, on: display) { rows.append("This display overrides gaps") }
        if DisplayOverrides.containerOverride(omniwm, on: display) != nil { rows.append("This display overrides containers") }
        return rows
    }

    /// The display showing the current workspace, as known to OmniWM; `nil` when unreachable.
    private var currentDisplayIdentity: DisplayIdentity? {
        guard bridge.reachable, let display = bridge.state.currentDisplay else { return nil }
        let numeric = DisplayIdentity.numericID(fromIPC: display.id)
        var uuid: String?
        if let numeric, let id = UInt32(numeric), let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            uuid = CFUUIDCreateString(nil, cfUUID) as String?
        }
        return DisplayIdentity(uuid: uuid, id: numeric, name: display.name)
    }

    /// Rows for the menu's warning section (PDR §5.2), without the ⚠ prefix.
    var warnings: [String] {
        var rows = config.issues.map(\.description)
        if !bridge.reachable { rows.append("OmniWM not reachable") }
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
        enqueue { [weak self] in
            await self?.execute(command) { HUDMessage($0) }
        }
    }

    /// Commands and display-policy actions run one after another on this chain.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = commandChain
        commandChain = Task {
            await previous?.value
            await work()
        }
    }

    /// Runs one command off the main thread, shows its HUD (unless an override masks it), runs any follow-up.
    @discardableResult
    private func execute(_ command: Command, hud message: (CommandResult) -> HUDMessage) async -> CommandResult? {
        guard let url = settings.url else {
            Log.settings.error("\(command.description, privacy: .public): OmniWM settings path not known yet")
            return nil
        }
        let presets = config.config.padding
        // Time for OmniWM to live-reload settings.toml before a follow-up (config: balance_sizes_delay_ms).
        // OmniWM 0.7.6 reloads 75–81 ms after our write.
        let reloadDelay = Duration.milliseconds(config.config.general.balanceSizesDelayMs)
        // Real Dwindle check (PDR §6.3); unknown when OmniWM isn't reachable → apply.
        let layout: WorkspaceLayout? = bridge.reachable ? bridge.state.currentLayout : nil

        let outcome = await Task.detached { () -> Result<CommandOutcome, CommandError> in
            do throws(CommandError) {
                return .success(try CommandPlanner.run(command, presets: presets, layout: layout, settingsURL: url))
            } catch {
                return .failure(error)
            }
        }.value
        defer { settings.reload() } // the watcher would catch it too; this keeps the menu state current sooner

        switch outcome {
        case let .success(outcome):
            lastCommandError = nil
            Log.settings.info("\(command.description, privacy: .public) → \(String(describing: outcome.result), privacy: .public)")
            showHUD(isMaskedByOverride(outcome.result) ? .maskedByOverride : message(outcome.result))
            if let followUp = outcome.followUp {
                await runFollowUp(followUp, after: reloadDelay)
            }
            return outcome.result
        case let .failure(error):
            lastCommandError = "Couldn't write OmniWM settings: \(error)"
            showHUD(.writeFailure)
            Log.settings.error("\(command.description, privacy: .public) failed: \(error.description, privacy: .public)")
            return nil
        }
    }

    // MARK: - Display awareness (PDR §6.5)

    /// In memory after the first load of state.json.
    private var displayState: DisplayState?
    private var checkedTopologyAtLaunch = false

    /// Queues the §6.5 policy for `topology` (launch check or a debounced screen change).
    func topologyChanged(_ topology: DisplayTopology) {
        enqueue { [weak self] in await self?.applyDisplayPolicy(topology) }
    }

    private func applyDisplayPolicy(_ current: DisplayTopology) async {
        guard let settingsURL = settings.url else { return }
        let stateURL = paths.stateURL

        let state: DisplayState
        if let displayState {
            state = displayState
        } else {
            let loaded = await Task.detached { DisplayStateStore.load(from: stateURL) }.value
            if let issue = loaded.issue { Log.display.error("\(issue, privacy: .public)") }
            state = loaded.state
        }
        // Fresh read: the exact numbers to save, so Custom round-trips.
        let gaps = await Task.detached { SettingsReader.load(from: settingsURL).settings?.outerGaps }.value
        let enabled = config.config.general.autoFullscreenOnBuiltin
        let decision = DisplayPolicy.decide(state: state, current: current, currentGaps: gaps, enabled: enabled)
        Log.display.info("Topology \(state.lastTopology?.rawValue ?? "none", privacy: .public) → \(current.rawValue, privacy: .public), enabled=\(enabled): \(String(describing: decision.action), privacy: .public)")

        // Persist before writing gaps, so the saved values survive a crash in between.
        displayState = decision.state
        if decision.state != state {
            let next = decision.state
            let saved = await Task.detached { () -> String? in
                do {
                    try DisplayStateStore.save(next, to: stateURL)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let saved { Log.display.error("Couldn't save state.json: \(saved, privacy: .public)") }
        }

        switch decision.action {
        case .none:
            break
        case .applyFirstPreset:
            guard let first = config.config.padding.first else { return }
            await execute(.selectPreset(first.name)) { result in
                if case let .paddingSet(name) = result { return .builtIn(name) }
                return HUDMessage(result)
            }
        case let .restore(gaps):
            await execute(.restoreGaps(gaps)) { result in
                if case let .paddingSet(name) = result { return .restored(name) }
                return HUDMessage(result)
            }
        }
    }

    /// A global value was set, but the current display overrides it (PDR §6.6).
    private func isMaskedByOverride(_ result: CommandResult) -> Bool {
        guard let omniwm = settings.settings, let display = currentDisplayIdentity else { return false }
        switch result {
        case .paddingSet: return DisplayOverrides.overridesGaps(omniwm, on: display)
        case .containersSet: return DisplayOverrides.containerOverride(omniwm, on: display) != nil
        case .bordersSet, .skippedDwindle: return false
        }
    }

    private func configChanged() {
        settings.watch(paths.omniwmSettingsURL(configured: config.config.general.omniwmSettings, build: omniwmBuild.build))
        updateHotkeys()
        onStatusChange?()
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
        let build = omniwmBuild.build
        let output = await Task.detached { () -> OmniWMCtl.Output? in
            try? await Task.sleep(for: delay)
            guard let ctl = OmniWMCtl.locate(
                homeDirectory: home,
                environment: ProcessInfo.processInfo.environment,
                build: build
            ) else {
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
