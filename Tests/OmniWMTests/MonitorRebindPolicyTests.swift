// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct MonitorRebindPolicyTests {
    private static func makeMonitor(
        displayId: CGDirectDisplayID,
        name: String,
        x: CGFloat = 0,
        width: CGFloat = 1920,
        height: CGFloat = 1080
    ) -> Monitor {
        let frame = CGRect(x: x, y: 0, width: width, height: height)
        return Monitor(
            id: Monitor.ID(displayId: displayId),
            displayId: displayId,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: name
        )
    }

    @Test func decideIsIdempotentOnUnchangedTopology() {
        let prev = [
            OutputId(displayId: 1, name: "Built-in"),
            OutputId(displayId: 2, name: "External")
        ]
        let monitors = [
            Self.makeMonitor(displayId: 1, name: "Built-in"),
            Self.makeMonitor(displayId: 2, name: "External", x: 1920)
        ]
        let workspaces = [
            WorkspaceDescriptor(name: "1"),
            WorkspaceDescriptor(name: "2")
        ]
        let snapshots = [
            WorkspaceRestoreSnapshot(
                monitor: MonitorRestoreKey(monitor: monitors[0]),
                workspaceId: workspaces[0].id
            ),
            WorkspaceRestoreSnapshot(
                monitor: MonitorRestoreKey(monitor: monitors[1]),
                workspaceId: workspaces[1].id
            )
        ]

        let first = MonitorRebindPolicy.decide(
            previousOutputs: prev,
            newMonitors: monitors,
            workspaces: workspaces,
            snapshots: snapshots
        )
        let second = MonitorRebindPolicy.decide(
            previousOutputs: prev,
            newMonitors: monitors,
            workspaces: workspaces,
            snapshots: snapshots
        )

        #expect(first == second)
        #expect(first.unresolvedOutputs.isEmpty)
        #expect(first.claimedMonitorIds == [monitors[0].id, monitors[1].id])
        #expect(first.workspaceMonitorAssignments[workspaces[0].id] == monitors[0].id)
        #expect(first.workspaceMonitorAssignments[workspaces[1].id] == monitors[1].id)
    }

    @Test func decideHandlesNameFallbackAfterDisplayIdChange() {
        let prev = [OutputId(displayId: 1, name: "Built-in")]
        let monitors = [Self.makeMonitor(displayId: 42, name: "Built-in")]
        let workspaces = [WorkspaceDescriptor(name: "1")]
        let snapshots = [
            WorkspaceRestoreSnapshot(
                monitor: MonitorRestoreKey(
                    monitor: Self.makeMonitor(displayId: 1, name: "Built-in")
                ),
                workspaceId: workspaces[0].id
            )
        ]

        let decision = MonitorRebindPolicy.decide(
            previousOutputs: prev,
            newMonitors: monitors,
            workspaces: workspaces,
            snapshots: snapshots
        )

        #expect(decision.reboundOutputs == [OutputId(from: monitors[0])])
        #expect(decision.unresolvedOutputs.isEmpty)
        #expect(decision.claimedMonitorIds == [monitors[0].id])
    }

    @Test func decideExposesUnresolvedOutputsForDisconnectedMonitors() {
        let prev = [
            OutputId(displayId: 1, name: "Built-in"),
            OutputId(displayId: 2, name: "External")
        ]
        let monitors = [Self.makeMonitor(displayId: 1, name: "Built-in")]
        let decision = MonitorRebindPolicy.decide(
            previousOutputs: prev,
            newMonitors: monitors,
            workspaces: [],
            snapshots: []
        )

        #expect(decision.unresolvedOutputs.contains { $0.displayId == 2 })
        #expect(decision.claimedMonitorIds == [monitors[0].id])
    }

    @Test func decideUsesConfiguredEffectiveWorkspaceAssignments() {
        let prev = [
            OutputId(displayId: 1, name: "Primary"),
            OutputId(displayId: 2, name: "Secondary")
        ]
        let monitors = [
            Self.makeMonitor(displayId: 1, name: "Primary"),
            Self.makeMonitor(displayId: 2, name: "Secondary", x: 1920)
        ]
        let workspaces = [
            WorkspaceDescriptor(name: "1"),
            WorkspaceDescriptor(name: "2")
        ]
        let decision = MonitorRebindPolicy.decide(
            previousOutputs: prev,
            newMonitors: monitors,
            workspaces: workspaces,
            snapshots: [],
            workspaceConfigurations: [
                WorkspaceConfiguration(name: "1", monitorAssignment: .main),
                WorkspaceConfiguration(name: "2", monitorAssignment: .secondary)
            ]
        )

        #expect(decision.workspaceMonitorAssignments[workspaces[0].id] == monitors[0].id)
        #expect(decision.workspaceMonitorAssignments[workspaces[1].id] == monitors[1].id)
    }

    @Test func decideFallsBackConfiguredSecondaryWorkspaceOnSingleDisplay() {
        let prev = [OutputId(displayId: 1, name: "Primary")]
        let monitors = [Self.makeMonitor(displayId: 1, name: "Primary")]
        let workspace = WorkspaceDescriptor(name: "2")
        let decision = MonitorRebindPolicy.decide(
            previousOutputs: prev,
            newMonitors: monitors,
            workspaces: [workspace],
            snapshots: [],
            workspaceConfigurations: [
                WorkspaceConfiguration(name: "2", monitorAssignment: .secondary)
            ]
        )

        #expect(decision.workspaceMonitorAssignments[workspace.id] == monitors[0].id)
    }

    @Test @MainActor func applyMonitorConfigurationChangeBumpsTopologyEpochOnRealChange() {
        resetSharedControllerStateForTests()
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [WorkspaceConfiguration(name: "1", monitorAssignment: .main)]
        let runtime = WMRuntime(settings: settings)

        #expect(runtime.currentTopologyEpoch == .invalid)
        runtime.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let firstEpoch = runtime.currentTopologyEpoch
        #expect(firstEpoch.isValid)

        runtime.applyMonitorConfigurationChange(
            [makeLayoutPlanTestMonitor(width: 2560, height: 1440)]
        )
        #expect(runtime.currentTopologyEpoch > firstEpoch)
    }

    @Test @MainActor func applyMonitorConfigurationChangeIsNoOpForIdenticalProfile() {
        resetSharedControllerStateForTests()
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [WorkspaceConfiguration(name: "1", monitorAssignment: .main)]
        let runtime = WMRuntime(settings: settings)

        let monitors = [makeLayoutPlanTestMonitor()]
        runtime.applyMonitorConfigurationChange(monitors)
        let firstEpoch = runtime.currentTopologyEpoch
        #expect(firstEpoch.isValid)

        runtime.applyMonitorConfigurationChange(monitors)
        #expect(runtime.currentTopologyEpoch == firstEpoch)
    }

    @Test @MainActor func disconnectThenReconnectPreservesWorkspaceBindings() {
        resetSharedControllerStateForTests()
        let primary = makeLayoutPlanPrimaryTestMonitor(name: "Primary")
        let secondary = makeLayoutPlanSecondaryTestMonitor(name: "Secondary", x: 1920)
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main),
            WorkspaceConfiguration(name: "2", monitorAssignment: .secondary)
        ]
        let runtime = WMRuntime(settings: settings)
        runtime.applyMonitorConfigurationChange([primary, secondary])

        guard let workspaceTwoId = runtime.workspaceManager
            .workspaceId(for: "2", createIfMissing: false)
        else {
            Issue.record("Expected workspace \"2\" to exist")
            return
        }
        #expect(runtime.workspaceManager.monitorId(for: workspaceTwoId) == secondary.id)

        runtime.applyMonitorConfigurationChange([primary])

        runtime.applyMonitorConfigurationChange([primary, secondary])
        #expect(runtime.workspaceManager.monitorId(for: workspaceTwoId) == secondary.id)
    }

    @Test @MainActor func policyDecisionAgreesWithManagerSnapshotsForMultiMonitorTopology() {
        resetSharedControllerStateForTests()
        let primary = makeLayoutPlanPrimaryTestMonitor(name: "Primary")
        let secondary = makeLayoutPlanSecondaryTestMonitor(name: "Secondary", x: 1920)
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main),
            WorkspaceConfiguration(name: "2", monitorAssignment: .secondary)
        ]
        let runtime = WMRuntime(settings: settings)
        runtime.applyMonitorConfigurationChange([primary, secondary])

        let workspaces = runtime.workspaceManager.allWorkspaceDescriptors()
        let snapshots = workspaces.compactMap { ws -> WorkspaceRestoreSnapshot? in
            guard let monitor = runtime.workspaceManager.monitor(for: ws.id) else { return nil }
            return WorkspaceRestoreSnapshot(
                monitor: MonitorRestoreKey(monitor: monitor),
                workspaceId: ws.id
            )
        }
        let decision = MonitorRebindPolicy.decide(
            previousOutputs: [primary, secondary].map { OutputId(from: $0) },
            newMonitors: [primary, secondary],
            workspaces: workspaces,
            snapshots: snapshots
        )
        #expect(!decision.workspaceMonitorAssignments.isEmpty)
        for (workspaceId, monitorId) in decision.workspaceMonitorAssignments {
            #expect([primary.id, secondary.id].contains(monitorId))
            #expect(workspaces.contains(where: { $0.id == workspaceId }))
        }
    }

    @Test @MainActor func currentTopologyProfileMirrorsWorkspaceManagerCachedProfile() {
        resetSharedControllerStateForTests()
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [WorkspaceConfiguration(name: "1", monitorAssignment: .main)]
        let runtime = WMRuntime(settings: settings)
        runtime.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])

        let snapshot = runtime.workspaceManager.reconcileSnapshot()
        #expect(runtime.workspaceManager.currentTopologyProfile == snapshot.topologyProfile)
    }
}
