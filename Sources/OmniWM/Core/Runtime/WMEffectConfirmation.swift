// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

enum WMEffectConfirmation: Equatable {
    case targetWorkspaceActivated(
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID,
        source: WMEventSource,
        originatingTransactionEpoch: TransactionEpoch
    )
    case interactionMonitorSet(
        monitorId: Monitor.ID,
        source: WMEventSource,
        originatingTransactionEpoch: TransactionEpoch
    )
    case workspaceSessionPatched(
        workspaceId: WorkspaceDescriptor.ID,
        rememberedFocusToken: WindowToken?,
        source: WMEventSource,
        originatingTransactionEpoch: TransactionEpoch
    )
    case axFrameWriteOutcome(
        token: WindowToken,
        axFailure: AXFrameWriteFailureReason?,
        source: WMEventSource,
        originatingTransactionEpoch: TransactionEpoch
    )
    case observedFrame(
        token: WindowToken,
        frame: CGRect,
        source: WMEventSource,
        originatingTransactionEpoch: TransactionEpoch
    )

    var originatingTransactionEpoch: TransactionEpoch {
        switch self {
        case let .targetWorkspaceActivated(_, _, _, epoch),
             let .interactionMonitorSet(_, _, epoch),
             let .workspaceSessionPatched(_, _, _, epoch),
             let .axFrameWriteOutcome(_, _, _, epoch),
             let .observedFrame(_, _, _, epoch):
            epoch
        }
    }

    var source: WMEventSource {
        switch self {
        case let .targetWorkspaceActivated(_, _, source, _),
             let .interactionMonitorSet(_, source, _),
             let .workspaceSessionPatched(_, _, source, _),
             let .axFrameWriteOutcome(_, _, source, _),
             let .observedFrame(_, _, source, _):
            source
        }
    }

    var kindForLog: String {
        switch self {
        case .targetWorkspaceActivated:
            "target_workspace_activated"
        case .interactionMonitorSet:
            "interaction_monitor_set"
        case .workspaceSessionPatched:
            "workspace_session_patched"
        case .axFrameWriteOutcome:
            "ax_frame_write_outcome"
        case .observedFrame:
            "observed_frame"
        }
    }
}
