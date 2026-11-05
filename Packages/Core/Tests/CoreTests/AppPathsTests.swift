import Foundation
import Testing
@testable import Core

@Suite struct AppPathsTests {
    let home = URL(filePath: "/Users/test", directoryHint: .isDirectory)

    @Test func bundleIdentifier() {
        #expect(AppPaths.bundleIdentifier == "com.omniwm.extension")
    }

    @Test func defaultsToDotConfigWhenXDGUnset() {
        let paths = AppPaths(environment: [:], homeDirectory: home)
        #expect(paths.omniwmSettingsURL.path == "/Users/test/.config/omniwm/settings.toml")
        #expect(paths.extensionConfigURL.path == "/Users/test/.config/omniwm-extension/config.toml")
        #expect(paths.extensionConfigDirectory.path == "/Users/test/.config/omniwm-extension")
    }

    @Test func usesAbsoluteXDGConfigHome() {
        let paths = AppPaths(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"], homeDirectory: home)
        #expect(paths.omniwmSettingsURL.path == "/tmp/xdg/omniwm/settings.toml")
        #expect(paths.extensionConfigURL.path == "/tmp/xdg/omniwm-extension/config.toml")
    }

    @Test(arguments: ["relative/xdg", "~/xdg", ""])
    func ignoresNonAbsoluteXDGConfigHome(_ value: String) {
        let paths = AppPaths(environment: ["XDG_CONFIG_HOME": value], homeDirectory: home)
        #expect(paths.extensionConfigURL.path == "/Users/test/.config/omniwm-extension/config.toml")
    }

    @Test func appSupportAndState() {
        let paths = AppPaths(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"], homeDirectory: home)
        #expect(paths.appSupportDirectory.path == "/Users/test/Library/Application Support/com.omniwm.extension")
        #expect(paths.stateURL.path == "/Users/test/Library/Application Support/com.omniwm.extension/state.json")
    }
}
