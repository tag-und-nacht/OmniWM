// SPDX-License-Identifier: GPL-2.0-only
import AppKit
import CoreGraphics
import Foundation

struct TopologyEpoch: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let value: UInt64

    static let invalid = TopologyEpoch(value: 0)

    init(value: UInt64) {
        self.value = value
    }

    var isValid: Bool { value != 0 }

    static func < (lhs: TopologyEpoch, rhs: TopologyEpoch) -> Bool {
        lhs.value < rhs.value
    }

    var description: String { "topo#\(value)" }
}

struct MonitorTopologyState: Equatable {
    struct DisplayNode: Equatable {
        let monitorId: Monitor.ID
        let outputId: OutputId
        let displayId: CGDirectDisplayID
        let frame: AppKitRect
        let visibleFrame: AppKitRect
        let workingFrame: AppKitRect
        let scale: CGFloat
        let orientation: Monitor.Orientation
        let hasNotch: Bool
        let name: String
        let activeWorkspaceId: WorkspaceDescriptor.ID?
        let assignedWorkspaceIds: [WorkspaceDescriptor.ID]

        var monitor: Monitor {
            Monitor(
                id: monitorId,
                displayId: displayId,
                frame: frame.raw,
                visibleFrame: visibleFrame.raw,
                hasNotch: hasNotch,
                name: name
            )
        }
    }

    struct RebindDecision: Equatable {
        let workspaceMonitorAssignments: [WorkspaceDescriptor.ID: Monitor.ID]
        let reboundOutputs: [OutputId]
        let unresolvedOutputs: [OutputId]
        let claimedMonitorIds: Set<Monitor.ID>
    }

    struct TransitionProjection: Equatable {
        let topology: MonitorTopologyState
        let rebindDecision: RebindDecision
        let workspaceProjections: [TopologyWorkspaceProjectionRecord]
    }

    let epoch: TopologyEpoch
    let nodes: [Monitor.ID: DisplayNode]
    let order: [Monitor.ID]
    let workspaceMonitor: [WorkspaceDescriptor.ID: Monitor.ID]
    let topologyProfile: TopologyProfile

    func node(_ id: Monitor.ID) -> DisplayNode? { nodes[id] }

    func node(forDisplay displayId: CGDirectDisplayID) -> DisplayNode? {
        nodes.values.first(where: { $0.displayId == displayId })
    }

    func node(containingPoint point: CGPoint) -> DisplayNode? {
        nodes.values.first(where: { $0.frame.raw.contains(point) })
    }

    func nearestNode(to point: CGPoint) -> DisplayNode? {
        if let containing = node(containingPoint: point) {
            return containing
        }
        var best: (node: DisplayNode, distance: CGFloat)?
        for monitorId in order {
            guard let candidate = nodes[monitorId] else { continue }
            let distance = candidate.frame.raw.distanceSquared(to: point)
            guard let current = best else {
                best = (candidate, distance)
                continue
            }
            if distance < current.distance {
                best = (candidate, distance)
            }
        }
        return best?.node
    }

    func relation(_ a: Monitor.ID, to b: Monitor.ID) -> Monitor.Orientation? {
        guard a != b, let aNode = nodes[a], let bNode = nodes[b] else { return nil }
        let aYRange = aNode.frame.raw.minY ..< aNode.frame.raw.maxY
        let bYRange = bNode.frame.raw.minY ..< bNode.frame.raw.maxY
        return aYRange.overlaps(bYRange) ? .horizontal : .vertical
    }

    func toAppKit(point: CGPoint) -> CGPoint {
        ScreenCoordinateSpace.toAppKit(point: point)
    }

    func toWindowServer(point: CGPoint) -> CGPoint {
        ScreenCoordinateSpace.toWindowServer(point: point)
    }

    @MainActor
    func mouseWarpOrder(
        axis: MouseWarpAxis,
        settings: SettingsStore
    ) -> [Monitor.ID] {
        settings.effectiveMouseWarpMonitorOrder(
            for: order.compactMap { nodes[$0]?.monitor },
            axis: axis
        )
    }

