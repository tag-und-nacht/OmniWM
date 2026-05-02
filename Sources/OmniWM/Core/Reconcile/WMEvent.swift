// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

enum WMEventSource: String, Equatable {
    case ax
    case workspaceManager
    case service
    case command
    case keyboard
    case config
    case animation
    case mouse
    case focusPolicy
    case ipc
}

enum WMEvent: Equatable {
    case windowAdmitted(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?,
        mode: TrackedWindowMode,
        source: WMEventSource
    )
    case windowRekeyed(
        from: WindowToken,
        to: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?,
        reason: ReplacementCorrelation.Reason,
        source: WMEventSource
    )
    case windowRemoved(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID?,
        source: WMEventSource
    )
    case workspaceAssigned(
        token: WindowToken,
        from: WorkspaceDescriptor.ID?,
        to: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?,
        source: WMEventSource
    )
    case windowModeChanged(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?,
        mode: TrackedWindowMode,
        source: WMEventSource
    )
    case floatingGeometryUpdated(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        referenceMonitorId: Monitor.ID?,
        frame: CGRect,
        restoreToFloating: Bool,
        source: WMEventSource
    )
    case hiddenStateChanged(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?,
        hiddenState: WindowModel.HiddenState?,
        source: WMEventSource
    )
    case nativeFullscreenTransition(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?,
        isActive: Bool,
        source: WMEventSource
    )
    case managedReplacementMetadataChanged(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?,
        source: WMEventSource
    )
    case topologyChanged(
        displays: [DisplayFingerprint],
        source: WMEventSource
    )
    case activeSpaceChanged(source: WMEventSource)
    case focusLeaseChanged(
        lease: FocusPolicyLease?,
        source: WMEventSource
    )
    case managedFocusRequested(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?,
        source: WMEventSource
    )
    case managedFocusConfirmed(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?,
        appFullscreen: Bool,
        source: WMEventSource,
        originatingTransactionEpoch: TransactionEpoch
    )
    case managedFocusCancelled(
        token: WindowToken?,
        workspaceId: WorkspaceDescriptor.ID?,
        source: WMEventSource,
        originatingTransactionEpoch: TransactionEpoch
    )
    case nonManagedFocusChanged(
        active: Bool,
        appFullscreen: Bool,
        preserveFocusedToken: Bool,
        source: WMEventSource
    )
    case systemSleep(source: WMEventSource)
    case systemWake(source: WMEventSource)
    case commandIntent(kindForLog: String, source: WMEventSource)

    var token: WindowToken? {
        switch self {
        case let .windowAdmitted(token, _, _, _, _),
             let .windowRemoved(token, _, _),
             let .workspaceAssigned(token, _, _, _, _),
             let .windowModeChanged(token, _, _, _, _),
             let .floatingGeometryUpdated(token, _, _, _, _, _),
             let .hiddenStateChanged(token, _, _, _, _),
             let .nativeFullscreenTransition(token, _, _, _, _),
             let .managedReplacementMetadataChanged(token, _, _, _),
             let .managedFocusRequested(token, _, _, _),
             let .managedFocusConfirmed(token, _, _, _, _, _):
            token
        case let .windowRekeyed(_, to, _, _, _, _):
            to
        case let .managedFocusCancelled(token, _, _, _):
            token
        case .topologyChanged,
             .activeSpaceChanged,
             .focusLeaseChanged,
             .nonManagedFocusChanged,
             .systemSleep,
             .systemWake,
             .commandIntent:
            nil
        }
    }

    var originatingTransactionEpoch: TransactionEpoch? {
        switch self {
        case let .managedFocusConfirmed(_, _, _, _, _, originatingTransactionEpoch),
             let .managedFocusCancelled(_, _, _, originatingTransactionEpoch):
            return originatingTransactionEpoch
        case .windowAdmitted,
             .windowRekeyed,
             .windowRemoved,
             .workspaceAssigned,
             .windowModeChanged,
             .floatingGeometryUpdated,
             .hiddenStateChanged,
             .nativeFullscreenTransition,
             .managedReplacementMetadataChanged,
             .topologyChanged,
             .activeSpaceChanged,
             .focusLeaseChanged,
             .managedFocusRequested,
             .nonManagedFocusChanged,
             .systemSleep,
             .systemWake,
             .commandIntent:
            return nil
        }
    }

    var isConfirmationFlavored: Bool {
        switch self {
        case .managedFocusConfirmed, .managedFocusCancelled:
            return true
        case .windowAdmitted,
             .windowRekeyed,
             .windowRemoved,
             .workspaceAssigned,
             .windowModeChanged,
             .floatingGeometryUpdated,
             .hiddenStateChanged,
             .nativeFullscreenTransition,
             .managedReplacementMetadataChanged,
             .topologyChanged,
             .activeSpaceChanged,
             .focusLeaseChanged,
             .managedFocusRequested,
             .nonManagedFocusChanged,
             .systemSleep,
             .systemWake,
             .commandIntent:
            return false
        }
    }

