// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct FrameReducerProductionRoutingTests {
    @MainActor
    private func makeManager() -> (WorkspaceManager, WorkspaceDescriptor.ID) {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let manager = WorkspaceManager(settings: settings)
        manager.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let workspaceId = manager.workspaceId(for: "1", createIfMissing: false)!
        _ = manager.setActiveWorkspace(workspaceId, on: manager.monitors.first!.id)
        return (manager, workspaceId)
    }

    @MainActor
    private func addWindow(
        _ manager: WorkspaceManager,
        workspaceId: WorkspaceDescriptor.ID,
        windowId: Int
    ) -> WindowToken {
        manager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceId
        )
    }

    private let desired = FrameState.Frame(
        rect: CGRect(x: 100, y: 100, width: 800, height: 600),
        space: .appKit,
        isVisibleFrame: true
    )
    private let observedExact = FrameState.Frame(
        rect: CGRect(x: 100, y: 100, width: 800, height: 600),
        space: .appKit,
        isVisibleFrame: true
    )
    private let observedDrift = FrameState.Frame(
        rect: CGRect(x: 200, y: 200, width: 800, height: 600),
        space: .appKit,
        isVisibleFrame: true
    )

    @Test @MainActor func recordDesiredFrameWritesDesiredSlot() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 8101)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id for fresh admission")
            return
        }
        let applied = manager.recordDesiredFrame(desired, for: token)
        #expect(applied)

        let viaReducer = FrameReducer.reduce(
            state: .initial,
            event: .desiredFrameRequested(desired)
        )
        #expect(manager.frameState(for: logicalId) == viaReducer.nextState)
        #expect(manager.frameState(for: logicalId)?.desired == desired)
    }

    @Test @MainActor func recordPendingFrameWriteWritesPendingAndStatus() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 8102)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id")
            return
        }
        _ = manager.recordDesiredFrame(desired, for: token)
        let requestId: AXFrameRequestId = 42
        let epoch = TransactionEpoch(value: 7)
        let applied = manager.recordPendingFrameWrite(
            desired,
            requestId: requestId,
            since: epoch,
            for: token
        )
        #expect(applied)

        let state = manager.frameState(for: logicalId)
        #expect(state?.pending == desired)
        #expect(state?.write == .pending(requestId: requestId, since: epoch))
        #expect(state?.hasPendingWrite == true)

        var expected = FrameState.initial
        let r1 = FrameReducer.reduce(state: expected, event: .desiredFrameRequested(desired))
        expected = r1.nextState
        let r2 = FrameReducer.reduce(
            state: expected,
            event: .pendingFrameWriteEmitted(desired, requestId: requestId, since: epoch)
        )
        expected = r2.nextState
        #expect(state == expected)
    }

    @Test @MainActor func observedFrameWithinTolerancePromotesToConfirmed() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 8103)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id")
            return
        }
        _ = manager.recordDesiredFrame(desired, for: token)
        _ = manager.recordPendingFrameWrite(
            desired,
            requestId: 1,
            since: TransactionEpoch(value: 1),
            for: token
        )
        _ = manager.recordObservedFrame(observedExact, for: token)

        let state = manager.frameState(for: logicalId)
        #expect(state?.confirmed == observedExact)
        #expect(state?.observed == observedExact)
        #expect(state?.pending == nil)
        #expect(state?.write == .idle)
    }

    @Test @MainActor func observedMismatchDoesNotPromoteAndPreservesPending() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 8104)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id")
            return
        }
        _ = manager.recordDesiredFrame(desired, for: token)
        _ = manager.recordPendingFrameWrite(
            desired,
            requestId: 5,
            since: TransactionEpoch(value: 3),
            for: token
        )
        _ = manager.recordObservedFrame(observedDrift, for: token)

        let state = manager.frameState(for: logicalId)
        #expect(state?.confirmed == nil)
        #expect(state?.observed == observedDrift)
        #expect(state?.desired == desired)
        #expect(state?.pending == desired)
        #expect(state?.write == .pending(requestId: 5, since: TransactionEpoch(value: 3)))
    }

    @Test @MainActor func recordFailedFrameWriteRecordsStatusAndKeepsPending() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 8105)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id")
            return
        }
        _ = manager.recordDesiredFrame(desired, for: token)
        _ = manager.recordPendingFrameWrite(
            desired,
            requestId: 9,
            since: TransactionEpoch(value: 11),
            for: token
        )
        let attemptedAt = TransactionEpoch(value: 12)
        let applied = manager.recordFailedFrameWrite(
            reason: .verificationMismatch,
            attemptedAt: attemptedAt,
            for: token
        )
        #expect(applied)

        let state = manager.frameState(for: logicalId)
        #expect(state?.write == .failed(reason: .verificationMismatch, attemptedAt: attemptedAt))
        #expect(state?.pending == desired)
        #expect(state?.desired == desired)
        #expect(state?.hasFailedWrite == true)
    }

    @Test @MainActor func captureRestorableCapturesConfirmedOnly() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 8106)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id")
            return
        }
        _ = manager.recordObservedFrame(observedExact, for: token)
        var captured = manager.captureRestorableFrame(for: logicalId)
        #expect(captured == false)
        #expect(manager.frameState(for: logicalId)?.restorable == nil)

        _ = manager.recordDesiredFrame(desired, for: token)
        _ = manager.recordObservedFrame(observedExact, for: token)
        #expect(manager.frameState(for: logicalId)?.confirmed == observedExact)

        captured = manager.captureRestorableFrame(for: logicalId)
        #expect(captured == true)
        #expect(manager.frameState(for: logicalId)?.restorable == observedExact)
    }

    @Test @MainActor func mutatorsReturnFalseForRetiredOrUnknownToken() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 8107)
        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)

        #expect(manager.recordDesiredFrame(desired, for: token) == false)
        #expect(manager.recordObservedFrame(observedExact, for: token) == false)
        #expect(
            manager.recordPendingFrameWrite(
                desired,
                requestId: 1,
                since: TransactionEpoch(value: 1),
                for: token
            ) == false
        )
        #expect(
            manager.recordFailedFrameWrite(
                reason: .cancelled,
                attemptedAt: TransactionEpoch(value: 1),
                for: token
            ) == false
        )
    }
}
