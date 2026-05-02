// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct QuarantineWiringTests {
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
    private func makeRuntime() -> (WMRuntime, WorkspaceDescriptor.ID) {
        resetSharedControllerStateForTests()
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main),
            WorkspaceConfiguration(name: "2", monitorAssignment: .main)
        ]
        let runtime = WMRuntime(settings: settings)
        runtime.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let workspaceId = runtime.workspaceManager.workspaceId(for: "1", createIfMissing: false)!
        _ = runtime.setActiveWorkspace(
            workspaceId,
            on: runtime.workspaceManager.monitors.first!.id,
            source: .command
        )
        return (runtime, workspaceId)
    }

    @MainActor
    private func addWindow(
        _ manager: WorkspaceManager,
        workspaceId: WorkspaceDescriptor.ID,
        pid: pid_t = 9001,
        windowId: Int
    ) -> WindowToken {
        manager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId),
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
    }

    @MainActor
    private func quarantineState(
        _ manager: WorkspaceManager,
        for token: WindowToken
    ) -> QuarantineState? {
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token) else {
            return nil
        }
        return manager.logicalWindowRegistry.record(for: logicalId)?.quarantine
    }

    private var pendingFrame: FrameState.Frame {
        FrameState.Frame(
            rect: CGRect(x: 20, y: 30, width: 640, height: 480),
            space: .appKit,
            isVisibleFrame: true
        )
    }


    @Test @MainActor func missingBelowThresholdMarksDelayedAdmission() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5001)

        manager.removeMissing(keys: [], requiredConsecutiveMisses: 2)

        #expect(manager.entry(for: token) != nil, "Window should still be tracked below threshold")
        #expect(quarantineState(manager, for: token) == .quarantined(reason: .delayedAdmission))
    }

    @Test @MainActor func reappearanceClearsDelayedAdmission() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5002)

        manager.removeMissing(keys: [], requiredConsecutiveMisses: 2)
        #expect(quarantineState(manager, for: token) == .quarantined(reason: .delayedAdmission))

        manager.removeMissing(keys: [token], requiredConsecutiveMisses: 2)
        #expect(quarantineState(manager, for: token) == .clear)
    }

    @Test @MainActor func confirmedMissingRetiresAndQuarantineBecomesMoot() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5003)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current binding after addWindow")
            return
        }

        manager.removeMissing(keys: [], requiredConsecutiveMisses: 1)

        #expect(manager.entry(for: token) == nil, "Window should be removed at threshold")
        #expect(manager.logicalWindowRegistry.lookup(token: token) == .retired(logicalId))
        let record = manager.logicalWindowRegistry.record(for: logicalId)
        #expect(record?.primaryPhase == .retired)
    }


    @Test @MainActor func staleCGSDestroyMarksRebindedLogicalId() {
        let (manager, workspaceId) = makeManager()
        let oldToken = addWindow(manager, workspaceId: workspaceId, windowId: 5101)

        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: oldToken) else {
            Issue.record("Expected current binding for oldToken")
            return
        }
        let newToken = WindowToken(pid: oldToken.pid, windowId: oldToken.windowId + 1000)
        let rekeyed = manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: newToken.windowId)
        )
        #expect(rekeyed != nil)
        #expect(manager.logicalWindowRegistry.lookup(token: oldToken) == .staleAlias(logicalId))
        #expect(manager.logicalWindowRegistry.lookup(token: newToken) == .current(logicalId))

        let recorded = manager.quarantineStaleCGSDestroyIfApplicable(probeToken: oldToken)
        #expect(recorded == logicalId)
        let record = manager.logicalWindowRegistry.record(for: logicalId)
        #expect(record?.quarantine == .quarantined(reason: .staleCGSDestroy))
        #expect(manager.logicalWindowRegistry.lookup(token: newToken) == .current(logicalId))
    }

    @Test @MainActor func staleCGSDestroyNoOpForCurrentOrUnknownToken() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5102)

        let currentOutcome = manager.quarantineStaleCGSDestroyIfApplicable(probeToken: token)
        #expect(currentOutcome == nil)
        #expect(quarantineState(manager, for: token) == .clear)

        let strangerToken = WindowToken(pid: 7777, windowId: 7777)
        let strangerOutcome = manager.quarantineStaleCGSDestroyIfApplicable(probeToken: strangerToken)
        #expect(strangerOutcome == nil)
    }


    @Test @MainActor func appDisappearedMarksAllSurvivingLogicalIdsForPid() {
        let (manager, workspaceId) = makeManager()
        let pid: pid_t = 9101
        let tokenA = addWindow(manager, workspaceId: workspaceId, pid: pid, windowId: 5201)
        let tokenB = addWindow(manager, workspaceId: workspaceId, pid: pid, windowId: 5202)
        let unrelatedToken = addWindow(manager, workspaceId: workspaceId, pid: 9999, windowId: 5203)

        let quarantined = manager.quarantineWindowsForTerminatedApp(pid: pid)
        #expect(quarantined.count == 2)

        #expect(quarantineState(manager, for: tokenA) == .quarantined(reason: .appDisappeared))
        #expect(quarantineState(manager, for: tokenB) == .quarantined(reason: .appDisappeared))
        #expect(quarantineState(manager, for: unrelatedToken) == .clear)
    }

    @Test @MainActor func appDisappearedNoOpForPidWithNoTrackedWindows() {
        let (manager, _) = makeManager()
        let quarantined = manager.quarantineWindowsForTerminatedApp(pid: 4242)
        #expect(quarantined.isEmpty)
    }


    @Test @MainActor func axOutcomeQuarantinesOnAXErrorFailure() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5301)

        let outcome = manager.applyAXOutcomeQuarantine(
            for: token,
            axFailure: .sizeWriteFailed(.cannotComplete)
        )
        #expect(outcome == .applied)
        #expect(quarantineState(manager, for: token) == .quarantined(reason: .axReadFailure))
    }

    @Test @MainActor func axOutcomeQuarantinesOnStaleElement() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5302)

        _ = manager.applyAXOutcomeQuarantine(for: token, axFailure: .staleElement)
        #expect(quarantineState(manager, for: token) == .quarantined(reason: .axReadFailure))
    }

    @Test @MainActor func axOutcomeClearsOnSuccessfulWrite() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5303)

        _ = manager.applyAXOutcomeQuarantine(for: token, axFailure: .staleElement)
        #expect(quarantineState(manager, for: token) == .quarantined(reason: .axReadFailure))

        _ = manager.applyAXOutcomeQuarantine(for: token, axFailure: nil)
        #expect(quarantineState(manager, for: token) == .clear)
    }

    @Test @MainActor func axOutcomeDoesNotQuarantineOnVerificationMismatch() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5304)

        _ = manager.applyAXOutcomeQuarantine(for: token, axFailure: .verificationMismatch)
        #expect(quarantineState(manager, for: token) == .clear)

        _ = manager.applyAXOutcomeQuarantine(for: token, axFailure: .readbackFailed)
        #expect(quarantineState(manager, for: token) == .clear)
    }

    @Test @MainActor func axOutcomeNoOpForUnknownToken() {
        let (manager, _) = makeManager()
        let strangerToken = WindowToken(pid: 4242, windowId: 4242)
        let outcome = manager.applyAXOutcomeQuarantine(
            for: strangerToken,
            axFailure: .staleElement
        )
        #expect(outcome == nil)
    }

    @Test @MainActor func axOutcomeConfirmationMutatesThroughRuntimeWhenCurrent() {
        let (runtime, workspaceId) = makeRuntime()
        let token = runtime.admitWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5305),
            pid: 9001,
            windowId: 5305,
            to: workspaceId
        )

        let pending = runtime.recordPendingFrameWrite(
            frame: pendingFrame,
            requestId: 5305,
            for: token
        )
        let changed = runtime.submitAXFrameWriteOutcome(
            for: token,
            axFailure: .staleElement,
            originatingTransactionEpoch: pending.transactionEpoch,
            source: .ax
        )

        #expect(changed)
        #expect(quarantineState(runtime.workspaceManager, for: token) == .quarantined(reason: .axReadFailure))
    }

    @Test @MainActor func axOutcomeConfirmationSurvivesUnrelatedRuntimeMutation() {
        let (runtime, workspaceId) = makeRuntime()
        let token = runtime.admitWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5306),
            pid: 9001,
            windowId: 5306,
            to: workspaceId
        )

        let pending = runtime.recordPendingFrameWrite(
            frame: pendingFrame,
            requestId: 5306,
            for: token
        )
        _ = runtime.submit(.activeSpaceChanged(source: .workspaceManager))
        let changed = runtime.submitAXFrameWriteOutcome(
            for: token,
            axFailure: .staleElement,
            originatingTransactionEpoch: pending.transactionEpoch,
            source: .ax
        )

        #expect(changed)
        #expect(quarantineState(runtime.workspaceManager, for: token) == .quarantined(reason: .axReadFailure))
    }

    @Test @MainActor func successfulAXOutcomeRequiresPendingWrite() {
        let (runtime, workspaceId) = makeRuntime()
        let token = runtime.admitWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5310),
            pid: 9001,
            windowId: 5310,
            to: workspaceId
        )
        _ = runtime.workspaceManager.applyAXOutcomeQuarantine(
            for: token,
            axFailure: .staleElement
        )
        #expect(quarantineState(runtime.workspaceManager, for: token) == .quarantined(reason: .axReadFailure))

        let changed = runtime.submitAXFrameWriteOutcome(
            for: token,
            axFailure: nil,
            originatingTransactionEpoch: runtime.currentEffectRunnerWatermark,
            source: .ax
        )

        #expect(!changed)
        #expect(quarantineState(runtime.workspaceManager, for: token) == .quarantined(reason: .axReadFailure))
    }

    @Test @MainActor func successfulAXOutcomeWithPendingWriteSurvivesUnrelatedMutation() {
        let (runtime, workspaceId) = makeRuntime()
        let token = runtime.admitWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5311),
            pid: 9001,
            windowId: 5311,
            to: workspaceId
        )
        _ = runtime.workspaceManager.applyAXOutcomeQuarantine(
            for: token,
            axFailure: .staleElement
        )
        let pending = runtime.recordPendingFrameWrite(
            frame: pendingFrame,
            requestId: 5311,
            for: token
        )
        _ = runtime.submit(.activeSpaceChanged(source: .workspaceManager))

        let changed = runtime.submitAXFrameWriteOutcome(
            for: token,
            axFailure: nil,
            originatingTransactionEpoch: pending.transactionEpoch,
            source: .ax
        )

        #expect(changed)
        #expect(quarantineState(runtime.workspaceManager, for: token) == .clear)
    }

    @Test @MainActor func axOutcomeConfirmationIsRejectedAfterNewerPendingWriteForSameWindow() {
        let (runtime, workspaceId) = makeRuntime()
        let token = runtime.admitWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5307),
            pid: 9001,
            windowId: 5307,
            to: workspaceId
        )

        let olderPending = runtime.recordPendingFrameWrite(
            frame: pendingFrame,
            requestId: 5307,
            for: token
        )
        _ = runtime.recordPendingFrameWrite(
            frame: FrameState.Frame(
                rect: CGRect(x: 40, y: 50, width: 700, height: 500),
                space: .appKit,
                isVisibleFrame: true
            ),
            requestId: 5308,
            for: token
        )
        let changed = runtime.submitAXFrameWriteOutcome(
            for: token,
            axFailure: .staleElement,
            originatingTransactionEpoch: olderPending.transactionEpoch,
            source: .ax
        )

        #expect(!changed)
        #expect(quarantineState(runtime.workspaceManager, for: token) == .clear)
    }

    @Test @MainActor func staleFrameFailureCallbackDoesNotFailNewerPendingWrite() {
        let (runtime, workspaceId) = makeRuntime()
        let controller = runtime.controller
        let token = runtime.admitWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5312),
            pid: 9001,
            windowId: 5312,
            to: workspaceId
        )

        let olderPending = runtime.recordPendingFrameWrite(
            frame: pendingFrame,
            requestId: 5312,
            for: token
        )
        let newerPending = runtime.recordPendingFrameWrite(
            frame: FrameState.Frame(
                rect: CGRect(x: 40, y: 50, width: 700, height: 500),
                space: .appKit,
                isVisibleFrame: true
            ),
            requestId: 5313,
            for: token
        )

        controller.axManager.onFrameFailed?(
            token.pid,
            token.windowId,
            pendingFrame.rect,
            .staleElement,
            olderPending.requestId
        )

        #expect(quarantineState(runtime.workspaceManager, for: token) == .clear)
        #expect(
            runtime.workspaceManager.frameState(for: token)?.write
                == .pending(requestId: newerPending.requestId, since: newerPending.transactionEpoch)
        )
    }

    @Test @MainActor func matchingFrameFailureCallbackFailsCurrentPendingWrite() {
        let (runtime, workspaceId) = makeRuntime()
        let controller = runtime.controller
        let token = runtime.admitWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5314),
            pid: 9001,
            windowId: 5314,
            to: workspaceId
        )

        let pending = runtime.recordPendingFrameWrite(
            frame: pendingFrame,
            requestId: 5314,
            for: token
        )

        controller.axManager.onFrameFailed?(
            token.pid,
            token.windowId,
            pendingFrame.rect,
            .staleElement,
            pending.requestId
        )

        #expect(quarantineState(runtime.workspaceManager, for: token) == .quarantined(reason: .axReadFailure))
        #expect(
            runtime.workspaceManager.frameState(for: token)?.write
                == .failed(reason: .staleElement, attemptedAt: pending.transactionEpoch)
        )
    }

    @Test @MainActor func rejectedObservedFrameConfirmationDoesNotPersistManagedRestoreGeometry() {
        let (runtime, workspaceId) = makeRuntime()
        let controller = runtime.controller
        let token = runtime.admitWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5308),
            pid: 9001,
            windowId: 5308,
            to: workspaceId
        )
        let originalFrame = CGRect(x: 20, y: 30, width: 640, height: 480)
        let olderConfirmedFrame = CGRect(x: 40, y: 50, width: 700, height: 500)
        let newerPendingFrame = CGRect(x: 240, y: 260, width: 760, height: 540)
        _ = controller.workspaceManager.setManagedReplacementMetadata(
            ManagedReplacementMetadata(
                bundleId: "com.example.rejected-observed-frame",
                workspaceId: workspaceId,
                mode: .tiling,
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String,
                title: "Rejected Observed Frame",
                windowLevel: 0,
                parentWindowId: nil,
                frame: originalFrame
            ),
            for: token
        )
        controller.recordManagedRestoreGeometry(for: token, frame: originalFrame)
        #expect(controller.workspaceManager.managedRestoreSnapshot(for: token)?.frame == originalFrame)

        _ = runtime.recordPendingFrameWrite(
            frame: FrameState.Frame(
                rect: olderConfirmedFrame,
                space: .appKit,
                isVisibleFrame: true
            ),
            requestId: 5308,
            for: token
        )
        let newerPending = runtime.recordPendingFrameWrite(
            frame: FrameState.Frame(
                rect: newerPendingFrame,
                space: .appKit,
                isVisibleFrame: true
            ),
            requestId: 5309,
            for: token
        )

        controller.axManager.onFrameConfirmed?(
            token.pid,
            token.windowId,
            olderConfirmedFrame,
            .confirmedWrite,
            5308
        )

        #expect(controller.workspaceManager.managedRestoreSnapshot(for: token)?.frame == originalFrame)
        #expect(
            runtime.workspaceManager.frameState(for: token)?.write
                == .pending(requestId: 5309, since: newerPending.transactionEpoch)
        )
    }

    @Test @MainActor func axOutcomeQuarantineRejectsStaleTokenWrites() {
        let (manager, workspaceId) = makeManager()
        let oldToken = addWindow(manager, workspaceId: workspaceId, windowId: 5401)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: oldToken)
        else {
            Issue.record("Expected current binding")
            return
        }

        let newToken = WindowToken(pid: oldToken.pid, windowId: oldToken.windowId + 5000)
        _ = manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: newToken.windowId)
        )

        #expect(manager.logicalWindowRegistry.record(for: logicalId)?.quarantine == .clear)

        let outcome = manager.applyAXOutcomeQuarantine(
            for: oldToken,
            axFailure: .staleElement
        )
        #expect(outcome == nil)
        #expect(manager.logicalWindowRegistry.record(for: logicalId)?.quarantine == .clear)
    }

    @Test @MainActor func staleCGSDestroyDoesNotSuppressLayoutMembership() {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let manager = WorkspaceManager(settings: settings)
        manager.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let workspaceId = manager.workspaceId(for: "1", createIfMissing: false)!
        _ = manager.setActiveWorkspace(workspaceId, on: manager.monitors.first!.id)

        let oldToken = addWindow(manager, workspaceId: workspaceId, windowId: 5501)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: oldToken)
        else {
            Issue.record("Expected current binding")
            return
        }

        let newToken = WindowToken(pid: oldToken.pid, windowId: oldToken.windowId + 5000)
        _ = manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: newToken.windowId)
        )

        let recorded = manager.quarantineStaleCGSDestroyIfApplicable(probeToken: oldToken)
        #expect(recorded == logicalId)
        #expect(
            manager.logicalWindowRegistry.record(for: logicalId)?.quarantine
                == .quarantined(reason: .staleCGSDestroy)
        )

        let graph = manager.workspaceGraphSnapshot()
        let node = graph.node(for: workspaceId)
        #expect(node?.tiledOrder == [logicalId])
        #expect(node?.suppressed.isEmpty == true)
        #expect(graph.entry(for: logicalId)?.isLayoutEligible == true)
    }
}
