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

    init(paths: AppPaths) {
        self.paths = paths
        config = ConfigController(url: paths.extensionConfigURL)

        config.onChange = { [weak self] _ in self?.configChanged() }
        settings.onChange = { [weak self] in self?.updateHotkeys() }
        hotkeys.onPress = { registration in
            // 0.3.0: log-only stubs. Commands arrive in 0.4.0.
            Log.hotkeys.info("Hotkey \(registration.hotkey.description, privacy: .public) → \(registration.action.description, privacy: .public) (stub)")
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
        return rows
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
