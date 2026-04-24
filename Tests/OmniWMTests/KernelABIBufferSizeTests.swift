// SPDX-License-Identifier: GPL-2.0-only

import COmniWMKernels
import Foundation
import Testing


@Suite struct KernelABIDwindleBufferSizeTests {
    private func makeLayoutInput() -> omniwm_dwindle_layout_input {
        omniwm_dwindle_layout_input(
            root_index: 0,
            screen_x: 0,
            screen_y: 0,
            screen_width: 1920,
            screen_height: 1080,
            inner_gap: 8,
            outer_gap_top: 0,
            outer_gap_bottom: 0,
            outer_gap_left: 0,
            outer_gap_right: 0,
            single_window_aspect_width: 16,
            single_window_aspect_height: 9,
            single_window_aspect_tolerance: 0.1,
            minimum_dimension: 50,
            gap_sticks_tolerance: 1,
            split_ratio_min: 0.05,
            split_ratio_max: 0.95,
            split_fraction_divisor: 1,
            split_fraction_min: 0,
            split_fraction_max: 1
        )
    }

    private func makeLeafNode() -> omniwm_dwindle_node_input {
        omniwm_dwindle_node_input(
            first_child_index: -1,
            second_child_index: -1,
            split_ratio: 0.5,
            min_width: 50,
            min_height: 50,
            kind: UInt32(OMNIWM_DWINDLE_NODE_KIND_LEAF),
            orientation: UInt32(OMNIWM_DWINDLE_ORIENTATION_HORIZONTAL),
            has_window: 1,
            fullscreen: 0
        )
    }

    @Test func smallerOutputCapacityReportsBufferTooSmall() {
        var input = makeLayoutInput()
        var nodes = [makeLeafNode(), makeLeafNode(), makeLeafNode()]
        var outputs = [omniwm_dwindle_node_frame](
            repeating: omniwm_dwindle_node_frame(
                x: 0, y: 0, width: 0, height: 0, has_frame: 0
            ),
            count: 1
        )

        let status = nodes.withUnsafeBufferPointer { nodesBuffer in
            outputs.withUnsafeMutableBufferPointer { outputBuffer in
                omniwm_dwindle_solve(
                    &input,
                    nodesBuffer.baseAddress,
                    nodesBuffer.count,
                    outputBuffer.baseAddress,
                    outputBuffer.count
                )
            }
        }

        #expect(status == OMNIWM_KERNELS_STATUS_BUFFER_TOO_SMALL)
    }

    @Test func zeroOutputCapacityWithNonZeroNodesReportsBufferTooSmall() {
        var input = makeLayoutInput()
        var nodes = [makeLeafNode()]

        var outputs = [omniwm_dwindle_node_frame(
            x: 0, y: 0, width: 0, height: 0, has_frame: 0
        )]

        let status = nodes.withUnsafeBufferPointer { nodesBuffer in
            outputs.withUnsafeMutableBufferPointer { outputBuffer in
                omniwm_dwindle_solve(
                    &input,
                    nodesBuffer.baseAddress,
                    nodesBuffer.count,
                    outputBuffer.baseAddress,
                    0
                )
            }
        }

        #expect(status == OMNIWM_KERNELS_STATUS_BUFFER_TOO_SMALL)
    }
}


@Suite struct KernelABIFloatingRescueBufferSizeTests {
    private func makeRescueCandidate(_ pid: Int32, _ windowId: Int64) -> omniwm_restore_floating_rescue_candidate {
        omniwm_restore_floating_rescue_candidate(
            token: omniwm_window_token(pid: pid, window_id: windowId),
            workspace_id: omniwm_uuid(high: 0, low: 1),
            target_monitor_id: 1,
            target_monitor_visible_frame: omniwm_rect(x: 0, y: 0, width: 1920, height: 1080),
            current_frame: omniwm_rect(x: 4000, y: 0, width: 800, height: 600),
            floating_frame: omniwm_rect(x: 4000, y: 0, width: 800, height: 600),
            normalized_origin: omniwm_point(x: 0, y: 0),
            reference_monitor_id: 1,
            has_current_frame: 1,
            has_normalized_origin: 0,
            has_reference_monitor_id: 1,
            is_scratchpad_hidden: 0,
            is_workspace_inactive_hidden: 0
        )
    }

