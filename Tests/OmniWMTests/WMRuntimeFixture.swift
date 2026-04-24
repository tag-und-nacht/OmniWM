// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@testable import OmniWM

@MainActor
struct WMRuntimeFixture {
    let runtime: WMRuntime

    var controller: WMController { runtime.controller }
    var workspaceManager: WorkspaceManager { runtime.workspaceManager }

    init(
        settings: SettingsStore,
        platform: WMPlatform = .live,
        windowFocusOperations: WindowFocusOperations? = nil,
        effectPlatform: (any WMEffectPlatform)? = nil
    ) {
        resetSharedControllerStateForTests()
        self.runtime = WMRuntime(
            settings: settings,
            platform: platform,
            windowFocusOperations: windowFocusOperations,
            effectPlatform: effectPlatform
        )
    }
}
