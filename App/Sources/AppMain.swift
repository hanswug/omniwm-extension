import AppKit
import Core

@main
@MainActor
enum AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var appController: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Log.app.info("OmniWM Extension \(version, privacy: .public) launched")
        let app = AppController(paths: .current)
        appController = app
        statusItemController = StatusItemController(app: app)
        app.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("OmniWM Extension terminating")
    }
}
