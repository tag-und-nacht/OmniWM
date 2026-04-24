// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct BorderFollowsFocusStateTests {
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

    @Test @MainActor func observedTokenMirrorsFocusedToken() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7301)
        _ = manager.setManagedFocus(token, in: workspaceId)
        let projection = manager.focusStateProjection
        #expect(projection.observedToken == token)
    }

    @Test @MainActor func observedTokenIsNilWithoutFocus() {
        let (manager, _) = makeManager()
        #expect(manager.focusStateProjection.observedToken == nil)
    }

    @Test @MainActor func observedTokenSurvivesRekey() {
        let (manager, workspaceId) = makeManager()
        let oldToken = addWindow(manager, workspaceId: workspaceId, windowId: 7302)
        _ = manager.setManagedFocus(oldToken, in: workspaceId)
        let logicalIdBefore = manager.focusedLogicalId

        let newToken = WindowToken(pid: oldToken.pid, windowId: 7303)
        _ = manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 7303)
        )
        #expect(manager.focusedLogicalId == logicalIdBefore)
    }

    @Test @MainActor func desiredFocusReflectsConfirmedWindow() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7304)
        _ = manager.setManagedFocus(token, in: workspaceId)
        let projection = manager.focusStateProjection
        if case let .logical(id, ws) = projection.desired {
            #expect(id == manager.focusedLogicalId)
            #expect(ws == workspaceId)
        } else {
            Issue.record("Expected desired = .logical after confirmed focus")
        }
    }

    @Test @MainActor func projectionReturnsIdleAfterRetirement() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7305)
        _ = manager.setManagedFocus(token, in: workspaceId)
        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)
        let projection = manager.focusStateProjection
        #expect(manager.focusedLogicalId == nil)
        #expect(projection.desired == .none)
    }
}