    func preferredHideSides() -> [Monitor.ID: HideSide] {
        Self.computePreferredHideSides(for: nodes.values.map(Self.monitorView))
    }

    static func preferredHideSides(for monitors: [Monitor]) -> [Monitor.ID: HideSide] {
        computePreferredHideSides(for: monitors.map(monitorView))
    }

    private struct MonitorView {
        let id: Monitor.ID
        let frame: CGRect
    }

    private static func monitorView(_ monitor: Monitor) -> MonitorView {
        MonitorView(id: monitor.id, frame: monitor.frame)
    }

    private static func monitorView(_ node: DisplayNode) -> MonitorView {
        MonitorView(id: node.monitorId, frame: node.frame.raw)
    }

    private static let hiddenEdgeCornerInsetRatio: CGFloat = 0.10
    private static let hiddenEdgeProbeOffsetPoints: CGFloat = 2
    private static let hiddenEdgeCornerHitWeight = 10

    private static func computePreferredHideSides(
        for monitors: [MonitorView]
    ) -> [Monitor.ID: HideSide] {
        var preferredSides: [Monitor.ID: HideSide] = [:]

        for monitor in monitors {
            let monitorFrame = monitor.frame
            let xOff = monitorFrame.width * Self.hiddenEdgeCornerInsetRatio
            let yOff = monitorFrame.height * Self.hiddenEdgeCornerInsetRatio
            let probeOffset = Self.hiddenEdgeProbeOffsetPoints

            let bottomRight = CGPoint(x: monitorFrame.maxX, y: monitorFrame.minY)
            let bottomLeft = CGPoint(x: monitorFrame.minX, y: monitorFrame.minY)

            let rightPoints = [
                CGPoint(x: bottomRight.x + probeOffset, y: bottomRight.y - yOff),
                CGPoint(x: bottomRight.x - xOff, y: bottomRight.y + probeOffset),
                CGPoint(x: bottomRight.x + probeOffset, y: bottomRight.y + probeOffset)
            ]

            let leftPoints = [
                CGPoint(x: bottomLeft.x - probeOffset, y: bottomLeft.y - yOff),
                CGPoint(x: bottomLeft.x + xOff, y: bottomLeft.y + probeOffset),
                CGPoint(x: bottomLeft.x - probeOffset, y: bottomLeft.y + probeOffset)
            ]

            func sideScore(_ points: [CGPoint]) -> Int {
                monitors.reduce(0) { partial, other in
                    let c1 = other.frame.contains(points[0]) ? 1 : 0
                    let c2 = other.frame.contains(points[1]) ? 1 : 0
                    let c3 = other.frame.contains(points[2]) ? 1 : 0
                    return partial + c1 + c2 + Self.hiddenEdgeCornerHitWeight * c3
                }
            }

            let leftScore = sideScore(leftPoints)
            let rightScore = sideScore(rightPoints)
            preferredSides[monitor.id] = leftScore < rightScore ? .left : .right
        }

        return preferredSides
    }
}

extension MonitorTopologyState {
    @MainActor
    static func projectTransition(
        previousOutputs: [OutputId],
        newMonitors: [Monitor],
        workspaces: [WorkspaceDescriptor],
        snapshots: [WorkspaceRestoreSnapshot],
        settings: SettingsStore,
        epoch: TopologyEpoch,
        insetWorkingFrame: (Monitor) -> CGRect = { $0.visibleFrame }
    ) -> TransitionProjection {
        let decision = rebindDecision(
            previousOutputs: previousOutputs,
            newMonitors: newMonitors,
            workspaces: workspaces,
            snapshots: snapshots,
            workspaceConfigurations: settings.workspaceConfigurations
        )
        let workspaceProjections = workspaceProjectionRecords(
            workspaces: workspaces,
            workspaceConfigurations: settings.workspaceConfigurations,
            monitors: newMonitors,
            snapshots: snapshots
        )
        let topology = projectTransitionTopology(
            monitors: newMonitors,
            workspaces: workspaces,
            decision: decision,
            workspaceProjections: workspaceProjections,
            settings: settings,
            epoch: epoch,
            insetWorkingFrame: insetWorkingFrame
        )
        return TransitionProjection(
            topology: topology,
            rebindDecision: decision,
            workspaceProjections: workspaceProjections
        )
    }

