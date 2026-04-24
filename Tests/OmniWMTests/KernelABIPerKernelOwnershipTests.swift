// SPDX-License-Identifier: GPL-2.0-only

import COmniWMKernels
import Foundation
import Testing

private func bytesOf<T>(_ value: inout T) -> [UInt8] {
    withUnsafeBytes(of: &value) { Array($0) }
}

private func zeroFill<T>(_ value: inout T) {
    withUnsafeMutableBytes(of: &value) { buffer in
        if let base = buffer.baseAddress {
            _ = memset(base, 0, buffer.count)
        }
    }
}

private func bytesOfArray<T>(_ array: [T]) -> [UInt8] {
    array.withUnsafeBufferPointer { buffer in
        let raw = UnsafeRawBufferPointer(buffer)
        return Array(raw)
    }
}


@Suite struct KernelABIDwindleSolveOwnershipTests {
    private func makeInput() -> omniwm_dwindle_layout_input {
        omniwm_dwindle_layout_input(
            root_index: 0,
            screen_x: 0, screen_y: 0, screen_width: 1920, screen_height: 1080,
            inner_gap: 8,
            outer_gap_top: 0, outer_gap_bottom: 0, outer_gap_left: 0, outer_gap_right: 0,
            single_window_aspect_width: 16, single_window_aspect_height: 9,
            single_window_aspect_tolerance: 0.1,
            minimum_dimension: 50,
            gap_sticks_tolerance: 1,
            split_ratio_min: 0.05, split_ratio_max: 0.95,
            split_fraction_divisor: 1, split_fraction_min: 0, split_fraction_max: 1
        )
    }
    private func makeNodes() -> [omniwm_dwindle_node_input] {
        [omniwm_dwindle_node_input(
            first_child_index: -1, second_child_index: -1,
            split_ratio: 0.5, min_width: 50, min_height: 50,
            kind: UInt32(OMNIWM_DWINDLE_NODE_KIND_LEAF),
            orientation: UInt32(OMNIWM_DWINDLE_ORIENTATION_HORIZONTAL),
            has_window: 1, fullscreen: 0
        )]
    }

    @Test func inputArrayIsNotMutated() {
        var input = makeInput()
        let nodes = makeNodes()
        let inputBefore = bytesOf(&input)
        let nodesBefore = bytesOfArray(nodes)
        var outputs = [omniwm_dwindle_node_frame](
            repeating: omniwm_dwindle_node_frame(x: 0, y: 0, width: 0, height: 0, has_frame: 0),
            count: nodes.count
        )

        _ = nodes.withUnsafeBufferPointer { n in
            outputs.withUnsafeMutableBufferPointer { o in
                omniwm_dwindle_solve(&input, n.baseAddress, n.count, o.baseAddress, o.count)
            }
        }

        #expect(bytesOf(&input) == inputBefore)
        #expect(bytesOfArray(nodes) == nodesBefore)
    }

    @Test func deterministicOutput() {
        var input1 = makeInput(), input2 = makeInput()
        let nodes1 = makeNodes(), nodes2 = makeNodes()
        var outputs1 = [omniwm_dwindle_node_frame](
            repeating: omniwm_dwindle_node_frame(x: 0, y: 0, width: 0, height: 0, has_frame: 0),
            count: nodes1.count
        )
        var outputs2 = outputs1

        let status1 = nodes1.withUnsafeBufferPointer { n in
            outputs1.withUnsafeMutableBufferPointer { o in
                omniwm_dwindle_solve(&input1, n.baseAddress, n.count, o.baseAddress, o.count)
            }
        }
        let status2 = nodes2.withUnsafeBufferPointer { n in
            outputs2.withUnsafeMutableBufferPointer { o in
                omniwm_dwindle_solve(&input2, n.baseAddress, n.count, o.baseAddress, o.count)
            }
        }

        #expect(status1 == status2)
        #expect(bytesOfArray(outputs1) == bytesOfArray(outputs2))
    }

    @Test func sentinelPadAroundOutputSurvives() {
        var input = makeInput()
        let nodes = makeNodes()
        let sentinel = omniwm_dwindle_node_frame(
            x: -1.0e308, y: -1.0e308, width: 9.99e9, height: 9.99e9, has_frame: 0xCD
        )
        var outputs = [omniwm_dwindle_node_frame](repeating: sentinel, count: nodes.count + 4)
        let trailingBefore = (nodes.count..<outputs.count).flatMap { bytesOf(&outputs[$0]) }

        _ = nodes.withUnsafeBufferPointer { n in
            outputs.withUnsafeMutableBufferPointer { o in
                omniwm_dwindle_solve(&input, n.baseAddress, n.count, o.baseAddress,  n.count)
            }
        }

        let trailingAfter = (nodes.count..<outputs.count).flatMap { bytesOf(&outputs[$0]) }
        #expect(trailingBefore == trailingAfter)
    }
}


