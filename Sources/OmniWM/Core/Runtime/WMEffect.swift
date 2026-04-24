// SPDX-License-Identifier: GPL-2.0-only
import Foundation

enum WMEffect: Equatable {
    case hideKeyboardFocusBorder(
        reason: String,
        epoch: EffectEpoch
    )
    case saveWorkspaceViewports(
        workspaceIds: [WorkspaceDescriptor.ID],
        source: WMEventSource,
        epoch: EffectEpoch
    )
    case activateTargetWorkspace(
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID,
        source: WMEventSource,
        epoch: EffectEpoch
    )
    case setInteractionMonitor(
        monitorId: Monitor.ID,
        source: WMEventSource,
        epoch: EffectEpoch
    )
    case syncMonitorsToNiri(epoch: EffectEpoch)
    case stopScrollAnimation(
        monitorId: Monitor.ID,
        epoch: EffectEpoch
    )
    case applyWorkspaceSessionPatch(
        workspaceId: WorkspaceDescriptor.ID,
        rememberedFocusToken: WindowToken?,
        source: WMEventSource,
        epoch: EffectEpoch
    )
    case commitWorkspaceTransition(
        affectedWorkspaceIds: Set<WorkspaceDescriptor.ID>,
        postAction: PostWorkspaceTransitionAction,
        source: WMEventSource,
        epoch: EffectEpoch
    )
    case controllerActionDispatch(
        kindForLog: String,
        source: WMEventSource,
        epoch: EffectEpoch
    )
    case focusActionDispatch(
        kindForLog: String,
        source: WMEventSource,
        epoch: EffectEpoch
    )
    case windowMoveActionDispatch(
        kindForLog: String,
        source: WMEventSource,
        epoch: EffectEpoch
    )
    case layoutMutationActionDispatch(
        kindForLog: String,
        source: WMEventSource,
        epoch: EffectEpoch
    )
    case workspaceNavigationActionDispatch(
        kindForLog: String,
        source: WMEventSource,
        epoch: EffectEpoch
    )
    case uiActionDispatch(
        kindForLog: String,
        source: WMEventSource,
        epoch: EffectEpoch
    )

    enum PostWorkspaceTransitionAction: Equatable {
        case none
        case focusWindow(WindowToken)
        case clearManagedFocusAfterEmptyWorkspaceTransition
    }

    var epoch: EffectEpoch {
        switch self {
        case let .hideKeyboardFocusBorder(_, epoch),
             let .saveWorkspaceViewports(_, _, epoch),
             let .activateTargetWorkspace(_, _, _, epoch),
             let .setInteractionMonitor(_, _, epoch),
             let .syncMonitorsToNiri(epoch),
             let .stopScrollAnimation(_, epoch),
             let .applyWorkspaceSessionPatch(_, _, _, epoch),
             let .commitWorkspaceTransition(_, _, _, epoch),
             let .controllerActionDispatch(_, _, epoch),
             let .focusActionDispatch(_, _, epoch),
             let .windowMoveActionDispatch(_, _, epoch),
             let .layoutMutationActionDispatch(_, _, epoch),
             let .workspaceNavigationActionDispatch(_, _, epoch),
             let .uiActionDispatch(_, _, epoch):
            epoch
        }
    }

    var kind: String {
        switch self {
        case .hideKeyboardFocusBorder: "hide_keyboard_focus_border"
        case .saveWorkspaceViewports: "save_workspace_viewports"
        case .activateTargetWorkspace: "activate_target_workspace"
        case .setInteractionMonitor: "set_interaction_monitor"
        case .syncMonitorsToNiri: "sync_monitors_to_niri"
        case .stopScrollAnimation: "stop_scroll_animation"
        case .applyWorkspaceSessionPatch: "apply_workspace_session_patch"
        case .commitWorkspaceTransition: "commit_workspace_transition"
        case let .controllerActionDispatch(kindForLog, _, _): "controller_action_dispatch:\(kindForLog)"
        case let .focusActionDispatch(kindForLog, _, _): "focus_action_dispatch:\(kindForLog)"
        case let .windowMoveActionDispatch(kindForLog, _, _): "window_move_action_dispatch:\(kindForLog)"
        case let .layoutMutationActionDispatch(kindForLog, _, _): "layout_mutation_action_dispatch:\(kindForLog)"
        case let .workspaceNavigationActionDispatch(kindForLog, _, _): "workspace_navigation_action_dispatch:\(kindForLog)"
        case let .uiActionDispatch(kindForLog, _, _): "ui_action_dispatch:\(kindForLog)"
        }
    }
}
