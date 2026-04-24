// SPDX-License-Identifier: GPL-2.0-only

import COmniWMKernels
import Testing

private func zeroSessionToken() -> omniwm_window_token {
    omniwm_window_token(pid: 0, window_id: 0)
}

private func zeroSessionLogicalId() -> omniwm_logical_window_id {
    omniwm_logical_window_id(value: 0)
}

private func zeroSessionUUID() -> omniwm_uuid {
    omniwm_uuid(high: 0, low: 0)
}

private func makeResolvePreferredFocusInput(
    workspaceId: omniwm_uuid
) -> omniwm_workspace_session_input {
    omniwm_workspace_session_input(
        operation: UInt32(OMNIWM_WORKSPACE_SESSION_OPERATION_RESOLVE_PREFERRED_FOCUS),
        workspace_id: workspaceId,
        monitor_id: 0,
        focused_workspace_id: zeroSessionUUID(),
        pending_tiled_workspace_id: zeroSessionUUID(),
        confirmed_tiled_workspace_id: zeroSessionUUID(),
        confirmed_floating_workspace_id: zeroSessionUUID(),
        pending_tiled_focus_logical_id: zeroSessionLogicalId(),
        confirmed_tiled_focus_logical_id: zeroSessionLogicalId(),
        confirmed_floating_focus_logical_id: zeroSessionLogicalId(),
        remembered_focus_logical_id: zeroSessionLogicalId(),
        interaction_monitor_id: 0,
        previous_interaction_monitor_id: 0,
        current_viewport_kind: UInt32(OMNIWM_WORKSPACE_SESSION_VIEWPORT_NONE),
        current_viewport_active_column_index: 0,
        patch_viewport_kind: UInt32(OMNIWM_WORKSPACE_SESSION_VIEWPORT_NONE),
        patch_viewport_active_column_index: 0,
        has_workspace_id: 1,
        has_monitor_id: 0,
        has_focused_workspace_id: 0,
        has_pending_tiled_workspace_id: 0,
        has_confirmed_tiled_workspace_id: 0,
        has_confirmed_floating_workspace_id: 0,
        has_pending_tiled_focus_logical_id: 0,
        has_confirmed_tiled_focus_logical_id: 0,
        has_confirmed_floating_focus_logical_id: 0,
        has_remembered_focus_logical_id: 0,
        has_interaction_monitor_id: 0,
        has_previous_interaction_monitor_id: 0,
        has_current_viewport_state: 0,
        has_patch_viewport_state: 0,
        should_update_interaction_monitor: 0,
        preserve_previous_interaction_monitor: 0
    )
}

private func makeWorkspaceWithRememberedToken(
    id: omniwm_uuid,
    rememberedTiledToken: omniwm_window_token
) -> omniwm_workspace_session_workspace {
    omniwm_workspace_session_workspace(
        workspace_id: id,
        assigned_anchor_point: omniwm_point(x: 0, y: 0),
        assignment_kind: UInt32(OMNIWM_WORKSPACE_SESSION_ASSIGNMENT_UNCONFIGURED),
        specific_display_id: 0,
        specific_display_name: omniwm_restore_string_ref(offset: 0, length: 0),
        remembered_tiled_focus_token: rememberedTiledToken,
        remembered_floating_focus_token: zeroSessionToken(),
        has_assigned_anchor_point: 0,
        has_specific_display_id: 0,
        has_specific_display_name: 0,
        has_remembered_tiled_focus_token: 1,
        has_remembered_floating_focus_token: 0
    )
}

private func makeCandidate(
    workspaceId: omniwm_uuid,
    pid: Int32,
    windowId: Int64,
    logicalId: UInt64
) -> omniwm_workspace_session_window_candidate {
    omniwm_workspace_session_window_candidate(
        workspace_id: workspaceId,
        token: omniwm_window_token(pid: pid, window_id: windowId),
        logical_id: omniwm_logical_window_id(value: logicalId),
        mode: UInt32(OMNIWM_WORKSPACE_SESSION_WINDOW_MODE_TILING),
        order_index: 0,
        has_hidden_proportional_position: 0,
        hidden_reason_is_workspace_inactive: 0
    )
}

