// SPDX-License-Identifier: GPL-2.0-only
import Foundation

// MainActor-isolated because `WorkspaceGraph` is now a `@MainActor final
// class` (ExecPlan 04 WGT-INV-02). Reading its properties from a non-
// MainActor context would fail compile.
@MainActor
enum WorkspaceGraphInvariants {
    enum Violation: Equatable {
        case windowAppearsInMultipleWorkspaces(LogicalWindowId, [WorkspaceDescriptor.ID])
        case windowAppearsInBothTiledAndFloating(LogicalWindowId, WorkspaceDescriptor.ID)
        case retiredLogicalIdReferenced(LogicalWindowId)
        case workspaceMembershipMissingFromIndex(LogicalWindowId, WorkspaceDescriptor.ID)
        case indexEntryMissingFromWorkspaceMembership(LogicalWindowId, WorkspaceDescriptor.ID)
        case indexEntryWorkspaceMismatch(
            LogicalWindowId,
            membershipWorkspace: WorkspaceDescriptor.ID,
            indexedWorkspace: WorkspaceDescriptor.ID
        )
        case layoutIneligibleWindowInLayoutMembership(LogicalWindowId, WorkspaceDescriptor.ID)
        case windowAppearsInBothLayoutAndSuppressed(LogicalWindowId, WorkspaceDescriptor.ID)
        case focusedLogicalIdMissingFromLayoutMembership(LogicalWindowId, WorkspaceDescriptor.ID)
        case pendingFocusedLogicalIdMissingFromLayoutMembership(LogicalWindowId, WorkspaceDescriptor.ID)
        case projectedTokenDisagreesWithRegistry(LogicalWindowId, WindowToken, WindowToken?)
    }

    static func eachLogicalIdInExactlyOneWorkspace(
        _ graph: WorkspaceGraph
    ) -> Violation? {
        var seenWorkspaces: [LogicalWindowId: [WorkspaceDescriptor.ID]] = [:]
        for node in graph.workspaces.values {
            for logicalId in node.tiledOrder + node.floating + node.suppressed {
                seenWorkspaces[logicalId, default: []].append(node.workspaceId)
            }
        }
        for (logicalId, workspaces) in seenWorkspaces where workspaces.count > 1 {
            return .windowAppearsInMultipleWorkspaces(logicalId, workspaces)
        }
        return nil
    }

    static func tiledAndFloatingDisjoint(
        _ graph: WorkspaceGraph
    ) -> Violation? {
        for node in graph.workspaces.values {
            let tiled = Set(node.tiledOrder)
            let floating = Set(node.floating)
            if let overlap = tiled.intersection(floating).first {
                return .windowAppearsInBothTiledAndFloating(overlap, node.workspaceId)
            }
            let layout = tiled.union(floating)
            let suppressed = Set(node.suppressed)
            if let overlap = layout.intersection(suppressed).first {
                return .windowAppearsInBothLayoutAndSuppressed(overlap, node.workspaceId)
            }
        }
        return nil
    }

    static func layoutMembershipIsEligible(
        _ graph: WorkspaceGraph
    ) -> Violation? {
        for node in graph.workspaces.values {
            for logicalId in node.tiledOrder + node.floating {
                guard let entry = graph.entriesByLogicalId[logicalId] else {
                    return .workspaceMembershipMissingFromIndex(logicalId, node.workspaceId)
                }
                if !entry.isLayoutEligible {
                    return .layoutIneligibleWindowInLayoutMembership(logicalId, node.workspaceId)
                }
            }
        }
        return nil
    }

    static func indexAgreesWithMembership(
        _ graph: WorkspaceGraph
    ) -> Violation? {
        var indexed = Set(graph.entriesByLogicalId.keys)
        for node in graph.workspaces.values {
            for logicalId in node.tiledOrder + node.floating + node.suppressed {
                guard let entry = graph.entriesByLogicalId[logicalId] else {
                    return .workspaceMembershipMissingFromIndex(logicalId, node.workspaceId)
                }
                if entry.workspaceId != node.workspaceId {
                    return .indexEntryWorkspaceMismatch(
                        logicalId,
                        membershipWorkspace: node.workspaceId,
                        indexedWorkspace: entry.workspaceId
                    )
                }
                indexed.remove(logicalId)
            }
        }
        if let orphan = indexed.first,
           let workspaceId = graph.entriesByLogicalId[orphan]?.workspaceId {
            return .indexEntryMissingFromWorkspaceMembership(orphan, workspaceId)
        }
        return nil
    }

    static func focusedLogicalIdsReferenceLayoutMembership(
        _ graph: WorkspaceGraph
    ) -> Violation? {
        for node in graph.workspaces.values {
            let layoutMembership = Set(node.tiledOrder + node.floating)
            if let focused = node.focusedLogicalId,
               !layoutMembership.contains(focused) {
                return .focusedLogicalIdMissingFromLayoutMembership(focused, node.workspaceId)
            }
            if let pending = node.pendingFocusedLogicalId,
               !layoutMembership.contains(pending) {
                return .pendingFocusedLogicalIdMissingFromLayoutMembership(pending, node.workspaceId)
            }
        }
        return nil
    }

    @MainActor
    static func projectedTokensMatchRegistry(
        _ graph: WorkspaceGraph,
        registry: any LogicalWindowRegistryReading
    ) -> Violation? {
        for entry in graph.entriesByLogicalId.values {
            let registryToken = registry.currentToken(for: entry.logicalId)
            if registryToken != entry.token {
                return .projectedTokenDisagreesWithRegistry(
                    entry.logicalId,
                    entry.token,
                    registryToken
                )
            }
        }
        return nil
    }

    static func validate(_ graph: WorkspaceGraph) -> Violation? {
        if let violation = eachLogicalIdInExactlyOneWorkspace(graph) {
            return violation
        }
        if let violation = tiledAndFloatingDisjoint(graph) {
            return violation
        }
        if let violation = layoutMembershipIsEligible(graph) {
            return violation
        }
        if let violation = indexAgreesWithMembership(graph) {
            return violation
        }
        if let violation = focusedLogicalIdsReferenceLayoutMembership(graph) {
            return violation
        }
        return nil
    }

    @MainActor
    static func validate(
        _ graph: WorkspaceGraph,
        registry: any LogicalWindowRegistryReading
    ) -> Violation? {
        if let violation = validate(graph) {
            return violation
        }
        if let violation = projectedTokensMatchRegistry(graph, registry: registry) {
            return violation
        }
        return nil
    }
}
