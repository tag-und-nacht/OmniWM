// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing
@testable import OmniWM

@Suite("WorkspaceGraph")
@MainActor
struct WorkspaceGraphTests {
    private struct DirectGraphFixture {
        let graph: WorkspaceGraph
        let workspaceA: WorkspaceDescriptor
        let workspaceB: WorkspaceDescriptor
        let logicalA: LogicalWindowId
        let logicalB: LogicalWindowId
        let tokenA: WindowToken
        let tokenB: WindowToken
    }

    private func makeFixture() -> (WorkspaceManager, SettingsStore, WorkspaceDescriptor.ID) {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let manager = WorkspaceManager(settings: settings)
        manager.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let workspaceId = manager.workspaceId(for: "1", createIfMissing: false)!
        _ = manager.setActiveWorkspace(workspaceId, on: manager.monitors.first!.id)
        return (manager, settings, workspaceId)
    }

    private func makeEntry(
        logicalId: LogicalWindowId,
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        mode: TrackedWindowMode = .tiling,
        quarantine: QuarantineState = .clear
    ) -> WorkspaceGraph.WindowEntry {
        WorkspaceGraph.WindowEntry(
            logicalId: logicalId,
            token: token,
            workspaceId: workspaceId,
            mode: mode,
            lifecyclePhase: mode == .tiling ? .tiled : .floating,
            visibility: .visible,
            quarantine: quarantine,
            floatingState: nil,
            replacementMetadata: nil,
            overlayParentWindowId: nil,
            isHidden: false,
            isMinimized: false,
            isNativeFullscreen: false,
            constraintRuleEffects: .none
        )
    }

    private func makeNode(
        descriptor: WorkspaceDescriptor,
        monitorId: Monitor.ID? = nil,
        tiledOrder: [LogicalWindowId] = [],
        floating: [LogicalWindowId] = [],
        focusedLogicalId: LogicalWindowId? = nil,
        pendingFocusedLogicalId: LogicalWindowId? = nil,
        lastTiledFocusedLogicalId: LogicalWindowId? = nil,
        lastFloatingFocusedLogicalId: LogicalWindowId? = nil
    ) -> WorkspaceGraph.WorkspaceNode {
        WorkspaceGraph.WorkspaceNode(
            workspaceId: descriptor.id,
            descriptor: descriptor,
            layoutType: .defaultLayout,
            monitorId: monitorId,
            tiledOrder: tiledOrder,
            floating: floating,
            suppressed: [],
            focusedLogicalId: focusedLogicalId,
            pendingFocusedLogicalId: pendingFocusedLogicalId,
            lastTiledFocusedLogicalId: lastTiledFocusedLogicalId,
            lastFloatingFocusedLogicalId: lastFloatingFocusedLogicalId
        )
    }

    private func makeDirectGraphFixture() -> DirectGraphFixture {
        let workspaceA = WorkspaceDescriptor(name: "graph-a")
        let workspaceB = WorkspaceDescriptor(name: "graph-b")
        let logicalA = LogicalWindowId(value: 1)
        let logicalB = LogicalWindowId(value: 2)
        let tokenA = WindowToken(pid: 9_001, windowId: 101)
        let tokenB = WindowToken(pid: 9_001, windowId: 102)

        let graph = WorkspaceGraph(
            workspaces: [
                workspaceA.id: makeNode(
                    descriptor: workspaceA,
                    tiledOrder: [logicalA]
                ),
                workspaceB.id: makeNode(descriptor: workspaceB)
            ],
            workspaceOrder: [workspaceA.id, workspaceB.id],
            entriesByLogicalId: [
                logicalA: makeEntry(
                    logicalId: logicalA,
                    token: tokenA,
                    workspaceId: workspaceA.id
                )
            ]
        )

        return DirectGraphFixture(
            graph: graph,
            workspaceA: workspaceA,
            workspaceB: workspaceB,
            logicalA: logicalA,
            logicalB: logicalB,
            tokenA: tokenA,
            tokenB: tokenB
        )
    }

    @Test func managerLiveGraphSatisfiesInvariantsOnInitialization() {
        let (manager, _, _) = makeFixture()
        // The live graph for an empty workspace must satisfy every
        // invariant before entries are added through manager sync points.
        let graph = manager.workspaceGraphSnapshot()
        let violation = WorkspaceGraphInvariants.validate(
            graph,
            registry: manager.logicalWindowRegistry
        )
        #expect(violation == nil)
    }

    @Test func graphAddFloatingMovesSameWorkspaceMembership() {
        let f = makeDirectGraphFixture()

        #expect(f.graph.addFloating(f.logicalA, to: f.workspaceA.id))
        let node = f.graph.node(for: f.workspaceA.id)
        #expect(node?.tiledOrder == [])
        #expect(node?.floating == [f.logicalA])
        #expect(WorkspaceGraphInvariants.validate(f.graph) == nil)
    }