private func makeResolvePreferredFocusInputWithPendingTiled(
    workspaceId: omniwm_uuid,
    pendingTiledWorkspaceId: omniwm_uuid,
    pendingLogicalId: omniwm_logical_window_id? = nil
) -> omniwm_workspace_session_input {
    omniwm_workspace_session_input(
        operation: UInt32(OMNIWM_WORKSPACE_SESSION_OPERATION_RESOLVE_PREFERRED_FOCUS),
        workspace_id: workspaceId,
        monitor_id: 0,
        focused_workspace_id: zeroSessionUUID(),
        pending_tiled_workspace_id: pendingTiledWorkspaceId,
        confirmed_tiled_workspace_id: zeroSessionUUID(),
        confirmed_floating_workspace_id: zeroSessionUUID(),
        pending_tiled_focus_logical_id: pendingLogicalId ?? zeroSessionLogicalId(),
        confirmed_tiled_focus_logical_id: zeroSessionLogicalId(),
        confirmed_floating_focus_logical_id: zeroSessionLogicalId(),
        remembered_focus_logical_id: zeroSessionLogicalId(),
        interaction_monitor_id: 0,
        previous_interaction_monitor_id: 0,
        current_viewport_kind: UInt32(OMNIWM_WORKSPACE_SESSION_VIEWPORT_NONE),
        current_viewport_active_column_index: 0,
        patch_viewport_kind: UInt32(OMNIWM_WORKSPACE_SESSION_VIEWPORT_NONE),
        patch_viewport_active_column_index: 0,
        has_workspace_id: 1,
        has_monitor_id: 0,
        has_focused_workspace_id: 0,
        has_pending_tiled_workspace_id: 1,
        has_confirmed_tiled_workspace_id: 0,
        has_confirmed_floating_workspace_id: 0,
        has_pending_tiled_focus_logical_id: pendingLogicalId == nil ? 0 : 1,
        has_confirmed_tiled_focus_logical_id: 0,
        has_confirmed_floating_focus_logical_id: 0,
        has_remembered_focus_logical_id: 0,
        has_interaction_monitor_id: 0,
        has_previous_interaction_monitor_id: 0,
        has_current_viewport_state: 0,
        has_patch_viewport_state: 0,
        should_update_interaction_monitor: 0,
        preserve_previous_interaction_monitor: 0
    )
}

private func runResolvePreferredFocusForPendingTiled(
    input: inout omniwm_workspace_session_input,
    workspaceId: omniwm_uuid,
    candidate: omniwm_workspace_session_window_candidate
) -> (status: Int32, output: omniwm_workspace_session_output) {
    let workspace = omniwm_workspace_session_workspace(
        workspace_id: workspaceId,
        assigned_anchor_point: omniwm_point(x: 0, y: 0),
        assignment_kind: UInt32(OMNIWM_WORKSPACE_SESSION_ASSIGNMENT_UNCONFIGURED),
        specific_display_id: 0,
        specific_display_name: omniwm_restore_string_ref(offset: 0, length: 0),
        remembered_tiled_focus_token: zeroSessionToken(),
        remembered_floating_focus_token: zeroSessionToken(),
        has_assigned_anchor_point: 0,
        has_specific_display_id: 0,
        has_specific_display_name: 0,
        has_remembered_tiled_focus_token: 0,
        has_remembered_floating_focus_token: 0
    )
    var output = makeOutput()
    let workspaces = [workspace]
    let candidates = [candidate]
    let status = workspaces.withUnsafeBufferPointer { workspaceBuffer in
        candidates.withUnsafeBufferPointer { candidateBuffer in
            omniwm_workspace_session_plan(
                &input,
                nil, 0,
                nil, 0,
                workspaceBuffer.baseAddress, workspaceBuffer.count,
                candidateBuffer.baseAddress, candidateBuffer.count,
                nil, 0,
                nil, 0,
                &output
            )
        }
    }
    return (status, output)
}

private func makeOutput() -> omniwm_workspace_session_output {
    omniwm_workspace_session_output(
        outcome: 0,
        patch_viewport_action: 0,
        focus_clear_action: 0,
        interaction_monitor_id: 0,
        previous_interaction_monitor_id: 0,
        resolved_focus_token: zeroSessionToken(),
        resolved_focus_logical_id: zeroSessionLogicalId(),
        monitor_results: nil,
        monitor_result_capacity: 0,
        monitor_result_count: 0,
        workspace_projections: nil,
        workspace_projection_capacity: 0,
        workspace_projection_count: 0,
        disconnected_cache_results: nil,
        disconnected_cache_result_capacity: 0,
        disconnected_cache_result_count: 0,
        has_interaction_monitor_id: 0,
        has_previous_interaction_monitor_id: 0,
        has_resolved_focus_token: 0,
        has_resolved_focus_logical_id: 0,
        should_remember_focus: 0,
        refresh_restore_intents: 0
    )
}

