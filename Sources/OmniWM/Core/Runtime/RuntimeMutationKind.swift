// SPDX-License-Identifier: GPL-2.0-only
import Foundation

/// Classification of every state-mutating path that flows through
/// `WMRuntime.performRuntimeMutation`. The raw value is the snake-case
/// taxonomy string used in `os_signpost` interval names and in the
/// `intakeLog.debug` / `intakeLog.notice` payloads. Treat the raw values
/// as a wire-format on the signpost / log surface — dashboards and offline
/// log scrapers key off these strings.
///
/// Extracted from `WMRuntime` (was a 43-case private enum) per ExecPlan 02
/// follow-on. Kept as a pure POD enum: no associated values, no methods.
/// Adding a case here is a pure-data change. Keep the cases sorted in the
/// order they were originally declared so signpost/log diffs stay clean.
enum RuntimeMutationKind: String {
    case activateInferredWorkspaceIfNeeded = "activate_inferred_workspace_if_needed"
    case activeWorkspaceSet = "active_workspace_set"
    case applyOrchestrationFocusState = "apply_orchestration_focus_state"
    case applyWorkspaceSettings = "workspace_settings_applied"
    case applySessionPatch = "session_patch"
    case applySessionTransfer = "session_transfer"
    case assignWorkspaceToMonitor = "assign_workspace_to_monitor"
    case clearManagedFocusAfterEmptyWorkspaceTransition = "clear_managed_focus_after_empty_workspace_transition"
    case clearManagedRestoreSnapshot = "clear_managed_restore_snapshot"
    case clearScratchpad = "clear_scratchpad"
    case commitWorkspaceSelection = "commit_workspace_selection"
    case enterNonManagedFocus = "enter_non_managed_focus"
    case finalizeNativeFullscreenRestore = "finalize_native_fullscreen_restore"
    case floatingGeometryUpdated = "floating_geometry_updated"
    case focusActivationFailure = "focus_activation_failure"
    case focusManagedWindowRemoved = "focus_managed_window_removed"
    case focusObservationSettled = "focus_observation_settled"
    case focusReducer = "focus_reducer"
    case garbageCollectUnusedWorkspaces = "garbage_collect_unused_workspaces"
    case hiddenStateChanged = "hidden_state_changed"
    case interactionMonitorSet = "interaction_monitor_set"
    case managedAppFullscreenSet = "managed_app_fullscreen_set"
    case managedReplacementMetadataChanged = "managed_replacement_metadata_changed"
    case managedRestoreSnapshotSet = "managed_restore_snapshot_set"
    case manualLayoutOverrideSet = "manual_layout_override_set"
    case nativeLayoutReasonSet = "native_layout_reason_set"
    case nativeFullscreenEnterRequested = "native_fullscreen_enter_requested"
    case nativeFullscreenExitRequested = "native_fullscreen_exit_requested"
    case nativeFullscreenRestoreSnapshotSeeded = "native_fullscreen_restore_snapshot_seeded"
    case nativeFullscreenSuspended = "native_fullscreen_suspended"
    case nativeFullscreenTemporarilyUnavailable = "native_fullscreen_temporarily_unavailable"
    case nativeFullscreenStaleExpiry = "native_fullscreen_stale_expiry"
    case nativeStateRestored = "native_state_restored"
    case niriViewportStateUpdated = "niri_viewport_state_updated"
    case borderOwnershipReconciled = "border_ownership_reconciled"
    case axFrameWriteOutcomeQuarantine = "ax_frame_write_outcome"
    case observedFrame = "observed_frame"
    case staleCGSDestroyAudit = "stale_cgs_destroy_audit"
    case appDisappearedQuarantineSweep = "app_disappeared_quarantine_sweep"
    case removeMissingWindows = "remove_missing_windows"
    case resolveWorkspaceFocus = "resolve_workspace_focus"
    case setFloatingState = "set_floating_state"
    case setScratchpad = "set_scratchpad"
    case setWorkspace = "set_workspace"
    case targetWorkspaceActivated = "target_workspace_activated"
    case tiledWindowOrderSwap = "tiled_window_order_swap"
    case workspaceSessionPatched = "workspace_session_patched"
    case workspaceMaterialized = "workspace_materialized"
    case workspaceSwap = "workspace_swap"
    case windowModeChanged = "window_mode_changed"
}
