// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OSLog

@MainActor
protocol RuntimeSnapshotPublishing: AnyObject {
    func refreshSnapshotState()
}

/// Shared mutation chokepoint for domain runtimes.
///
/// `RuntimeKernel` remains the only epoch mint. This coordinator owns the
/// repeated signpost/log/snapshot/transaction pattern and also accepts an
/// externally supplied transaction epoch for command effects, so mutations
/// produced by a typed command are stamped with the transaction that submitted
/// that command.
@MainActor
final class RuntimeMutationCoordinator {
    let kernel: RuntimeKernel
    let effectRunner: WMEffectRunner
    private unowned let workspaceManager: WorkspaceManager
    private var activeCommandTransactionEpoch: TransactionEpoch?
    weak var snapshotPublisher: RuntimeSnapshotPublishing?

    init(
        kernel: RuntimeKernel,
        effectRunner: WMEffectRunner,
        workspaceManager: WorkspaceManager
    ) {
        self.kernel = kernel
        self.effectRunner = effectRunner
        self.workspaceManager = workspaceManager
    }

    var highestAcceptedTransactionEpoch: TransactionEpoch {
        effectRunner.highestAcceptedTransactionEpoch
    }

    func allocateTransactionEpoch() -> TransactionEpoch {
        kernel.allocateTransactionEpoch()
    }

    func allocateEffectEpoch() -> EffectEpoch {
        kernel.allocateEffectEpoch()
    }

    func allocateTopologyEpoch() -> TopologyEpoch {
        kernel.allocateTopologyEpoch()
    }

    func noteTransactionCommitted(_ epoch: TransactionEpoch) {
        effectRunner.noteTransactionCommitted(epoch)
    }

    func refreshSnapshotState() {
        snapshotPublisher?.refreshSnapshotState()
    }

    @discardableResult
    func perform<Result>(
        _ kind: RuntimeMutationKind,
        source: WMEventSource,
        recordTransaction: Bool,
        transactionEpoch suppliedEpoch: TransactionEpoch? = nil,
        resultNotes: (Result) -> [String] = { _ in [] },
        _ operation: (TransactionEpoch) -> Result
    ) -> Result {
        let epoch = suppliedEpoch ?? activeCommandTransactionEpoch ?? allocateTransactionEpoch()
        precondition(epoch.isValid, "RuntimeMutationCoordinator requires a valid transaction epoch")
        let signpostState = kernel.intakeSignpost.beginInterval(
            "runtime_mutation",
            id: kernel.intakeSignpost.makeSignpostID(),
            "kind=\(kind.rawValue) source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let before = workspaceManager.reconcileSnapshot()
        let result = operation(epoch)
        let changed = before != workspaceManager.reconcileSnapshot()
        if recordTransaction {
            workspaceManager.recordRuntimeTransaction(
                kindForLog: kind.rawValue,
                source: source,
                transactionEpoch: epoch,
                notes: ["changed=\(changed)"] + resultNotes(result)
            )
        }
        noteTransactionCommitted(epoch)
        refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("runtime_mutation", signpostState)
        kernel.intakeLog.debug(
            "runtime_mutation_intake kind=\(kind.rawValue, privacy: .public) source=\(source.rawValue, privacy: .public) txn=\(epoch.value) changed=\(changed) us=\(durationMicros)"
        )
        return result
    }

    @discardableResult
    func performCommandEffect<Result>(
        kindForLog: String,
        source: WMEventSource,
        transactionEpoch: TransactionEpoch,
        resultNotes: (Result) -> [String] = { _ in [] },
        _ operation: () -> Result
    ) -> Result {
        precondition(transactionEpoch.isValid, "typed command effect requires a valid transaction epoch")
        let signpostState = kernel.intakeSignpost.beginInterval(
            "runtime_command_effect",
            id: kernel.intakeSignpost.makeSignpostID(),
            "kind=\(kindForLog) source=\(source.rawValue) txn=\(transactionEpoch.value)"
        )
        let previousCommandTransactionEpoch = activeCommandTransactionEpoch
        activeCommandTransactionEpoch = transactionEpoch
        defer { activeCommandTransactionEpoch = previousCommandTransactionEpoch }
        let startTime = ContinuousClock.now
        let before = workspaceManager.reconcileSnapshot()
        let result = operation()
        let changed = before != workspaceManager.reconcileSnapshot()
        workspaceManager.recordRuntimeTransaction(
            kindForLog: kindForLog,
            source: source,
            transactionEpoch: transactionEpoch,
            notes: ["command_effect=true", "changed=\(changed)"] + resultNotes(result)
        )
        noteTransactionCommitted(transactionEpoch)
        refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("runtime_command_effect", signpostState)
        kernel.intakeLog.debug(
            "runtime_command_effect_intake kind=\(kindForLog, privacy: .public) source=\(source.rawValue, privacy: .public) txn=\(transactionEpoch.value) changed=\(changed) us=\(durationMicros)"
        )
        return result
    }

    func rejectStaleOriginIfNeeded(
        _ originatingTransactionEpoch: TransactionEpoch?,
        kind: String,
        txn: TransactionEpoch,
        source: WMEventSource,
        signpostName: StaticString,
        signpostState: OSSignpostIntervalState,
        startTime: ContinuousClock.Instant
    ) -> Bool? {
        guard let originating = originatingTransactionEpoch else {
            return nil
        }
        guard originating.isValid else {
            refreshSnapshotState()
            let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
            kernel.intakeSignpost.endInterval(signpostName, signpostState)
            kernel.intakeLog.debug(
                "focus_mutation_rejected_invalid_epoch kind=\(kind, privacy: .public) source=\(source.rawValue, privacy: .public) txn=\(txn.value) origin_txn=\(originating.value) us=\(durationMicros)"
            )
            return false
        }
        guard originating < effectRunner.highestAcceptedTransactionEpoch else {
            return nil
        }
        refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval(signpostName, signpostState)
        let highValue = effectRunner.highestAcceptedTransactionEpoch.value
        kernel.intakeLog.debug(
            "focus_mutation_rejected_superseded kind=\(kind, privacy: .public) source=\(source.rawValue, privacy: .public) txn=\(txn.value) origin_txn=\(originating.value) high=\(highValue) us=\(durationMicros)"
        )
        return false
    }
}
