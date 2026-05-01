// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct StaleConfirmationRejectionTests {
    @MainActor
    private func workspaceId(
        _ rawWorkspaceID: String,
        in runtime: WMRuntime
    ) -> WorkspaceDescriptor.ID {
        runtime.controller.workspaceManager.workspaceId(
            for: rawWorkspaceID,
            createIfMissing: false
        )!
    }

    @MainActor
    private func requestFocus(
        in runtime: WMRuntime,
        windowId: Int,
        rawWorkspaceID: String = "1"
    ) -> (token: WindowToken, workspaceId: WorkspaceDescriptor.ID, origin: TransactionEpoch) {
        let workspaceId = workspaceId(rawWorkspaceID, in: runtime)
        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceId,
            source: .ax
        )
        _ = runtime.requestManagedFocus(
            token: token,
            workspaceId: workspaceId,
            source: .command
        )
        guard let origin = runtime.controller.focusBridge.originTransactionEpoch(
            forToken: token
        ) else {
            Issue.record("expected runtime-routed focus request to stamp origin epoch")
            return (token, workspaceId, .invalid)
        }
        return (token, workspaceId, origin)
    }

    @Test @MainActor func unstampedConfirmationIsRejectedWithoutStateMutation() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        _ = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )
        let token = WindowToken(pid: 4242, windowId: 9001)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "2",
            createIfMissing: false
        )!

        let beforeSnapshot = runtime.controller.workspaceManager.reconcileSnapshot()
        let txn = runtime.submit(
            .managedFocusConfirmed(
                token: token,
                workspaceId: workspaceId,
                monitorId: nil,
                appFullscreen: false,
                source: .ax,
                originatingTransactionEpoch: .invalid
            )
        )
        let afterSnapshot = runtime.controller.workspaceManager.reconcileSnapshot()

        #expect(txn.transactionEpoch.isValid)
        #expect(txn.plan.isEmpty)
        #expect(txn.effects.isEmpty)
        #expect(beforeSnapshot == afterSnapshot)
    }

    @Test @MainActor func matchingPendingConfirmationIsAcceptedAfterUnrelatedMutation() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let request = requestFocus(in: runtime, windowId: 31_010)
        _ = runtime.submit(.activeSpaceChanged(source: .workspaceManager))
        #expect(runtime.currentEffectRunnerWatermark > request.origin)

        let txn = runtime.submit(
            .managedFocusConfirmed(
                token: request.token,
                workspaceId: request.workspaceId,
                monitorId: nil,
                appFullscreen: false,
                source: .ax,
                originatingTransactionEpoch: request.origin
            )
        )

        #expect(txn.transactionEpoch.isValid)
        #expect(runtime.currentEffectRunnerWatermark == txn.transactionEpoch)
        #expect(txn.plan.focusSession?.focusedToken == request.token)
        #expect(txn.plan.focusSession?.pendingManagedFocus.token == nil)
    }

    @Test @MainActor func stampedConfirmationAtCurrentWatermarkIsAccepted() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let request = requestFocus(in: runtime, windowId: 31_011)
        let txn = runtime.submit(
            .managedFocusConfirmed(
                token: request.token,
                workspaceId: request.workspaceId,
                monitorId: nil,
                appFullscreen: false,
                source: .ax,
                originatingTransactionEpoch: request.origin
            )
        )
        #expect(txn.transactionEpoch.isValid)
        #expect(runtime.currentEffectRunnerWatermark == txn.transactionEpoch)
        #expect(txn.plan.focusSession?.focusedToken == request.token)
        #expect(txn.plan.focusSession?.pendingManagedFocus.token == nil)
    }

    @Test @MainActor func stampedManagedFocusCancellationFollowsScopedRequestRules() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let request = requestFocus(in: runtime, windowId: 31_012)
        _ = runtime.submit(.activeSpaceChanged(source: .workspaceManager))
        #expect(runtime.controller.workspaceManager.pendingFocusedToken == request.token)
        let txn = runtime.submit(
            .managedFocusCancelled(
                token: request.token,
                workspaceId: request.workspaceId,
                source: .ax,
                originatingTransactionEpoch: request.origin
            )
        )
        #expect(txn.transactionEpoch.isValid)
        #expect(runtime.currentEffectRunnerWatermark == txn.transactionEpoch)
        #expect(txn.plan.focusSession?.pendingManagedFocus.token == nil)
    }

    @Test @MainActor func stampedManagedFocusCancellationRequiresTokenAndWorkspace() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let request = requestFocus(in: runtime, windowId: 31_112)
        let watermarkAfterRequest = runtime.currentEffectRunnerWatermark

        _ = runtime.submit(
            .managedFocusCancelled(
                token: nil,
                workspaceId: request.workspaceId,
                source: .ax,
                originatingTransactionEpoch: request.origin
            )
        )
        #expect(runtime.controller.workspaceManager.pendingFocusedToken == request.token)
        #expect(runtime.currentEffectRunnerWatermark == watermarkAfterRequest)

        _ = runtime.submit(
            .managedFocusCancelled(
                token: request.token,
                workspaceId: nil,
                source: .ax,
                originatingTransactionEpoch: request.origin
            )
        )
        #expect(runtime.controller.workspaceManager.pendingFocusedToken == request.token)
        #expect(runtime.currentEffectRunnerWatermark == watermarkAfterRequest)
    }

    @Test func originatingTransactionEpochIsNilForNonConfirmationEvents() {
        let token = WindowToken(pid: 1, windowId: 2)
        let workspaceId = UUID()
        let cases: [WMEvent] = [
            .windowAdmitted(token: token, workspaceId: workspaceId, monitorId: nil, mode: .tiling, source: .ax),
            .windowRemoved(token: token, workspaceId: workspaceId, source: .ax),
            .activeSpaceChanged(source: .workspaceManager),
            .systemSleep(source: .service),
            .commandIntent(kindForLog: "test", source: .command)
        ]
        for event in cases {
            #expect(event.originatingTransactionEpoch == nil)
        }
    }

    @Test @MainActor func unstampedConfirmationDoesNotAdvanceRunnerWatermark() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        _ = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )
        let watermarkBefore = runtime.currentEffectRunnerWatermark

        let token = WindowToken(pid: 4242, windowId: 9001)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "2",
            createIfMissing: false
        )!
        _ = runtime.submit(
            .managedFocusConfirmed(
                token: token,
                workspaceId: workspaceId,
                monitorId: nil,
                appFullscreen: false,
                source: .ax,
                originatingTransactionEpoch: .invalid
            )
        )

        #expect(runtime.currentEffectRunnerWatermark == watermarkBefore)
    }

    @Test @MainActor func olderFocusConfirmationAfterNewerRequestDoesNotAdvanceRunnerWatermark() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let older = requestFocus(in: runtime, windowId: 31_013)
        let newer = requestFocus(in: runtime, windowId: 31_014)
        let watermarkAfterSecond = runtime.currentEffectRunnerWatermark

        _ = runtime.submit(
            .managedFocusConfirmed(
                token: older.token,
                workspaceId: older.workspaceId,
                monitorId: nil,
                appFullscreen: false,
                source: .ax,
                originatingTransactionEpoch: older.origin
            )
        )

        #expect(runtime.controller.workspaceManager.pendingFocusedToken == newer.token)
        #expect(runtime.controller.workspaceManager.focusedToken != older.token)
        #expect(runtime.currentEffectRunnerWatermark == watermarkAfterSecond)
    }

    @Test @MainActor func externalManagedFocusObservationAdvancesWatermarkAndMutatesState() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 31_001),
            pid: getpid(),
            windowId: 31_001,
            to: workspaceId,
            source: .ax
        )

        let watermarkBefore = runtime.currentEffectRunnerWatermark
        let changed = runtime.observeExternalManagedFocus(
            token,
            in: workspaceId,
            appFullscreen: false,
            activateWorkspaceOnMonitor: false,
            source: .ax
        )

        #expect(changed)
        #expect(runtime.currentEffectRunnerWatermark.value == watermarkBefore.value + 1)

        let txn = runtime.controller.workspaceManager.lastRecordedTransaction
        #expect(txn?.transactionEpoch.isValid == true)
        if case .managedFocusConfirmed = txn?.event {
        } else {
            Issue.record("expected managedFocusConfirmed reconcile event")
        }
    }

    @Test @MainActor func externalManagedFocusSetAdvancesWatermarkOnce() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 31_002),
            pid: getpid(),
            windowId: 31_002,
            to: workspaceId,
            source: .ax
        )

        let watermarkBefore = runtime.currentEffectRunnerWatermark
        _ = runtime.observeExternalManagedFocusSet(
            token,
            in: workspaceId,
            source: .ax
        )
        #expect(runtime.currentEffectRunnerWatermark.value == watermarkBefore.value + 1)
    }

    @Test @MainActor func externalObservationDoesNotInvalidateAlreadyAcceptedConfirmation() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 31_003),
            pid: getpid(),
            windowId: 31_003,
            to: workspaceId,
            source: .ax
        )

        _ = runtime.requestManagedFocus(
            token: token,
            workspaceId: workspaceId,
            source: .command
        )
        guard let earlyOrigin = runtime.controller.focusBridge.originTransactionEpoch(
            forToken: token
        ) else {
            Issue.record("expected runtime-routed focus request to stamp origin epoch")
            return
        }

        let confirmedTxn = runtime.submit(
            .managedFocusConfirmed(
                token: token,
                workspaceId: workspaceId,
                monitorId: nil,
                appFullscreen: false,
                source: .ax,
                originatingTransactionEpoch: earlyOrigin
            )
        )
        #expect(confirmedTxn.transactionEpoch.isValid)

        let snapshotBetween = runtime.controller.workspaceManager.reconcileSnapshot()
        _ = runtime.observeExternalManagedFocus(
            token,
            in: workspaceId,
            appFullscreen: false,
            activateWorkspaceOnMonitor: false,
            source: .ax
        )
        _ = snapshotBetween
    }

    @Test func originatingTransactionEpochThreadsThroughConfirmationCases() {
        let token = WindowToken(pid: 1, windowId: 2)
        let workspaceId = UUID()
        let originating = TransactionEpoch(value: 42)
        let confirmed: WMEvent = .managedFocusConfirmed(
            token: token,
            workspaceId: workspaceId,
            monitorId: nil,
            appFullscreen: false,
            source: .ax,
            originatingTransactionEpoch: originating
        )
        let cancelled: WMEvent = .managedFocusCancelled(
            token: token,
            workspaceId: workspaceId,
            source: .ax,
            originatingTransactionEpoch: originating
        )
        #expect(confirmed.originatingTransactionEpoch == originating)
        #expect(cancelled.originatingTransactionEpoch == originating)
    }
}
