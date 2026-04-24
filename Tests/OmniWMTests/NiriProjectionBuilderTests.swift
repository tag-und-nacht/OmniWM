// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct NiriProjectionBuilderTests {
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
    private func makeBuilder(_ fixture: Fixture) -> NiriProjectionBuilder {
        let graph = fixture.workspaceManager.workspaceGraphSnapshot()
        let topology = MonitorTopologyState.project(
            manager: fixture.workspaceManager,
            settings: fixture.settings,
            epoch: TopologyEpoch(value: 1),
            insetWorkingFrame: { [controller = fixture.controller] mon in
                controller.insetWorkingFrame(for: mon)
            }
        )
        return NiriProjectionBuilder(
            graph: graph,
            topology: topology,
            lifecycle: fixture.workspaceManager
        )
    }

    @MainActor
    private func makeBaselineSnapshot(
        _ fixture: Fixture,
        builder: NiriProjectionBuilder
    ) -> NiriWorkspaceSnapshot? {
        builder.buildSnapshot(
            for: fixture.workspaceA,
            monitorId: fixture.primary.id,
            viewportState: ViewportState(),
            preferredFocusToken: fixture.workspaceManager.preferredFocusToken(in: fixture.workspaceA),
            confirmedFocusedToken: fixture.workspaceManager.focusedToken,
            pendingFocusedToken: fixture.workspaceManager.pendingFocusedToken,
            pendingFocusedWorkspaceId: fixture.workspaceManager.pendingFocusedWorkspaceId,
            isNonManagedFocusActive: fixture.workspaceManager.isNonManagedFocusActive,
            hasCompletedInitialRefresh: false,
            useScrollAnimationPath: false,
            removalSeed: nil,
            gap: CGFloat(fixture.workspaceManager.gaps),
            outerGaps: fixture.workspaceManager.outerGaps,
            displayRefreshRate: 60.0,
            isActiveWorkspace: true,
            isInteractionWorkspace: true
        )
    }


    @Test @MainActor func niriSnapshotMembershipMatchesGraphTiledOrder() {
        let f = makeFixture()
        let token1 = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 11_001)
        let token2 = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 11_002)

        let builder = makeBuilder(f)
        let graph = f.workspaceManager.workspaceGraphSnapshot()
        let snapshot = makeBaselineSnapshot(f, builder: builder)

        let expectedTokens = graph.tiledMembership(in: f.workspaceA).map(\.token)
        #expect(expectedTokens == [token1, token2])
        #expect(snapshot?.windows.map(\.token) == expectedTokens)
    }

    @Test @MainActor func niriSnapshotMonitorFieldsMatchTopologyNode() {
        let f = makeFixture()
        _ = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 11_010)

        let builder = makeBuilder(f)
        let snapshot = makeBaselineSnapshot(f, builder: builder)
        let topology = MonitorTopologyState.project(
            manager: f.workspaceManager,
            settings: f.settings,
            epoch: TopologyEpoch(value: 1),
            insetWorkingFrame: { [weak controller = f.controller] mon in
                controller?.insetWorkingFrame(for: mon) ?? mon.visibleFrame
            }
        )
        let node = topology.node(f.primary.id)

        #expect(snapshot?.monitor.monitorId == node?.monitorId)
        #expect(snapshot?.monitor.displayId == node?.displayId)
        #expect(snapshot?.monitor.frame == node?.frame.raw)
        #expect(snapshot?.monitor.visibleFrame == node?.visibleFrame.raw)
        #expect(snapshot?.monitor.workingFrame == node?.workingFrame.raw)
        #expect(snapshot?.monitor.scale == node?.scale)
    }

    @Test @MainActor func niriSnapshotWindowFieldsMirrorLifecycleProvider() {
        let f = makeFixture()
        let token = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 11_020)
        f.workspaceManager.setHiddenState(
            WindowModel.HiddenState(
                proportionalPosition: CGPoint(x: 0.5, y: 0.5),
                referenceMonitorId: f.primary.id,
                workspaceInactive: true
            ),
            for: token
        )

        let builder = makeBuilder(f)
        let snapshot = makeBaselineSnapshot(f, builder: builder)
        let projectedWindow = snapshot?.windows.first

        #expect(projectedWindow?.token == token)
        #expect(projectedWindow?.hiddenState == f.workspaceManager.hiddenState(for: token))
        #expect(projectedWindow?.layoutReason == f.workspaceManager.layoutReason(for: token))
        #expect(projectedWindow?.nativeFullscreenRestore == f.workspaceManager.nativeFullscreenRestoreContext(for: token))
    }

    @Test @MainActor func niriSnapshotMergesRuleMinimumSizeEffectsWhenRequested() {
        let f = makeFixture()
        let windowId = 11_021
        let cachedMinWidth: CGFloat = 240
        let cachedMinHeight: CGFloat = 180
        let ruleMinWidth: Double = 480
        let ruleMinHeight: Double = 320
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

    @Test @MainActor func niriSnapshotIsNilForUnknownMonitor() {
        let f = makeFixture()
        let builder = makeBuilder(f)
        let unknown = Monitor.ID(displayId: 9_999_999)

        let snapshot = builder.buildSnapshot(
            for: f.workspaceA,
            monitorId: unknown,
            viewportState: ViewportState(),
            preferredFocusToken: nil,
            confirmedFocusedToken: nil,
            pendingFocusedToken: nil,
            pendingFocusedWorkspaceId: nil,
            isNonManagedFocusActive: false,
            hasCompletedInitialRefresh: false,
            useScrollAnimationPath: false,
            removalSeed: nil,
            gap: 0,
            outerGaps: .zero,
            displayRefreshRate: 60.0,
            isActiveWorkspace: false,
            isInteractionWorkspace: false
        )

        #expect(snapshot == nil)
    }


    @Test @MainActor func parityDiffIsNilForIdenticalSnapshots() {
        let f = makeFixture()
        _ = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 11_030)

        let builder = makeBuilder(f)
        let lhs = makeBaselineSnapshot(f, builder: builder)
        let rhs = makeBaselineSnapshot(f, builder: builder)

        guard let lhs, let rhs else {
            Issue.record("Expected both snapshots to project")
            return
        }
        #expect(NiriSnapshotParity.diff(legacy: lhs, projection: rhs) == nil)
    }

    @Test @MainActor func parityDiffDetectsWorkspaceIdMismatch() {
        let f = makeFixture()
        _ = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 11_040)

        let builder = makeBuilder(f)
        guard let baseline = makeBaselineSnapshot(f, builder: builder) else {
            Issue.record("Expected baseline snapshot")
            return
        }

        let alteredId = WorkspaceDescriptor.ID()
        let altered = NiriWorkspaceSnapshot(
            workspaceId: alteredId,
            monitor: baseline.monitor,
            windows: baseline.windows,
            viewportState: baseline.viewportState,
            preferredFocusToken: baseline.preferredFocusToken,
            confirmedFocusedToken: baseline.confirmedFocusedToken,
            pendingFocusedToken: baseline.pendingFocusedToken,
            pendingFocusedWorkspaceId: baseline.pendingFocusedWorkspaceId,
            isNonManagedFocusActive: baseline.isNonManagedFocusActive,
            hasCompletedInitialRefresh: baseline.hasCompletedInitialRefresh,
            useScrollAnimationPath: baseline.useScrollAnimationPath,
            removalSeed: baseline.removalSeed,
            gap: baseline.gap,
            outerGaps: baseline.outerGaps,
            displayRefreshRate: baseline.displayRefreshRate,
            isActiveWorkspace: baseline.isActiveWorkspace,
            isInteractionWorkspace: baseline.isInteractionWorkspace
        )

        #expect(NiriSnapshotParity.diff(legacy: baseline, projection: altered) == .workspaceIdDiffers)
    }

    @Test @MainActor func parityDiffDetectsWindowOrderMismatch() {
        let f = makeFixture()
        let token1 = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 11_050)
        let token2 = addLayoutPlanTestWindow(on: f.controller, workspaceId: f.workspaceA, windowId: 11_051)

        let builder = makeBuilder(f)
        guard let baseline = makeBaselineSnapshot(f, builder: builder) else {
            Issue.record("Expected baseline snapshot")
            return
        }

        let reversed = NiriWorkspaceSnapshot(
            workspaceId: baseline.workspaceId,
            monitor: baseline.monitor,
            windows: baseline.windows.reversed(),
            viewportState: baseline.viewportState,
            preferredFocusToken: baseline.preferredFocusToken,
            confirmedFocusedToken: baseline.confirmedFocusedToken,
            pendingFocusedToken: baseline.pendingFocusedToken,
            pendingFocusedWorkspaceId: baseline.pendingFocusedWorkspaceId,
            isNonManagedFocusActive: baseline.isNonManagedFocusActive,
            hasCompletedInitialRefresh: baseline.hasCompletedInitialRefresh,
            useScrollAnimationPath: baseline.useScrollAnimationPath,
            removalSeed: baseline.removalSeed,
            gap: baseline.gap,
            outerGaps: baseline.outerGaps,
            displayRefreshRate: baseline.displayRefreshRate,
            isActiveWorkspace: baseline.isActiveWorkspace,
            isInteractionWorkspace: baseline.isInteractionWorkspace
        )

        let drift = NiriSnapshotParity.diff(legacy: baseline, projection: reversed)
        #expect(drift == .windowTokenOrderDiffers(index: 0, legacy: token1, projection: token2))
    }
}
