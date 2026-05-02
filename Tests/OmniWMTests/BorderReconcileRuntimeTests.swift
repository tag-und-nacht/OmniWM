// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct BorderReconcileRuntimeTests {
    @Test @MainActor func cgsDestroyedReconcileAdvancesWatermark() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let baseline = runtime.currentEffectRunnerWatermark
        _ = runtime.reconcileBorderOwnership(
            event: .cgsDestroyed(windowId: 41_001),
            source: .ax
        )
        #expect(runtime.currentEffectRunnerWatermark.value == baseline.value + 1)
    }

    @Test @MainActor func cgsClosedReconcileAdvancesWatermark() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let baseline = runtime.currentEffectRunnerWatermark
        _ = runtime.reconcileBorderOwnership(
            event: .cgsClosed(windowId: 41_002),
            source: .ax
        )
        #expect(runtime.currentEffectRunnerWatermark.value == baseline.value + 1)
    }

    @Test @MainActor func cleanupReconcileAdvancesWatermark() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let baseline = runtime.currentEffectRunnerWatermark
        _ = runtime.reconcileBorderOwnership(event: .cleanup, source: .service)
        #expect(runtime.currentEffectRunnerWatermark.value == baseline.value + 1)
    }

    @Test @MainActor func multipleBorderReconcileEventsAdvanceWatermarkPerCall() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let baseline = runtime.currentEffectRunnerWatermark
        _ = runtime.reconcileBorderOwnership(
            event: .cgsDestroyed(windowId: 41_101),
            source: .ax
        )
        _ = runtime.reconcileBorderOwnership(
            event: .cgsClosed(windowId: 41_102),
            source: .ax
        )
        #expect(runtime.currentEffectRunnerWatermark.value == baseline.value + 2)
    }

    @Test @MainActor func cgsFrameChangedDoesNotAdvanceRuntimeWatermark() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let baseline = runtime.currentEffectRunnerWatermark
        _ = runtime.controller.borderCoordinator.reconcile(
            event: .cgsFrameChanged(windowId: 41_201)
        )
        #expect(runtime.currentEffectRunnerWatermark == baseline)
    }
}
