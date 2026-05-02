// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct WorkspaceSwitchTransactionTests {
    @Test @MainActor func submittingExplicitSwitchAllocatesFreshTransactionEpoch() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let result = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )

        #expect(result.transactionEpoch.isValid)
        #expect(result.transactionEpoch == TransactionEpoch(value: 1))
        #expect(result.transaction.transactionEpoch == result.transactionEpoch)
        #expect(!result.transaction.hasNoEffects)
    }

    @Test @MainActor func successiveSubmissionsAdvanceTransactionEpoch() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let first = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )
        let second = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "1"))
        )

        #expect(first.transactionEpoch < second.transactionEpoch)
        #expect(second.transactionEpoch == TransactionEpoch(value: 2))
    }

    @Test @MainActor func effectEpochsAreMonotonicWithinAndAcrossTransactions() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let first = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )
        let second = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "1"))
        )

        let firstEffectEpochs = first.transaction.effects.map(\.epoch.value)
        let secondEffectEpochs = second.transaction.effects.map(\.epoch.value)

        for pair in zip(firstEffectEpochs, firstEffectEpochs.dropFirst()) {
            #expect(pair.0 < pair.1, "within-transaction effect epochs must strictly increase")
        }
        if let lastFirst = firstEffectEpochs.last,
           let firstSecond = secondEffectEpochs.first
        {
            #expect(lastFirst < firstSecond, "effect epochs must be monotonic across transactions")
        }
    }

    @Test @MainActor func unknownWorkspaceProducesNoEffects() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let result = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "does-not-exist"))
        )

        #expect(result.transaction.hasNoEffects)
        #expect(result.transactionEpoch.isValid)
        #expect(platform.events.isEmpty, "empty transaction must not invoke effects")
    }

    @Test @MainActor func transactionEffectsLeadWithBorderHideAndEndWithWorkspaceCommit() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let result = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )

        #expect(result.transaction.effects.first?.kind == "hide_keyboard_focus_border")
        #expect(result.transaction.effects.last?.kind == "commit_workspace_transition")
    }

    @Test @MainActor func submitEventAlsoStampsTransactionEpoch() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let txn = runtime.submit(.activeSpaceChanged(source: .workspaceManager))
        #expect(txn.transactionEpoch.isValid)
    }

    @Test @MainActor func runtimeSessionPatchRecordsStampedCompatibilityTxn() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        _ = runtime.applySessionPatch(
            .init(
                workspaceId: workspaceId,
                viewportState: nil,
                rememberedFocusToken: nil
            ),
            source: .focusPolicy
        )

        let txn = runtime.controller.workspaceManager.lastRecordedTransaction
        #expect(txn?.transactionEpoch.isValid == true)
        #expect(txn?.event == .commandIntent(kindForLog: "session_patch", source: .focusPolicy))
    }

    @Test @MainActor func recordTransactionWithoutRuntimeHasInvalidEpoch() {
        resetSharedControllerStateForTests()
        let settings = makeTransactionTestRuntimeSettings()
        let manager = WorkspaceManager(settings: settings)
        manager.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])

        let txn = manager.recordTransaction(
            for: .activeSpaceChanged(source: .workspaceManager)
        )
        #expect(!txn.transactionEpoch.isValid)
    }

    @Test @MainActor func directManagerRecordCompletesInvariantChecks() {
        resetSharedControllerStateForTests()
        let settings = makeTransactionTestRuntimeSettings()
        let manager = WorkspaceManager(settings: settings)
        manager.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let workspaceId = manager.workspaceId(for: "1", createIfMissing: false)!
        let missingToken = WindowToken(pid: 91_101, windowId: 91_102)

        _ = manager.setManagedFocus(missingToken, in: workspaceId)

        let txn = manager.recordTransaction(
            for: .activeSpaceChanged(source: .workspaceManager)
        )

        #expect(txn.isCompleted)
        #expect(txn.invariantViolations.contains { $0.code == "focused_token_missing" })
        #expect(manager.lastRecordedTransaction?.isCompleted == true)
    }

    @Test @MainActor func effectConfirmationAppliesWorkspaceActivationThroughRuntime() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let monitorId = runtime.controller.workspaceManager.monitors.first!.id
        let workspaceTwo = runtime.controller.workspaceManager.workspaceId(
            for: "2",
            createIfMissing: false
        )!

        let changed = runtime.submit(
            .targetWorkspaceActivated(
                workspaceId: workspaceTwo,
                monitorId: monitorId,
                source: .command,
                originatingTransactionEpoch: TransactionEpoch(value: 1)
            )
        )

        #expect(changed)
        #expect(runtime.controller.workspaceManager.activeWorkspace(on: monitorId)?.id == workspaceTwo)
        #expect(runtime.snapshot.reconcile == runtime.controller.workspaceManager.reconcileSnapshot())
    }

    @Test @MainActor func repeatedActivationConfirmationKeepsReducerParity() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let monitorId = runtime.controller.workspaceManager.monitors.first!.id
        let workspaceOne = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        let applied = runtime.submit(
            .targetWorkspaceActivated(
                workspaceId: workspaceOne,
                monitorId: monitorId,
                source: .command,
                originatingTransactionEpoch: TransactionEpoch(value: 1)
            )
        )

        #expect(applied)
        #expect(runtime.controller.workspaceManager.activeWorkspace(on: monitorId)?.id == workspaceOne)
        #expect(runtime.snapshot.reconcile == runtime.controller.workspaceManager.reconcileSnapshot())
    }

    @Test @MainActor func workspaceConfirmationSurvivesUnrelatedWatermarkMovement() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let monitorId = runtime.controller.workspaceManager.monitors.first!.id
        let workspaceTwo = runtime.controller.workspaceManager.workspaceId(
            for: "2",
            createIfMissing: false
        )!

        _ = runtime.submit(.activeSpaceChanged(source: .workspaceManager))
        _ = runtime.submit(.activeSpaceChanged(source: .workspaceManager))

        let changed = runtime.submit(
            .targetWorkspaceActivated(
                workspaceId: workspaceTwo,
                monitorId: monitorId,
                source: .command,
                originatingTransactionEpoch: TransactionEpoch(value: 1)
            )
        )

        #expect(changed)
        #expect(runtime.controller.workspaceManager.activeWorkspace(on: monitorId)?.id == workspaceTwo)
    }

    @Test @MainActor func saveWorkspaceViewportSurvivesUnrelatedWatermarkMovement() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceOne = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        let transition = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )
        _ = runtime.submit(.activeSpaceChanged(source: .workspaceManager))
        #expect(runtime.currentEffectRunnerWatermark > transition.transactionEpoch)

        _ = runtime.saveWorkspaceViewport(
            for: workspaceOne,
            originatingTransactionEpoch: transition.transactionEpoch,
            source: .command
        )

        #expect(
            runtime.controller.workspaceManager.lastRecordedTransaction?.event
                == .commandIntent(
                    kindForLog: RuntimeMutationKind.commitWorkspaceSelection.rawValue,
                    source: .command
                )
        )
        #expect(
            runtime.controller.workspaceManager.lastRecordedTransaction?.transactionEpoch
                == transition.transactionEpoch
        )
    }

    @Test @MainActor func saveWorkspaceViewportRejectsOlderSameWorkspaceTransition() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceOne = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        let olderTransition = runtime.commitWorkspaceTransition(
            affectedWorkspaceIds: [workspaceOne],
            postAction: .none,
            source: .command
        )
        let newerTransition = runtime.commitWorkspaceTransition(
            affectedWorkspaceIds: [workspaceOne],
            postAction: .none,
            source: .command
        )

        let changed = runtime.saveWorkspaceViewport(
            for: workspaceOne,
            originatingTransactionEpoch: olderTransition.transactionEpoch,
            source: .command
        )

        #expect(!changed)
        #expect(
            runtime.controller.workspaceManager.lastRecordedTransaction?.transactionEpoch
                == newerTransition.transactionEpoch
        )
    }

    @Test @MainActor func invalidEffectConfirmationDoesNotMutateWorkspaceActivation() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let monitorId = runtime.controller.workspaceManager.monitors.first!.id
        let workspaceOne = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let workspaceTwo = runtime.controller.workspaceManager.workspaceId(
            for: "2",
            createIfMissing: false
        )!

        let changed = runtime.submit(
            .targetWorkspaceActivated(
                workspaceId: workspaceTwo,
                monitorId: monitorId,
                source: .command,
                originatingTransactionEpoch: .invalid
            )
        )

        #expect(!changed)
        #expect(runtime.controller.workspaceManager.activeWorkspace(on: monitorId)?.id == workspaceOne)
    }
}
