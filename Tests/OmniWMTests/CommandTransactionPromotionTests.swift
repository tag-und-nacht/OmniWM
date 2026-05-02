// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct CommandTransactionPromotionTests {
    @Test @MainActor func workspaceSwitchCommandProducesNonNilTransactionWithStampedEpoch() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let result = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )

        #expect(result.transaction.transactionEpoch == result.transactionEpoch)
        #expect(result.transaction.transactionEpoch.isValid)
        #expect(result.transaction.isCompleted)
        #expect(runtime.controller.workspaceManager.lastRecordedTransaction == result.transaction)
        #expect(result.transaction.invariantViolations.isEmpty)
    }

    @Test @MainActor func typedActionCommandRecordsCompletedTransactionWithInvariantResults() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let result = runtime.submit(
            command: .controllerAction(.rescueOffscreenWindows(source: .ipc))
        )

        #expect(result.externalCommandResult == .executed)
        #expect(result.transaction.transactionEpoch == result.transactionEpoch)
        #expect(result.transaction.isCompleted)
        #expect(result.transaction.snapshot == runtime.controller.workspaceManager.reconcileSnapshot())
        #expect(result.transaction.invariantViolations.isEmpty)
        #expect(runtime.controller.workspaceManager.lastRecordedTransaction == result.transaction)
    }

    @Test @MainActor func commandTxnEventIsCommandIntentWithRedactedKindAndSource() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let result = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )

        guard case let .commandIntent(kindForLog, source) = result.transaction.event else {
            Issue.record("expected commandIntent event on synthesized command Transaction")
            return
        }
        #expect(kindForLog == "workspace_switch_explicit")
        #expect(source == .command)
        #expect(result.transaction.event == result.transaction.normalizedEvent)
    }

    @Test @MainActor func uiInputBindingTriggerTxnTagsSourceWithIPCWhenIPCRouted() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let result = runtime.submit(
            command: WMRuntime.typedCommand(for: .toggleOverview, source: .ipc)
        )

        guard case let .commandIntent(kindForLog, source) = result.transaction.event else {
            Issue.record("expected commandIntent event")
            return
        }
        #expect(kindForLog == "ui_action:toggle_overview")
        #expect(source == .ipc)
    }

    @Test @MainActor func commandTxnSnapshotMatchesPostApplyReconcileSnapshot() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let result = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )

        #expect(result.transaction.snapshot == runtime.controller.workspaceManager.reconcileSnapshot())
    }

    @Test @MainActor func commandTxnHasEmptyActionPlanByConstruction() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let result = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )

        #expect(result.transaction.plan.isEmpty)
    }

    @Test @MainActor func commandTxnRunsInvariantChecksAgainstPostApplySnapshot() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let missingToken = WindowToken(pid: 91_001, windowId: 91_002)

        _ = runtime.controller.workspaceManager.setManagedFocus(
            missingToken,
            in: workspaceId
        )

        let result = runtime.submit(
            command: WMRuntime.typedCommand(for: .toggleOverview, source: .command)
        )

        #expect(result.transaction.snapshot.focusedToken == missingToken)
        #expect(result.transaction.isCompleted)
        #expect(runtime.controller.workspaceManager.lastRecordedTransaction == result.transaction)
        #expect(result.transaction.invariantViolations.contains {
            $0.code == "focused_token_missing"
        })
    }

    @Test @MainActor func consecutiveCommandsProduceMonotonicTransactionEpochs() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let first = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )
        let second = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "1"))
        )

        #expect(first.transaction.transactionEpoch < second.transaction.transactionEpoch)
    }
}