@Suite struct KernelABIGeometryHelperOwnershipTests {
    private let spans: [Double] = [120, 80, 200, 50]
    private let modes: [UInt8] = [0, 0, 0, 0]

    @Test func containerPositionIsDeterministicAndPure() {
        let before = bytesOfArray(spans)
        let first = spans.withUnsafeBufferPointer {
            omniwm_geometry_container_position($0.baseAddress, $0.count, 8, 2)
        }
        let second = spans.withUnsafeBufferPointer {
            omniwm_geometry_container_position($0.baseAddress, $0.count, 8, 2)
        }
        #expect(first == second)
        #expect(bytesOfArray(spans) == before)
    }

    @Test func centeredOffsetIsDeterministicAndPure() {
        let beforeSpans = bytesOfArray(spans), beforeModes = bytesOfArray(modes)
        let first = spans.withUnsafeBufferPointer { s in
            modes.withUnsafeBufferPointer { m in
                omniwm_geometry_centered_offset(s.baseAddress, m.baseAddress, s.count, 8, 1000, 1)
            }
        }
        let second = spans.withUnsafeBufferPointer { s in
            modes.withUnsafeBufferPointer { m in
                omniwm_geometry_centered_offset(s.baseAddress, m.baseAddress, s.count, 8, 1000, 1)
            }
        }
        #expect(first == second)
        #expect(bytesOfArray(spans) == beforeSpans)
        #expect(bytesOfArray(modes) == beforeModes)
    }

    @Test func visibleOffsetIsDeterministicAndPure() {
        let beforeSpans = bytesOfArray(spans), beforeModes = bytesOfArray(modes)
        let first = spans.withUnsafeBufferPointer { s in
            modes.withUnsafeBufferPointer { m in
                omniwm_geometry_visible_offset(
                    s.baseAddress, m.baseAddress, s.count, 8, 1000, 1, 0,
                     0,  0,  0,  2.0
                )
            }
        }
        let second = spans.withUnsafeBufferPointer { s in
            modes.withUnsafeBufferPointer { m in
                omniwm_geometry_visible_offset(
                    s.baseAddress, m.baseAddress, s.count, 8, 1000, 1, 0,
                     0,  0,  0,  2.0
                )
            }
        }
        #expect(first == second)
        #expect(bytesOfArray(spans) == beforeSpans)
        #expect(bytesOfArray(modes) == beforeModes)
    }

    @Test func snapTargetIsDeterministicAndPure() {
        let beforeSpans = bytesOfArray(spans), beforeModes = bytesOfArray(modes)
        var first = spans.withUnsafeBufferPointer { s in
            modes.withUnsafeBufferPointer { m in
                omniwm_geometry_snap_target(s.baseAddress, m.baseAddress, s.count, 8, 1000, 100, 50, 0, 0)
            }
        }
        var second = spans.withUnsafeBufferPointer { s in
            modes.withUnsafeBufferPointer { m in
                omniwm_geometry_snap_target(s.baseAddress, m.baseAddress, s.count, 8, 1000, 100, 50, 0, 0)
            }
        }
        #expect(first.view_pos == second.view_pos)
        #expect(first.column_index == second.column_index)
        _ = bytesOf(&first); _ = bytesOf(&second)
        #expect(bytesOfArray(spans) == beforeSpans)
        #expect(bytesOfArray(modes) == beforeModes)
    }
}


@Suite struct KernelABIReconcileRestoreIntentOwnershipTests {
    private func makeEntry() -> omniwm_reconcile_entry {
        var entry = omniwm_reconcile_entry()
        return entry
    }

    @Test func inputNotMutatedAndDeterministic() {
        var entry1 = makeEntry()
        let entryBefore = bytesOf(&entry1)
        var output1 = omniwm_reconcile_restore_intent_output(); zeroFill(&output1)
        let status1 = omniwm_reconcile_restore_intent(&entry1, nil, 0, &output1)
        let entryAfter = bytesOf(&entry1)
        #expect(entryBefore == entryAfter)

        var entry2 = makeEntry()
        var output2 = omniwm_reconcile_restore_intent_output(); zeroFill(&output2)
        let status2 = omniwm_reconcile_restore_intent(&entry2, nil, 0, &output2)

        #expect(status1 == status2)
        #expect(bytesOf(&output1) == bytesOf(&output2))
    }

