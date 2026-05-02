// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct WorkspaceGraphProjectionTests {
    @MainActor
    private struct Fixture {
        let manager: WorkspaceManager
        let settings: SettingsStore
        let workspaceA: WorkspaceDescriptor.ID
        let workspaceB: WorkspaceDescriptor.ID

        var monitorId: Monitor.ID { manager.monitors.first!.id }
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main),
            WorkspaceConfiguration(name: "2", monitorAssignment: .main)
        ]
        let manager = WorkspaceManager(settings: settings)
        manager.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let workspaceA = manager.workspaceId(for: "1", createIfMissing: false)!
        let workspaceB = manager.workspaceId(for: "2", createIfMissing: false)!
        _ = manager.setActiveWorkspace(workspaceA, on: manager.monitors.first!.id)
        return Fixture(
            manager: manager,
            settings: settings,
            workspaceA: workspaceA,
            workspaceB: workspaceB
        )
    }

    @MainActor
    private func addTilingWindow(
        _ manager: WorkspaceManager,
        workspaceId: WorkspaceDescriptor.ID,
        windowId: Int
    ) -> WindowToken {
        manager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceId,
            mode: .tiling
        )
    }

    @MainActor
    private func addFloatingWindow(
        _ manager: WorkspaceManager,
        workspaceId: WorkspaceDescriptor.ID,
        windowId: Int
    ) -> WindowToken {
        manager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceId,
            mode: .floating
        )
    }

    @MainActor
    private func assertWindowModelGraphWorkspaceMirror(_ manager: WorkspaceManager) {
        let graph = manager.workspaceGraphSnapshot()
        for record in manager.logicalWindowRegistry.activeRecords() {
            guard let token = record.currentToken else {
                continue
            }
            #expect(manager.workspace(for: token) == graph.workspaceId(containing: record.logicalId))
            #expect(record.lastKnownWorkspaceId == graph.workspaceId(containing: record.logicalId))
        }
    }


    @Test @MainActor func projectionContainsEachManagedLogicalIdExactlyOnce() {
        let f = makeFixture()
        let tokenA = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7001)
        let tokenB = addTilingWindow(f.manager, workspaceId: f.workspaceB, windowId: 7002)

        let graph = f.manager.workspaceGraphSnapshot()
        guard case let .current(idA) = f.manager.logicalWindowRegistry.lookup(token: tokenA),
              case let .current(idB) = f.manager.logicalWindowRegistry.lookup(token: tokenB)
        else {
            Issue.record("Expected current bindings for both tokens")
            return
        }

        #expect(graph.allLogicalIds == [idA, idB])
        #expect(graph.workspaceId(containing: idA) == f.workspaceA)
        #expect(graph.workspaceId(containing: idB) == f.workspaceB)
        #expect(WorkspaceGraphInvariants.validate(graph) == nil)
    }

    @Test @MainActor func tiledAndFloatingMembershipsAreDisjoint() {
        let f = makeFixture()
        let tiled = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7010)
        let floating = addFloatingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7011)

        let graph = f.manager.workspaceGraphSnapshot()
        guard case let .current(tiledId) = f.manager.logicalWindowRegistry.lookup(token: tiled),
              case let .current(floatingId) = f.manager.logicalWindowRegistry.lookup(token: floating),
              let node = graph.node(for: f.workspaceA)
        else {
            Issue.record("Expected current bindings and a workspace node")
            return
        }

        #expect(node.tiledOrder == [tiledId])
        #expect(node.floating == [floatingId])
        #expect(Set(node.tiledOrder).intersection(Set(node.floating)).isEmpty)
        #expect(WorkspaceGraphInvariants.tiledAndFloatingDisjoint(graph) == nil)
    }

    @Test @MainActor func graphSnapshotProjectsWorkspaceMembership() {
        let f = makeFixture()
        let tiled = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7012)
        let floating = addFloatingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7013)

        let graph = f.manager.workspaceGraphSnapshot()
        let tiledFromGraph = graph.tiledMembership(in: f.workspaceA).map(\.token)
        let floatingFromGraph = graph.floatingMembership(in: f.workspaceA).map(\.token)

        #expect(tiledFromGraph == [tiled])
        #expect(floatingFromGraph == [floating])
    }

    @Test @MainActor func retiredLogicalIdNotPresentAfterRemove() {
        let f = makeFixture()
        let token = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7020)
        guard case let .current(id) = f.manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current binding")
            return
        }

        let beforeGraph = f.manager.workspaceGraphSnapshot()
        #expect(beforeGraph.contains(logicalId: id))

        _ = f.manager.removeWindow(pid: token.pid, windowId: token.windowId)

        let afterGraph = f.manager.workspaceGraphSnapshot()
        #expect(!afterGraph.contains(logicalId: id))
        #expect(afterGraph.entry(for: id) == nil)
        #expect(WorkspaceGraphInvariants.validate(afterGraph) == nil)
    }


    @Test @MainActor func rekeyDoesNotReshapeProjection() {
        let f = makeFixture()
        let oldToken = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7030)
        guard case let .current(logicalId) = f.manager.logicalWindowRegistry.lookup(token: oldToken)
        else {
            Issue.record("Expected current binding for original token")
            return
        }

        let beforeGraph = f.manager.workspaceGraphSnapshot()
        #expect(beforeGraph.node(for: f.workspaceA)?.tiledOrder == [logicalId])

        let newToken = WindowToken(pid: getpid(), windowId: 7031)
        _ = f.manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 7031)
        )

        let afterGraph = f.manager.workspaceGraphSnapshot()
        #expect(afterGraph.node(for: f.workspaceA)?.tiledOrder == [logicalId])
        #expect(afterGraph.entry(for: logicalId)?.token == newToken)
        #expect(
            WorkspaceGraphInvariants.validate(
                afterGraph,
                registry: f.manager.logicalWindowRegistry
            ) == nil
        )
        #expect(
            f.manager.logicalWindowRegistry.currentToken(for: logicalId) == newToken
        )
    }

    @Test @MainActor func entryByTokenResolvesViaRegistry() {
        let f = makeFixture()
        let token = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7040)

        let graph = f.manager.workspaceGraphSnapshot()
        guard case let .current(logicalId) = f.manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Expected current binding")
            return
        }

        let entryByToken = graph.entry(for: token, registry: f.manager.logicalWindowRegistry)
        let entryByLogicalId = graph.entry(for: logicalId)
        #expect(entryByToken == entryByLogicalId)
        #expect(entryByToken?.token == token)
    }


    @Test @MainActor func lastFocusedProjectionMirrorsManagerLastFocusedLogicalId() {
        let f = makeFixture()
        let token = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7050)
        guard case let .current(logicalId) = f.manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Expected current binding")
            return
        }
        _ = f.manager.rememberFocus(token, in: f.workspaceA)

        let graph = f.manager.workspaceGraphSnapshot()
        let node = graph.node(for: f.workspaceA)
        #expect(node?.lastTiledFocusedLogicalId == logicalId)
        #expect(node?.lastTiledFocusedLogicalId == f.manager.lastFocusedLogicalId(in: f.workspaceA))
    }

    @Test @MainActor func focusedLogicalIdAppearsOnlyOnContainingWorkspaceNode() {
        let f = makeFixture()
        let token = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7051)
        _ = f.manager.setManagedFocus(token, in: f.workspaceA, onMonitor: f.monitorId)
        guard case let .current(logicalId) = f.manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Expected current binding")
            return
        }

        let graph = f.manager.workspaceGraphSnapshot()
        #expect(graph.node(for: f.workspaceA)?.focusedLogicalId == logicalId)
        #expect(graph.node(for: f.workspaceB)?.focusedLogicalId == nil)
    }


    @Test @MainActor func unassignedWorkspaceMonitorIdProjectsAsNil() {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let manager = WorkspaceManager(settings: settings)

        let workspaceId = manager.workspaceId(for: "1", createIfMissing: true)!
        let graph = manager.workspaceGraphSnapshot()
        #expect(graph.node(for: workspaceId)?.monitorId == manager.monitorId(for: workspaceId))
    }

    @Test @MainActor func coldMonitorProjectionCacheDoesNotReenterGraphProjection() {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        let manager = WorkspaceManager(settings: settings)
        let monitor = makeLayoutPlanTestMonitor()
        manager.applyMonitorConfigurationChange([monitor])

        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let workspaceId = manager.workspaceId(for: "1", createIfMissing: true)!
        let token = addTilingWindow(manager, workspaceId: workspaceId, windowId: 7059)

        let graph = manager.workspaceGraphSnapshot()
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Expected current binding")
            return
        }

        #expect(graph.node(for: workspaceId)?.monitorId == monitor.id)
        #expect(graph.node(for: workspaceId)?.tiledOrder == [logicalId])
        #expect(WorkspaceGraphInvariants.validate(graph) == nil)
    }

    @Test @MainActor func nativeFullscreenEntryProjectsIsNativeFullscreenTrue() {
        let f = makeFixture()
        let token = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7060)
        guard case let .current(logicalId) = f.manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Expected current binding")
            return
        }
        _ = f.manager.requestNativeFullscreenEnter(token, in: f.workspaceA)

        let graph = f.manager.workspaceGraphSnapshot()
        #expect(graph.entry(for: logicalId)?.isNativeFullscreen == true)
    }

    @Test @MainActor func axReadFailureQuarantineSuppressesLayoutMembership() {
        let f = makeFixture()
        let token = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7061)
        guard case let .current(logicalId) = f.manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Expected current binding")
            return
        }

        _ = f.manager.applyAXOutcomeQuarantine(for: token, axFailure: .contextUnavailable)

        let graph = f.manager.workspaceGraphSnapshot()
        let node = graph.node(for: f.workspaceA)
        #expect(node?.tiledOrder.isEmpty == true)
        #expect(node?.suppressed == [logicalId])
        #expect(graph.entry(for: logicalId)?.quarantine == .quarantined(reason: .axReadFailure))
    }

    @Test @MainActor func delayedAdmissionQuarantineRetainsLayoutMembership() {
        let f = makeFixture()
        let token = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7062)
        guard case let .current(logicalId) = f.manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Expected current binding")
            return
        }

        f.manager.applyMissingRescanQuarantineDelta(delayed: [token], cleared: [])

        let graph = f.manager.workspaceGraphSnapshot()
        let node = graph.node(for: f.workspaceA)
        #expect(node?.tiledOrder == [logicalId])
        #expect(node?.suppressed.isEmpty == true)
        #expect(graph.entry(for: logicalId)?.quarantine == .quarantined(reason: .delayedAdmission))
    }

    @Test @MainActor func tiledOrderSwapUpdatesGraphProjectionOrder() {
        let f = makeFixture()
        let firstToken = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7063)
        let secondToken = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7064)
        guard case let .current(firstId) = f.manager.logicalWindowRegistry.lookup(token: firstToken),
              case let .current(secondId) = f.manager.logicalWindowRegistry.lookup(token: secondToken)
        else {
            Issue.record("Expected current bindings")
            return
        }

        #expect(f.manager.workspaceGraphSnapshot().node(for: f.workspaceA)?.tiledOrder == [firstId, secondId])
        #expect(f.manager.swapTiledWindowOrder(firstToken, secondToken, in: f.workspaceA))

        let graph = f.manager.workspaceGraphSnapshot()
        #expect(graph.node(for: f.workspaceA)?.tiledOrder == [secondId, firstId])
    }

    @Test @MainActor func workspaceOrderMatchesAllWorkspaceDescriptorsOrder() {
        let f = makeFixture()
        let graph = f.manager.workspaceGraphSnapshot()
        let descriptorOrder = f.manager.allWorkspaceDescriptors().map(\.id)
        #expect(graph.workspaceOrder == descriptorOrder)
    }

    @Test @MainActor func projectionLayoutTypeMirrorsSettingsForWorkspace() {
        let f = makeFixture()
        let descriptor = f.manager.descriptor(for: f.workspaceA)!
        let graph = f.manager.workspaceGraphSnapshot()
        #expect(graph.node(for: f.workspaceA)?.layoutType == f.settings.layoutType(for: descriptor.name))
    }

    @Test @MainActor func windowModelWorkspaceMirrorStaysInSyncAcrossLifecyclePaths() {
        let f = makeFixture()
        let primary = addTilingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7070)
        let secondary = addFloatingWindow(f.manager, workspaceId: f.workspaceA, windowId: 7071)
        guard case let .current(primaryId) = f.manager.logicalWindowRegistry.lookup(token: primary),
              case let .current(secondaryId) = f.manager.logicalWindowRegistry.lookup(token: secondary)
        else {
            Issue.record("Expected current logical ids for seeded windows")
            return
        }
        assertWindowModelGraphWorkspaceMirror(f.manager)

        f.manager.setWorkspace(for: primary, to: f.workspaceB)
        assertWindowModelGraphWorkspaceMirror(f.manager)

        let rekeyedPrimary = WindowToken(pid: getpid(), windowId: 7072)
        _ = f.manager.rekeyWindow(
            from: primary,
            to: rekeyedPrimary,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 7072)
        )
        #expect(f.manager.logicalWindowRegistry.currentToken(for: primaryId) == rekeyedPrimary)
        assertWindowModelGraphWorkspaceMirror(f.manager)

        _ = f.manager.quarantineStaleCGSDestroyIfApplicable(probeToken: primary)
        _ = f.manager.applyAXOutcomeQuarantine(for: secondary, axFailure: .contextUnavailable)
        assertWindowModelGraphWorkspaceMirror(f.manager)

        #expect(f.manager.setWindowMode(.floating, for: rekeyedPrimary))
        assertWindowModelGraphWorkspaceMirror(f.manager)

        _ = f.manager.removeWindow(pid: secondary.pid, windowId: secondary.windowId)
        let graph = f.manager.workspaceGraphSnapshot()
        #expect(!graph.contains(logicalId: secondaryId))
        #expect(f.manager.workspace(for: secondary) == nil)
        assertWindowModelGraphWorkspaceMirror(f.manager)
    }
}
