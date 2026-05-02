// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

enum FrameReducer {
    enum Event: Equatable {
        case desiredFrameRequested(FrameState.Frame)
        case pendingFrameWriteEmitted(
            FrameState.Frame,
            requestId: AXFrameRequestId,
            since: TransactionEpoch
        )
        case observedFrameReceived(FrameState.Frame)
        case writeFailed(reason: AXFrameWriteFailureReason, attemptedAt: TransactionEpoch)
        case captureRestorable
    }

    struct Reduction: Equatable {
        let nextState: FrameState
        let didChange: Bool
        let didPromoteToConfirmed: Bool
    }

    static func reduce(state: FrameState, event: Event) -> Reduction {
        var next = state
        var didPromote = false

        switch event {
        case let .desiredFrameRequested(frame):
            next.recordDesired(frame)

        case let .pendingFrameWriteEmitted(frame, requestId, since):
            next.recordPendingWrite(frame, requestId: requestId, since: since)

        case let .observedFrameReceived(frame):
            next.recordObserved(frame)
            didPromote = next.confirmIfObservedMatchesDesired()

        case let .writeFailed(reason, attemptedAt):
            next.recordFailedWrite(reason: reason, attemptedAt: attemptedAt)

        case .captureRestorable:
            next.captureRestorableFromConfirmed()
        }

        return Reduction(
            nextState: next,
            didChange: next != state,
            didPromoteToConfirmed: didPromote
        )
    }
}

extension FrameReducer.Event {
    init?(confirmation: WMEffectConfirmation) {
        switch confirmation {
        case let .observedFrame(_, frame, _, _):
            self = .observedFrameReceived(
                .init(rect: frame, space: .appKit, isVisibleFrame: true)
            )
        case let .axFrameWriteOutcome(_, axFailure, _, originatingTransactionEpoch):
            guard let axFailure else { return nil }
            self = .writeFailed(reason: axFailure, attemptedAt: originatingTransactionEpoch)
        case .targetWorkspaceActivated, .interactionMonitorSet, .workspaceSessionPatched:
            return nil
        }
    }
}
