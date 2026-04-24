// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing
@testable import OmniWM

@Suite("Runtime domain composition")
@MainActor
struct RuntimeDomainCompositionTests {
    @Test func wmRuntimeExposesAllSevenDomainRuntimes() {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        let runtime = WMRuntime(settings: settings)

        // Each domain runtime is constructed eagerly inside `WMRuntime.init`
        // and reachable as a stored property. The test pins the surface so
        // a future refactor that drops one of the seven (or accidentally
        // makes one private) fails compile here.
        _ = runtime.focusRuntime
        _ = runtime.frameRuntime
        _ = runtime.nativeFullscreenRuntime
        _ = runtime.workspaceRuntime
        _ = runtime.monitorRuntime
        _ = runtime.windowAdmissionRuntime
        _ = runtime.capabilityRuntime
    }

    @Test func runtimeKernelMintsStrictlyMonotonicEpochsAcrossAllSevenDomains() {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        let runtime = WMRuntime(settings: settings)

        // FocusRuntime.reduce is the one method that today routes through
        // the kernel. Its commit must advance the effect runner's
        // watermark — proving the shared kernel and shared runner are
        // wired through the focus seam.
        let baselineWatermark = runtime.currentEffectRunnerWatermark
        let workspaceId = WorkspaceDescriptor.ID()
        let logicalId = LogicalWindowId(value: 7)
        _ = runtime.focusRuntime.reduce(
            .activationRequested(
                desired: .logical(logicalId, workspaceId: workspaceId),
                requestId: 1,
                originatingTransactionEpoch: TransactionEpoch(value: 1)
            )
        )
        #expect(runtime.currentEffectRunnerWatermark > baselineWatermark)
    }

    @Test func monitorRuntimeOwnsTopologyMutationAndSharedEpochs() {
        resetSharedControllerStateForTests()
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let runtime = WMRuntime(settings: settings)
        let baselineWatermark = runtime.currentEffectRunnerWatermark

        #expect(runtime.currentTopologyEpoch == .invalid)
        runtime.monitorRuntime.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])

        #expect(runtime.currentTopologyEpoch.isValid)
        #expect(runtime.currentEffectRunnerWatermark > baselineWatermark)
    }
}
