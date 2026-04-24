// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OSLog

private let workspaceGraphLog = Logger(
    subsystem: "com.omniwm.core",
    category: "WorkspaceGraph"
)

/// Authoritative workspace structure: workspace nodes, tiled/floating order,
/// layout-suppressed membership, and per-workspace focus pointers live here.
/// `WorkspaceManager` and its registries still own OS-facing per-window state;
/// manager mutators refresh the affected graph entry at the same transaction
/// boundary so structural readers never need to re-project from `WindowModel`.
@MainActor
final class WorkspaceGraph: @MainActor Equatable {
    struct WindowEntry: Equatable {
        let logicalId: LogicalWindowId
        let token: WindowToken
        let workspaceId: WorkspaceDescriptor.ID
        let mode: TrackedWindowMode
        let lifecyclePhase: WindowLifecyclePhase
        let visibility: LifecycleVisibility
        let quarantine: QuarantineState
        let floatingState: WindowModel.FloatingState?
        let replacementMetadata: ManagedReplacementMetadata?
        let overlayParentWindowId: UInt32?
        let hiddenState: WindowModel.HiddenState?
        let isHidden: Bool
        let isMinimized: Bool
        let isNativeFullscreen: Bool
        let constraintRuleEffects: LayoutConstraintRuleEffects

        init(
            logicalId: LogicalWindowId,
            token: WindowToken,
            workspaceId: WorkspaceDescriptor.ID,
            mode: TrackedWindowMode,
            lifecyclePhase: WindowLifecyclePhase,
            visibility: LifecycleVisibility,
            quarantine: QuarantineState,
            floatingState: WindowModel.FloatingState?,
            replacementMetadata: ManagedReplacementMetadata?,
            overlayParentWindowId: UInt32?,
            hiddenState: WindowModel.HiddenState? = nil,
            isHidden: Bool,
            isMinimized: Bool,
            isNativeFullscreen: Bool,
            constraintRuleEffects: LayoutConstraintRuleEffects
        ) {
            self.logicalId = logicalId
            self.token = token
            self.workspaceId = workspaceId
            self.mode = mode
            self.lifecyclePhase = lifecyclePhase
            self.visibility = visibility
            self.quarantine = quarantine
            self.floatingState = floatingState
            self.replacementMetadata = replacementMetadata
            self.overlayParentWindowId = overlayParentWindowId
            self.hiddenState = hiddenState
            self.isHidden = isHidden
            self.isMinimized = isMinimized
            self.isNativeFullscreen = isNativeFullscreen
            self.constraintRuleEffects = constraintRuleEffects
        }

        var isLayoutEligible: Bool {
            guard !isMinimized else { return false }
            return !quarantine.suppressesLayout
        }
    }

    struct WorkspaceNode: Equatable {
        let workspaceId: WorkspaceDescriptor.ID
        let descriptor: WorkspaceDescriptor
        let layoutType: LayoutType
        var monitorId: Monitor.ID?
        var tiledOrder: [LogicalWindowId]
        var floating: [LogicalWindowId]
        var suppressed: [LogicalWindowId]
        var focusedLogicalId: LogicalWindowId?
        var pendingFocusedLogicalId: LogicalWindowId?
        var lastTiledFocusedLogicalId: LogicalWindowId?
        var lastFloatingFocusedLogicalId: LogicalWindowId?
    }

    private(set) var workspaces: [WorkspaceDescriptor.ID: WorkspaceNode]
    private(set) var workspaceOrder: [WorkspaceDescriptor.ID]
    private(set) var entriesByLogicalId: [LogicalWindowId: WindowEntry]

    enum MembershipKind {
        case tiled
        case floating
        case suppressed
    }

    init(
        workspaces: [WorkspaceDescriptor.ID: WorkspaceNode],
        workspaceOrder: [WorkspaceDescriptor.ID],
        entriesByLogicalId: [LogicalWindowId: WindowEntry]
    ) {
        self.workspaces = workspaces
        self.workspaceOrder = workspaceOrder
        self.entriesByLogicalId = entriesByLogicalId
    }

