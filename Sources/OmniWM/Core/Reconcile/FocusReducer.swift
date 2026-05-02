// SPDX-License-Identifier: GPL-2.0-only
import Foundation

enum FocusReducer {
    enum Event: Equatable {
        case scratchpadHideStarted(
            hiddenLogicalId: LogicalWindowId,
            wasFocused: Bool,
            recoveryCandidate: LogicalWindowId?,
            workspaceId: WorkspaceDescriptor.ID,
            txn: TransactionEpoch
        )
        case focusedManagedWindowRemoved(
            removedLogicalId: LogicalWindowId,
            txn: TransactionEpoch
        )
        case activationRequested(
            desired: FocusState.DesiredFocus,
            requestId: UInt64,
            originatingTransactionEpoch: TransactionEpoch
        )
        case activationConfirmed(
            observedToken: WindowToken,
            observedAt: TransactionEpoch
        )
        case activationFailed(
            reason: FocusState.FocusFailureReason,
            attemptedAt: TransactionEpoch
        )
        case activationCancelled(txn: TransactionEpoch)
        case preempted(source: FocusState.PreemptionSource)
        case preemptionEnded
        case observationSettled(
            observedToken: WindowToken,
            txn: TransactionEpoch
        )
    }

    struct Reduction: Equatable {
        let nextState: FocusState
        let didChange: Bool
        let recommendedAction: RecommendedAction?
    }

    enum RecommendedAction: Equatable {
        case requestFocus(LogicalWindowId, workspaceId: WorkspaceDescriptor.ID)
        case clearBorder
        case resolveWorkspaceLastFocused(
            workspaceId: WorkspaceDescriptor.ID,
            monitorId: Monitor.ID?
        )
    }

    static func reduce(state: FocusState, event: Event) -> Reduction {
        var next = state
        var action: RecommendedAction? = nil

        // Gate stale activation outcomes against the live activation epoch.
        // Without this, a late-arriving confirm/fail/cancel from a superseded
        // request can wipe a freshly-pending activation or roll a confirmed
        // activation back to recovering. The activation-retry Task.sleep was
        // removed during the reliability migration, so reducer ordering is
        // the only safety net here.
        if let staleEpoch = staleActivationEpoch(state: state, event: event) {
            _ = staleEpoch  // explicit drop; surface via debugger if needed
            return Reduction(nextState: state, didChange: false, recommendedAction: nil)
        }

        switch event {
        case let .scratchpadHideStarted(_, wasFocused, recoveryCandidate, workspaceId, txn):
            if let recoveryCandidate {
                next.desired = .logical(recoveryCandidate, workspaceId: workspaceId)
                if wasFocused {
                    next.enterRecovery(reason: .scratchpadHide, since: txn)
                }
                action = .requestFocus(recoveryCandidate, workspaceId: workspaceId)
            } else if wasFocused {
                next.desired = .none
                next.enterRecovery(reason: .scratchpadHide, since: txn)
                action = .resolveWorkspaceLastFocused(
                    workspaceId: workspaceId,
                    monitorId: nil
                )
            }

        case let .focusedManagedWindowRemoved(removedLogicalId, txn):
            next.observedToken = nil
            next.enterRecovery(
                reason: .focusedRemoval(expected: removedLogicalId),
                since: txn
            )

        case let .activationRequested(desired, requestId, originatingTransactionEpoch):
            next.beginActivation(
                desired: desired,
                requestId: requestId,
                originatingTransactionEpoch: originatingTransactionEpoch
            )

        case let .activationConfirmed(observedToken, observedAt):
            next.confirmActivation(observedToken: observedToken, observedAt: observedAt)

        case let .activationFailed(reason, attemptedAt):
            next.enterActivationFailureRecovery(
                reason: reason,
                since: attemptedAt
            )

        case .activationCancelled:
            next.activation = .idle

        case let .preempted(source):
            next.notePreemption(source: source)

        case .preemptionEnded:
            next.clearPreemption()

        case let .observationSettled(observedToken, txn):
            next.observedToken = observedToken
            if state.isRecovering {
                next.activation = .confirmed(observedAt: txn)
                next.clearPreemption()
                next.lastFailureReason = nil
            }
        }

        let didChange = next != state
        return Reduction(nextState: next, didChange: didChange, recommendedAction: action)
    }

    /// If `event` carries an activation epoch and that epoch is strictly
    /// older than the current activation's epoch, the event is from a
    /// superseded request and must be dropped. Returns the (event_epoch,
    /// state_epoch) pair when stale; `nil` otherwise.
    private static func staleActivationEpoch(
        state: FocusState,
        event: Event
    ) -> (event: TransactionEpoch, state: TransactionEpoch)? {
        let eventEpoch: TransactionEpoch
        switch event {
        case let .activationConfirmed(_, observedAt):
            eventEpoch = observedAt
        case let .activationFailed(_, attemptedAt):
            eventEpoch = attemptedAt
        case let .activationCancelled(txn):
            eventEpoch = txn
        case let .observationSettled(_, txn):
            eventEpoch = txn
        case .scratchpadHideStarted,
             .focusedManagedWindowRemoved,
             .activationRequested,
             .preempted,
             .preemptionEnded:
            return nil
        }

        let stateEpoch: TransactionEpoch
        switch state.activation {
        case .idle:
            return nil
        case let .pending(_, originatingTransactionEpoch):
            stateEpoch = originatingTransactionEpoch
        case let .confirmed(observedAt):
            stateEpoch = observedAt
        case let .failed(_, attemptedAt):
            stateEpoch = attemptedAt
        case let .recovering(_, since):
            stateEpoch = since
        }

        guard stateEpoch.isValid, eventEpoch.isValid, eventEpoch < stateEpoch else {
            return nil
        }
        return (event: eventEpoch, state: stateEpoch)
    }
}
