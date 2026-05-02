// SPDX-License-Identifier: GPL-2.0-only
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

private func makeActivationFailureTestDefaults() -> UserDefaults {
    let suiteName = "com.omniwm.activation-failure.test.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
}

@MainActor
private func makeActivationFailureTestRuntime() -> WMRuntime {
    resetSharedControllerStateForTests()
    let settings = SettingsStore(defaults: makeActivationFailureTestDefaults())
    settings.workspaceConfigurations = [
        WorkspaceConfiguration(name: "1", monitorAssignment: .main),
    ]
    let runtime = WMRuntime(settings: settings)
    runtime.workspaceManager.applyMonitorConfigurationChange([
        makeLayoutPlanPrimaryTestMonitor(name: "Main"),
    ])
    return runtime
}

private func makeActivationFailureWindow(windowId: Int) -> AXWindowRef {
    AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId)
}

@Suite(.serialized) struct ActivationFailureRecoveryTests {

    @Test @MainActor func missingFocusedWindowDeferralRecordsRecoveryWithReason() {
        let runtime = makeActivationFailureTestRuntime()
        let workspaceManager = runtime.workspaceManager
        let token = WindowToken(pid: 4_001, windowId: 41_001)

        runtime.recordActivationFailure(
            reason: .missingFocusedWindow,
            requestId: 7,
            token: token,
            source: .ax
        )

        let state = workspaceManager.storedFocusStateSnapshot
        guard case let .recovering(reason, _) = state.activation else {
            Issue.record("Expected .recovering, got \(state.activation)")
            return
        }
        #expect(reason == .activationFailure(reason: .missingFocusedWindow))
        #expect(state.lastFailureReason == .missingFocusedWindow)
    }

    @Test @MainActor func pendingFocusMismatchAndUnmanagedTokenMapToDistinctReasons() {
        let runtime = makeActivationFailureTestRuntime()
        let workspaceManager = runtime.workspaceManager

        runtime.recordActivationFailure(
            reason: .pendingFocusMismatch,
            requestId: 1,
            token: WindowToken(pid: 1, windowId: 1),
            source: .ax
        )
        let mismatch = workspaceManager.storedFocusStateSnapshot
        if case let .recovering(reason, _) = mismatch.activation {
            #expect(reason == .activationFailure(reason: .pendingFocusMismatch))
        } else {
            Issue.record("Expected .recovering(.pendingFocusMismatch)")
        }

        runtime.recordActivationFailure(
            reason: .pendingFocusUnmanagedToken,
            requestId: 2,
            token: WindowToken(pid: 1, windowId: 2),
            source: .ax
        )
        let unmanaged = workspaceManager.storedFocusStateSnapshot
        if case let .recovering(reason, _) = unmanaged.activation {
            #expect(reason == .activationFailure(reason: .pendingFocusUnmanagedToken))
        } else {
            Issue.record("Expected .recovering(.pendingFocusUnmanagedToken)")
        }
        #expect(unmanaged.lastFailureReason == .pendingFocusUnmanagedToken)
    }


    @Test @MainActor func deferralPreservesDesiredAndActiveManagedRequest() {
        let runtime = makeActivationFailureTestRuntime()
        let workspaceManager = runtime.workspaceManager
        guard let workspaceId = workspaceManager.workspaceId(
            for: "1",
            createIfMissing: true
        ) else {
            Issue.record("Failed to create workspace")
            return
        }
        let monitorId = workspaceManager.monitorId(for: workspaceId)
        if let monitorId {
            _ = workspaceManager.setActiveWorkspace(workspaceId, on: monitorId)
        }
        let token = workspaceManager.addWindow(
            makeActivationFailureWindow(windowId: 51_001),
            pid: getpid(),
            windowId: 51_001,
            to: workspaceId
        )
        _ = workspaceManager.setManagedFocus(token, in: workspaceId, onMonitor: monitorId)
        let activeRequest = ManagedFocusRequest(
            requestId: 42,
            token: token,
            workspaceId: workspaceId
        )
        runtime.controller.focusBridge.applyOrchestrationState(
            nextManagedRequestId: 43,
            activeManagedRequest: activeRequest
        )
        let before = workspaceManager.storedFocusStateSnapshot
        let desiredBefore = before.desired

        runtime.recordActivationFailure(
            reason: .pendingFocusMismatch,
            requestId: activeRequest.requestId,
            token: activeRequest.token,
            source: .ax
        )

        let after = workspaceManager.storedFocusStateSnapshot
        #expect(after.desired == desiredBefore)
        #expect(after.isRecovering)
        #expect(runtime.controller.focusBridge.activeManagedRequest != nil)
        #expect(runtime.controller.focusBridge.activeManagedRequest?.requestId
            == activeRequest.requestId)
    }


    @Test @MainActor func laterObservationExitsRecoveryWithoutTimer() {
        let runtime = makeActivationFailureTestRuntime()
        let workspaceManager = runtime.workspaceManager
        let token = WindowToken(pid: 6_001, windowId: 61_001)

        runtime.recordActivationFailure(
            reason: .missingFocusedWindow,
            requestId: 13,
            token: token,
            source: .ax
        )
        #expect(workspaceManager.storedFocusStateSnapshot.isRecovering)

        runtime.recordFocusObservationSettled(token)

        let after = workspaceManager.storedFocusStateSnapshot
        #expect(!after.isRecovering)
        if case .confirmed = after.activation {
        } else {
            Issue.record("Expected .confirmed activation, got \(after.activation)")
        }
        #expect(after.observedToken == token)
        #expect(after.lastFailureReason == nil)
    }


    @Test @MainActor func retryExhaustionRecordsTerminalRecovery() {
        let runtime = makeActivationFailureTestRuntime()
        let workspaceManager = runtime.workspaceManager
        let token = WindowToken(pid: 7_001, windowId: 71_001)

        runtime.recordActivationFailure(
            reason: .retryExhausted,
            requestId: 99,
            token: token,
            source: .ax
        )

        let state = workspaceManager.storedFocusStateSnapshot
        guard case let .recovering(reason, _) = state.activation else {
            Issue.record("Expected .recovering, got \(state.activation)")
            return
        }
        #expect(reason == .activationFailure(reason: .retryExhausted))
        #expect(state.lastFailureReason == .retryExhausted)
    }
}