    static func rebindDecision(
        previousOutputs: [OutputId],
        newMonitors: [Monitor],
        workspaces: [WorkspaceDescriptor],
        snapshots: [WorkspaceRestoreSnapshot],
        workspaceConfigurations: [WorkspaceConfiguration] = []
    ) -> RebindDecision {
        let resolution = OutputId.resolveOrderedPreservingUnresolved(
            previousOutputs,
            in: newMonitors
        )
        let unresolved = zip(resolution.reboundOutputs, previousOutputs).enumerated().compactMap {
            index, pair -> OutputId? in
            resolution.resolvedSlotIndices.contains(index) ? nil : pair.0
        }

        let workspaceIds = Set(workspaces.map(\.id))
        let workspaceMonitorAssignments: [WorkspaceDescriptor.ID: Monitor.ID]
        if workspaceConfigurations.isEmpty {
            let monitorAssignments = resolveWorkspaceRestoreAssignments(
                snapshots: snapshots,
                monitors: newMonitors,
                workspaceExists: { workspaceIds.contains($0) }
            )

            var invertedAssignments: [WorkspaceDescriptor.ID: Monitor.ID] = [:]
            invertedAssignments.reserveCapacity(monitorAssignments.count)
            for (monitorId, workspaceId) in monitorAssignments {
                invertedAssignments[workspaceId] = monitorId
            }
            workspaceMonitorAssignments = invertedAssignments
        } else {
            workspaceMonitorAssignments = Dictionary(
                uniqueKeysWithValues: workspaceProjectionRecords(
                    workspaces: workspaces,
                    workspaceConfigurations: workspaceConfigurations,
                    monitors: newMonitors,
                    snapshots: snapshots
                ).compactMap { record in
                    guard let monitorId = record.effectiveMonitorId else { return nil }
                    return (record.workspaceId, monitorId)
                }
            )
        }

        return RebindDecision(
            workspaceMonitorAssignments: workspaceMonitorAssignments,
            reboundOutputs: resolution.reboundOutputs,
            unresolvedOutputs: unresolved,
            claimedMonitorIds: resolution.claimedMonitorIds
        )
    }

    private static func workspaceProjectionRecords(
        workspaces: [WorkspaceDescriptor],
        workspaceConfigurations: [WorkspaceConfiguration],
        monitors: [Monitor],
        snapshots: [WorkspaceRestoreSnapshot]
    ) -> [TopologyWorkspaceProjectionRecord] {
        guard !workspaces.isEmpty, !monitors.isEmpty else { return [] }

        if workspaceConfigurations.isEmpty {
            let workspaceIds = Set(workspaces.map(\.id))
            let monitorAssignments = resolveWorkspaceRestoreAssignments(
                snapshots: snapshots,
                monitors: monitors,
                workspaceExists: { workspaceIds.contains($0) }
            )
            return monitorAssignments.map { monitorId, workspaceId in
                TopologyWorkspaceProjectionRecord(
                    workspaceId: workspaceId,
                    projectedMonitorId: monitorId,
                    homeMonitorId: monitorId,
                    effectiveMonitorId: monitorId
                )
            }
            .sorted { lhs, rhs in
                (workspaces.firstIndex { $0.id == lhs.workspaceId } ?? Int.max)
                    < (workspaces.firstIndex { $0.id == rhs.workspaceId } ?? Int.max)
            }
        }

        return configuredWorkspaceProjectionRecords(
            workspaces: workspaces,
            workspaceConfigurations: workspaceConfigurations,
            monitors: monitors,
            snapshots: snapshots
        )
    }