@Suite struct WorkspaceSessionLogicalIdentityTests {
    @Test func resolvedFocusEmitsLogicalIdWhenCandidateHasIt() {
        let workspaceId = omniwm_uuid(high: 1, low: 1)
        let rememberedToken = omniwm_window_token(pid: 100, window_id: 5050)
        let logicalIdValue: UInt64 = 42

        var input = makeResolvePreferredFocusInput(workspaceId: workspaceId)

        let workspace = makeWorkspaceWithRememberedToken(
            id: workspaceId,
            rememberedTiledToken: rememberedToken
        )
        let candidate = makeCandidate(
            workspaceId: workspaceId,
            pid: 100,
            windowId: 5050,
            logicalId: logicalIdValue
        )

        var output = makeOutput()
        let workspaces = [workspace]
        let candidates = [candidate]

        let status = workspaces.withUnsafeBufferPointer { workspaceBuffer in
            candidates.withUnsafeBufferPointer { candidateBuffer in
                omniwm_workspace_session_plan(
                    &input,
                    nil, 0,
                    nil, 0,
                    workspaceBuffer.baseAddress, workspaceBuffer.count,
                    candidateBuffer.baseAddress, candidateBuffer.count,
                    nil, 0,
                    nil, 0,
                    &output
                )
            }
        }

        #expect(status == OMNIWM_KERNELS_STATUS_OK)
        #expect(output.outcome == UInt32(OMNIWM_WORKSPACE_SESSION_OUTCOME_APPLY))
        #expect(output.has_resolved_focus_token == 1)
        #expect(output.resolved_focus_token.pid == 100)
        #expect(output.resolved_focus_token.window_id == 5050)
        #expect(output.has_resolved_focus_logical_id == 1)
        #expect(output.resolved_focus_logical_id.value == logicalIdValue)
    }

    @Test func resolvedFocusOmitsLogicalIdWhenCandidateHasZero() {
        let workspaceId = omniwm_uuid(high: 2, low: 2)
        let rememberedToken = omniwm_window_token(pid: 200, window_id: 7070)

        var input = makeResolvePreferredFocusInput(workspaceId: workspaceId)

        let workspace = makeWorkspaceWithRememberedToken(
            id: workspaceId,
            rememberedTiledToken: rememberedToken
        )
        let candidate = makeCandidate(
            workspaceId: workspaceId,
            pid: 200,
            windowId: 7070,
            logicalId: 0
        )

        var output = makeOutput()
        let workspaces = [workspace]
        let candidates = [candidate]

        let status = workspaces.withUnsafeBufferPointer { workspaceBuffer in
            candidates.withUnsafeBufferPointer { candidateBuffer in
                omniwm_workspace_session_plan(
                    &input,
                    nil, 0,
                    nil, 0,
                    workspaceBuffer.baseAddress, workspaceBuffer.count,
                    candidateBuffer.baseAddress, candidateBuffer.count,
                    nil, 0,
                    nil, 0,
                    &output
                )
            }
        }

        #expect(status == OMNIWM_KERNELS_STATUS_OK)
        #expect(output.outcome == UInt32(OMNIWM_WORKSPACE_SESSION_OUTCOME_APPLY))
        #expect(output.has_resolved_focus_token == 1)
        #expect(output.resolved_focus_token.pid == 200)
        #expect(output.resolved_focus_token.window_id == 7070)
        #expect(output.has_resolved_focus_logical_id == 0)
        #expect(output.resolved_focus_logical_id.value == 0)
    }

    @Test func noResolvedFocusKeepsLogicalIdZeroed() {
        let workspaceId = omniwm_uuid(high: 3, low: 3)
        var input = makeResolvePreferredFocusInput(workspaceId: workspaceId)

        var output = makeOutput()

        let status = omniwm_workspace_session_plan(
            &input,
            nil, 0,
            nil, 0,
            nil, 0,
            nil, 0,
            nil, 0,
            nil, 0,
            &output
        )

        #expect(status == OMNIWM_KERNELS_STATUS_OK)
        #expect(output.outcome == UInt32(OMNIWM_WORKSPACE_SESSION_OUTCOME_NOOP))
        #expect(output.has_resolved_focus_token == 0)
        #expect(output.has_resolved_focus_logical_id == 0)
        #expect(output.resolved_focus_logical_id.value == 0)
    }

    @Test func logicalIdEncodingMatchesSwiftRawValue() {
        let logicalId: UInt64 = 0xCAFE_F00D_DEAD_BEEF
        let encoded = omniwm_logical_window_id(value: logicalId)
        #expect(encoded.value == logicalId)
        #expect(MemoryLayout<omniwm_logical_window_id>.size == 8)
        #expect(MemoryLayout<omniwm_logical_window_id>.alignment == 8)
    }