    static func == (lhs: WorkspaceGraph, rhs: WorkspaceGraph) -> Bool {
        lhs.workspaces == rhs.workspaces
            && lhs.workspaceOrder == rhs.workspaceOrder
            && lhs.entriesByLogicalId == rhs.entriesByLogicalId
    }

    func node(for workspaceId: WorkspaceDescriptor.ID) -> WorkspaceNode? {
        workspaces[workspaceId]
    }

    func snapshot() -> WorkspaceGraph {
        WorkspaceGraph(
            workspaces: workspaces,
            workspaceOrder: workspaceOrder,
            entriesByLogicalId: entriesByLogicalId
        )
    }

    private func rejectMutation(
        operation: String,
        violation: WorkspaceGraphInvariants.Violation
    ) -> Bool {
        let violationText = String(describing: violation)
        workspaceGraphLog.fault(
            "graph_mutation_rejected op=\(operation, privacy: .public) reason=\(violationText, privacy: .public)"
        )
        return false
    }

    @discardableResult
    private func mutateWorkspaceNode(
        operation: String,
        workspaceId: WorkspaceDescriptor.ID,
        _ mutate: (inout WorkspaceNode) -> Bool
    ) -> Bool {
        guard var node = workspaces[workspaceId] else { return false }
        let previousNode = node
        guard mutate(&node) else { return false }

        workspaces[workspaceId] = node
        if let violation = WorkspaceGraphInvariants.validate(self) {
            workspaces[workspaceId] = previousNode
            return rejectMutation(operation: operation, violation: violation)
        }
        return true
    }

    @discardableResult
    private func mutateGraph(
        operation: String,
        _ mutate: () -> Bool
    ) -> Bool {
        let previousWorkspaces = workspaces
        let previousOrder = workspaceOrder
        let previousEntries = entriesByLogicalId
        guard mutate() else { return false }
        if let violation = WorkspaceGraphInvariants.validate(self) {
            workspaces = previousWorkspaces
            workspaceOrder = previousOrder
            entriesByLogicalId = previousEntries
            return rejectMutation(operation: operation, violation: violation)
        }
        return true
    }

    private func removeMembershipReferences(
        to logicalId: LogicalWindowId,
        clearFocus: Bool,
        in node: inout WorkspaceNode
    ) {
        node.tiledOrder.removeAll(where: { $0 == logicalId })
        node.floating.removeAll(where: { $0 == logicalId })
        node.suppressed.removeAll(where: { $0 == logicalId })
        guard clearFocus else { return }
        _ = clearAllFocusReferences(to: logicalId, in: &node)
    }

    private func clearActiveFocusReferences(
        to logicalId: LogicalWindowId,
        in node: inout WorkspaceNode
    ) -> Bool {
        let before = node
        if node.focusedLogicalId == logicalId {
            node.focusedLogicalId = nil
        }
        if node.pendingFocusedLogicalId == logicalId {
            node.pendingFocusedLogicalId = nil
        }
        return before != node
    }

    private func clearAllFocusReferences(
        to logicalId: LogicalWindowId,
        in node: inout WorkspaceNode
    ) -> Bool {
        let before = node
        _ = clearActiveFocusReferences(to: logicalId, in: &node)
        if node.lastTiledFocusedLogicalId == logicalId {
            node.lastTiledFocusedLogicalId = nil
        }
        if node.lastFloatingFocusedLogicalId == logicalId {
            node.lastFloatingFocusedLogicalId = nil
        }
        return before != node
    }

    private func membershipKind(for entry: WindowEntry) -> MembershipKind {
        guard entry.isLayoutEligible else { return .suppressed }
        switch entry.mode {
        case .tiling:
            return .tiled
        case .floating:
            return .floating
        }
    }

