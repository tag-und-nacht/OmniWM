// SPDX-License-Identifier: GPL-2.0-only
import COmniWMKernels
import CoreGraphics
import Foundation
import OSLog

private let restoreAssignmentsLog = Logger(
    subsystem: "com.omniwm.core",
    category: "MonitorRestoreAssignments"
)

struct MonitorRestoreKey: Hashable {
    let displayId: CGDirectDisplayID
    let name: String
    let anchorPoint: CGPoint
    let frameSize: CGSize

    init(monitor: Monitor) {
        displayId = monitor.displayId
        name = monitor.name
        anchorPoint = monitor.workspaceAnchorPoint
        frameSize = monitor.frame.size
    }
}

struct WorkspaceRestoreSnapshot: Hashable {
    let monitor: MonitorRestoreKey
    let workspaceId: WorkspaceDescriptor.ID
}

func resolveWorkspaceRestoreAssignments(
    snapshots: [WorkspaceRestoreSnapshot],
    monitors: [Monitor],
    workspaceExists: (WorkspaceDescriptor.ID) -> Bool
) -> [Monitor.ID: WorkspaceDescriptor.ID] {
    guard !snapshots.isEmpty, !monitors.isEmpty else { return [:] }

    var filteredSnapshots: [WorkspaceRestoreSnapshot] = []
    var seenWorkspaceIds: Set<WorkspaceDescriptor.ID> = []
    filteredSnapshots.reserveCapacity(snapshots.count)

    for snapshot in snapshots {
        guard workspaceExists(snapshot.workspaceId) else { continue }
        guard seenWorkspaceIds.insert(snapshot.workspaceId).inserted else { continue }
        filteredSnapshots.append(snapshot)
    }

    guard !filteredSnapshots.isEmpty else { return [:] }

    var snapshotInputs = ContiguousArray<omniwm_restore_snapshot>()
    snapshotInputs.reserveCapacity(filteredSnapshots.count)
    for snapshot in filteredSnapshots {
        snapshotInputs.append(
            omniwm_restore_snapshot(
                display_id: snapshot.monitor.displayId,
                anchor_x: snapshot.monitor.anchorPoint.x,
                anchor_y: snapshot.monitor.anchorPoint.y,
                frame_width: snapshot.monitor.frameSize.width,
                frame_height: snapshot.monitor.frameSize.height
            )
        )
    }

    var monitorInputs = ContiguousArray<omniwm_restore_monitor>()
    monitorInputs.reserveCapacity(monitors.count)
    for monitor in monitors {
        monitorInputs.append(
            omniwm_restore_monitor(
                display_id: monitor.displayId,
                frame_min_x: monitor.frame.minX,
                frame_max_y: monitor.frame.maxY,
                anchor_x: monitor.workspaceAnchorPoint.x,
                anchor_y: monitor.workspaceAnchorPoint.y,
                frame_width: monitor.frame.width,
                frame_height: monitor.frame.height
            )
        )
    }

    var namePenalties = ContiguousArray<UInt8>()
    namePenalties.reserveCapacity(filteredSnapshots.count * monitors.count)
    for snapshot in filteredSnapshots {
        for monitor in monitors {
            namePenalties.append(
                snapshot.monitor.name.localizedCaseInsensitiveCompare(monitor.name) == .orderedSame ? 0 : 1
            )
        }
    }

    var rawAssignments = ContiguousArray(
        repeating: omniwm_restore_assignment(snapshot_index: 0, monitor_index: 0),
        count: min(filteredSnapshots.count, monitors.count)
    )
    var rawAssignmentCount = 0

    let status = snapshotInputs.withUnsafeBufferPointer { snapshotBuffer in
        monitorInputs.withUnsafeBufferPointer { monitorBuffer in
            namePenalties.withUnsafeBufferPointer { penaltyBuffer in
                rawAssignments.withUnsafeMutableBufferPointer { assignmentBuffer in
                    omniwm_restore_resolve_assignments(
                        snapshotBuffer.baseAddress,
                        snapshotBuffer.count,
                        monitorBuffer.baseAddress,
                        monitorBuffer.count,
                        penaltyBuffer.baseAddress,
                        penaltyBuffer.count,
                        assignmentBuffer.baseAddress,
                        assignmentBuffer.count,
                        &rawAssignmentCount
                    )
                }
            }
        }
    }

    // The assignment kernel runs from inside the display-reconfigure pipeline.
    // Crashing here would crash the WM at the worst possible moment (the OS
    // is mid-reconfigure); degrade to "no restored assignments" instead and
    // let the topology pipeline recover via reconciliation.
    guard status == OMNIWM_KERNELS_STATUS_OK else {
        restoreAssignmentsLog.error(
            "omniwm_restore_resolve_assignments returned non-OK status \(status, privacy: .public); returning empty assignment map"
        )
        return [:]
    }

    var assignments: [Monitor.ID: WorkspaceDescriptor.ID] = [:]
    assignments.reserveCapacity(rawAssignmentCount)

    for assignment in rawAssignments.prefix(rawAssignmentCount) {
        let monitorIndex = Int(assignment.monitor_index)
        let snapshotIndex = Int(assignment.snapshot_index)
        guard monitors.indices.contains(monitorIndex),
              filteredSnapshots.indices.contains(snapshotIndex)
        else {
            restoreAssignmentsLog.error(
                "kernel returned out-of-bounds restore assignment (monitor \(monitorIndex, privacy: .public), snapshot \(snapshotIndex, privacy: .public)); skipping"
            )
            continue
        }
        assignments[monitors[monitorIndex].id] =
            filteredSnapshots[snapshotIndex].workspaceId
    }

    return assignments
}