    @Test func outputStructDoesNotOverflow() {
        struct Wrapped {
            var output: omniwm_reconcile_restore_intent_output
            var sentinel: UInt64
        }
        let sentinel: UInt64 = 0xFEED_BABE_DEAD_C0DE
        var wrapped = Wrapped(output: omniwm_reconcile_restore_intent_output(), sentinel: sentinel)
        var entry = makeEntry()

        _ = withUnsafeMutablePointer(to: &wrapped.output) { ptr in
            omniwm_reconcile_restore_intent(&entry, nil, 0, ptr)
        }
        #expect(wrapped.sentinel == sentinel)
    }
}


@Suite struct KernelABIReconcilePlanOwnershipTests {
    private func makeEvent() -> omniwm_reconcile_event {
        omniwm_reconcile_event()
    }
    private func makeEntry() -> omniwm_reconcile_entry {
        omniwm_reconcile_entry()
    }
    private func makeFocus() -> omniwm_reconcile_focus_session {
        omniwm_reconcile_focus_session()
    }
    private func makeHydration() -> omniwm_reconcile_persisted_hydration {
        omniwm_reconcile_persisted_hydration()
    }

    @Test func inputsNotMutatedAndDeterministic() {
        var event1 = makeEvent(), entry1 = makeEntry(), focus1 = makeFocus(), hyd1 = makeHydration()
        let eb = bytesOf(&event1), tb = bytesOf(&entry1), fb = bytesOf(&focus1), hb = bytesOf(&hyd1)
        var output1 = omniwm_reconcile_plan_output(); zeroFill(&output1)
        let status1 = omniwm_reconcile_plan(&event1, &entry1, &focus1, nil, 0, &hyd1, &output1)
        #expect(bytesOf(&event1) == eb)
        #expect(bytesOf(&entry1) == tb)
        #expect(bytesOf(&focus1) == fb)
        #expect(bytesOf(&hyd1) == hb)

        var event2 = makeEvent(), entry2 = makeEntry(), focus2 = makeFocus(), hyd2 = makeHydration()
        var output2 = omniwm_reconcile_plan_output(); zeroFill(&output2)
        let status2 = omniwm_reconcile_plan(&event2, &entry2, &focus2, nil, 0, &hyd2, &output2)

        #expect(status1 == status2)
        #expect(bytesOf(&output1) == bytesOf(&output2))
    }
}


@Suite struct KernelABIOrchestrationLayoutOwnershipTests {
    @Test func deterministicAndOutputDoesNotOverflow() {
        var output1 = omniwm_orchestration_abi_layout_info()
        let status1 = omniwm_orchestration_get_abi_layout(&output1)

        var output2 = omniwm_orchestration_abi_layout_info()
        let status2 = omniwm_orchestration_get_abi_layout(&output2)

        #expect(status1 == status2)
        #expect(bytesOf(&output1) == bytesOf(&output2))

        struct Wrapped {
            var output: omniwm_orchestration_abi_layout_info
            var sentinel: UInt64
        }
        let sentinel: UInt64 = 0xFEED_BABE_DEAD_C0DE
        var wrapped = Wrapped(output: omniwm_orchestration_abi_layout_info(), sentinel: sentinel)
        _ = withUnsafeMutablePointer(to: &wrapped.output) { ptr in
            omniwm_orchestration_get_abi_layout(ptr)
        }
        #expect(wrapped.sentinel == sentinel)
    }
}


@Suite struct KernelABIWorkspaceSessionPlanOwnershipTests {
    private func makeInput() -> omniwm_workspace_session_input {
        var input = omniwm_workspace_session_input(); zeroFill(&input)
        input.operation = UInt32(OMNIWM_WORKSPACE_SESSION_OPERATION_PROJECT)
        return input
    }