    private static func configuredWorkspaceProjectionRecords(
        workspaces: [WorkspaceDescriptor],
        workspaceConfigurations: [WorkspaceConfiguration],
        monitors: [Monitor],
        snapshots: [WorkspaceRestoreSnapshot]
    ) -> [TopologyWorkspaceProjectionRecord] {
        guard !workspaces.isEmpty, !monitors.isEmpty else { return [] }

        let sortedMonitors = Monitor.sortedByPosition(monitors)
        var configsByName: [String: WorkspaceConfiguration] = [:]
        for configuration in workspaceConfigurations {
            guard configsByName[configuration.name] == nil else { continue }
            configsByName[configuration.name] = configuration
        }
        var snapshotAnchors: [WorkspaceDescriptor.ID: CGPoint] = [:]
        for snapshot in snapshots {
            guard snapshotAnchors[snapshot.workspaceId] == nil else { continue }
            snapshotAnchors[snapshot.workspaceId] = snapshot.monitor.anchorPoint
        }

        var records: [TopologyWorkspaceProjectionRecord] = []
        records.reserveCapacity(workspaces.count)
        for workspace in workspaces {
            guard let config = configsByName[workspace.name],
                  let effectiveMonitorId = effectiveMonitorId(
                    for: config.monitorAssignment,
                    workspace: workspace,
                    sortedMonitors: sortedMonitors,
                    snapshotAnchor: snapshotAnchors[workspace.id]
                  )
            else { continue }
            let homeMonitorId = homeMonitor(
                for: config.monitorAssignment,
                sortedMonitors: sortedMonitors
            )?.id
            records.append(
                TopologyWorkspaceProjectionRecord(
                    workspaceId: workspace.id,
                    projectedMonitorId: effectiveMonitorId,
                    homeMonitorId: homeMonitorId,
                    effectiveMonitorId: effectiveMonitorId
                )
            )
        }
        return records
    }

    private static func effectiveMonitorId(
        for assignment: MonitorAssignment,
        workspace: WorkspaceDescriptor,
        sortedMonitors: [Monitor],
        snapshotAnchor: CGPoint?
    ) -> Monitor.ID? {
        if let homeMonitor = homeMonitor(for: assignment, sortedMonitors: sortedMonitors) {
            return homeMonitor.id
        }
        guard let fallback = sortedMonitors.first else { return nil }
        guard let anchor = workspace.assignedMonitorPoint ?? snapshotAnchor else {
            return fallback.id
        }
        return nearestMonitor(to: anchor, sortedMonitors: sortedMonitors)?.id ?? fallback.id
    }

    private static func homeMonitor(
        for assignment: MonitorAssignment,
        sortedMonitors: [Monitor]
    ) -> Monitor? {
        switch assignment {
        case .main:
            return sortedMonitors.first(where: { $0.isMain }) ?? sortedMonitors.first
        case .secondary:
            guard sortedMonitors.count >= 2 else { return nil }
            if let main = sortedMonitors.first(where: { $0.isMain }) {
                return sortedMonitors.first(where: { $0.id != main.id })
            }
            return sortedMonitors.dropFirst().first
        case let .specificDisplay(output):
            let resolved = output.rebound(in: sortedMonitors) ?? output
            return sortedMonitors.first(where: { $0.displayId == resolved.displayId })
        }
    }

    private static func nearestMonitor(
        to anchor: CGPoint,
        sortedMonitors: [Monitor]
    ) -> Monitor? {
        var best: (monitor: Monitor, distance: CGFloat, sortIndex: Int)?
        for (sortIndex, monitor) in sortedMonitors.enumerated() {
            let dx = monitor.workspaceAnchorPoint.x - anchor.x
            let dy = monitor.workspaceAnchorPoint.y - anchor.y
            let candidate = (
                monitor: monitor,
                distance: dx * dx + dy * dy,
                sortIndex: sortIndex
            )
            guard let current = best else {
                best = candidate
                continue
            }
            if candidate.distance < current.distance
                || (candidate.distance == current.distance && candidate.sortIndex < current.sortIndex)
            {
                best = candidate
            }
        }
        return best?.monitor
    }

