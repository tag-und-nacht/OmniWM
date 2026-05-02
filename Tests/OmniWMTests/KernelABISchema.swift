// SPDX-License-Identifier: GPL-2.0-only

import COmniWMKernels
import Foundation

struct KernelABISchemaEntry: Equatable, Hashable {
    let name: String
    let size: Int
    let stride: Int
    let alignment: Int
}

enum KernelABISchema {
    static let schemaVersion: Int = 1

    static func currentLayouts() -> [KernelABISchemaEntry] {
        [
            entry("omniwm_axis_input", omniwm_axis_input.self),
            entry("omniwm_axis_output", omniwm_axis_output.self),
            entry("omniwm_dwindle_layout_input", omniwm_dwindle_layout_input.self),
            entry("omniwm_dwindle_node_input", omniwm_dwindle_node_input.self),
            entry("omniwm_dwindle_node_frame", omniwm_dwindle_node_frame.self),
            entry("omniwm_niri_layout_input", omniwm_niri_layout_input.self),
            entry("omniwm_niri_container_input", omniwm_niri_container_input.self),
            entry("omniwm_niri_window_input", omniwm_niri_window_input.self),
            entry("omniwm_niri_hidden_placement_monitor", omniwm_niri_hidden_placement_monitor.self),
            entry("omniwm_niri_container_output", omniwm_niri_container_output.self),
            entry("omniwm_niri_window_output", omniwm_niri_window_output.self),
            entry("omniwm_niri_topology_column_input", omniwm_niri_topology_column_input.self),
            entry("omniwm_niri_topology_window_input", omniwm_niri_topology_window_input.self),
            entry("omniwm_geometry_snap_target_result", omniwm_geometry_snap_target_result.self),
            entry("omniwm_niri_topology_input", omniwm_niri_topology_input.self),
            entry("omniwm_niri_topology_column_output", omniwm_niri_topology_column_output.self),
            entry("omniwm_niri_topology_window_output", omniwm_niri_topology_window_output.self),
            entry("omniwm_niri_topology_result", omniwm_niri_topology_result.self),
            entry("omniwm_overview_context", omniwm_overview_context.self),
            entry("omniwm_overview_workspace_input", omniwm_overview_workspace_input.self),
            entry("omniwm_overview_generic_window_input", omniwm_overview_generic_window_input.self),
            entry("omniwm_overview_niri_tile_input", omniwm_overview_niri_tile_input.self),
            entry("omniwm_overview_niri_column_input", omniwm_overview_niri_column_input.self),
            entry("omniwm_overview_section_output", omniwm_overview_section_output.self),
            entry("omniwm_overview_generic_window_output", omniwm_overview_generic_window_output.self),
            entry("omniwm_overview_niri_tile_output", omniwm_overview_niri_tile_output.self),
            entry("omniwm_overview_niri_column_output", omniwm_overview_niri_column_output.self),
            entry("omniwm_overview_drop_zone_output", omniwm_overview_drop_zone_output.self),
            entry("omniwm_overview_result", omniwm_overview_result.self),
            entry("omniwm_restore_snapshot", omniwm_restore_snapshot.self),
            entry("omniwm_restore_monitor", omniwm_restore_monitor.self),
            entry("omniwm_restore_assignment", omniwm_restore_assignment.self),
            entry("omniwm_point", omniwm_point.self),
            entry("omniwm_rect", omniwm_rect.self),
            entry("omniwm_uuid", omniwm_uuid.self),
            entry("omniwm_window_token", omniwm_window_token.self),
            entry("omniwm_logical_window_id", omniwm_logical_window_id.self),
            entry("omniwm_restore_string_ref", omniwm_restore_string_ref.self),
            entry("omniwm_restore_monitor_key", omniwm_restore_monitor_key.self),
            entry("omniwm_restore_monitor_context", omniwm_restore_monitor_context.self),
            entry("omniwm_restore_event_input", omniwm_restore_event_input.self),
            entry("omniwm_restore_event_output", omniwm_restore_event_output.self),
            entry("omniwm_restore_visible_workspace_snapshot", omniwm_restore_visible_workspace_snapshot.self),
            entry("omniwm_restore_disconnected_cache_entry", omniwm_restore_disconnected_cache_entry.self),
            entry("omniwm_restore_workspace_monitor_fact", omniwm_restore_workspace_monitor_fact.self),
            entry("omniwm_restore_topology_input", omniwm_restore_topology_input.self),
            entry("omniwm_restore_visible_assignment", omniwm_restore_visible_assignment.self),
            entry("omniwm_restore_disconnected_cache_output_entry", omniwm_restore_disconnected_cache_output_entry.self),
            entry("omniwm_restore_topology_output", omniwm_restore_topology_output.self),
            entry("omniwm_restore_persisted_key", omniwm_restore_persisted_key.self),
            entry("omniwm_restore_persisted_entry_snapshot", omniwm_restore_persisted_entry_snapshot.self),
            entry("omniwm_restore_persisted_hydration_input", omniwm_restore_persisted_hydration_input.self),
            entry("omniwm_restore_persisted_hydration_output", omniwm_restore_persisted_hydration_output.self),
            entry("omniwm_restore_floating_rescue_candidate", omniwm_restore_floating_rescue_candidate.self),
            entry("omniwm_restore_floating_rescue_operation", omniwm_restore_floating_rescue_operation.self),
            entry("omniwm_restore_floating_rescue_output", omniwm_restore_floating_rescue_output.self),
            entry("omniwm_window_decision_rule_summary", omniwm_window_decision_rule_summary.self),
            entry("omniwm_window_decision_built_in_rule_summary", omniwm_window_decision_built_in_rule_summary.self),
            entry("omniwm_window_decision_input", omniwm_window_decision_input.self),
            entry("omniwm_window_decision_output", omniwm_window_decision_output.self),
            entry("omniwm_workspace_navigation_input", omniwm_workspace_navigation_input.self),
            entry("omniwm_workspace_navigation_monitor", omniwm_workspace_navigation_monitor.self),
            entry("omniwm_workspace_navigation_workspace", omniwm_workspace_navigation_workspace.self),
            entry("omniwm_workspace_navigation_output", omniwm_workspace_navigation_output.self),
            entry("omniwm_workspace_session_input", omniwm_workspace_session_input.self),
            entry("omniwm_workspace_session_monitor", omniwm_workspace_session_monitor.self),
            entry("omniwm_workspace_session_previous_monitor", omniwm_workspace_session_previous_monitor.self),
            entry("omniwm_workspace_session_disconnected_cache_entry", omniwm_workspace_session_disconnected_cache_entry.self),
            entry("omniwm_workspace_session_workspace", omniwm_workspace_session_workspace.self),
            entry("omniwm_workspace_session_window_candidate", omniwm_workspace_session_window_candidate.self),
            entry("omniwm_workspace_session_monitor_result", omniwm_workspace_session_monitor_result.self),
            entry("omniwm_workspace_session_workspace_projection", omniwm_workspace_session_workspace_projection.self),
            entry("omniwm_workspace_session_disconnected_cache_result", omniwm_workspace_session_disconnected_cache_result.self),
            entry("omniwm_workspace_session_output", omniwm_workspace_session_output.self),
            entry("omniwm_reconcile_observed_state", omniwm_reconcile_observed_state.self),
            entry("omniwm_reconcile_desired_state", omniwm_reconcile_desired_state.self),
            entry("omniwm_reconcile_floating_state", omniwm_reconcile_floating_state.self),
            entry("omniwm_reconcile_entry", omniwm_reconcile_entry.self),
            entry("omniwm_reconcile_monitor", omniwm_reconcile_monitor.self),
            entry("omniwm_reconcile_pending_focus", omniwm_reconcile_pending_focus.self),
            entry("omniwm_reconcile_focus_session", omniwm_reconcile_focus_session.self),
            entry("omniwm_reconcile_persisted_hydration", omniwm_reconcile_persisted_hydration.self),
            entry("omniwm_reconcile_event", omniwm_reconcile_event.self),
            entry("omniwm_reconcile_restore_intent_output", omniwm_reconcile_restore_intent_output.self),
            entry("omniwm_reconcile_replacement_correlation", omniwm_reconcile_replacement_correlation.self),
            entry("omniwm_reconcile_focus_session_output", omniwm_reconcile_focus_session_output.self),
            entry("omniwm_reconcile_plan_output", omniwm_reconcile_plan_output.self),
            entry("omniwm_orchestration_old_frame_record", omniwm_orchestration_old_frame_record.self),
            entry("omniwm_orchestration_window_removal_payload", omniwm_orchestration_window_removal_payload.self),
            entry("omniwm_orchestration_follow_up_refresh", omniwm_orchestration_follow_up_refresh.self),
            entry("omniwm_orchestration_refresh", omniwm_orchestration_refresh.self),
            entry("omniwm_orchestration_managed_request", omniwm_orchestration_managed_request.self),
            entry("omniwm_orchestration_refresh_snapshot", omniwm_orchestration_refresh_snapshot.self),
            entry("omniwm_orchestration_focus_snapshot", omniwm_orchestration_focus_snapshot.self),
            entry("omniwm_orchestration_snapshot", omniwm_orchestration_snapshot.self),
            entry("omniwm_orchestration_refresh_request_event", omniwm_orchestration_refresh_request_event.self),
            entry("omniwm_orchestration_refresh_completion_event", omniwm_orchestration_refresh_completion_event.self),
            entry("omniwm_orchestration_focus_request_event", omniwm_orchestration_focus_request_event.self),
            entry("omniwm_orchestration_activation_observation", omniwm_orchestration_activation_observation.self),
            entry("omniwm_orchestration_event", omniwm_orchestration_event.self),
            entry("omniwm_orchestration_decision", omniwm_orchestration_decision.self),
            entry("omniwm_orchestration_action", omniwm_orchestration_action.self),
            entry("omniwm_orchestration_step_input", omniwm_orchestration_step_input.self),
            entry("omniwm_orchestration_step_output", omniwm_orchestration_step_output.self),
            entry("omniwm_orchestration_abi_layout_info", omniwm_orchestration_abi_layout_info.self),
        ]
    }

    private static func entry<T>(_ name: String, _ type: T.Type) -> KernelABISchemaEntry {
        KernelABISchemaEntry(
            name: name,
            size: MemoryLayout<T>.size,
            stride: MemoryLayout<T>.stride,
            alignment: MemoryLayout<T>.alignment
        )
    }
}