    @Test func graphRejectsCrossWorkspaceDuplicateMembership() {
        let f = makeDirectGraphFixture()

        #expect(!f.graph.addTiled(f.logicalA, to: f.workspaceB.id))
        #expect(f.graph.node(for: f.workspaceA.id)?.tiledOrder == [f.logicalA])
        #expect(f.graph.node(for: f.workspaceB.id)?.tiledOrder == [])
        #expect(WorkspaceGraphInvariants.validate(f.graph) == nil)
    }

    @Test func graphRejectsEntryWorkspaceMismatch() {
        let f = makeDirectGraphFixture()
        let mismatchedEntry = makeEntry(
            logicalId: f.logicalA,
            token: f.tokenA,
            workspaceId: f.workspaceB.id
        )

        #expect(!f.graph.upsertEntry(mismatchedEntry))
        #expect(f.graph.entry(for: f.logicalA)?.workspaceId == f.workspaceA.id)
        #expect(WorkspaceGraphInvariants.validate(f.graph) == nil)
    }

    @Test func graphRejectsOrphanEntryUpsert() {
        let f = makeDirectGraphFixture()
        let orphanEntry = makeEntry(
            logicalId: f.logicalB,
            token: f.tokenB,
            workspaceId: f.workspaceA.id
        )

        #expect(!f.graph.upsertEntry(orphanEntry))
        #expect(f.graph.entry(for: f.logicalB) == nil)
        #expect(WorkspaceGraphInvariants.validate(f.graph) == nil)
    }

    @Test func graphRejectsDroppingEntryStillReferencedByMembership() {
        let f = makeDirectGraphFixture()

        #expect(!f.graph.dropEntry(f.logicalA))
        #expect(f.graph.entry(for: f.logicalA) != nil)
        #expect(f.graph.node(for: f.workspaceA.id)?.tiledOrder == [f.logicalA])
        #expect(WorkspaceGraphInvariants.validate(f.graph) == nil)
    }

    @Test func graphRejectsFocusedLogicalIdOutsideLayoutMembership() {
        let f = makeDirectGraphFixture()

        #expect(!f.graph.setFocused(f.logicalB, in: f.workspaceA.id))
        #expect(f.graph.node(for: f.workspaceA.id)?.focusedLogicalId == nil)
        #expect(WorkspaceGraphInvariants.validate(f.graph) == nil)
    }

    @Test func graphPlaceEntryPreservesOrderForFacetOnlySync() {
        let f = makeDirectGraphFixture()
        #expect(f.graph.placeEntry(
            makeEntry(logicalId: f.logicalB, token: f.tokenB, workspaceId: f.workspaceA.id)
        ))

        let rekeyedToken = WindowToken(pid: f.tokenA.pid, windowId: 201)
        #expect(f.graph.placeEntry(
            makeEntry(logicalId: f.logicalA, token: rekeyedToken, workspaceId: f.workspaceA.id)
        ))

        #expect(f.graph.node(for: f.workspaceA.id)?.tiledOrder == [f.logicalA, f.logicalB])
        #expect(f.graph.entry(for: f.logicalA)?.token == rekeyedToken)
        #expect(WorkspaceGraphInvariants.validate(f.graph) == nil)
    }

    @Test func graphPlaceEntrySuppressionPreservesRememberedFocus() {
        let workspace = WorkspaceDescriptor(name: "graph-focus")
        let logicalId = LogicalWindowId(value: 42)
        let token = WindowToken(pid: 9_002, windowId: 401)
        let graph = WorkspaceGraph(
            workspaces: [
                workspace.id: makeNode(
                    descriptor: workspace,
                    tiledOrder: [logicalId],
                    focusedLogicalId: logicalId,
                    pendingFocusedLogicalId: logicalId,
                    lastTiledFocusedLogicalId: logicalId
                )
            ],
            workspaceOrder: [workspace.id],
            entriesByLogicalId: [
                logicalId: makeEntry(logicalId: logicalId, token: token, workspaceId: workspace.id)
            ]
        )

        #expect(graph.placeEntry(
            makeEntry(
                logicalId: logicalId,
                token: token,
                workspaceId: workspace.id,
                quarantine: .quarantined(reason: .axReadFailure)
            )
        ))

        let node = graph.node(for: workspace.id)
        #expect(node?.tiledOrder == [])
        #expect(node?.suppressed == [logicalId])
        #expect(node?.focusedLogicalId == nil)
        #expect(node?.pendingFocusedLogicalId == nil)
        #expect(node?.lastTiledFocusedLogicalId == logicalId)
        #expect(WorkspaceGraphInvariants.validate(graph) == nil)
    }

    @Test func graphUpdateMonitorIdsClearsWorkspacesMissingFromProjection() {
        let monitorId = makeLayoutPlanTestMonitor().id
        let workspace = WorkspaceDescriptor(name: "graph-monitor")
        let graph = WorkspaceGraph(
            workspaces: [
                workspace.id: makeNode(
                    descriptor: workspace,
                    monitorId: monitorId
                )
            ],
            workspaceOrder: [workspace.id],
            entriesByLogicalId: [:]
        )

        #expect(graph.updateMonitorIds([:]))
        #expect(graph.node(for: workspace.id)?.monitorId == nil)
        #expect(WorkspaceGraphInvariants.validate(graph) == nil)
    }
}
