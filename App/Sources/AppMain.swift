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
    /// SIGTERM (e.g. `make install`, logout) → normal termination, so the omniwmctl child is killed too.
    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Log.app.info("OmniWM Extension \(version, privacy: .public) launched")
        let app = AppController(paths: .current)
        appController = app
        statusItemController = StatusItemController(app: app)
        app.start()

        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            Log.app.info("SIGTERM received; terminating")
            NSApp.terminate(nil)
        }
        source.resume()
        sigtermSource = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("OmniWM Extension terminating")
        appController?.stop()
    }
}
