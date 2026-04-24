// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct FocusConfirmationStampingTests {
    @Test @MainActor func originEpochIsRecordedWhenRuntimeRequestsFocus() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 12_345),
            pid: getpid(),
            windowId: 12_345,
            to: workspaceId,
            source: .ax
        )

        _ = runtime.requestManagedFocus(token: token, workspaceId: workspaceId, source: .ax)

        let recordedEpoch = runtime.controller.focusBridge.originTransactionEpoch(forToken: token)
        #expect(recordedEpoch != nil)
        #expect(recordedEpoch?.isValid == true)
    }

    @Test @MainActor func ipcFocusRequestPreservesSourceOnManagedFocusTransaction() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 12_346),
            pid: getpid(),
            windowId: 12_346,
            to: workspaceId,
            source: .ax
        )

        runtime.controller.focusWindow(token, source: .ipc)

        let txn = runtime.controller.workspaceManager.lastRecordedTransaction
        guard case let .managedFocusRequested(_, _, _, source) = txn?.event else {
            Issue.record("expected managedFocusRequested transaction")
            return
        }
        #expect(source == .ipc)
    }

    @Test @MainActor func runtimeFocusConfirmationRecordsStampedTransaction() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 23_456),
            pid: getpid(),
            windowId: 23_456,
            to: workspaceId,
            source: .ax
        )

        _ = runtime.observeExternalManagedFocus(
            token,
            in: workspaceId,
            appFullscreen: false,
            activateWorkspaceOnMonitor: false,
            source: .ax
        )

        let txn = runtime.controller.workspaceManager.lastRecordedTransaction
        #expect(txn?.transactionEpoch.isValid == true)
        if case .managedFocusConfirmed = txn?.event {
        } else {
            Issue.record("expected managedFocusConfirmed transaction")
        }
    }

    @Test @MainActor func focusBridgeOriginMapReturnsNilForUnrequestedToken() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let unrequestedToken = WindowToken(pid: 99999, windowId: 55555)
        #expect(
            runtime.controller.focusBridge.originTransactionEpoch(forToken: unrequestedToken) == nil
        )
    }

    @Test @MainActor func stampedConfirmationPastRunnerWatermarkIsRejected() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let token = WindowToken(pid: 4242, windowId: 9001)
        let stampEpoch = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "1"))
        ).transactionEpoch
        _ = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "2"))
        )

        let beforeSnapshot = runtime.controller.workspaceManager.reconcileSnapshot()
        _ = runtime.submit(
            .managedFocusConfirmed(
                token: token,
                workspaceId: workspaceId,
                monitorId: nil,
                appFullscreen: false,
                source: .ax,
                originatingTransactionEpoch: stampEpoch
            )
        )
        let afterSnapshot = runtime.controller.workspaceManager.reconcileSnapshot()
        #expect(beforeSnapshot == afterSnapshot)
    }

    @Test @MainActor func cancellingRequestAlsoCleansUpOriginEpoch() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 77_777),
            pid: getpid(),
            windowId: 77_777,
            to: workspaceId,
            source: .ax
        )
        _ = runtime.requestManagedFocus(token: token, workspaceId: workspaceId, source: .ax)
        #expect(runtime.controller.focusBridge.originTransactionEpoch(forToken: token) != nil)

        _ = runtime.controller.focusBridge.cancelManagedRequest(
            matching: token,
            workspaceId: workspaceId
        )
        #expect(runtime.controller.focusBridge.originTransactionEpoch(forToken: token) == nil)
    }

    @Test func isConfirmationFlavoredClassifiesCorrectly() {
        let token = WindowToken(pid: 1, windowId: 2)
        let workspaceId = UUID()
        #expect(
            WMEvent.managedFocusConfirmed(
                token: token, workspaceId: workspaceId, monitorId: nil,
                appFullscreen: false, source: .ax,
                originatingTransactionEpoch: .invalid
            ).isConfirmationFlavored
        )
        #expect(
            WMEvent.managedFocusCancelled(
                token: token, workspaceId: workspaceId, source: .ax,
                originatingTransactionEpoch: .invalid
            ).isConfirmationFlavored
        )
        #expect(
            !WMEvent.windowAdmitted(
                token: token, workspaceId: workspaceId, monitorId: nil,
                mode: .tiling, source: .ax
            ).isConfirmationFlavored
        )
        #expect(
            !WMEvent.managedFocusRequested(
                token: token, workspaceId: workspaceId, monitorId: nil,
                source: .ax
            ).isConfirmationFlavored
        )
    }
}
