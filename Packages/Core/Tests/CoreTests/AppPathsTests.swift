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

    @Test func configuredOmniWMSettingsPath() {
        let paths = AppPaths(environment: [:], homeDirectory: home)
        #expect(paths.omniwmSettingsURL(configured: "").path == "/Users/test/.config/omniwm/settings.toml")
        #expect(paths.omniwmSettingsURL(configured: "  ").path == "/Users/test/.config/omniwm/settings.toml")
        #expect(paths.omniwmSettingsURL(configured: "~/dot/omniwm.toml").path == "/Users/test/dot/omniwm.toml")
        #expect(paths.omniwmSettingsURL(configured: "/etc/omniwm.toml").path == "/etc/omniwm.toml")
    }

    @Test func devBuildUsesDevSettingsUnlessConfigured() {
        let paths = AppPaths(environment: [:], homeDirectory: home)
        #expect(paths.omniwmSettingsURL(configured: "", build: .dev).path == "/Users/test/.config/omniwm-dev/settings.toml")
        #expect(paths.omniwmSettingsURL(configured: "/etc/omniwm.toml", build: .dev).path == "/etc/omniwm.toml")
        let xdg = AppPaths(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"], homeDirectory: home)
        #expect(xdg.omniwmDevSettingsURL.path == "/tmp/xdg/omniwm-dev/settings.toml")
    }
}