    private func appendMembership(
        _ logicalId: LogicalWindowId,
        kind: MembershipKind,
        to node: inout WorkspaceNode
    ) {
        switch kind {
        case .tiled:
            if !node.tiledOrder.contains(logicalId) {
                node.tiledOrder.append(logicalId)
            }
        case .floating:
            if !node.floating.contains(logicalId) {
                node.floating.append(logicalId)
            }
        case .suppressed:
            if !node.suppressed.contains(logicalId) {
                node.suppressed.append(logicalId)
            }
        }
    }

    private func removeWorkspaceNode(
        _ workspaceId: WorkspaceDescriptor.ID
    ) {
        workspaces.removeValue(forKey: workspaceId)
        workspaceOrder.removeAll(where: { $0 == workspaceId })
    }

    // MARK: Workspace metadata

    @discardableResult
    func replaceWorkspaces(
        _ descriptors: [WorkspaceDescriptor],
        layoutTypeFor: (WorkspaceDescriptor) -> LayoutType,
        monitorIdFor: (WorkspaceDescriptor.ID) -> Monitor.ID?
    ) -> Bool {
        mutateGraph(operation: "replaceWorkspaces") {
            let descriptorIds = Set(descriptors.map(\.id))
            for workspaceId in workspaces.keys where !descriptorIds.contains(workspaceId) {
                removeWorkspaceNode(workspaceId)
            }

            workspaceOrder = descriptors.map(\.id)
            for descriptor in descriptors {
                let existing = workspaces[descriptor.id]
                workspaces[descriptor.id] = WorkspaceNode(
                    workspaceId: descriptor.id,
                    descriptor: descriptor,
                    layoutType: layoutTypeFor(descriptor),
                    monitorId: monitorIdFor(descriptor.id),
                    tiledOrder: existing?.tiledOrder ?? [],
                    floating: existing?.floating ?? [],
                    suppressed: existing?.suppressed ?? [],
                    focusedLogicalId: existing?.focusedLogicalId,
                    pendingFocusedLogicalId: existing?.pendingFocusedLogicalId,
                    lastTiledFocusedLogicalId: existing?.lastTiledFocusedLogicalId,
                    lastFloatingFocusedLogicalId: existing?.lastFloatingFocusedLogicalId
                )
            }
            return true
        }
    }

    @discardableResult
    func updateMonitorIds(
        _ monitorIdsByWorkspace: [WorkspaceDescriptor.ID: Monitor.ID?]
    ) -> Bool {
        mutateGraph(operation: "updateMonitorIds") {
            var changed = false
            for workspaceId in workspaces.keys {
                // Absence from the projection map means the workspace is
                // currently unresolved, so clear any previously cached monitor.
                let monitorId = monitorIdsByWorkspace[workspaceId, default: nil]
                guard var node = workspaces[workspaceId],
                      node.monitorId != monitorId
                else { continue }
                node.monitorId = monitorId
                workspaces[workspaceId] = node
                changed = true
            }
            return changed
        }
    }

    // MARK: Mutator surface (ExecPlan 04 WGT-INV-02..04)

    /// Append `logicalId` to the tiled order of `workspaceId` if not already
    /// present. Removes any prior floating / suppressed listing in the same
    /// workspace to maintain the disjoint-membership invariant.
    @discardableResult
    func addTiled(
        _ logicalId: LogicalWindowId,
        to workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        mutateWorkspaceNode(
            operation: "addTiled",
            workspaceId: workspaceId
        ) { node in
            node.floating.removeAll(where: { $0 == logicalId })
            node.suppressed.removeAll(where: { $0 == logicalId })
            if !node.tiledOrder.contains(logicalId) {
                node.tiledOrder.append(logicalId)
            }
            return true
        }
    }

