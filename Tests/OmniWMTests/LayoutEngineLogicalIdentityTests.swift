// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct LayoutEngineLogicalIdentityTests {

    @Test @MainActor func niriAssignLogicalIdMakesNodeFindableByLogicalKey() {
        let engine = NiriLayoutEngine()
        let token = WindowToken(pid: 7777, windowId: 700)
        let node = NiriWindow(token: token)
        engine.tokenToNode[token] = node
        let logicalId = LogicalWindowId(value: 42)

        engine.assignLogicalId(logicalId, to: node)

        #expect(engine.findNode(forLogicalId: logicalId) === node)
        #expect(node.logicalId == logicalId)
    }

    @Test @MainActor func niriRekeyPreservesLogicalIdIndexWithoutRewrite() {
        let engine = NiriLayoutEngine()
        let oldToken = WindowToken(pid: 7777, windowId: 701)
        let newToken = WindowToken(pid: 7777, windowId: 702)
        let node = NiriWindow(token: oldToken)
        engine.tokenToNode[oldToken] = node
        let logicalId = LogicalWindowId(value: 7)
        engine.assignLogicalId(logicalId, to: node)

        let rekeyed = engine.rekeyWindow(from: oldToken, to: newToken)
        #expect(rekeyed)

        #expect(engine.findNode(for: newToken) === node)
        #expect(engine.findNode(for: oldToken) == nil)
        #expect(engine.findNode(forLogicalId: logicalId) === node)
        #expect(node.logicalId == logicalId)
    }

    @Test @MainActor func niriAssignLogicalIdRebindsExistingNodeIndex() {
        let engine = NiriLayoutEngine()
        let token = WindowToken(pid: 7777, windowId: 703)
        let node = NiriWindow(token: token)
        engine.tokenToNode[token] = node

        let firstId = LogicalWindowId(value: 100)
        let secondId = LogicalWindowId(value: 200)
        engine.assignLogicalId(firstId, to: node)
        engine.assignLogicalId(secondId, to: node)

        #expect(engine.findNode(forLogicalId: firstId) == nil)
        #expect(engine.findNode(forLogicalId: secondId) === node)
        #expect(node.logicalId == secondId)
    }

    @Test @MainActor func niriAssignLogicalIdIgnoresInvalidId() {
        let engine = NiriLayoutEngine()
        let token = WindowToken(pid: 7777, windowId: 704)
        let node = NiriWindow(token: token)
        engine.tokenToNode[token] = node

        engine.assignLogicalId(.invalid, to: node)
        #expect(node.logicalId == .invalid)
        #expect(engine.findNode(forLogicalId: .invalid) == nil)
    }

    @Test @MainActor func niriSyncLogicalIdsBindsAllNodesFromRegistry() {
        let engine = NiriLayoutEngine()
        let registry = LogicalWindowRegistry()
        let workspaceId = WorkspaceDescriptor(name: "ws").id

        let tokenA = WindowToken(pid: 7777, windowId: 800)
        let tokenB = WindowToken(pid: 7777, windowId: 801)
        let nodeA = NiriWindow(token: tokenA)
        let nodeB = NiriWindow(token: tokenB)
        engine.tokenToNode[tokenA] = nodeA
        engine.tokenToNode[tokenB] = nodeB

        let idA = registry.allocate(
            boundTo: tokenA,
            workspaceId: workspaceId,
            monitorId: nil
        )
        let idB = registry.allocate(
            boundTo: tokenB,
            workspaceId: workspaceId,
            monitorId: nil
        )

        engine.syncLogicalIds(from: registry)
        #expect(engine.findNode(forLogicalId: idA) === nodeA)
        #expect(engine.findNode(forLogicalId: idB) === nodeB)
    }


    @Test @MainActor func dwindleAssignLogicalIdMakesNodeFindableByLogicalKey() {
        let engine = DwindleLayoutEngine()
        let token = WindowToken(pid: 7777, windowId: 900)
        let workspaceId = WorkspaceDescriptor(name: "ws").id
        _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
        guard let node = engine.findNode(for: token) else {
            Issue.record("Expected dwindle leaf for token after addWindow")
            return
        }

        let logicalId = LogicalWindowId(value: 11)
        engine.assignLogicalId(logicalId, to: node)

        #expect(engine.findNode(forLogicalId: logicalId) === node)
        #expect(node.logicalId == logicalId)
    }

    @Test @MainActor func dwindleRekeyPreservesLogicalIdIndexWithoutRewrite() {
        let engine = DwindleLayoutEngine()
        let oldToken = WindowToken(pid: 7777, windowId: 901)
        let newToken = WindowToken(pid: 7777, windowId: 902)
        let workspaceId = WorkspaceDescriptor(name: "ws").id

        _ = engine.addWindow(token: oldToken, to: workspaceId, activeWindowFrame: nil)
        guard let node = engine.findNode(for: oldToken) else {
            Issue.record("Expected dwindle leaf for oldToken")
            return
        }

        let logicalId = LogicalWindowId(value: 13)
        engine.assignLogicalId(logicalId, to: node)

        let rekeyed = engine.rekeyWindow(from: oldToken, to: newToken, in: workspaceId)
        #expect(rekeyed)

        #expect(engine.findNode(for: newToken) === node)
        #expect(engine.findNode(for: oldToken) == nil)
        #expect(engine.findNode(forLogicalId: logicalId) === node)
        #expect(node.logicalId == logicalId)
    }

    @Test @MainActor func dwindleRemoveDropsLogicalIdIndexEntry() {
        let engine = DwindleLayoutEngine()
        let token = WindowToken(pid: 7777, windowId: 903)
        let workspaceId = WorkspaceDescriptor(name: "ws").id
        _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
        guard let node = engine.findNode(for: token) else {
            Issue.record("Expected dwindle leaf for token after addWindow")
            return
        }
        let logicalId = LogicalWindowId(value: 17)
        engine.assignLogicalId(logicalId, to: node)
        #expect(engine.findNode(forLogicalId: logicalId) === node)

        engine.removeWindow(token: token, from: workspaceId)
        #expect(engine.findNode(forLogicalId: logicalId) == nil)
    }

    @Test @MainActor func dwindleSyncLogicalIdsBindsAllLeavesFromRegistry() {
        let engine = DwindleLayoutEngine()
        let registry = LogicalWindowRegistry()
        let workspaceId = WorkspaceDescriptor(name: "ws").id

        let tokenA = WindowToken(pid: 7777, windowId: 910)
        let tokenB = WindowToken(pid: 7777, windowId: 911)
        _ = engine.addWindow(token: tokenA, to: workspaceId, activeWindowFrame: nil)
        _ = engine.addWindow(token: tokenB, to: workspaceId, activeWindowFrame: nil)

        let idA = registry.allocate(
            boundTo: tokenA,
            workspaceId: workspaceId,
            monitorId: nil
        )
        let idB = registry.allocate(
            boundTo: tokenB,
            workspaceId: workspaceId,
            monitorId: nil
        )

        engine.syncLogicalIds(from: registry)
        #expect(engine.findNode(forLogicalId: idA) != nil)
        #expect(engine.findNode(forLogicalId: idB) != nil)
        #expect(engine.findNode(forLogicalId: idA) === engine.findNode(for: tokenA))
        #expect(engine.findNode(forLogicalId: idB) === engine.findNode(for: tokenB))
    }
}
