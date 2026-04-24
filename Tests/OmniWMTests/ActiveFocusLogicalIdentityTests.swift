// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct ActiveFocusLogicalIdentityTests {
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


    @Test @MainActor func focusedLogicalIdResolvesFromCurrentBinding() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6201)
        _ = manager.setManagedFocus(token, in: workspaceId)

        guard case let .current(expected) = manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current logical-id binding")
            return
        }
        #expect(manager.focusedLogicalId == expected)
        #expect(manager.focusedToken == token)
    }

    @Test @MainActor func focusedLogicalIdSurvivesRekeyEvenIfStoredTokenLags() {
        let (manager, workspaceId) = makeManager()
        let oldToken = addWindow(manager, workspaceId: workspaceId, windowId: 6202)
        _ = manager.setManagedFocus(oldToken, in: workspaceId)

        guard let logicalIdBefore = manager.focusedLogicalId else {
            Issue.record("Expected focused logical id")
            return
        }

        let newToken = WindowToken(pid: oldToken.pid, windowId: 6203)
        _ = manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 6203)
        )

        #expect(manager.focusedLogicalId == logicalIdBefore)
    }

    @Test @MainActor func focusedLogicalIdReturnsNilForRetiredBinding() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6204)
        _ = manager.setManagedFocus(token, in: workspaceId)
        #expect(manager.focusedLogicalId != nil)

        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)
        #expect(manager.focusedLogicalId == nil)
    }

    @Test @MainActor func focusedLogicalIdNilWhenNoActiveFocus() {
        let (manager, _) = makeManager()
        #expect(manager.focusedLogicalId == nil)
        #expect(manager.focusedToken == nil)
    }


    @Test @MainActor func pendingFocusedLogicalIdResolvesFromCurrentBinding() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6211)
        _ = manager.beginManagedFocusRequest(
            token,
            in: workspaceId,
            onMonitor: nil
        )

        guard case let .current(expected) = manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current logical-id binding")
            return
        }
        #expect(manager.pendingFocusedLogicalId == expected)
        #expect(manager.pendingFocusedToken == token)
    }

    @Test @MainActor func pendingFocusedLogicalIdNilForRetiredBinding() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6212)
        _ = manager.beginManagedFocusRequest(
            token,
            in: workspaceId,
            onMonitor: nil
        )

        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)
        #expect(manager.pendingFocusedLogicalId == nil)
    }

    @Test @MainActor func pendingFocusedLogicalIdNilWhenNoPendingRequest() {
        let (manager, _) = makeManager()
        #expect(manager.pendingFocusedLogicalId == nil)
    }
}
