// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct RememberedFocusLogicalIdentityTests {
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
        windowId: Int,
        mode: TrackedWindowMode = .tiling
    ) -> WindowToken {
        manager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceId,
            mode: mode
        )
    }


    @Test @MainActor func rememberFocusStoresLogicalIdAndResolvesBackToCurrentToken() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5001)

        _ = manager.rememberFocus(token, in: workspaceId)

        #expect(manager.lastFocusedToken(in: workspaceId) == token)
    }

    @Test @MainActor func rememberFocusRejectsStaleTokenWithoutWriting() {
        let (manager, workspaceId) = makeManager()
        let originalToken = addWindow(manager, workspaceId: workspaceId, windowId: 5002)
        let newToken = WindowToken(pid: originalToken.pid, windowId: 5003)
        _ = manager.rekeyWindow(
            from: originalToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5003)
        )
        _ = manager.rememberFocus(originalToken, in: workspaceId)

        #expect(manager.lastFocusedToken(in: workspaceId) == nil)
    }


    @Test @MainActor func rekeyPreservesRememberedFocusWithoutTokenRewrite() {
        let (manager, workspaceId) = makeManager()
        let oldToken = addWindow(manager, workspaceId: workspaceId, windowId: 5010)
        _ = manager.rememberFocus(oldToken, in: workspaceId)

        let newToken = WindowToken(pid: oldToken.pid, windowId: 5011)
        _ = manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5011)
        )

        #expect(manager.lastFocusedToken(in: workspaceId) == newToken)
    }

    @Test @MainActor func pingPongRekeyKeepsRememberedFocusStable() {
        let (manager, workspaceId) = makeManager()
        let t1 = addWindow(manager, workspaceId: workspaceId, windowId: 5020)
        _ = manager.rememberFocus(t1, in: workspaceId)

        let t2 = WindowToken(pid: t1.pid, windowId: 5021)
        _ = manager.rekeyWindow(
            from: t1,
            to: t2,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5021)
        )
        #expect(manager.lastFocusedToken(in: workspaceId) == t2)

        _ = manager.rekeyWindow(
            from: t2,
            to: t1,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: t1.windowId)
        )
        #expect(manager.lastFocusedToken(in: workspaceId) == t1)
    }


    @Test @MainActor func retiredWindowHasNoRememberedFocusReadback() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5030)
        _ = manager.rememberFocus(token, in: workspaceId)
        #expect(manager.lastFocusedToken(in: workspaceId) == token)

        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)

        #expect(manager.lastFocusedToken(in: workspaceId) == nil)
    }

    @Test @MainActor func destroyingPreReplacementTokenPurgesRememberedFocusOfLogicalWindow() {
        let (manager, workspaceId) = makeManager()
        let oldToken = addWindow(manager, workspaceId: workspaceId, windowId: 5040)
        _ = manager.rememberFocus(oldToken, in: workspaceId)

        let newToken = WindowToken(pid: oldToken.pid, windowId: 5041)
        _ = manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5041)
        )

        _ = manager.removeWindow(pid: newToken.pid, windowId: newToken.windowId)
        #expect(manager.lastFocusedToken(in: workspaceId) == nil)
    }


    @Test @MainActor func remembersTiledAndFloatingSeparatelyByLogicalId() {
        let (manager, workspaceId) = makeManager()
        let tiled = addWindow(manager, workspaceId: workspaceId, windowId: 5050, mode: .tiling)
        let floating = addWindow(manager, workspaceId: workspaceId, windowId: 5051, mode: .floating)

        _ = manager.rememberFocus(tiled, in: workspaceId)
        _ = manager.rememberFocus(floating, in: workspaceId)

        #expect(manager.lastFocusedToken(in: workspaceId) == tiled)
        #expect(manager.lastFloatingFocusedToken(in: workspaceId) == floating)
    }


    @Test @MainActor func canonicalLogicalIdAccessorReturnsStableIdentity() {
        let (manager, workspaceId) = makeManager()
        let oldToken = addWindow(manager, workspaceId: workspaceId, windowId: 5060)
        _ = manager.rememberFocus(oldToken, in: workspaceId)

        guard let logicalIdBefore = manager.lastFocusedLogicalId(in: workspaceId) else {
            Issue.record("Expected canonical logical id after rememberFocus")
            return
        }

        let newToken = WindowToken(pid: oldToken.pid, windowId: 5061)
        _ = manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 5061)
        )

        #expect(manager.lastFocusedLogicalId(in: workspaceId) == logicalIdBefore)
        #expect(manager.lastFocusedToken(in: workspaceId) == newToken)
    }

    @Test @MainActor func logicalIdAccessorReturnsNilForRetiredIdentity() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5070)
        _ = manager.rememberFocus(token, in: workspaceId)
        #expect(manager.lastFocusedLogicalId(in: workspaceId) != nil)

        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)

        #expect(manager.lastFocusedLogicalId(in: workspaceId) == nil)
        #expect(manager.lastFocusedToken(in: workspaceId) == nil)
    }

    @Test @MainActor func logicalIdAndTokenAccessorsAgreeWhenLive() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5080)
        _ = manager.rememberFocus(token, in: workspaceId)

        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current logical-id binding")
            return
        }

        #expect(manager.lastFocusedLogicalId(in: workspaceId) == logicalId)
        #expect(manager.lastFocusedToken(in: workspaceId) == token)
    }

    @Test @MainActor func floatingLogicalIdAccessorMirrorsTiledShape() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 5090, mode: .floating)
        _ = manager.rememberFocus(token, in: workspaceId)

        guard let logicalId = manager.lastFloatingFocusedLogicalId(in: workspaceId) else {
            Issue.record("Expected floating logical id")
            return
        }
        #expect(manager.lastFloatingFocusedToken(in: workspaceId) == token)
        #expect(manager.lastFocusedLogicalId(in: workspaceId) == nil)
        guard case let .current(registryLogicalId) = manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current binding")
            return
        }
        #expect(logicalId == registryLogicalId)
    }
}
