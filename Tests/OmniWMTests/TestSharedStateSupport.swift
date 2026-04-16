import AppKit
import Foundation

@testable import OmniWM

private let testConfigurationDirectoryKey = "__omniwm.test.configurationDirectory"

func configurationDirectoryForTests(defaults: UserDefaults) -> URL {
    if let path = defaults.string(forKey: testConfigurationDirectoryKey) {
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("omniwm-config-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defaults.set(directory.path, forKey: testConfigurationDirectoryKey)
    return directory
}

@MainActor
func runtimeStateStoreForTests(defaults: UserDefaults) -> RuntimeStateStore {
    RuntimeStateStore(
        directory: configurationDirectoryForTests(defaults: defaults),
        deferSaves: false
    )
}

@MainActor
extension SettingsStore {
    convenience init(defaults: UserDefaults) {
        let directory = configurationDirectoryForTests(defaults: defaults)
        self.init(
            persistence: SettingsFilePersistence(
                directory: directory,
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: directory,
                deferSaves: false
            )
        )
    }
}

@MainActor
func resetSharedControllerStateForTests() {
    let contextFactory = AppAXContext.contextFactoryForTests
    let axWindowRefProvider = AXWindowService.axWindowRefProviderForTests
    let setFrameResultProvider = AXWindowService.setFrameResultProviderForTests
    let fastFrameProvider = AXWindowService.fastFrameProviderForTests
    let titleLookupProvider = AXWindowService.titleLookupProviderForTests
    let timeSource = AXWindowService.timeSourceForTests

    SettingsWindowController.shared.windowForTests?.close()
    AppRulesWindowController.shared.windowForTests?.close()
    SponsorsWindowController.shared.windowForTests?.close()
    UpdateWindowController.shared.windowForTests?.close()
    OwnedWindowRegistry.shared.resetForTests()

    AppAXContext.contextFactoryForTests = contextFactory
    AXWindowService.axWindowRefProviderForTests = axWindowRefProvider
    AXWindowService.setFrameResultProviderForTests = setFrameResultProvider
    AXWindowService.fastFrameProviderForTests = fastFrameProvider
    AXWindowService.titleLookupProviderForTests = titleLookupProvider
    AXWindowService.timeSourceForTests = timeSource
    AXWindowService.clearTitleCacheForTests()
}
