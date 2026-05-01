// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct WorkspaceGraphLayoutSwitchTests {
    @MainActor
    private struct Fixture {
        let controller: WMController
        let workspaceA: WorkspaceDescriptor.ID
        let workspaceB: WorkspaceDescriptor.ID
        let workspaceAName: String
        let workspaceBName: String
        let primary: Monitor
        let secondary: Monitor

        var workspaceManager: WorkspaceManager { controller.workspaceManager }
        var settings: SettingsStore { controller.settings }
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let primary = makeLayoutPlanPrimaryTestMonitor(name: "Primary")
        let secondary = makeLayoutPlanSecondaryTestMonitor(name: "Secondary", x: 1920)
        let controller = makeLayoutPlanTestController(
            monitors: [primary, secondary],
            workspaceConfigurations: [
                WorkspaceConfiguration(name: "1", monitorAssignment: .main),
                WorkspaceConfiguration(name: "2", monitorAssignment: .secondary)
            ]
        )
        let workspaceA = controller.workspaceManager.workspaceId(for: "1", createIfMissing: false)!
        let workspaceB = controller.workspaceManager.workspaceId(for: "2", createIfMissing: false)!
        _ = controller.workspaceManager.setActiveWorkspace(workspaceA, on: primary.id)
        _ = controller.workspaceManager.setActiveWorkspace(workspaceB, on: secondary.id)
        return Fixture(
            controller: controller,
            workspaceA: workspaceA,
            workspaceB: workspaceB,
            workspaceAName: "1",
            workspaceBName: "2",
            primary: primary,
            secondary: secondary
        )
    }

    @MainActor
    private func setLayout(
        _ fixture: Fixture,
        workspaceName: String,
        to layout: LayoutType
    ) {
        guard let runtime = fixture.controller.runtime else {
            Issue.record("Expected runtime for layout switch fixture")
            return
        }
        _ = runtime.controllerOperations.setWorkspaceLayout(
            layout,
            forWorkspaceNamed: workspaceName
        )
    }

    @MainActor
    private func currentLayout(_ fixture: Fixture, named name: String) -> LayoutType {
        fixture.settings.layoutType(for: name)
    }

    @Test @MainActor func settingLayoutPreservesTiledLogicalIdSet() {
        let f = makeFixture()
        let token1 = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 9001)
        let token2 = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 9002)

        let pre = f.workspaceManager.workspaceGraphSnapshot()
        let preTiled = Set(pre.node(for: f.workspaceA)?.tiledOrder ?? [])
        #expect(!preTiled.isEmpty)

        let target: LayoutType = currentLayout(f, named: f.workspaceAName) == .dwindle ? .niri : .dwindle
        setLayout(f, workspaceName: f.workspaceAName, to: target)

        let post = f.workspaceManager.workspaceGraphSnapshot()
        let postTiled = Set(post.node(for: f.workspaceA)?.tiledOrder ?? [])
        #expect(preTiled == postTiled)
        #expect(post.node(for: f.workspaceA)?.layoutType == target)
        for token in [token1, token2] {
            #expect(f.workspaceManager.logicalWindowRegistry.lookup(token: token).isCurrent)
        }
    }

    @Test @MainActor func settingLayoutPreservesFloatingLogicalIdSet() {
        let f = makeFixture()
        _ = f.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 9010),
            pid: getpid(),
            windowId: 9010,
            to: f.workspaceA,
            mode: .floating
        )
        _ = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 9011)

        let pre = f.workspaceManager.workspaceGraphSnapshot()
        let preFloating = Set(pre.node(for: f.workspaceA)?.floating ?? [])
        let preTiled = Set(pre.node(for: f.workspaceA)?.tiledOrder ?? [])
        #expect(preFloating.count == 1)
        #expect(preTiled.count == 1)

        let target: LayoutType = currentLayout(f, named: f.workspaceAName) == .dwindle ? .niri : .dwindle
        setLayout(f, workspaceName: f.workspaceAName, to: target)

        let post = f.workspaceManager.workspaceGraphSnapshot()
        #expect(Set(post.node(for: f.workspaceA)?.floating ?? []) == preFloating)
        #expect(Set(post.node(for: f.workspaceA)?.tiledOrder ?? []) == preTiled)
    }

    @Test @MainActor func settingLayoutPreservesFocusProjection() {
        let f = makeFixture()
        let focused = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 9020)
        _ = f.workspaceManager.setManagedFocus(
            focused,
            in: f.workspaceA,
            onMonitor: f.primary.id
        )

        let pre = f.workspaceManager.workspaceGraphSnapshot()
        let preFocused = pre.node(for: f.workspaceA)?.focusedLogicalId
        let preLastTiled = pre.node(for: f.workspaceA)?.lastTiledFocusedLogicalId
        #expect(preFocused != nil)

        let target: LayoutType = currentLayout(f, named: f.workspaceAName) == .dwindle ? .niri : .dwindle
        setLayout(f, workspaceName: f.workspaceAName, to: target)

        let post = f.workspaceManager.workspaceGraphSnapshot()
        #expect(post.node(for: f.workspaceA)?.focusedLogicalId == preFocused)
        #expect(post.node(for: f.workspaceA)?.lastTiledFocusedLogicalId == preLastTiled)
    }

    @Test @MainActor func settingLayoutPreservesMonitorAssignment() {
        let f = makeFixture()
        _ = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 9030)

        let pre = f.workspaceManager.workspaceGraphSnapshot()
        let preAssignmentA = pre.node(for: f.workspaceA)?.monitorId
        let preAssignmentB = pre.node(for: f.workspaceB)?.monitorId
        #expect(preAssignmentA == f.primary.id)
        #expect(preAssignmentB == f.secondary.id)

        let target: LayoutType = currentLayout(f, named: f.workspaceAName) == .dwindle ? .niri : .dwindle
        setLayout(f, workspaceName: f.workspaceAName, to: target)

        let post = f.workspaceManager.workspaceGraphSnapshot()
        #expect(post.node(for: f.workspaceA)?.monitorId == preAssignmentA)
        #expect(post.node(for: f.workspaceB)?.monitorId == preAssignmentB)
    }

    @Test @MainActor func settingLayoutPreservesNiriViewportStateOnRoundTrip() {
        let f = makeFixture()
        _ = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 9040)
        let mutatedNodeId = NodeId()
        f.workspaceManager.withNiriViewportState(for: f.workspaceA) { state in
            state.selectedNodeId = mutatedNodeId
        }
        let preState = f.workspaceManager.niriViewportState(for: f.workspaceA)
        #expect(preState.selectedNodeId == mutatedNodeId)

        setLayout(f, workspaceName: f.workspaceAName, to: .dwindle)
        setLayout(f, workspaceName: f.workspaceAName, to: .niri)

        let postState = f.workspaceManager.niriViewportState(for: f.workspaceA)
        #expect(postState.selectedNodeId == mutatedNodeId)
    }

    @Test @MainActor func runtimeToggleLayoutPreservesGraphStateAcrossRoundTrip() {
        let f = makeFixture()
        guard let runtime = f.controller.runtime else {
            Issue.record("Expected runtime for layout switch fixture")
            return
        }
        setLayout(f, workspaceName: f.workspaceAName, to: .niri)
        let focused = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 9050)
        _ = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 9051)
        _ = f.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 9052),
            pid: getpid(),
            windowId: 9052,
            to: f.workspaceA,
            mode: .floating
        )
        _ = f.workspaceManager.setManagedFocus(
            focused,
            in: f.workspaceA,
            onMonitor: f.primary.id
        )
        let selectedNodeId = NodeId()
        f.workspaceManager.withNiriViewportState(for: f.workspaceA) { state in
            state.selectedNodeId = selectedNodeId
        }

        let preGraph = f.workspaceManager.workspaceGraphSnapshot()
        let preViewportState = f.workspaceManager.niriViewportState(for: f.workspaceA)
        #expect(currentLayout(f, named: f.workspaceAName) == .niri)

        #expect(runtime.dispatchHotkey(.toggleWorkspaceLayout) == .executed)
        let dwindleGraph = f.workspaceManager.workspaceGraphSnapshot()
        #expect(currentLayout(f, named: f.workspaceAName) == .dwindle)
        #expect(preGraph.preservesLayoutSwitchInvariants(equals: dwindleGraph))

        #expect(runtime.dispatchHotkey(.toggleWorkspaceLayout) == .executed)
        let postGraph = f.workspaceManager.workspaceGraphSnapshot()
        let postViewportState = f.workspaceManager.niriViewportState(for: f.workspaceA)
        #expect(currentLayout(f, named: f.workspaceAName) == .niri)
        #expect(preGraph.preservesLayoutSwitchInvariants(equals: postGraph))
        #expect(postViewportState.selectedNodeId == preViewportState.selectedNodeId)
    }
}

private extension LogicalWindowRegistry.TokenBindingState {
    var isCurrent: Bool {
        if case .current = self { return true }
        return false
    }
}
