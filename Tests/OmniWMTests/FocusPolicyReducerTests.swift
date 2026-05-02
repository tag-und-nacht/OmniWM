// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct FocusPolicyReducerTests {
    private let workspaceId = WorkspaceDescriptor.ID()
    private let logicalA = LogicalWindowId(value: 1)
    private let logicalB = LogicalWindowId(value: 2)
    private let token = WindowToken(pid: 100, windowId: 7)


    @Test func scratchpadHideRedirectsDesiredToRecoveryCandidate() {
        let state = FocusState.initial
        let txn = TransactionEpoch(value: 5)
        let reduction = FocusReducer.reduce(
            state: state,
            event: .scratchpadHideStarted(
                hiddenLogicalId: logicalA,
                wasFocused: true,
                recoveryCandidate: logicalB,
                workspaceId: workspaceId,
                txn: txn
            )
        )
        #expect(reduction.didChange)
        #expect(reduction.nextState.desired == .logical(logicalB, workspaceId: workspaceId))
        #expect(reduction.nextState.activation == .recovering(reason: .scratchpadHide, since: txn))
        #expect(reduction.recommendedAction == .requestFocus(logicalB, workspaceId: workspaceId))
    }

    @Test func scratchpadHideFallsBackToWorkspaceLastFocusedWhenNoRecovery() {
        let state = FocusState.initial
        let txn = TransactionEpoch(value: 5)
        let reduction = FocusReducer.reduce(
            state: state,
            event: .scratchpadHideStarted(
                hiddenLogicalId: logicalA,
                wasFocused: true,
                recoveryCandidate: nil,
                workspaceId: workspaceId,
                txn: txn
            )
        )
        #expect(reduction.didChange)
        #expect(reduction.nextState.desired == .none)
        #expect(reduction.nextState.activation == .recovering(reason: .scratchpadHide, since: txn))
        #expect(reduction.recommendedAction == .resolveWorkspaceLastFocused(
            workspaceId: workspaceId,
            monitorId: nil
        ))
    }

    @Test func scratchpadHideOfNonFocusedWindowIsNoOp() {
        var state = FocusState.initial
        state.confirmActivation(observedToken: token, observedAt: TransactionEpoch(value: 1))
        let reduction = FocusReducer.reduce(
            state: state,
            event: .scratchpadHideStarted(
                hiddenLogicalId: logicalA,
                wasFocused: false,
                recoveryCandidate: nil,
                workspaceId: workspaceId,
                txn: TransactionEpoch(value: 5)
            )
        )
        #expect(!reduction.didChange)
        #expect(reduction.recommendedAction == nil)
    }


    @Test func focusedRemovalEntersRecovery() {
        var state = FocusState.initial
        state.confirmActivation(observedToken: token, observedAt: TransactionEpoch(value: 1))
        let txn = TransactionEpoch(value: 5)
        let reduction = FocusReducer.reduce(
            state: state,
            event: .focusedManagedWindowRemoved(removedLogicalId: logicalA, txn: txn)
        )
        #expect(reduction.didChange)
        #expect(reduction.nextState.activation == .recovering(reason: .focusedRemoval(expected: logicalA), since: txn))
        #expect(reduction.nextState.observedToken == nil)
    }


    @Test func activationRequestedTransitionsToPending() {
        let state = FocusState.initial
        let originating = TransactionEpoch(value: 7)
        let reduction = FocusReducer.reduce(
            state: state,
            event: .activationRequested(
                desired: .logical(logicalA, workspaceId: workspaceId),
                requestId: 42,
                originatingTransactionEpoch: originating
            )
        )
        #expect(reduction.didChange)
        #expect(reduction.nextState.desired == .logical(logicalA, workspaceId: workspaceId))
        #expect(reduction.nextState.activation == .pending(requestId: 42, originatingTransactionEpoch: originating))
    }

    @Test func activationConfirmedClearsPreemption() {
        var state = FocusState.initial
        state.beginActivation(
            desired: .logical(logicalA, workspaceId: workspaceId),
            requestId: 1,
            originatingTransactionEpoch: TransactionEpoch(value: 1)
        )
        state.notePreemption(source: .nativeMenu)
        let reduction = FocusReducer.reduce(
            state: state,
            event: .activationConfirmed(observedToken: token, observedAt: TransactionEpoch(value: 2))
        )
        #expect(reduction.didChange)
        #expect(reduction.nextState.activation == .confirmed(observedAt: TransactionEpoch(value: 2)))
        #expect(reduction.nextState.preemption == .none)
    }

    @Test func activationFailedEntersRecoveryAndPreservesDesired() {
        var state = FocusState.initial
        state.beginActivation(
            desired: .logical(logicalA, workspaceId: workspaceId),
            requestId: 1,
            originatingTransactionEpoch: TransactionEpoch(value: 1)
        )
        state.notePreemption(source: .nativeMenu)

        let reduction = FocusReducer.reduce(
            state: state,
            event: .activationFailed(
                reason: .missingFocusedWindow,
                attemptedAt: TransactionEpoch(value: 3)
            )
        )
        #expect(reduction.didChange)
        #expect(reduction.nextState.desired == .logical(logicalA, workspaceId: workspaceId))
        #expect(reduction.nextState.activation == .recovering(
            reason: .activationFailure(reason: .missingFocusedWindow),
            since: TransactionEpoch(value: 3)
        ))
        #expect(reduction.nextState.lastFailureReason == .missingFocusedWindow)
        #expect(reduction.nextState.preemption == .nativeMenu)
    }

    @Test func activationFailedRecoveryExitsViaObservationSettled() {
        var state = FocusState.initial
        state.beginActivation(
            desired: .logical(logicalA, workspaceId: workspaceId),
            requestId: 1,
            originatingTransactionEpoch: TransactionEpoch(value: 1)
        )
        let failed = FocusReducer.reduce(
            state: state,
            event: .activationFailed(
                reason: .pendingFocusMismatch,
                attemptedAt: TransactionEpoch(value: 3)
            )
        ).nextState
        #expect(failed.isRecovering)

        let settled = FocusReducer.reduce(
            state: failed,
            event: .observationSettled(
                observedToken: token,
                txn: TransactionEpoch(value: 4)
            )
        )
        #expect(settled.didChange)
        #expect(settled.nextState.activation == .confirmed(observedAt: TransactionEpoch(value: 4)))
        #expect(settled.nextState.observedToken == token)
        #expect(settled.nextState.lastFailureReason == nil)
    }

    @Test func activationFailedReasonsAreDistinctOnRecovery() {
        let reasons: [FocusState.FocusFailureReason] = [
            .missingFocusedWindow,
            .pendingFocusMismatch,
            .pendingFocusUnmanagedToken,
            .retryExhausted,
        ]
        for reason in reasons {
            var state = FocusState.initial
            state.beginActivation(
                desired: .logical(logicalA, workspaceId: workspaceId),
                requestId: 1,
                originatingTransactionEpoch: TransactionEpoch(value: 1)
            )
            let reduction = FocusReducer.reduce(
                state: state,
                event: .activationFailed(
                    reason: reason,
                    attemptedAt: TransactionEpoch(value: 5)
                )
            )
            #expect(reduction.nextState.activation == .recovering(
                reason: .activationFailure(reason: reason),
                since: TransactionEpoch(value: 5)
            ))
            #expect(reduction.nextState.lastFailureReason == reason)
        }
    }

    @Test func activationCancelledReturnsToIdle() {
        var state = FocusState.initial
        state.beginActivation(
            desired: .logical(logicalA, workspaceId: workspaceId),
            requestId: 1,
            originatingTransactionEpoch: TransactionEpoch(value: 1)
        )
        let reduction = FocusReducer.reduce(
            state: state,
            event: .activationCancelled(txn: TransactionEpoch(value: 4))
        )
        #expect(reduction.didChange)
        #expect(reduction.nextState.activation == .idle)
        #expect(reduction.nextState.desired == .logical(logicalA, workspaceId: workspaceId))
    }


    @Test func preemptionPreservesDesired() {
        var state = FocusState.initial
        state.beginActivation(
            desired: .logical(logicalA, workspaceId: workspaceId),
            requestId: 1,
            originatingTransactionEpoch: TransactionEpoch(value: 1)
        )
        let reduction = FocusReducer.reduce(
            state: state,
            event: .preempted(source: .appSwitcher)
        )
        #expect(reduction.didChange)
        #expect(reduction.nextState.preemption == .appSwitcher)
        #expect(reduction.nextState.desired == .logical(logicalA, workspaceId: workspaceId))
    }

    @Test func preemptionEndedClears() {
        var state = FocusState.initial
        state.notePreemption(source: .nativeFullscreen)
        let reduction = FocusReducer.reduce(
            state: state,
            event: .preemptionEnded
        )
        #expect(reduction.didChange)
        #expect(reduction.nextState.preemption == .none)
    }


    @Test func observationSettledExitsRecoveryWithoutTimer() {
        var state = FocusState.initial
        state.enterRecovery(reason: .scratchpadHide, since: TransactionEpoch(value: 1))
        let observedAt = TransactionEpoch(value: 2)
        let reduction = FocusReducer.reduce(
            state: state,
            event: .observationSettled(observedToken: token, txn: observedAt)
        )
        #expect(reduction.didChange)
        #expect(reduction.nextState.activation == .confirmed(observedAt: observedAt))
        #expect(reduction.nextState.observedToken == token)
    }

    @Test func observationSettledOutsideRecoveryJustUpdatesObservedToken() {
        var state = FocusState.initial
        state.confirmActivation(observedToken: token, observedAt: TransactionEpoch(value: 1))
        let other = WindowToken(pid: 200, windowId: 8)
        let reduction = FocusReducer.reduce(
            state: state,
            event: .observationSettled(observedToken: other, txn: TransactionEpoch(value: 2))
        )
        #expect(reduction.didChange)
        #expect(reduction.nextState.observedToken == other)
        #expect(reduction.nextState.activation == .confirmed(observedAt: TransactionEpoch(value: 1)))
    }
}
