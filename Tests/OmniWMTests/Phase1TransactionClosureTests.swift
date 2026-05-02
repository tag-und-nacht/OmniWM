// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct Phase1TransactionClosureTests {
    @Test @MainActor func workspaceSettingsApplyRecordsStampedConfigTransaction() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let baseline = runtime.currentEffectRunnerWatermark

        _ = runtime.applyWorkspaceSettings(source: .config)

        #expect(runtime.currentEffectRunnerWatermark.value == baseline.value + 1)
        #expect(
            runtime.controller.workspaceManager.lastRecordedTransaction?.event
                == .commandIntent(kindForLog: "workspace_settings_applied", source: .config)
        )
    }

    @Test @MainActor func workspaceMaterializationRecordsStampedTransaction() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        runtime.settings.workspaceConfigurations.append(
            WorkspaceConfiguration(name: "3", monitorAssignment: .main)
        )
        let baseline = runtime.currentEffectRunnerWatermark

        let workspaceId = runtime.materializeWorkspace(named: "3", source: .command)

        #expect(workspaceId != nil)
        #expect(runtime.currentEffectRunnerWatermark.value == baseline.value + 1)
        #expect(
            runtime.controller.workspaceManager.lastRecordedTransaction?.event
                == .commandIntent(kindForLog: "workspace_materialized", source: .command)
        )
    }

    @Test @MainActor func niriViewportMutationRecordsStampedTransaction() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let baseline = runtime.currentEffectRunnerWatermark

        runtime.withNiriViewportState(for: workspaceId, source: .mouse) { state in
            state.selectionProgress = 0.5
        }

        #expect(runtime.currentEffectRunnerWatermark.value == baseline.value + 1)
        #expect(runtime.controller.workspaceManager.niriViewportState(for: workspaceId).selectionProgress == 0.5)
        #expect(
            runtime.controller.workspaceManager.lastRecordedTransaction?.event
                == .commandIntent(kindForLog: "niri_viewport_state_updated", source: .mouse)
        )
    }

    @Test @MainActor func niriViewportMutationPreservesIPCProvenance() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        runtime.withNiriViewportState(for: workspaceId, source: .ipc) { state in
            state.selectionProgress = 0.25
        }

        #expect(
            runtime.controller.workspaceManager.lastRecordedTransaction?.event
                == .commandIntent(kindForLog: "niri_viewport_state_updated", source: .ipc)
        )
    }
}