    @Test func inputNotMutatedAndDeterministic() {
        var input1 = makeInput()
        let inputBefore = bytesOf(&input1)
        var output1 = omniwm_workspace_session_output(); zeroFill(&output1)
        let status1 = omniwm_workspace_session_plan(
            &input1, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, &output1
        )
        #expect(bytesOf(&input1) == inputBefore)

        var input2 = makeInput()
        var output2 = omniwm_workspace_session_output(); zeroFill(&output2)
        let status2 = omniwm_workspace_session_plan(
            &input2, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, &output2
        )
        #expect(status1 == status2)
        #expect(output1.outcome == output2.outcome)
        #expect(output1.patch_viewport_action == output2.patch_viewport_action)
        #expect(output1.focus_clear_action == output2.focus_clear_action)
        #expect(output1.has_resolved_focus_token == output2.has_resolved_focus_token)
        #expect(output1.has_resolved_focus_logical_id == output2.has_resolved_focus_logical_id)
        #expect(output1.monitor_result_count == output2.monitor_result_count)
        #expect(output1.workspace_projection_count == output2.workspace_projection_count)
        #expect(output1.disconnected_cache_result_count == output2.disconnected_cache_result_count)
        #expect(output1.should_remember_focus == output2.should_remember_focus)
        #expect(output1.refresh_restore_intents == output2.refresh_restore_intents)
    }
}

@Suite struct KernelABIWorkspaceNavigationPlanOwnershipTests {
    @Test func inputNotMutatedAndDeterministic() {
        var input1 = omniwm_workspace_navigation_input(); zeroFill(&input1)
        let inputBefore = bytesOf(&input1)
        var output1 = omniwm_workspace_navigation_output(); zeroFill(&output1)
        let status1 = omniwm_workspace_navigation_plan(
            &input1, nil, 0, nil, 0, &output1
        )
        #expect(bytesOf(&input1) == inputBefore)

        var input2 = omniwm_workspace_navigation_input(); zeroFill(&input2)
        var output2 = omniwm_workspace_navigation_output(); zeroFill(&output2)
        let status2 = omniwm_workspace_navigation_plan(
            &input2, nil, 0, nil, 0, &output2
        )
        #expect(status1 == status2)
        #expect(output1.outcome == output2.outcome)
        #expect(output1.subject_kind == output2.subject_kind)
        #expect(output1.focus_action == output2.focus_action)
        #expect(output1.has_resolved_focus_token == output2.has_resolved_focus_token)
        #expect(output1.has_subject_token == output2.has_subject_token)
        #expect(output1.save_workspace_count == output2.save_workspace_count)
        #expect(output1.affected_workspace_count == output2.affected_workspace_count)
        #expect(output1.affected_monitor_count == output2.affected_monitor_count)
    }
}

@Suite struct KernelABIOrchestrationStepOwnershipTests {
    private func makeInput() -> omniwm_orchestration_step_input {
        omniwm_orchestration_step_input()
    }

    @Test func inputNotMutatedAndDeterministic() {
        var input1 = makeInput()
        let inputBefore = bytesOf(&input1)
        var output1 = omniwm_orchestration_step_output(); zeroFill(&output1)
        let status1 = omniwm_orchestration_step(&input1, &output1)
        #expect(bytesOf(&input1) == inputBefore)

        var input2 = makeInput()
        var output2 = omniwm_orchestration_step_output(); zeroFill(&output2)
        let status2 = omniwm_orchestration_step(&input2, &output2)
        #expect(status1 == status2)
        #expect(bytesOf(&output1) == bytesOf(&output2))
    }
}

@Suite struct KernelABINiriLayoutSolveOwnershipTests {
    private func makeInput() -> omniwm_niri_layout_input {
        omniwm_niri_layout_input()
    }

    @Test func inputNotMutatedAndDeterministicForEmptyInput() {
        var input1 = makeInput()
        let inputBefore = bytesOf(&input1)
        let status1 = omniwm_niri_layout_solve(&input1, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0)
        #expect(bytesOf(&input1) == inputBefore)

        var input2 = makeInput()
        let status2 = omniwm_niri_layout_solve(&input2, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0)
        #expect(status1 == status2)
    }
}

@Suite struct KernelABINiriTopologyPlanOwnershipTests {
    private func makeInput() -> omniwm_niri_topology_input {
        omniwm_niri_topology_input()
    }

    @Test func inputNotMutatedAndDeterministicForEmptyInput() {
        var input1 = makeInput()
        let inputBefore = bytesOf(&input1)
        var result1 = omniwm_niri_topology_result(); zeroFill(&result1)
        let status1 = omniwm_niri_topology_plan(
            &input1, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, &result1
        )
        #expect(bytesOf(&input1) == inputBefore)

        var input2 = makeInput()
        var result2 = omniwm_niri_topology_result(); zeroFill(&result2)
        let status2 = omniwm_niri_topology_plan(
            &input2, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, &result2
        )
        #expect(status1 == status2)
        #expect(bytesOf(&result1) == bytesOf(&result2))
    }
}