    @MainActor
    private static func projectTransitionTopology(
        monitors: [Monitor],
        workspaces: [WorkspaceDescriptor],
        decision: RebindDecision,
        workspaceProjections: [TopologyWorkspaceProjectionRecord],
        settings: SettingsStore,
        epoch: TopologyEpoch,
        insetWorkingFrame: (Monitor) -> CGRect
    ) -> MonitorTopologyState {
        let sortedMonitors = Monitor.sortedByPosition(monitors)
        let order = sortedMonitors.map(\.id)
        let liveMonitorIds = Set(order)
        let workspaceIndex = Dictionary(uniqueKeysWithValues: workspaces.enumerated().map { index, descriptor in
            (descriptor.id, index)
        })

        let projectedWorkspaceMonitor: [WorkspaceDescriptor.ID: Monitor.ID] = Dictionary(
            uniqueKeysWithValues: workspaceProjections.compactMap { record in
                guard let monitorId = record.effectiveMonitorId else { return nil }
                return (record.workspaceId, monitorId)
            }
        )
        let workspaceMonitor = projectedWorkspaceMonitor.filter {
            liveMonitorIds.contains($0.value)
        }
        var assignedByMonitor: [Monitor.ID: [WorkspaceDescriptor.ID]] = [:]
        for workspace in workspaces {
            guard let monitorId = workspaceMonitor[workspace.id] else { continue }
            assignedByMonitor[monitorId, default: []].append(workspace.id)
        }
        for monitorId in assignedByMonitor.keys {
            assignedByMonitor[monitorId]?.sort {
                (workspaceIndex[$0] ?? Int.max) < (workspaceIndex[$1] ?? Int.max)
            }
        }

        var nodes: [Monitor.ID: DisplayNode] = [:]
        for monitor in sortedMonitors {
            let workingFrame = insetWorkingFrame(monitor)
            let assigned = assignedByMonitor[monitor.id] ?? []
            let scale = ScreenLookupCache.shared.backingScale(for: monitor.displayId)
            let orientation = settings.effectiveOrientation(for: monitor)

            nodes[monitor.id] = DisplayNode(
                monitorId: monitor.id,
                outputId: OutputId(from: monitor),
                displayId: monitor.displayId,
                frame: AppKitRect(monitor.frame),
                visibleFrame: AppKitRect(monitor.visibleFrame),
                workingFrame: AppKitRect(workingFrame),
                scale: scale,
                orientation: orientation,
                hasNotch: monitor.hasNotch,
                name: monitor.name,
                activeWorkspaceId: assigned.first,
                assignedWorkspaceIds: assigned
            )
        }

        return MonitorTopologyState(
            epoch: epoch,
            nodes: nodes,
            order: order,
            workspaceMonitor: workspaceMonitor,
            topologyProfile: TopologyProfile(monitors: monitors)
        )
    }