    /// Remove `logicalId` from the tiled order of `workspaceId` (no-op if
    /// it isn't there).
    @discardableResult
    func removeTiled(
        _ logicalId: LogicalWindowId,
        from workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        mutateWorkspaceNode(
            operation: "removeTiled",
            workspaceId: workspaceId
        ) { node in
            let before = node.tiledOrder.count
            node.tiledOrder.removeAll(where: { $0 == logicalId })
            return node.tiledOrder.count != before
        }
    }

    /// Append `logicalId` to the floating list of `workspaceId` if not
    /// already present. Removes any prior tiled / suppressed listing.
    @discardableResult
    func addFloating(
        _ logicalId: LogicalWindowId,
        to workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        mutateWorkspaceNode(
            operation: "addFloating",
            workspaceId: workspaceId
        ) { node in
            node.tiledOrder.removeAll(where: { $0 == logicalId })
            node.suppressed.removeAll(where: { $0 == logicalId })
            if !node.floating.contains(logicalId) {
                node.floating.append(logicalId)
            }
            return true
        }
    }

    /// Remove `logicalId` from the floating list of `workspaceId`.
    @discardableResult
    func removeFloating(
        _ logicalId: LogicalWindowId,
        from workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        mutateWorkspaceNode(
            operation: "removeFloating",
            workspaceId: workspaceId
        ) { node in
            let before = node.floating.count
            node.floating.removeAll(where: { $0 == logicalId })
            return node.floating.count != before
        }
    }

    /// Set the focused logical id within `workspaceId`. Pass `nil` to clear.
    @discardableResult
    func setFocused(
        _ logicalId: LogicalWindowId?,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        mutateWorkspaceNode(
            operation: "setFocused",
            workspaceId: workspaceId
        ) { node in
            guard node.focusedLogicalId != logicalId else { return false }
            node.focusedLogicalId = logicalId
            return true
        }
    }

    /// Set the pending-focused logical id within `workspaceId`.
    @discardableResult
    func setPendingFocused(
        _ logicalId: LogicalWindowId?,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        mutateWorkspaceNode(
            operation: "setPendingFocused",
            workspaceId: workspaceId
        ) { node in
            guard node.pendingFocusedLogicalId != logicalId else { return false }
            node.pendingFocusedLogicalId = logicalId
            return true
        }
    }

    /// Insert / overwrite a window entry in the index.
    @discardableResult
    func upsertEntry(_ entry: WindowEntry) -> Bool {
        let previousEntry = entriesByLogicalId[entry.logicalId]
        entriesByLogicalId[entry.logicalId] = entry
        if let violation = WorkspaceGraphInvariants.validate(self) {
            if let previousEntry {
                entriesByLogicalId[entry.logicalId] = previousEntry
            } else {
                entriesByLogicalId.removeValue(forKey: entry.logicalId)
            }
            return rejectMutation(operation: "upsertEntry", violation: violation)
        }
        return true
    }

    /// Drop a window entry from the index only when no workspace membership
    /// references it. Runtime removal should use `removeEntry(_:)`, which
    /// clears membership and entry atomically.
    @discardableResult
    func dropEntry(_ logicalId: LogicalWindowId) -> Bool {
        guard let previousEntry = entriesByLogicalId.removeValue(forKey: logicalId) else {
            return false
        }
        if let violation = WorkspaceGraphInvariants.validate(self) {
            entriesByLogicalId[logicalId] = previousEntry
            return rejectMutation(operation: "dropEntry", violation: violation)
        }
        return true
    }

