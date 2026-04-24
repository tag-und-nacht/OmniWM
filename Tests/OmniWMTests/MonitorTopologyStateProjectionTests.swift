// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct MonitorTopologyStateProjectionTests {
    @MainActor
    private struct Fixture {
        let manager: WorkspaceManager
        let settings: SettingsStore
        let workspaceA: WorkspaceDescriptor.ID
        let workspaceB: WorkspaceDescriptor.ID
        let primaryMonitor: Monitor
        let secondaryMonitor: Monitor

        var primaryId: Monitor.ID { primaryMonitor.id }
        var secondaryId: Monitor.ID { secondaryMonitor.id }
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let primary = makeLayoutPlanPrimaryTestMonitor(name: "Primary")
        let secondary = makeLayoutPlanSecondaryTestMonitor(name: "Secondary", x: 1920)

        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main),
            WorkspaceConfiguration(name: "2", monitorAssignment: .secondary)
        ]
        let manager = WorkspaceManager(settings: settings)
        manager.applyMonitorConfigurationChange([primary, secondary])
        let workspaceA = manager.workspaceId(for: "1", createIfMissing: false)!
        let workspaceB = manager.workspaceId(for: "2", createIfMissing: false)!
        _ = manager.setActiveWorkspace(workspaceA, on: primary.id)
        _ = manager.setActiveWorkspace(workspaceB, on: secondary.id)

        return Fixture(
            manager: manager,
            settings: settings,
            workspaceA: workspaceA,
            workspaceB: workspaceB,
            primaryMonitor: primary,
            secondaryMonitor: secondary
        )
    }

    @MainActor
    private func project(
        _ fixture: Fixture,
        epoch: TopologyEpoch = TopologyEpoch(value: 1)
    ) -> MonitorTopologyState {
        MonitorTopologyState.project(
            manager: fixture.manager,
            settings: fixture.settings,
            epoch: epoch
        )
    }

    @Test @MainActor func projectionExposesEachMonitorInPositionOrder() {
        let f = makeFixture()
        let topology = project(f)

        #expect(topology.order == [f.primaryId, f.secondaryId])
        #expect(Set(topology.nodes.keys) == [f.primaryId, f.secondaryId])
    }

    @Test @MainActor func workspaceMonitorMapMatchesWorkspaceManager() {
        let f = makeFixture()
        let topology = project(f)

        #expect(topology.workspaceMonitor[f.workspaceA] == f.primaryId)
        #expect(topology.workspaceMonitor[f.workspaceB] == f.secondaryId)
    }

    @Test @MainActor func activeWorkspaceMatchesMonitorVisibleWorkspace() {
        let f = makeFixture()
        let topology = project(f)

        #expect(topology.node(f.primaryId)?.activeWorkspaceId == f.workspaceA)
        #expect(topology.node(f.secondaryId)?.activeWorkspaceId == f.workspaceB)
    }

    @Test @MainActor func nodeContainingPointReturnsExpectedMonitor() {
        let f = makeFixture()
        let topology = project(f)

        let primaryPoint = CGPoint(x: 100, y: 100)
        let secondaryPoint = CGPoint(x: 2000, y: 100)
        #expect(topology.node(containingPoint: primaryPoint)?.monitorId == f.primaryId)
        #expect(topology.node(containingPoint: secondaryPoint)?.monitorId == f.secondaryId)
    }

    @Test @MainActor func nearestNodeReturnsClosestForOffMonitorPoint() {
        let f = makeFixture()
        let topology = project(f)

        let offMonitorPoint = CGPoint(x: 3000, y: -500)
        #expect(topology.nearestNode(to: offMonitorPoint)?.monitorId == f.secondaryId)
    }

    @Test @MainActor func relationMatchesMonitorRelationDirectly() {
        let f = makeFixture()
        let topology = project(f)

        #expect(topology.relation(f.primaryId, to: f.secondaryId) == f.primaryMonitor.relation(to: f.secondaryMonitor))
        #expect(topology.relation(f.primaryId, to: f.primaryId) == nil)
    }

    @Test @MainActor func topologyProfileMatchesReconcileSnapshotProfile() {
        let f = makeFixture()
        let topology = project(f)
        let snapshot = f.manager.reconcileSnapshot()
        #expect(topology.topologyProfile == snapshot.topologyProfile)
    }

    @Test @MainActor func epochIsMonotonicAcrossSequentialApplyConfigurationChange() {
        resetSharedControllerStateForTests()
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let runtime = WMRuntime(settings: settings)
        let initial = runtime.currentTopologyEpoch
        runtime.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let afterFirst = runtime.currentTopologyEpoch
        runtime.applyMonitorConfigurationChange(
            [makeLayoutPlanTestMonitor(width: 2560, height: 1440)]
        )
        let afterSecond = runtime.currentTopologyEpoch

        #expect(initial == .invalid)
        #expect(afterFirst > initial)
        #expect(afterSecond > afterFirst)
    }

    @Test @MainActor func unassignedDisplayHasNilActiveWorkspace() {
        let primary = makeLayoutPlanPrimaryTestMonitor()
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let manager = WorkspaceManager(settings: settings)
        let secondary = makeLayoutPlanSecondaryTestMonitor(name: "Secondary", x: 1920)
        manager.applyMonitorConfigurationChange([primary, secondary])
        let workspaceA = manager.workspaceId(for: "1", createIfMissing: false)!
        _ = manager.setActiveWorkspace(workspaceA, on: primary.id)

        let topology = MonitorTopologyState.project(
            manager: manager,
            settings: settings,
            epoch: TopologyEpoch(value: 1)
        )

        #expect(topology.node(primary.id)?.activeWorkspaceId == workspaceA)
        #expect(topology.node(secondary.id)?.activeWorkspaceId == nil)
    }


    @Test @MainActor func preferredHideSidesIsStableForUnchangedTopology() {
        let f = makeFixture()
        let topology = project(f)
        let first = topology.preferredHideSides()
        let second = topology.preferredHideSides()
        #expect(first == second)
    }

    @Test @MainActor func preferredHideSidesRecomputesForDifferentMonitorSet() {
        let single = [makeLayoutPlanTestMonitor()]
        let dual = [
            makeLayoutPlanPrimaryTestMonitor(),
            makeLayoutPlanSecondaryTestMonitor(x: 1920)
        ]
        let singleSides = MonitorTopologyState.preferredHideSides(for: single)
        let dualSides = MonitorTopologyState.preferredHideSides(for: dual)
        #expect(singleSides.count == 1)
        #expect(dualSides.count == 2)
        #expect(singleSides[single[0].id] == .right)
        #expect(dualSides[dual[0].id] == .left)
    }

    @Test @MainActor func preferredHideSidesRespectsThreeMonitorAdjacency() {
        let left = makeLayoutPlanTestMonitor(displayId: 101, name: "Left", x: 0)
        let middle = makeLayoutPlanTestMonitor(displayId: 102, name: "Middle", x: 1920)
        let right = makeLayoutPlanTestMonitor(displayId: 103, name: "Right", x: 3840)
        let sides = MonitorTopologyState.preferredHideSides(for: [left, middle, right])
        #expect(sides[left.id] == .left)
        #expect(sides[right.id] == .right)
    }

    @Test @MainActor func preferredHideSideStableForSingleMonitor() {
        let monitor = makeLayoutPlanTestMonitor()
        let sides = MonitorTopologyState.preferredHideSides(for: [monitor])
        #expect(sides[monitor.id] != nil)
        let firstChoice = sides[monitor.id]!
        let secondChoice = MonitorTopologyState.preferredHideSides(for: [monitor])[monitor.id]
        #expect(firstChoice == secondChoice)
    }

    @Test @MainActor func preferredHideSidesInstanceMatchesStaticForSameMonitors() {
        let f = makeFixture()
        let topology = project(f)
        let instanceSides = topology.preferredHideSides()
        let staticSides = MonitorTopologyState.preferredHideSides(for: f.manager.monitors)
        #expect(instanceSides == staticSides)
    }

    @Test @MainActor func preferredHideSidesReflectNewMonitorSetAfterEpochBump() {
        let f = makeFixture()
        let dualTopology = project(f, epoch: TopologyEpoch(value: 1))
        let dualSides = dualTopology.preferredHideSides()
        #expect(dualSides[f.primaryId] == .left)
        #expect(dualSides[f.secondaryId] == .right)

        f.manager.applyMonitorConfigurationChange([f.primaryMonitor])
        let singleTopology = MonitorTopologyState.project(
            manager: f.manager,
            settings: f.settings,
            epoch: TopologyEpoch(value: 2)
        )
        let singleSides = singleTopology.preferredHideSides()
        #expect(singleSides.count == 1)
        #expect(singleSides[f.primaryId] != nil)
    }

    @Test @MainActor func nodeFieldsMirrorSourceMonitor() {
        let f = makeFixture()
        let topology = project(f)
        guard let node = topology.node(f.primaryId) else {
            Issue.record("Expected node for primary monitor")
            return
        }
        #expect(node.displayId == f.primaryMonitor.displayId)
        #expect(node.frame.raw == f.primaryMonitor.frame)
        #expect(node.visibleFrame.raw == f.primaryMonitor.visibleFrame)
        #expect(node.hasNotch == f.primaryMonitor.hasNotch)
        #expect(node.name == f.primaryMonitor.name)
        #expect(node.outputId == OutputId(from: f.primaryMonitor))
        #expect(node.assignedWorkspaceIds == [f.workspaceA])
    }
}
