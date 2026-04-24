// SPDX-License-Identifier: GPL-2.0-only
import Foundation

struct FocusState: Equatable {
    enum DesiredFocus: Equatable {
        case none
        case logical(LogicalWindowId, workspaceId: WorkspaceDescriptor.ID)
    }

    enum ActivationStatus: Equatable {
        case idle
        case pending(requestId: UInt64, originatingTransactionEpoch: TransactionEpoch)
        case confirmed(observedAt: TransactionEpoch)
        case failed(reason: FocusFailureReason, attemptedAt: TransactionEpoch)
        case recovering(reason: FocusRecoveryReason, since: TransactionEpoch)
    }

    enum PreemptionSource: Equatable {
        case none
        case nativeMenu
        case appSwitcher
        case nativeFullscreen
        case userClick(observed: WindowToken?)
    }

    enum FocusFailureReason: Equatable {
        case axActivationFailed
        case windowDestroyed
        case workspaceMismatch
        case capabilityDenied
        case missingFocusedWindow
        case pendingFocusMismatch
        case pendingFocusUnmanagedToken
        case retryExhausted
        case unknown
    }

    enum FocusRecoveryReason: Equatable {
        case focusedRemoval(expected: LogicalWindowId)
        case nativeFullscreenExit
        case scratchpadHide
        case axRefStale
        case activationFailure(reason: FocusFailureReason)
    }

    var desired: DesiredFocus = .none
    var observedToken: WindowToken?
    var activation: ActivationStatus = .idle
    var preemption: PreemptionSource = .none
    var lastFailureReason: FocusFailureReason?

    static let initial = FocusState()
}

extension FocusState {
    var hasPendingActivation: Bool {
        if case .pending = activation { return true }
        return false
    }

    var isRecovering: Bool {
        if case .recovering = activation { return true }
        return false
    }

    var isPreempted: Bool {
        preemption != .none
    }


    mutating func beginActivation(
        desired: DesiredFocus,
        requestId: UInt64,
        originatingTransactionEpoch: TransactionEpoch
    ) {
        self.desired = desired
        activation = .pending(
            requestId: requestId,
            originatingTransactionEpoch: originatingTransactionEpoch
        )
    }

    mutating func confirmActivation(
        observedToken: WindowToken,
        observedAt: TransactionEpoch
    ) {
        self.observedToken = observedToken
        activation = .confirmed(observedAt: observedAt)
        preemption = .none
        lastFailureReason = nil
    }

    mutating func failActivation(
        reason: FocusFailureReason,
        attemptedAt: TransactionEpoch
    ) {
        activation = .failed(reason: reason, attemptedAt: attemptedAt)
        lastFailureReason = reason
    }

    mutating func enterActivationFailureRecovery(
        reason: FocusFailureReason,
        since: TransactionEpoch
    ) {
        activation = .recovering(
            reason: .activationFailure(reason: reason),
            since: since
        )
        lastFailureReason = reason
    }

    mutating func enterRecovery(
        reason: FocusRecoveryReason,
        since: TransactionEpoch
    ) {
        activation = .recovering(reason: reason, since: since)
    }

    mutating func notePreemption(source: PreemptionSource) {
        preemption = source
    }

    mutating func clearPreemption() {
        preemption = .none
    }
}
