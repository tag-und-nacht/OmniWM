// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import OSLog

struct PendingFrameWriteRecordResult: Equatable {
    let changed: Bool
    let requestId: AXFrameRequestId
    let transactionEpoch: TransactionEpoch
}

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

    /// The cold-start / post-reset origin epoch used for standalone observed
    /// frame samples when no pending write exists.
    func observedFrameOriginEpoch(source: WMEventSource = .ax) -> TransactionEpoch {
        let current = effectRunner.highestAcceptedTransactionEpoch
        guard current.isValid else {
            let allocated = kernel.allocateTransactionEpoch()
            effectRunner.noteTransactionCommitted(allocated)
            return allocated
        }
        return current
    }

    // MARK: Mutations (migrated from WMRuntime — ExecPlan 02 surface migration)

    func frameWriteOutcomeOriginEpoch(
        for token: WindowToken,
        requestId: AXFrameRequestId,
        source: WMEventSource = .ax
    ) -> TransactionEpoch {
        if case let .pending(pendingRequestId, since) = workspaceManager.frameState(for: token)?.write,
           pendingRequestId == requestId
        {
            return since
        }
        return .invalid
    }

    func observedFrameOriginEpoch(
        for token: WindowToken,
        source: WMEventSource = .ax
    ) -> TransactionEpoch {
        if case let .pending(_, since) = workspaceManager.frameState(for: token)?.write {
            return since
        }
        return observedFrameOriginEpoch(source: source)
    }

    func observedFrameOriginEpoch(
        for token: WindowToken,
        requestId: AXFrameRequestId?,
        source: WMEventSource = .ax
    ) -> TransactionEpoch {
        if let requestId {
            return frameWriteOutcomeOriginEpoch(
                for: token,
                requestId: requestId,
                source: source
            )
        }
        return observedFrameOriginEpoch(for: token, source: source)
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
    func submitAXFrameWriteOutcome(
        for token: WindowToken,
        requestId: AXFrameRequestId,
        axFailure: AXFrameWriteFailureReason?,
        source: WMEventSource = .ax
    ) -> Bool {
        let originatingTransactionEpoch = frameWriteOutcomeOriginEpoch(
            for: token,
            requestId: requestId,
            source: source
        )
        return submitAXFrameWriteOutcome(
            for: token,
            axFailure: axFailure,
            originatingTransactionEpoch: originatingTransactionEpoch,
            source: source
        )
    }

    @discardableResult
    func recordPendingFrameWrite(
        frame: FrameState.Frame,
        requestId: AXFrameRequestId? = nil,
        for token: WindowToken,
        source: WMEventSource = .ax
    ) -> PendingFrameWriteRecordResult {
        let epoch = kernel.allocateTransactionEpoch()
        let resolvedRequestId = requestId ?? epoch.value
        let changed = mutationCoordinator.perform(
            .pendingFrameWrite,
            source: source,
            recordTransaction: true,
            transactionEpoch: epoch,
            resultNotes: { _ in ["request_id=\(resolvedRequestId)"] }
        ) { txn in
            workspaceManager.recordPendingFrameWrite(
                frame,
                requestId: resolvedRequestId,
                since: txn,
                for: token
            )
        }
        return .init(
            changed: changed,
            requestId: resolvedRequestId,
            transactionEpoch: epoch
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
        guard frameConfirmationEpochIsCurrent(
            originatingTransactionEpoch,
            kindForLog: RuntimeMutationKind.axFrameWriteOutcomeQuarantine.rawValue,
            token: token,
            requiresPendingWrite: true,
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
        guard frameConfirmationEpochIsCurrent(
            originatingTransactionEpoch,
            kindForLog: RuntimeMutationKind.observedFrame.rawValue,
            token: token,
            observedFrame: frame,
            requiresPendingWrite: false,
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

    private func frameConfirmationEpochIsCurrent(
        _ originatingEpoch: TransactionEpoch,
        kindForLog: String,
        token: WindowToken,
        observedFrame: FrameState.Frame? = nil,
        requiresPendingWrite: Bool,
        source: WMEventSource
    ) -> Bool {
        guard originatingEpoch.isValid else {
            mutationCoordinator.refreshSnapshotState()
            kernel.intakeLog.debug(
                "frame_confirmation_rejected_invalid_epoch kind=\(kindForLog, privacy: .public) source=\(source.rawValue, privacy: .public) origin_txn=\(originatingEpoch.value)"
            )
            return false
        }
        guard let state = workspaceManager.frameState(for: token) else {
            if requiresPendingWrite {
                mutationCoordinator.refreshSnapshotState()
                kernel.intakeLog.debug(
                    "frame_confirmation_rejected_no_frame_state kind=\(kindForLog, privacy: .public) source=\(source.rawValue, privacy: .public) origin_txn=\(originatingEpoch.value)"
                )
                return false
            }
            return true
        }
        if case let .pending(_, since) = state.write {
            guard since == originatingEpoch else {
                mutationCoordinator.refreshSnapshotState()
                kernel.intakeLog.debug(
                    "frame_confirmation_rejected_superseded_pending_write kind=\(kindForLog, privacy: .public) source=\(source.rawValue, privacy: .public) origin_txn=\(originatingEpoch.value) pending_txn=\(since.value)"
                )
                return false
            }
            if let observedFrame {
                guard let pendingFrame = state.pending else {
                    mutationCoordinator.refreshSnapshotState()
                    kernel.intakeLog.debug(
                        "frame_confirmation_rejected_missing_pending_frame kind=\(kindForLog, privacy: .public) source=\(source.rawValue, privacy: .public) origin_txn=\(originatingEpoch.value)"
                    )
                    return false
                }
                guard observedFrame.isWithinTolerance(of: pendingFrame) else {
                    mutationCoordinator.refreshSnapshotState()
                    kernel.intakeLog.debug(
                        "frame_confirmation_rejected_pending_frame_mismatch kind=\(kindForLog, privacy: .public) source=\(source.rawValue, privacy: .public) origin_txn=\(originatingEpoch.value)"
                    )
                    return false
                }
            }
            return true
        }
        if requiresPendingWrite {
            mutationCoordinator.refreshSnapshotState()
            kernel.intakeLog.debug(
                "frame_confirmation_rejected_no_pending_write kind=\(kindForLog, privacy: .public) source=\(source.rawValue, privacy: .public) origin_txn=\(originatingEpoch.value)"
            )
            return false
        }
        return true
    }
}
