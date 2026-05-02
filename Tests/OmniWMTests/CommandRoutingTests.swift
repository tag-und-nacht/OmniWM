// SPDX-License-Identifier: GPL-2.0-only
import Testing

@testable import OmniWM

@Suite @MainActor struct CommandRoutingTests {
    @Test func commandPaletteDisplayNameReflectsToggleBehavior() {
        #expect(InputBindingTrigger.openCommandPalette.displayName == "Toggle Command Palette")
    }

    // ExecPlan 03 TX-CMD-01g: typed command routing is runtime-owned now.
    // The overview gate lives inline in `WMRuntime.dispatchHotkey(_:source:)`;
    // higher-level dispatch coverage lives in `ServiceLifecycleManagerTests`
    // and `RefreshRoutingTests`.
}
