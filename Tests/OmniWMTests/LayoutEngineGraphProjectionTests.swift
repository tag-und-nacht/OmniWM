// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct LayoutEngineGraphProjectionTests {
    @MainActor
    private struct Fixture {
        let manager: WorkspaceManager
        let settings: SettingsStore
        let workspaceId: WorkspaceDescriptor.ID
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let manager = WorkspaceManager(settings: settings)
        manager.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let workspaceId = manager.workspaceId(for: "1", createIfMissing: false)!
        _ = manager.setActiveWorkspace(workspaceId, on: manager.monitors.first!.id)
        return Fixture(manager: manager, settings: settings, workspaceId: workspaceId)
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
            to: workspaceId,
            mode: .tiling
        )
    }

    @Test @MainActor func niriEngineMembershipMatchesGraphLogicalIds() {
        let f = makeFixture()
        let engine = NiriLayoutEngine()
        let tokenA = addWindow(f.manager, workspaceId: f.workspaceId, windowId: 21_001)
        let tokenB = addWindow(f.manager, workspaceId: f.workspaceId, windowId: 21_002)

        let nodeA = NiriWindow(token: tokenA)
        let nodeB = NiriWindow(token: tokenB)
        engine.tokenToNode[tokenA] = nodeA
        engine.tokenToNode[tokenB] = nodeB
        engine.syncLogicalIds(from: f.manager.logicalWindowRegistry)

        let graph = f.manager.workspaceGraphSnapshot()
        for (logicalId, _) in graph.entriesByLogicalId {
            #expect(engine.findNode(forLogicalId: logicalId) != nil)
        }
        guard case let .current(idA) = f.manager.logicalWindowRegistry.lookup(token: tokenA),
              case let .current(idB) = f.manager.logicalWindowRegistry.lookup(token: tokenB)
        else {
            Issue.record("Expected current bindings")
            return
        }
        #expect(graph.contains(logicalId: idA))
        #expect(graph.contains(logicalId: idB))
        #expect(engine.findNode(forLogicalId: idA) === nodeA)
        #expect(engine.findNode(forLogicalId: idB) === nodeB)
    }

    @Test @MainActor func dwindleEngineMembershipMatchesGraphLogicalIds() {
        let f = makeFixture()
        let engine = DwindleLayoutEngine()
        let token = addWindow(f.manager, workspaceId: f.workspaceId, windowId: 21_010)

        _ = engine.addWindow(token: token, to: f.workspaceId, activeWindowFrame: nil)
        engine.syncLogicalIds(from: f.manager.logicalWindowRegistry)

        let graph = f.manager.workspaceGraphSnapshot()
        guard case let .current(logicalId) = f.manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current binding")
            return
        }
        #expect(graph.contains(logicalId: logicalId))
        #expect(engine.findNode(forLogicalId: logicalId) != nil)
    }

    @Test @MainActor func niriEngineNeverReceivesRetiredLogicalIds() {
        let f = makeFixture()
        let engine = NiriLayoutEngine()
        let token = addWindow(f.manager, workspaceId: f.workspaceId, windowId: 21_020)
        let node = NiriWindow(token: token)
        engine.tokenToNode[token] = node
        engine.syncLogicalIds(from: f.manager.logicalWindowRegistry)
        guard case let .current(logicalId) = f.manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current binding")
            return
        }

        _ = f.manager.removeWindow(pid: token.pid, windowId: token.windowId)
        engine.syncLogicalIds(from: f.manager.logicalWindowRegistry)

        let graph = f.manager.workspaceGraphSnapshot()
        #expect(!graph.contains(logicalId: logicalId))
        #expect(graph.entry(for: logicalId) == nil)
        #expect(engine.findNode(forLogicalId: logicalId) == nil)
        #expect(node.logicalId == .invalid)
    }

    @Test @MainActor func dwindleEngineNeverReceivesRetiredLogicalIds() {
        let f = makeFixture()
        let engine = DwindleLayoutEngine()
        let token = addWindow(f.manager, workspaceId: f.workspaceId, windowId: 21_030)
        _ = engine.addWindow(token: token, to: f.workspaceId, activeWindowFrame: nil)
        engine.syncLogicalIds(from: f.manager.logicalWindowRegistry)
        guard case let .current(logicalId) = f.manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current binding")
            return
        }

        _ = f.manager.removeWindow(pid: token.pid, windowId: token.windowId)
        engine.syncLogicalIds(from: f.manager.logicalWindowRegistry)
        let graph = f.manager.workspaceGraphSnapshot()
        #expect(!graph.contains(logicalId: logicalId))
        #expect(engine.findNode(forLogicalId: logicalId) == nil)
    }

    @Test @MainActor func projectionEntryTokenEqualsCurrentBinding() {
        let f = makeFixture()
        let token = addWindow(f.manager, workspaceId: f.workspaceId, windowId: 21_040)
        guard case let .current(logicalId) = f.manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current binding")
            return
        }

        let graph = f.manager.workspaceGraphSnapshot()
        #expect(graph.entry(for: logicalId)?.token == token)
        #expect(f.manager.logicalWindowRegistry.currentToken(for: logicalId) == token)
    }
}
