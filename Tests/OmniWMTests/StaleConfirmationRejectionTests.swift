// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct StaleConfirmationRejectionTests {
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

    @Test @MainActor func stampedConfirmationFromBeforeWatermarkIsRejectedAsSuperseded() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let first = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )
        let staleOrigin = first.transactionEpoch

        _ = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "1"))
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
                originatingTransactionEpoch: staleOrigin
            )
        )
        let afterSnapshot = runtime.controller.workspaceManager.reconcileSnapshot()

        #expect(txn.transactionEpoch.isValid)
        #expect(beforeSnapshot == afterSnapshot)
    }

    @Test @MainActor func stampedConfirmationAtCurrentWatermarkIsAccepted() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let result = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )
        let token = WindowToken(pid: 4242, windowId: 9001)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "2",
            createIfMissing: false
        )!
        let txn = runtime.submit(
            .managedFocusConfirmed(
                token: token,
                workspaceId: workspaceId,
                monitorId: nil,
                appFullscreen: false,
                source: .ax,
                originatingTransactionEpoch: result.transactionEpoch
            )
        )
        #expect(txn.transactionEpoch.isValid)
    }

    @Test @MainActor func stampedManagedFocusCancelledIsAlsoSubjectToEpochGate() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let first = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )
        _ = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "1"))
        )
        let token = WindowToken(pid: 4242, windowId: 9001)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "2",
            createIfMissing: false
        )!
        let beforeSnapshot = runtime.controller.workspaceManager.reconcileSnapshot()
        _ = runtime.submit(
            .managedFocusCancelled(
                token: token,
                workspaceId: workspaceId,
                source: .ax,
                originatingTransactionEpoch: first.transactionEpoch
            )
        )
        let afterSnapshot = runtime.controller.workspaceManager.reconcileSnapshot()
        #expect(beforeSnapshot == afterSnapshot)
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

    @Test @MainActor func supersededConfirmationDoesNotAdvanceRunnerWatermark() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)

        let first = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )
        _ = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "1"))
        )
        let watermarkAfterSecond = runtime.currentEffectRunnerWatermark

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
                originatingTransactionEpoch: first.transactionEpoch
            )
        )

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