    @Test func zeroOperationCapacityReportsBufferTooSmall() {
        let candidates = [
            makeRescueCandidate(123, 1),
            makeRescueCandidate(123, 2),
        ]
        var output = omniwm_restore_floating_rescue_output(
            operations: nil,
            operation_capacity: 0,
            operation_count: 0
        )

        let status = candidates.withUnsafeBufferPointer { buffer in
            omniwm_restore_plan_floating_rescue(
                buffer.baseAddress,
                buffer.count,
                &output
            )
        }

        if status == OMNIWM_KERNELS_STATUS_BUFFER_TOO_SMALL {
            #expect(output.operation_count > 0)
        } else {
            #expect(status == OMNIWM_KERNELS_STATUS_OK)
            #expect(output.operation_count == 0)
        }
    }
}


@Suite struct KernelABIResolveAssignmentsBufferSizeTests {
    @Test func smallerAssignmentCapacityFailsOrReportsZeroAssignments() {
        let snapshots = [
            omniwm_restore_snapshot(
                display_id: 1,
                anchor_x: 0,
                anchor_y: 0,
                frame_width: 1920,
                frame_height: 1080
            ),
            omniwm_restore_snapshot(
                display_id: 2,
                anchor_x: 1920,
                anchor_y: 0,
                frame_width: 1920,
                frame_height: 1080
            ),
        ]
        let monitors = [
            omniwm_restore_monitor(
                display_id: 1,
                frame_min_x: 0,
                frame_max_y: 1080,
                anchor_x: 0,
                anchor_y: 0,
                frame_width: 1920,
                frame_height: 1080
            ),
            omniwm_restore_monitor(
                display_id: 2,
                frame_min_x: 1920,
                frame_max_y: 1080,
                anchor_x: 1920,
                anchor_y: 0,
                frame_width: 1920,
                frame_height: 1080
            ),
        ]

        var assignmentCount: Int = 0
        var assignmentBuffer = [omniwm_restore_assignment](
            repeating: omniwm_restore_assignment(snapshot_index: 0, monitor_index: 0),
            count: 0
        )

        let status = snapshots.withUnsafeBufferPointer { snapshotBuffer in
            monitors.withUnsafeBufferPointer { monitorBuffer in
                assignmentBuffer.withUnsafeMutableBufferPointer { outputBuffer in
                    omniwm_restore_resolve_assignments(
                        snapshotBuffer.baseAddress,
                        snapshotBuffer.count,
                        monitorBuffer.baseAddress,
                        monitorBuffer.count,
                        nil,
                        0,
                        outputBuffer.baseAddress,
                        outputBuffer.count,
                        &assignmentCount
                    )
                }
            }
        }

        if status == OMNIWM_KERNELS_STATUS_BUFFER_TOO_SMALL {
            #expect(assignmentCount > 0)
        } else if status == OMNIWM_KERNELS_STATUS_OK {
            #expect(assignmentCount == 0)
        } else if status == OMNIWM_KERNELS_STATUS_INVALID_ARGUMENT {
        } else {
            #expect(Bool(false), "unexpected status \(status)")
        }
    }

    @Test func zeroSnapshotsAndZeroMonitorsReturnsOk() {
        var assignmentCount: Int = 99
        let status = omniwm_restore_resolve_assignments(
            nil, 0,
            nil, 0,
            nil, 0,
            nil, 0,
            &assignmentCount
        )

        #expect(status == OMNIWM_KERNELS_STATUS_OK)
        #expect(assignmentCount == 0)
    }
}