    var source: WMEventSource {
        switch self {
        case let .windowAdmitted(_, _, _, _, source),
             let .windowRekeyed(_, _, _, _, _, source),
             let .windowRemoved(_, _, source),
             let .workspaceAssigned(_, _, _, _, source),
             let .windowModeChanged(_, _, _, _, source),
             let .floatingGeometryUpdated(_, _, _, _, _, source),
             let .hiddenStateChanged(_, _, _, _, source),
             let .nativeFullscreenTransition(_, _, _, _, source),
             let .managedReplacementMetadataChanged(_, _, _, source),
             let .topologyChanged(_, source),
             let .activeSpaceChanged(source),
             let .focusLeaseChanged(_, source),
             let .managedFocusRequested(_, _, _, source),
             let .managedFocusConfirmed(_, _, _, _, source, _),
             let .managedFocusCancelled(_, _, source, _),
             let .nonManagedFocusChanged(_, _, _, source),
             let .systemSleep(source),
             let .systemWake(source),
             let .commandIntent(_, source):
            source
        }
    }

    var kindForLog: String {
        switch self {
        case .windowAdmitted: "window_admitted"
        case .windowRekeyed: "window_rekeyed"
        case .windowRemoved: "window_removed"
        case .workspaceAssigned: "workspace_assigned"
        case .windowModeChanged: "window_mode_changed"
        case .floatingGeometryUpdated: "floating_geometry_updated"
        case .hiddenStateChanged: "hidden_state_changed"
        case .nativeFullscreenTransition: "native_fullscreen_transition"
        case .managedReplacementMetadataChanged: "managed_replacement_metadata_changed"
        case .topologyChanged: "topology_changed"
        case .activeSpaceChanged: "active_space_changed"
        case .focusLeaseChanged: "focus_lease_changed"
        case .managedFocusRequested: "managed_focus_requested"
        case .managedFocusConfirmed: "managed_focus_confirmed"
        case .managedFocusCancelled: "managed_focus_cancelled"
        case .nonManagedFocusChanged: "non_managed_focus_changed"
        case .systemSleep: "system_sleep"
        case .systemWake: "system_wake"
        case let .commandIntent(kindForLog, _): "command_intent:\(kindForLog)"
        }
    }

    var summary: String {
        switch self {
        case let .windowAdmitted(token, workspaceId, _, mode, _):
            "window_admitted token=\(token) workspace=\(workspaceId.uuidString) mode=\(mode)"
        case let .windowRekeyed(from, to, workspaceId, _, reason, _):
            "window_rekeyed from=\(from) to=\(to) workspace=\(workspaceId.uuidString) reason=\(reason.rawValue)"
        case let .windowRemoved(token, workspaceId, _):
            "window_removed token=\(token) workspace=\(workspaceId?.uuidString ?? "nil")"
        case let .workspaceAssigned(token, from, to, _, _):
            "workspace_assigned token=\(token) from=\(from?.uuidString ?? "nil") to=\(to.uuidString)"
        case let .windowModeChanged(token, workspaceId, _, mode, _):
            "window_mode_changed token=\(token) workspace=\(workspaceId.uuidString) mode=\(mode)"
        case let .floatingGeometryUpdated(token, workspaceId, _, frame, restoreToFloating, _):
            "floating_geometry_updated token=\(token) workspace=\(workspaceId.uuidString) frame=\(frame.debugDescription) restore=\(restoreToFloating)"
        case let .hiddenStateChanged(token, workspaceId, _, hiddenState, _):
            "hidden_state_changed token=\(token) workspace=\(workspaceId.uuidString) hidden=\(hiddenState != nil)"
        case let .nativeFullscreenTransition(token, workspaceId, _, isActive, _):
            "native_fullscreen token=\(token) workspace=\(workspaceId.uuidString) active=\(isActive)"
        case let .managedReplacementMetadataChanged(token, workspaceId, monitorId, _):
            "managed_replacement_metadata_changed token=\(token) workspace=\(workspaceId.uuidString) monitor=\(String(describing: monitorId))"
        case let .topologyChanged(displays, _):
            "topology_changed displays=\(displays.count)"
        case .activeSpaceChanged:
            "active_space_changed"
        case let .focusLeaseChanged(lease, _):
            "focus_lease_changed owner=\(lease?.owner.rawValue ?? "nil") reason=\(lease?.reason ?? "")"
        case let .managedFocusRequested(token, workspaceId, monitorId, _):
            "managed_focus_requested token=\(token) workspace=\(workspaceId.uuidString) monitor=\(String(describing: monitorId))"
        case let .managedFocusConfirmed(token, workspaceId, monitorId, appFullscreen, _, originatingTransactionEpoch):
            "managed_focus_confirmed token=\(token) workspace=\(workspaceId.uuidString) monitor=\(String(describing: monitorId)) fullscreen=\(appFullscreen) origin_txn=\(originatingTransactionEpoch.value)"
        case let .managedFocusCancelled(token, workspaceId, _, originatingTransactionEpoch):
            "managed_focus_cancelled token=\(token.map(String.init(describing:)) ?? "nil") workspace=\(workspaceId?.uuidString ?? "nil") origin_txn=\(originatingTransactionEpoch.value)"
        case let .nonManagedFocusChanged(active, appFullscreen, preserveFocusedToken, _):
            "non_managed_focus_changed active=\(active) fullscreen=\(appFullscreen) preserve=\(preserveFocusedToken)"
        case .systemSleep:
            "system_sleep"
        case .systemWake:
            "system_wake"
        case let .commandIntent(kindForLog, source):
            "command_intent kind=\(kindForLog) source=\(source.rawValue)"
        }
    }
}