    @discardableResult
    func placeEntry(_ entry: WindowEntry) -> Bool {
        mutateGraph(operation: "placeEntry") {
            guard workspaces[entry.workspaceId] != nil else { return false }
            let previousEntry = entriesByLogicalId[entry.logicalId]
            let previousKind = previousEntry.map(membershipKind(for:))
            let nextKind = membershipKind(for: entry)
            let shouldClearRememberedFocus = previousEntry.map {
                $0.workspaceId != entry.workspaceId || $0.mode != entry.mode
            } ?? false

            for workspaceId in Array(workspaces.keys) {
                guard var node = workspaces[workspaceId] else { continue }
                let sameMembership = previousEntry?.workspaceId == entry.workspaceId
                    && workspaceId == entry.workspaceId
                    && previousKind == nextKind

                if !sameMembership {
                    removeMembershipReferences(
                        to: entry.logicalId,
                        clearFocus: shouldClearRememberedFocus,
                        in: &node
                    )
                }
                if workspaceId == entry.workspaceId, !entry.isLayoutEligible {
                    _ = clearActiveFocusReferences(to: entry.logicalId, in: &node)
                }
                workspaces[workspaceId] = node
            }

            entriesByLogicalId[entry.logicalId] = entry
            guard var targetNode = workspaces[entry.workspaceId] else { return false }
            appendMembership(
                entry.logicalId,
                kind: membershipKind(for: entry),
                to: &targetNode
            )
            workspaces[entry.workspaceId] = targetNode
            return true
        }
    }

    @discardableResult
    func removeEntry(_ logicalId: LogicalWindowId) -> Bool {
        mutateGraph(operation: "removeEntry") {
            guard entriesByLogicalId.removeValue(forKey: logicalId) != nil else {
                return false
            }
            for workspaceId in Array(workspaces.keys) {
                guard var node = workspaces[workspaceId] else { continue }
                removeMembershipReferences(to: logicalId, clearFocus: true, in: &node)
                workspaces[workspaceId] = node
            }
            return true
        }
    }

    @discardableResult
    func swapTiledOrder(
        _ lhs: LogicalWindowId,
        _ rhs: LogicalWindowId,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        mutateWorkspaceNode(
            operation: "swapTiledOrder",
            workspaceId: workspaceId
        ) { node in
            guard let lhsIndex = node.tiledOrder.firstIndex(of: lhs),
                  let rhsIndex = node.tiledOrder.firstIndex(of: rhs),
                  lhsIndex != rhsIndex
            else {
                return false
            }
            node.tiledOrder.swapAt(lhsIndex, rhsIndex)
            return true
        }
    }

    @discardableResult
    func setLastFocused(
        _ logicalId: LogicalWindowId?,
        in workspaceId: WorkspaceDescriptor.ID,
        mode: TrackedWindowMode
    ) -> Bool {
        mutateWorkspaceNode(
            operation: "setLastFocused",
            workspaceId: workspaceId
        ) { node in
            switch mode {
            case .tiling:
                guard node.lastTiledFocusedLogicalId != logicalId else { return false }
                node.lastTiledFocusedLogicalId = logicalId
            case .floating:
                guard node.lastFloatingFocusedLogicalId != logicalId else { return false }
                node.lastFloatingFocusedLogicalId = logicalId
            }
            return true
        }
    }

    @discardableResult
    func clearFocusReferences(
        to logicalId: LogicalWindowId,
        in workspaceId: WorkspaceDescriptor.ID? = nil
    ) -> Bool {
        mutateGraph(operation: "clearFocusReferences") {
            var changed = false
            let ids = workspaceId.map { [$0] } ?? Array(workspaces.keys)
            for id in ids {
                guard var node = workspaces[id] else { continue }
                if clearAllFocusReferences(to: logicalId, in: &node) {
                    workspaces[id] = node
                    changed = true
                }
            }
            return changed
        }
    }

    @discardableResult
    func replaceActiveFocus(
        focused focusedLogicalId: LogicalWindowId?,
        focusedWorkspaceId: WorkspaceDescriptor.ID?,
        pending pendingLogicalId: LogicalWindowId?,
        pendingWorkspaceId: WorkspaceDescriptor.ID?
    ) -> Bool {
        mutateGraph(operation: "replaceActiveFocus") {
            var changed = false
            for workspaceId in Array(workspaces.keys) {
                guard var node = workspaces[workspaceId] else { continue }
                let nextFocused = workspaceId == focusedWorkspaceId ? focusedLogicalId : nil
                let nextPending = workspaceId == pendingWorkspaceId ? pendingLogicalId : nil
                if node.focusedLogicalId != nextFocused {
                    node.focusedLogicalId = nextFocused
                    changed = true
                }
                if node.pendingFocusedLogicalId != nextPending {
                    node.pendingFocusedLogicalId = nextPending
                    changed = true
                }
                workspaces[workspaceId] = node
            }
            return changed
        }
    }

