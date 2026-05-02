// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct DwindleProjectionBuilderTests {
    @MainActor
    private struct Fixture {
        let controller: WMController
        let workspaceA: WorkspaceDescriptor.ID
        let primary: Monitor

        var workspaceManager: WorkspaceManager { controller.workspaceManager }
        var settings: SettingsStore { controller.settings }
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let primary = makeLayoutPlanPrimaryTestMonitor()
        let controller = makeLayoutPlanTestController(monitors: [primary])
        let workspaceA = controller.workspaceManager.workspaceId(for: "1", createIfMissing: false)!
        _ = controller.workspaceManager.setActiveWorkspace(workspaceA, on: primary.id)
        return Fixture(controller: controller, workspaceA: workspaceA, primary: primary)
    }

    @MainActor
    private func makeBuilder(_ fixture: Fixture) -> DwindleProjectionBuilder {
        let graph = fixture.workspaceManager.workspaceGraphSnapshot()
        let topology = MonitorTopologyState.project(
            manager: fixture.workspaceManager,
            settings: fixture.settings,
            epoch: TopologyEpoch(value: 1),
            insetWorkingFrame: { [controller = fixture.controller] mon in
                controller.insetWorkingFrame(for: mon)
            }
        )
        return DwindleProjectionBuilder(
            graph: graph,
            topology: topology,
            lifecycle: fixture.workspaceManager
        )
    }

    @MainActor
    private func makeBaselineSnapshot(
        _ fixture: Fixture,
        builder: DwindleProjectionBuilder
    ) -> DwindleWorkspaceSnapshot? {
        builder.buildSnapshot(
            for: fixture.workspaceA,
            monitorId: fixture.primary.id,
            preferredFocusToken: fixture.workspaceManager.preferredFocusToken(in: fixture.workspaceA),
            confirmedFocusedToken: fixture.workspaceManager.focusedToken,
            selectedToken: nil,
            settings: fixture.settings.resolvedDwindleSettings(for: fixture.primary),
            displayRefreshRate: 60.0,
            isActiveWorkspace: true
        )
    }

    @Test @MainActor func dwindleSnapshotMembershipMatchesGraphTiledOrder() {
        let f = makeFixture()
        let token1 = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 12_001)
        let token2 = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 12_002)

        let builder = makeBuilder(f)
        let snapshot = makeBaselineSnapshot(f, builder: builder)
        let graph = f.workspaceManager.workspaceGraphSnapshot()

        let expectedTokens = graph.tiledMembership(in: f.workspaceA).map(\.token)
        #expect(expectedTokens == [token1, token2])
        #expect(snapshot?.windows.map(\.token) == expectedTokens)
    }

    @Test @MainActor func dwindleSnapshotMonitorFieldsMatchTopologyNode() {
        let f = makeFixture()
        _ = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 12_010)

        let builder = makeBuilder(f)
        let snapshot = makeBaselineSnapshot(f, builder: builder)
        let topology = MonitorTopologyState.project(
            manager: f.workspaceManager,
            settings: f.settings,
            epoch: TopologyEpoch(value: 1),
            insetWorkingFrame: { [controller = f.controller] mon in
                controller.insetWorkingFrame(for: mon)
            }
        )
        let node = topology.node(f.primary.id)

        #expect(snapshot?.monitor.monitorId == node?.monitorId)
        #expect(snapshot?.monitor.frame == node?.frame.raw)
        #expect(snapshot?.monitor.workingFrame == node?.workingFrame.raw)
    }

    @Test @MainActor func dwindleSnapshotConfirmedFocusedTokenFromCallSite() {
        let f = makeFixture()
        let token = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 12_020)
        _ = f.workspaceManager.setManagedFocus(token, in: f.workspaceA, onMonitor: f.primary.id)

        let builder = makeBuilder(f)
        let snapshot = makeBaselineSnapshot(f, builder: builder)
        #expect(snapshot?.confirmedFocusedToken == token)
    }

    @Test @MainActor func dwindleSnapshotMergesRuleMinimumSizeEffectsWhenRequested() {
        let f = makeFixture()
        let windowId = 12_021
        let cachedMinWidth: CGFloat = 260
        let cachedMinHeight: CGFloat = 170
        let ruleMinWidth: Double = 520
        let ruleMinHeight: Double = 340
        let cachedConstraints = WindowSizeConstraints(
            minSize: CGSize(width: cachedMinWidth, height: cachedMinHeight),
            maxSize: .zero,
            isFixed: false
        )
        let ruleEffects = ManagedWindowRuleEffects(
            minWidth: ruleMinWidth,
            minHeight: ruleMinHeight
        )
        let token = f.workspaceManager.addWindow(
            makeLayoutPlanTestWindow(windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: f.workspaceA,
            ruleEffects: ruleEffects
        )
        f.workspaceManager.setCachedConstraints(cachedConstraints, for: token)

        let builder = makeBuilder(f)
        let mergedSnapshot = makeBaselineSnapshot(f, builder: builder)

        #expect(mergedSnapshot?.windows.first?.constraints.minSize.width == CGFloat(ruleMinWidth))
        #expect(mergedSnapshot?.windows.first?.constraints.minSize.height == CGFloat(ruleMinHeight))
    }

    @Test @MainActor func dwindleSnapshotIsNilForUnknownMonitor() {
        let f = makeFixture()
        let builder = makeBuilder(f)
        let unknown = Monitor.ID(displayId: 8_888_888)

        let snapshot = builder.buildSnapshot(
            for: f.workspaceA,
            monitorId: unknown,
            preferredFocusToken: nil,
            confirmedFocusedToken: nil,
            selectedToken: nil,
            settings: f.settings.resolvedDwindleSettings(for: f.primary),
            displayRefreshRate: 60.0,
            isActiveWorkspace: false
        )
        #expect(snapshot == nil)
    }

    @Test @MainActor func parityDiffIsNilForIdenticalSnapshots() {
        let f = makeFixture()
        _ = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 12_030)

        let builder = makeBuilder(f)
        let lhs = makeBaselineSnapshot(f, builder: builder)
        let rhs = makeBaselineSnapshot(f, builder: builder)
        guard let lhs, let rhs else {
            Issue.record("Expected both snapshots to project")
            return
        }
        #expect(DwindleSnapshotParity.diff(legacy: lhs, projection: rhs) == nil)
    }
}