@Suite struct KernelABIOverviewProjectionSolveOwnershipTests {
    private func makeContext() -> omniwm_overview_context {
        omniwm_overview_context()
    }

    @Test func inputNotMutatedAndDeterministicForEmptyInput() {
        var ctx1 = makeContext()
        let ctxBefore = bytesOf(&ctx1)
        var result1 = omniwm_overview_result(); zeroFill(&result1)
        let status1 = omniwm_overview_projection_solve(
            &ctx1, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, &result1
        )
        #expect(bytesOf(&ctx1) == ctxBefore)

        var ctx2 = makeContext()
        var result2 = omniwm_overview_result(); zeroFill(&result2)
        let status2 = omniwm_overview_projection_solve(
            &ctx2, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, &result2
        )
        #expect(status1 == status2)
        #expect(bytesOf(&result1) == bytesOf(&result2))
    }
}


@Suite struct KernelABIRestorePlanEventOwnershipTests {
    @Test func inputNotMutatedAndDeterministic() {
        var input1 = omniwm_restore_event_input(); zeroFill(&input1)
        let inputBefore = bytesOf(&input1)
        var output1 = omniwm_restore_event_output(); zeroFill(&output1)
        let status1 = omniwm_restore_plan_event(&input1, &output1)
        #expect(bytesOf(&input1) == inputBefore)

        var input2 = omniwm_restore_event_input(); zeroFill(&input2)
        var output2 = omniwm_restore_event_output(); zeroFill(&output2)
        let status2 = omniwm_restore_plan_event(&input2, &output2)
        #expect(status1 == status2)
        #expect(bytesOf(&output1) == bytesOf(&output2))
    }
}

@Suite struct KernelABIRestorePlanTopologyOwnershipTests {
    @Test func inputNotMutatedAndDeterministic() {
        var input1 = omniwm_restore_topology_input(); zeroFill(&input1)
        let inputBefore = bytesOf(&input1)
        var output1 = omniwm_restore_topology_output(); zeroFill(&output1)
        let status1 = omniwm_restore_plan_topology(&input1, &output1)
        #expect(bytesOf(&input1) == inputBefore)

        var input2 = omniwm_restore_topology_input(); zeroFill(&input2)
        var output2 = omniwm_restore_topology_output(); zeroFill(&output2)
        let status2 = omniwm_restore_plan_topology(&input2, &output2)
        #expect(status1 == status2)
        #expect(bytesOf(&output1) == bytesOf(&output2))
    }
}

@Suite struct KernelABIRestorePlanPersistedHydrationOwnershipTests {
    @Test func inputNotMutatedAndDeterministic() {
        var input1 = omniwm_restore_persisted_hydration_input(); zeroFill(&input1)
        let inputBefore = bytesOf(&input1)
        var output1 = omniwm_restore_persisted_hydration_output(); zeroFill(&output1)
        let status1 = omniwm_restore_plan_persisted_hydration(&input1, &output1)
        #expect(bytesOf(&input1) == inputBefore)

        var input2 = omniwm_restore_persisted_hydration_input(); zeroFill(&input2)
        var output2 = omniwm_restore_persisted_hydration_output(); zeroFill(&output2)
        let status2 = omniwm_restore_plan_persisted_hydration(&input2, &output2)
        #expect(status1 == status2)
        #expect(bytesOf(&output1) == bytesOf(&output2))
    }
}

@Suite struct KernelABIRestorePlanFloatingRescueOwnershipTests {
    @Test func inputNotMutatedAndDeterministic() {
        var output1 = omniwm_restore_floating_rescue_output(); zeroFill(&output1)
        let status1 = omniwm_restore_plan_floating_rescue(nil, 0, &output1)

        var output2 = omniwm_restore_floating_rescue_output(); zeroFill(&output2)
        let status2 = omniwm_restore_plan_floating_rescue(nil, 0, &output2)

        #expect(status1 == status2)
        #expect(bytesOf(&output1) == bytesOf(&output2))
    }
}

@Suite struct KernelABIRestoreResolveAssignmentsOwnershipTests {
    @Test func inputNotMutatedAndDeterministic() {
        var outputCount1: size_t = 0
        let status1 = omniwm_restore_resolve_assignments(
            nil, 0, nil, 0, nil, 0, nil, 0, &outputCount1
        )

        var outputCount2: size_t = 0
        let status2 = omniwm_restore_resolve_assignments(
            nil, 0, nil, 0, nil, 0, nil, 0, &outputCount2
        )

        #expect(status1 == status2)
        #expect(outputCount1 == outputCount2)
    }
}
