// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import OSLog

/// Per-domain runtime for frame state — desired / pending / observed /
/// confirmed / restorable rectangles, plus AX write outcomes. Mirrors
/// `FrameStateLedger` (which owns the storage on the manager side, per
/// ExecPlan 01) and provides the epoch-stamped read/reduce surface.
///
/// Owns frame confirmation and restorable geometry mutations.
@MainActor
final class FrameRuntime {
    private let kernel: RuntimeKernel
    private let effectRunner: WMEffectRunner
    private let mutationCoordinator: RuntimeMutationCoordinator
    private unowned let workspaceManager: WorkspaceManager

    init(
        kernel: RuntimeKernel,
        effectRunner: WMEffectRunner,
        mutationCoordinator: RuntimeMutationCoordinator,
        workspaceManager: WorkspaceManager
    ) {
        self.kernel = kernel
        self.effectRunner = effectRunner
        self.mutationCoordinator = mutationCoordinator
        self.workspaceManager = workspaceManager
    }

    // MARK: Read surface

    /// The stored `FrameState` for `logicalId`, or `nil` if no frame events
    /// have been recorded for that window.
    func state(for logicalId: LogicalWindowId) -> FrameState? {
        workspaceManager.frameState(for: logicalId)
    }

    /// The stored `FrameState` for the current AX token, resolved via the
    /// logical-window registry.
    func state(for token: WindowToken) -> FrameState? {
        workspaceManager.frameState(for: token)
    }

    /// The cold-start / post-reset origin epoch used when the runner has
    /// not yet ratcheted; mirrors `WMRuntime.frameWriteOutcomeOriginEpoch`
    /// (which the migration pass made allocate-and-ratchet, so the value is
    /// stable across calls until a real commit lands).
    func outcomeOriginEpoch() -> TransactionEpoch {
        let current = effectRunner.highestAcceptedTransactionEpoch
        guard current.isValid else {
            let allocated = kernel.allocateTransactionEpoch()
            effectRunner.noteTransactionCommitted(allocated)
            return allocated
        }
        return current
    }

    // MARK: Mutations (migrated from WMRuntime — ExecPlan 02 surface migration)

    func frameWriteOutcomeOriginEpoch(source: WMEventSource = .ax) -> TransactionEpoch {
        let current = effectRunner.highestAcceptedTransactionEpoch
        guard current.isValid else {
            // Cold start / post-reset: there is no committed epoch yet, so
            // allocate one AND ratchet the runner immediately. Without the
            // ratchet, a second call to this function would allocate yet
            // another, higher epoch — leaving the first allocation behind
            // the watermark and silently rejecting the eventual frame-write
            // outcome confirmation (so quarantine never advances). The
            // allocate+ratchet pair makes the function idempotent for as
            // long as no other commit lands.
            let allocated = kernel.allocateTransactionEpoch()
            effectRunner.noteTransactionCommitted(allocated)
            return allocated
        }
        return current
    }

    @discardableResult
    func submitAXFrameWriteOutcome(
        for token: WindowToken,
        axFailure: AXFrameWriteFailureReason?,
        originatingTransactionEpoch: TransactionEpoch,
        source: WMEventSource = .ax
    ) -> Bool {
        confirmAXFrameWriteOutcome(
            for: token,
            axFailure: axFailure,
            originatingTransactionEpoch: originatingTransactionEpoch,
            source: source
        )
    }

    @discardableResult
    func recordPendingFrameWrite(
        frame: FrameState.Frame,
        requestId: AXFrameRequestId,
        for token: WindowToken
    ) -> Bool {
        let epoch = kernel.allocateTransactionEpoch()
        return workspaceManager.recordPendingFrameWrite(
            frame,
            requestId: requestId,
            since: epoch,
            for: token
        )
    }

    @discardableResult
    func recordObservedFrame(
        frame: FrameState.Frame,
        for token: WindowToken
    ) -> Bool {
        let epoch = kernel.allocateTransactionEpoch()
        return confirmObservedFrame(
            frame: frame,
            for: token,
            originatingTransactionEpoch: epoch,
            source: .ax
        )
    }

