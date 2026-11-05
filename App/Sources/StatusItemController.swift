import AppKit
import Core
import ServiceManagement

/// Owns the menu bar status item and its menu (PDR §5.1, §5.2).
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let app: AppController
    private var config: ConfigController { app.config }

    init(app: AppController) {
        self.app = app
        super.init()
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.toolTip = "OmniWM Extension"
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    // MARK: - Icon

    private static func menuBarIcon() -> NSImage? {
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        Log.app.notice("MenuBarIcon resource missing, using SF Symbol fallback")
        let image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "OmniWM Extension")
        image?.isTemplate = true
        return image
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Warnings section (PDR §5.2). Clicking a row opens the config file.
        let warnings = app.warnings
        for warning in warnings {
            let row = item("⚠ \(warning)", action: #selector(editConfigFile))
            row.toolTip = "Open config file"
            menu.addItem(row)
        }
        if !warnings.isEmpty { menu.addItem(.separator()) }

        menu.addItem(item("Edit config file", action: #selector(editConfigFile)))
        menu.addItem(item("Reload config", action: #selector(reloadConfig)))

        let login = item("Start at login", action: #selector(toggleStartAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Restart", action: #selector(restart)))
        menu.addItem(item("Quit", action: #selector(quit), key: "q"))
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func editConfigFile() {
        Task {
            do {
                try await config.ensureFileExists()
                open(config.url)
            } catch {
                Log.config.error("Edit config failed: \(String(describing: error), privacy: .public)")
                showError("Couldn't open config file", detail: String(describing: error))
            }
        }
    }

    @objc private func reloadConfig() {
        Log.config.info("Reload config requested")
        config.reload(force: true)
    }

    private func open(_ url: URL) {
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else {
            // No app registered for .toml → TextEdit.
            Log.config.info("No default app for .toml, opening with open -t")
            launch("/usr/bin/open", ["-t", url.path])
        }
    }

    @objc private func toggleStartAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
                Log.app.info("Start at login disabled")
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
                Log.app.info("Start at login enabled (status \(service.status.rawValue))")
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            Log.app.error("Start at login failed: \(error.localizedDescription, privacy: .public)")
            showError("Couldn't change Start at login", detail: error.localizedDescription)
        }
    }

    @objc private func restart() {
        let bundlePath = Bundle.main.bundlePath
        Log.app.info("Restarting from \(bundlePath, privacy: .public)")
        // The shell outlives us, waits for this instance to exit, then relaunches this app only.
        guard launch("/bin/sh", ["-c", "sleep 0.5; exec /usr/bin/open -n \"$1\"", "sh", bundlePath]) else {
            showError("Couldn't restart", detail: "Failed to spawn the relaunch helper.")
            return
        }
        NSApp.terminate(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    /// Spawns a child without waiting for it.
    @discardableResult
    private func launch(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        do {
            try process.run()
            return true
        } catch {
            Log.app.error("Failed to launch \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func showError(_ message: String, detail: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
