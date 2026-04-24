// SPDX-License-Identifier: GPL-2.0-only
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

private func makeRuntimeFocusTestDefaults() -> UserDefaults {
    let suiteName = "com.omniwm.runtime-focus.test.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
}

private func makeRuntimeFocusTestMonitor() -> Monitor {
    makeLayoutPlanPrimaryTestMonitor(name: "Main")
}

@MainActor
private func makeRuntimeFocusTestRuntime() -> WMRuntime {
    resetSharedControllerStateForTests()
    let defaults = makeRuntimeFocusTestDefaults()
    let settings = SettingsStore(defaults: defaults)
    settings.workspaceConfigurations = [
        WorkspaceConfiguration(name: "1", monitorAssignment: .main),
        WorkspaceConfiguration(name: "2", monitorAssignment: .main)
    ]
    let runtime = WMRuntime(settings: settings)
    runtime.workspaceManager.applyMonitorConfigurationChange([
        makeRuntimeFocusTestMonitor()
    ])
    return runtime
}

private func makeRuntimeFocusTestWindow(windowId: Int) -> AXWindowRef {
    AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId)
}

@Suite(.serialized) struct RuntimeFocusReducerTests {

    @Test @MainActor func reduceScratchpadHidePersistsRecoveryStateToDurableFocus() {
        let runtime = makeRuntimeFocusTestRuntime()
        let workspaceManager = runtime.workspaceManager
        guard let workspaceId = workspaceManager.workspaceId(
            for: "1",
            createIfMissing: true
        ) else {
            Issue.record("Failed to create workspace")
            return
        }

        let windowId = 12_345
        let token = workspaceManager.addWindow(
            makeRuntimeFocusTestWindow(windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceId
        )
        let monitorId = workspaceManager.monitorId(for: workspaceId)
        _ = workspaceManager.confirmManagedFocus(
            token,
            in: workspaceId,
            onMonitor: monitorId,
            appFullscreen: false,
            activateWorkspaceOnMonitor: true,
            originatingTransactionEpoch: .invalid
        )
        #expect(workspaceManager.focusedToken == token)

        let registry = workspaceManager.logicalWindowRegistry
        guard let hiddenLogicalId = registry.lookup(token: token).liveLogicalId else {
            Issue.record("Failed to resolve logical id for admitted window")
            return
        }

        let baseline = runtime.currentEffectRunnerWatermark
        let action = runtime.reduceScratchpadHide(
            hiddenLogicalId: hiddenLogicalId,
            wasFocused: true,
            recoveryCandidate: nil,
            workspaceId: workspaceId,
            monitorId: monitorId
        )
        #expect(action != nil)
        guard let recorded = workspaceManager.lastRecordedTransaction else {
            Issue.record("Expected scratchpad hide reducer to record a transaction")
            return
        }
        #expect(recorded.transactionEpoch > baseline)
        #expect(recorded.transactionEpoch == runtime.currentEffectRunnerWatermark)
        #expect(recorded.isCompleted)
        #expect(recorded.snapshot == workspaceManager.reconcileSnapshot())
        guard case let .commandIntent(kindForLog, source) = recorded.event else {
            Issue.record("Expected scratchpad hide reducer transaction to be commandIntent")
            return
        }
        #expect(kindForLog == "focus_reducer")
        #expect(source == .focusPolicy)

        let durableState = workspaceManager.storedFocusStateSnapshot
        guard case let .recovering(reason, _) = durableState.activation else {
            Issue.record("Expected durable activation .recovering, got \(durableState.activation)")
            return
        }
        #expect(reason == .scratchpadHide)
    }

    @Test @MainActor func reduceScratchpadHideWithRecoveryCandidatePersistsDesiredAndRecovery() {
        let runtime = makeRuntimeFocusTestRuntime()
        let workspaceManager = runtime.workspaceManager
        guard let workspaceId = workspaceManager.workspaceId(
            for: "1",
            createIfMissing: true
        ) else {
            Issue.record("Failed to create workspace")
            return
        }
        let monitorId = workspaceManager.monitorId(for: workspaceId)

        let hiddenWindowId = 24_001
        let recoveryWindowId = 24_002
        let hiddenToken = workspaceManager.addWindow(
            makeRuntimeFocusTestWindow(windowId: hiddenWindowId),
            pid: getpid(),
            windowId: hiddenWindowId,
            to: workspaceId
        )
        let recoveryToken = workspaceManager.addWindow(
            makeRuntimeFocusTestWindow(windowId: recoveryWindowId),
            pid: getpid(),
            windowId: recoveryWindowId,
            to: workspaceId
        )
        _ = workspaceManager.confirmManagedFocus(
            hiddenToken,
            in: workspaceId,
            onMonitor: monitorId,
            appFullscreen: false,
            activateWorkspaceOnMonitor: true,
            originatingTransactionEpoch: .invalid
        )

        let registry = workspaceManager.logicalWindowRegistry
        guard let hiddenLogicalId = registry.lookup(token: hiddenToken).liveLogicalId,
              let recoveryLogicalId = registry.lookup(token: recoveryToken).liveLogicalId else {
            Issue.record("Failed to resolve logical ids")
            return
        }

        let action = runtime.reduceScratchpadHide(
            hiddenLogicalId: hiddenLogicalId,
            wasFocused: true,
            recoveryCandidate: recoveryLogicalId,
            workspaceId: workspaceId,
            monitorId: monitorId
        )
        #expect(action == .requestFocus(recoveryLogicalId, workspaceId: workspaceId))

        let durableState = workspaceManager.storedFocusStateSnapshot
        #expect(durableState.desired == .logical(recoveryLogicalId, workspaceId: workspaceId))
        guard case .recovering = durableState.activation else {
            Issue.record("Expected durable activation .recovering, got \(durableState.activation)")
            return
        }
    }

    @Test @MainActor func reduceScratchpadHideOfNonFocusedWindowDoesNotMutateDurableState() {
        let runtime = makeRuntimeFocusTestRuntime()
        let workspaceManager = runtime.workspaceManager
        guard let workspaceId = workspaceManager.workspaceId(
            for: "1",
            createIfMissing: true
        ) else {
            Issue.record("Failed to create workspace")
            return
        }
        let stateBefore = workspaceManager.storedFocusStateSnapshot
        let logicalId = LogicalWindowId(value: 9_999)

        let action = runtime.reduceScratchpadHide(
            hiddenLogicalId: logicalId,
            wasFocused: false,
            recoveryCandidate: nil,
            workspaceId: workspaceId,
            monitorId: nil
        )
        #expect(action == nil)
        #expect(workspaceManager.storedFocusStateSnapshot == stateBefore)
    }


    @Test @MainActor func resolveAndSetWorkspaceFocusReturnsRememberedTokenWithoutMutatingFocus() {
        let runtime = makeRuntimeFocusTestRuntime()
        let workspaceManager = runtime.workspaceManager
        guard let workspaceId = workspaceManager.workspaceId(
            for: "1",
            createIfMissing: true
        ) else {
            Issue.record("Failed to create workspace")
            return
        }

        let windowId = 30_001
        let token = workspaceManager.addWindow(
            makeRuntimeFocusTestWindow(windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceId
        )
        _ = workspaceManager.rememberFocus(token, in: workspaceId)
        #expect(workspaceManager.focusedToken == nil)

        let resolved = runtime.resolveAndSetWorkspaceFocusToken(
            in: workspaceId,
            onMonitor: workspaceManager.monitorId(for: workspaceId),
            source: .focusPolicy
        )
        #expect(resolved == token)

        #expect(workspaceManager.lastFocusedToken(in: workspaceId) == token)
        #expect(workspaceManager.focusedToken == nil)
    }


    @Test @MainActor func applyResolvedWorkspaceFocusClearMirrorPendingAndConfirmedClearsConfirmedFocus() {
        let runtime = makeRuntimeFocusTestRuntime()
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

        let windowId = 32_001
        let token = workspaceManager.addWindow(
            makeRuntimeFocusTestWindow(windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceId
        )
        _ = workspaceManager.setManagedFocus(token, in: workspaceId, onMonitor: monitorId)
        #expect(workspaceManager.focusedToken == token)

        let changed = workspaceManager.applyResolvedWorkspaceFocusClearMirror(
            in: workspaceId,
            scope: .pendingAndConfirmed
        )
        #expect(changed)
        #expect(workspaceManager.focusedToken == nil)
    }

    @Test @MainActor func applyResolvedWorkspaceFocusClearMirrorPendingAndConfirmedDoesNotClearOtherWorkspaceFocus() {
        let runtime = makeRuntimeFocusTestRuntime()
        let workspaceManager = runtime.workspaceManager
        guard let workspaceA = workspaceManager.workspaceId(for: "1", createIfMissing: true),
              let workspaceB = workspaceManager.workspaceId(for: "2", createIfMissing: true) else {
            Issue.record("Failed to create workspaces")
            return
        }
        let monitorId = workspaceManager.monitorId(for: workspaceA)
        if let monitorId {
            _ = workspaceManager.setActiveWorkspace(workspaceB, on: monitorId)
        }

        let windowId = 33_001
        let tokenB = workspaceManager.addWindow(
            makeRuntimeFocusTestWindow(windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceB
        )
        _ = workspaceManager.setManagedFocus(tokenB, in: workspaceB, onMonitor: monitorId)
        #expect(workspaceManager.focusedToken == tokenB)

        _ = workspaceManager.applyResolvedWorkspaceFocusClearMirror(
            in: workspaceA,
            scope: .pendingAndConfirmed
        )
        #expect(workspaceManager.focusedToken == tokenB)
    }

    @Test @MainActor func applyResolvedWorkspaceFocusClearMirrorNoneIsNoOp() {
        let runtime = makeRuntimeFocusTestRuntime()
        let workspaceManager = runtime.workspaceManager
        guard let workspaceId = workspaceManager.workspaceId(
            for: "1",
            createIfMissing: true
        ) else {
            Issue.record("Failed to create workspace")
            return
        }
        let stateBefore = workspaceManager.storedFocusStateSnapshot
        let changed = workspaceManager.applyResolvedWorkspaceFocusClearMirror(
            in: workspaceId,
            scope: .none
        )
        #expect(!changed)
        #expect(workspaceManager.storedFocusStateSnapshot == stateBefore)
    }
}
