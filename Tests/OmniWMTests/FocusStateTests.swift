// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct FocusStateTests {
    private let workspaceId = WorkspaceDescriptor.ID()
    private let logicalId = LogicalWindowId(value: 42)
    private let observedToken = WindowToken(pid: 100, windowId: 7)

    @Test func initialStateIsIdleAndUnfocused() {
        let state = FocusState.initial
        #expect(state.desired == .none)
        #expect(state.observedToken == nil)
        #expect(state.activation == .idle)
        #expect(state.preemption == .none)
        #expect(state.lastFailureReason == nil)
        #expect(!state.hasPendingActivation)
        #expect(!state.isRecovering)
        #expect(!state.isPreempted)
    }

    @Test func beginActivationTransitionsToPending() {
        var state = FocusState.initial
        let originating = TransactionEpoch(value: 1)
        state.beginActivation(
            desired: .logical(logicalId, workspaceId: workspaceId),
            requestId: 99,
            originatingTransactionEpoch: originating
        )
        #expect(state.desired == .logical(logicalId, workspaceId: workspaceId))
        #expect(state.activation == .pending(requestId: 99, originatingTransactionEpoch: originating))
        #expect(state.hasPendingActivation)
    }

    @Test func confirmActivationTransitionsToConfirmedAndClearsPreemption() {
        var state = FocusState.initial
        state.beginActivation(
            desired: .logical(logicalId, workspaceId: workspaceId),
            requestId: 1,
            originatingTransactionEpoch: TransactionEpoch(value: 1)
        )
        state.notePreemption(source: .nativeMenu)
        let observedAt = TransactionEpoch(value: 2)
        state.confirmActivation(observedToken: observedToken, observedAt: observedAt)
        #expect(state.activation == .confirmed(observedAt: observedAt))
        #expect(state.observedToken == observedToken)
        #expect(state.preemption == .none)
        #expect(state.lastFailureReason == nil)
    }

    @Test func failActivationRecordsReason() {
        var state = FocusState.initial
        let attemptedAt = TransactionEpoch(value: 7)
        state.failActivation(reason: .axActivationFailed, attemptedAt: attemptedAt)
        #expect(state.activation == .failed(reason: .axActivationFailed, attemptedAt: attemptedAt))
        #expect(state.lastFailureReason == .axActivationFailed)
    }

    @Test func enterRecoveryDoesNotClearLastFailureReason() {
        var state = FocusState.initial
        state.failActivation(reason: .windowDestroyed, attemptedAt: TransactionEpoch(value: 3))
        let since = TransactionEpoch(value: 4)
        state.enterRecovery(reason: .focusedRemoval(expected: logicalId), since: since)
        #expect(state.activation == .recovering(reason: .focusedRemoval(expected: logicalId), since: since))
        #expect(state.lastFailureReason == .windowDestroyed)
        #expect(state.isRecovering)
        #expect(!state.hasPendingActivation)
    }

    @Test func recoveryResolvesViaConfirmation() {
        var state = FocusState.initial
        state.enterRecovery(reason: .scratchpadHide, since: TransactionEpoch(value: 5))
        #expect(state.isRecovering)
        let observedAt = TransactionEpoch(value: 6)
        state.confirmActivation(observedToken: observedToken, observedAt: observedAt)
        #expect(state.activation == .confirmed(observedAt: observedAt))
        #expect(!state.isRecovering)
    }

    @Test func preemptionDoesNotClobberDesired() {
        var state = FocusState.initial
        state.beginActivation(
            desired: .logical(logicalId, workspaceId: workspaceId),
            requestId: 11,
            originatingTransactionEpoch: TransactionEpoch(value: 1)
        )
        state.notePreemption(source: .appSwitcher)
        #expect(state.desired == .logical(logicalId, workspaceId: workspaceId))
        #expect(state.preemption == .appSwitcher)
        #expect(state.isPreempted)
        state.clearPreemption()
        #expect(state.preemption == .none)
        #expect(state.desired == .logical(logicalId, workspaceId: workspaceId))
    }

    @Test func userClickPreemptionCarriesObservedToken() {
        var state = FocusState.initial
        state.notePreemption(source: .userClick(observed: observedToken))
        #expect(state.preemption == .userClick(observed: observedToken))
        #expect(state.isPreempted)
    }
}