    static func transitionPlan(
        previousMonitors: [Monitor],
        newMonitors: [Monitor],
        previousSessionState: WorkspaceSessionState,
        disconnectedVisibleWorkspaceCache: [MonitorRestoreKey: WorkspaceDescriptor.ID],
        workspaces: [WorkspaceDescriptor],
        projection: TransitionProjection
    ) -> TopologyTransitionPlan {
        let sortedNewMonitors = Monitor.sortedByPosition(
            newMonitors.isEmpty ? [Monitor.fallback()] : newMonitors
        )
        let liveMonitorIds = Set(sortedNewMonitors.map(\.id))
        let workspaceIds = Set(workspaces.map(\.id))
        let workspaceIndex = Dictionary(uniqueKeysWithValues: workspaces.enumerated().map { index, workspace in
            (workspace.id, index)
        })
        let workspaceAssignments: [WorkspaceDescriptor.ID: Monitor.ID] = Dictionary(
            uniqueKeysWithValues: projection.workspaceProjections.compactMap { record in
                guard let monitorId = record.effectiveMonitorId,
                      liveMonitorIds.contains(monitorId),
                      workspaceIds.contains(record.workspaceId)
                else { return nil }
                return (record.workspaceId, monitorId)
            }
        )

        var assignedByMonitor: [Monitor.ID: [WorkspaceDescriptor.ID]] = [:]
        for workspace in workspaces {
            guard let monitorId = workspaceAssignments[workspace.id] else { continue }
            assignedByMonitor[monitorId, default: []].append(workspace.id)
        }
        for monitorId in assignedByMonitor.keys {
            assignedByMonitor[monitorId]?.sort {
                (workspaceIndex[$0] ?? Int.max) < (workspaceIndex[$1] ?? Int.max)
            }
        }

        var usedVisibleWorkspaces: Set<WorkspaceDescriptor.ID> = []
        var monitorStates: [TopologyMonitorSessionState] = []
        monitorStates.reserveCapacity(sortedNewMonitors.count)
        for monitor in sortedNewMonitors {
            let previous = previousSessionState.monitorSessions[monitor.id]
            let visible = resolvedVisibleWorkspace(
                previous: previous?.visibleWorkspaceId,
                monitorId: monitor.id,
                assignedByMonitor: assignedByMonitor,
                workspaceAssignments: workspaceAssignments,
                usedVisibleWorkspaces: &usedVisibleWorkspaces
            )
            let previousVisible = previousVisibleWorkspace(
                previous: previous,
                visibleWorkspaceId: visible,
                workspaceExists: { workspaceIds.contains($0) }
            )
            monitorStates.append(
                TopologyMonitorSessionState(
                    monitorId: monitor.id,
                    visibleWorkspaceId: visible,
                    previousVisibleWorkspaceId: previousVisible
                )
            )
        }

        let interactionMonitorId: Monitor.ID? = {
            if let current = previousSessionState.interactionMonitorId,
               liveMonitorIds.contains(current)
            {
                return current
            }
            return sortedNewMonitors.first?.id
        }()
        let previousInteractionMonitorId: Monitor.ID? = {
            guard previousSessionState.interactionMonitorId != interactionMonitorId else {
                return previousSessionState.previousInteractionMonitorId
            }
            return previousSessionState.interactionMonitorId
                ?? previousSessionState.previousInteractionMonitorId
        }()

        let disconnectedCache = disconnectedWorkspaceCache(
            previousMonitors: previousMonitors,
            previousSessionState: previousSessionState,
            existingCache: disconnectedVisibleWorkspaceCache,
            unresolvedOutputs: projection.rebindDecision.unresolvedOutputs,
            liveMonitorIds: liveMonitorIds
        )

        return TopologyTransitionPlan(
            previousMonitors: previousMonitors,
            newMonitors: sortedNewMonitors,
            monitorStates: monitorStates,
            workspaceProjections: projection.workspaceProjections,
            disconnectedVisibleWorkspaceCache: disconnectedCache,
            interactionMonitorId: interactionMonitorId,
            previousInteractionMonitorId: previousInteractionMonitorId,
            refreshRestoreIntents: true
        )
    }

    private static func resolvedVisibleWorkspace(
        previous: WorkspaceDescriptor.ID?,
        monitorId: Monitor.ID,
        assignedByMonitor: [Monitor.ID: [WorkspaceDescriptor.ID]],
        workspaceAssignments: [WorkspaceDescriptor.ID: Monitor.ID],
        usedVisibleWorkspaces: inout Set<WorkspaceDescriptor.ID>
    ) -> WorkspaceDescriptor.ID? {
        if let previous,
           workspaceAssignments[previous] == monitorId,
           usedVisibleWorkspaces.insert(previous).inserted
        {
            return previous
        }
        guard let candidates = assignedByMonitor[monitorId] else { return nil }
        for candidate in candidates where !usedVisibleWorkspaces.contains(candidate) {
            usedVisibleWorkspaces.insert(candidate)
            return candidate
        }
        return nil
    }