    @Test func liveLogicalIdResolvesToCandidateCurrentToken() {
        let workspaceId = omniwm_uuid(high: 7, low: 7)
        let currentToken = omniwm_window_token(pid: 100, window_id: 5050)
        let logicalId: UInt64 = 42

        var input = makeResolvePreferredFocusInputWithPendingTiled(
            workspaceId: workspaceId,
            pendingTiledWorkspaceId: workspaceId,
            pendingLogicalId: omniwm_logical_window_id(value: logicalId)
        )
        let candidate = omniwm_workspace_session_window_candidate(
            workspace_id: workspaceId,
            token: currentToken,
            logical_id: omniwm_logical_window_id(value: logicalId),
            mode: UInt32(OMNIWM_WORKSPACE_SESSION_WINDOW_MODE_TILING),
            order_index: 0,
            has_hidden_proportional_position: 0,
            hidden_reason_is_workspace_inactive: 0
        )

        let (status, output) = runResolvePreferredFocusForPendingTiled(
            input: &input,
            workspaceId: workspaceId,
            candidate: candidate
        )

        #expect(status == OMNIWM_KERNELS_STATUS_OK)
        #expect(output.outcome == UInt32(OMNIWM_WORKSPACE_SESSION_OUTCOME_APPLY))
        #expect(output.has_resolved_focus_token == 1)
        #expect(output.resolved_focus_token.pid == currentToken.pid)
        #expect(output.resolved_focus_token.window_id == currentToken.window_id)
        #expect(output.has_resolved_focus_logical_id == 1)
        #expect(output.resolved_focus_logical_id.value == logicalId)
    }

    @Test func wrongLogicalIdFallsThroughToFirstEligible() {
        let workspaceId = omniwm_uuid(high: 9, low: 9)
        let candidateToken = omniwm_window_token(pid: 300, window_id: 7777)
        let candidateLogicalId: UInt64 = 11

        var input = makeResolvePreferredFocusInputWithPendingTiled(
            workspaceId: workspaceId,
            pendingTiledWorkspaceId: workspaceId,
            pendingLogicalId: omniwm_logical_window_id(value: 99)
        )
        let candidate = omniwm_workspace_session_window_candidate(
            workspace_id: workspaceId,
            token: candidateToken,
            logical_id: omniwm_logical_window_id(value: candidateLogicalId),
            mode: UInt32(OMNIWM_WORKSPACE_SESSION_WINDOW_MODE_TILING),
            order_index: 0,
            has_hidden_proportional_position: 0,
            hidden_reason_is_workspace_inactive: 0
        )

        let (status, output) = runResolvePreferredFocusForPendingTiled(
            input: &input,
            workspaceId: workspaceId,
            candidate: candidate
        )

        #expect(status == OMNIWM_KERNELS_STATUS_OK)
        #expect(output.has_resolved_focus_token == 1)
        #expect(output.resolved_focus_token.pid == candidateToken.pid)
        #expect(output.resolved_focus_token.window_id == candidateToken.window_id)
        #expect(output.has_resolved_focus_logical_id == 1)
        #expect(output.resolved_focus_logical_id.value == candidateLogicalId)
    }

    @Test func missingLogicalIdFallsBackToFirstEligible() {
        let workspaceId = omniwm_uuid(high: 10, low: 10)
        let currentToken = omniwm_window_token(pid: 400, window_id: 5050)

        var input = makeResolvePreferredFocusInputWithPendingTiled(
            workspaceId: workspaceId,
            pendingTiledWorkspaceId: workspaceId,
            pendingLogicalId: nil
        )
        let candidate = omniwm_workspace_session_window_candidate(
            workspace_id: workspaceId,
            token: currentToken,
            logical_id: omniwm_logical_window_id(value: 42),
            mode: UInt32(OMNIWM_WORKSPACE_SESSION_WINDOW_MODE_TILING),
            order_index: 0,
            has_hidden_proportional_position: 0,
            hidden_reason_is_workspace_inactive: 0
        )

        let (status, output) = runResolvePreferredFocusForPendingTiled(
            input: &input,
            workspaceId: workspaceId,
            candidate: candidate
        )

        #expect(status == OMNIWM_KERNELS_STATUS_OK)
        #expect(output.has_resolved_focus_token == 1)
        #expect(output.resolved_focus_token.window_id == currentToken.window_id)
    }
}