    func tiledMembership(in workspaceId: WorkspaceDescriptor.ID) -> [WindowEntry] {
        guard let node = workspaces[workspaceId] else { return [] }
        return node.tiledOrder.compactMap { entriesByLogicalId[$0] }
    }

    func floatingMembership(in workspaceId: WorkspaceDescriptor.ID) -> [WindowEntry] {
        guard let node = workspaces[workspaceId] else { return [] }
        return node.floating.compactMap { entriesByLogicalId[$0] }
    }

    func suppressedMembership(in workspaceId: WorkspaceDescriptor.ID) -> [WindowEntry] {
        guard let node = workspaces[workspaceId] else { return [] }
        return node.suppressed.compactMap { entriesByLogicalId[$0] }
    }

    func entry(for logicalId: LogicalWindowId) -> WindowEntry? {
        entriesByLogicalId[logicalId]
    }

    @MainActor
    func entry(
        for token: WindowToken,
        registry: any LogicalWindowRegistryReading
    ) -> WindowEntry? {
        switch registry.lookup(token: token) {
        case let .current(logicalId), let .staleAlias(logicalId):
            return entriesByLogicalId[logicalId]
        case .retired, .unknown:
            return nil
        }
    }

    func workspaceId(containing logicalId: LogicalWindowId) -> WorkspaceDescriptor.ID? {
        entriesByLogicalId[logicalId]?.workspaceId
    }

    func contains(logicalId: LogicalWindowId) -> Bool {
        entriesByLogicalId[logicalId] != nil
    }

    var allLogicalIds: Set<LogicalWindowId> {
        Set(entriesByLogicalId.keys)
    }

    func stateSnapshot() -> WorkspaceGraphStateSnapshot {
        WorkspaceGraphStateSnapshot(
            workspaces: workspaces,
            workspaceOrder: workspaceOrder,
            entriesByLogicalId: entriesByLogicalId
        )
    }
}

struct WorkspaceGraphStateSnapshot: Equatable {
    static let empty = WorkspaceGraphStateSnapshot(
        workspaces: [:],
        workspaceOrder: [],
        entriesByLogicalId: [:]
    )

    let workspaces: [WorkspaceDescriptor.ID: WorkspaceGraph.WorkspaceNode]
    let workspaceOrder: [WorkspaceDescriptor.ID]
    let entriesByLogicalId: [LogicalWindowId: WorkspaceGraph.WindowEntry]
}

extension WorkspaceGraph {
    func preservedShape(equals other: WorkspaceGraph) -> Bool {
        guard Set(workspaceOrder) == Set(other.workspaceOrder) else {
            return false
        }
        for (workspaceId, node) in workspaces {
            guard let otherNode = other.workspaces[workspaceId] else { return false }
            if node.monitorId != otherNode.monitorId { return false }
            if Set(node.tiledOrder) != Set(otherNode.tiledOrder) { return false }
            if Set(node.floating) != Set(otherNode.floating) { return false }
            if Set(node.suppressed) != Set(otherNode.suppressed) { return false }
            if node.focusedLogicalId != otherNode.focusedLogicalId { return false }
            if node.pendingFocusedLogicalId != otherNode.pendingFocusedLogicalId { return false }
            if node.lastTiledFocusedLogicalId != otherNode.lastTiledFocusedLogicalId { return false }
            if node.lastFloatingFocusedLogicalId != otherNode.lastFloatingFocusedLogicalId { return false }
        }
        return true
    }
}