    private static func previousVisibleWorkspace(
        previous: WorkspaceSessionState.MonitorSession?,
        visibleWorkspaceId: WorkspaceDescriptor.ID?,
        workspaceExists: (WorkspaceDescriptor.ID) -> Bool
    ) -> WorkspaceDescriptor.ID? {
        guard let previous else { return nil }
        let candidates = [
            previous.visibleWorkspaceId,
            previous.previousVisibleWorkspaceId
        ]
        for candidate in candidates {
            guard let candidate,
                  candidate != visibleWorkspaceId,
                  workspaceExists(candidate)
            else { continue }
            return candidate
        }
        return nil
    }

    private static func disconnectedWorkspaceCache(
        previousMonitors: [Monitor],
        previousSessionState: WorkspaceSessionState,
        existingCache: [MonitorRestoreKey: WorkspaceDescriptor.ID],
        unresolvedOutputs: [OutputId],
        liveMonitorIds: Set<Monitor.ID>
    ) -> [MonitorRestoreKey: WorkspaceDescriptor.ID] {
        let unresolved = Set(unresolvedOutputs)
        var cache: [MonitorRestoreKey: WorkspaceDescriptor.ID] = [:]

        for (key, workspaceId) in existingCache {
            let output = OutputId(displayId: key.displayId, name: key.name)
            if unresolved.contains(output) {
                cache[key] = workspaceId
            }
        }

        for monitor in previousMonitors where !liveMonitorIds.contains(monitor.id) {
            let output = OutputId(from: monitor)
            guard unresolved.contains(output),
                  let workspaceId = previousSessionState.monitorSessions[monitor.id]?.visibleWorkspaceId
            else { continue }
            cache[MonitorRestoreKey(monitor: monitor)] = workspaceId
        }

        return cache
    }

    @MainActor
    static func project(
        manager: WorkspaceManager,
        settings: SettingsStore,
        epoch: TopologyEpoch,
        insetWorkingFrame: (Monitor) -> CGRect = { $0.visibleFrame }
    ) -> MonitorTopologyState {
        let monitors = manager.monitors
        let sortedMonitors = Monitor.sortedByPosition(monitors)
        let order = sortedMonitors.map(\.id)

        var workspaceMonitor: [WorkspaceDescriptor.ID: Monitor.ID] = [:]
        var assignedByMonitor: [Monitor.ID: [WorkspaceDescriptor.ID]] = [:]
        for descriptor in manager.allWorkspaceDescriptors() {
            guard let monitorId = manager.monitorId(for: descriptor.id) else { continue }
            workspaceMonitor[descriptor.id] = monitorId
            assignedByMonitor[monitorId, default: []].append(descriptor.id)
        }

        var nodes: [Monitor.ID: DisplayNode] = [:]
        for monitor in sortedMonitors {
            let workingFrame = insetWorkingFrame(monitor)
            let activeWorkspaceId = manager.activeWorkspace(on: monitor.id)?.id
            let assigned = assignedByMonitor[monitor.id] ?? []
            let scale = ScreenLookupCache.shared.backingScale(for: monitor.displayId)
            let orientation = settings.effectiveOrientation(for: monitor)

            nodes[monitor.id] = DisplayNode(
                monitorId: monitor.id,
                outputId: OutputId(from: monitor),
                displayId: monitor.displayId,
                frame: AppKitRect(monitor.frame),
                visibleFrame: AppKitRect(monitor.visibleFrame),
                workingFrame: AppKitRect(workingFrame),
                scale: scale,
                orientation: orientation,
                hasNotch: monitor.hasNotch,
                name: monitor.name,
                activeWorkspaceId: activeWorkspaceId,
                assignedWorkspaceIds: assigned
            )
        }

        return MonitorTopologyState(
            epoch: epoch,
            nodes: nodes,
            order: order,
            workspaceMonitor: workspaceMonitor,
            topologyProfile: TopologyProfile(monitors: monitors)
        )
    }
}