    @discardableResult
    func confirmAXFrameWriteOutcome(
        for token: WindowToken,
        axFailure: AXFrameWriteFailureReason?,
        originatingTransactionEpoch: TransactionEpoch,
        source: WMEventSource = .ax
    ) -> Bool {
        guard confirmationEpochIsCurrent(
            originatingTransactionEpoch,
            kindForLog: RuntimeMutationKind.axFrameWriteOutcomeQuarantine.rawValue,
            source: source
        ) else {
            return false
        }
        return mutationCoordinator.perform(
            .axFrameWriteOutcomeQuarantine,
            source: source,
            recordTransaction: true,
            transactionEpoch: originatingTransactionEpoch
        ) { _ in
            let outcome = workspaceManager.applyAXOutcomeQuarantine(
                for: token,
                axFailure: axFailure
            )
            if let axFailure {
                _ = workspaceManager.recordFailedFrameWrite(
                    reason: axFailure,
                    attemptedAt: originatingTransactionEpoch,
                    for: token
                )
                kernel.intakeLog.info(
                    "frame_write_failed token=\(String(describing: token), privacy: .public) reason=\(String(describing: axFailure), privacy: .public) origin_txn=\(originatingTransactionEpoch.value)"
                )
            }
            return outcome == .applied
        }
    }

    @discardableResult
    func confirmObservedFrame(
        frame: FrameState.Frame,
        for token: WindowToken,
        originatingTransactionEpoch: TransactionEpoch,
        source: WMEventSource = .ax
    ) -> Bool {
        guard confirmationEpochIsCurrent(
            originatingTransactionEpoch,
            kindForLog: RuntimeMutationKind.observedFrame.rawValue,
            source: source
        ) else {
            return false
        }
        return mutationCoordinator.perform(
            .observedFrame,
            source: source,
            recordTransaction: true,
            transactionEpoch: originatingTransactionEpoch
        ) { _ in
            workspaceManager.recordObservedFrame(frame, for: token)
        }
    }

    func updateFloatingGeometry(
        frame: CGRect,
        for token: WindowToken,
        referenceMonitor: Monitor? = nil,
        restoreToFloating: Bool = true,
        source: WMEventSource = .command
    ) {
        mutationCoordinator.perform(
            .floatingGeometryUpdated,
            source: source,
            recordTransaction: false
        ) { epoch in
            workspaceManager.updateFloatingGeometry(
                frame: frame,
                for: token,
                referenceMonitor: referenceMonitor,
                restoreToFloating: restoreToFloating,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    func setFloatingState(
        _ state: WindowModel.FloatingState?,
        for token: WindowToken,
        source: WMEventSource = .command
    ) {
        mutationCoordinator.perform(
            .setFloatingState,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.setFloatingState(state, for: token)
        }
    }

    private func confirmationEpochIsCurrent(
        _ originatingEpoch: TransactionEpoch,
        kindForLog: String,
        source: WMEventSource
    ) -> Bool {
        guard originatingEpoch.isValid else {
            mutationCoordinator.refreshSnapshotState()
            kernel.intakeLog.debug(
                "frame_confirmation_rejected_invalid_epoch kind=\(kindForLog, privacy: .public) source=\(source.rawValue, privacy: .public) origin_txn=\(originatingEpoch.value)"
            )
            return false
        }
        guard originatingEpoch >= effectRunner.highestAcceptedTransactionEpoch else {
            mutationCoordinator.refreshSnapshotState()
            let highValue = effectRunner.highestAcceptedTransactionEpoch.value
            kernel.intakeLog.debug(
                "frame_confirmation_rejected_superseded kind=\(kindForLog, privacy: .public) source=\(source.rawValue, privacy: .public) origin_txn=\(originatingEpoch.value) high=\(highValue)"
            )
            return false
        }
        return true
    }
}
