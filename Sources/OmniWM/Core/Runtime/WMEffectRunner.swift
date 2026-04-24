// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OSLog

@MainActor
protocol WMEffectPlatform: AnyObject {
    func hideKeyboardFocusBorder(reason: String)
    func saveWorkspaceViewport(
        for workspaceId: WorkspaceDescriptor.ID,
        transactionEpoch: TransactionEpoch,
        source: WMEventSource
    )
    @discardableResult
    func activateTargetWorkspace(
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID,
        transactionEpoch: TransactionEpoch,
        source: WMEventSource
    ) -> Bool
    func setInteractionMonitor(
        monitorId: Monitor.ID,
        transactionEpoch: TransactionEpoch,
        source: WMEventSource
    )
    func syncMonitorsToNiri()
    func stopScrollAnimation(monitorId: Monitor.ID)
    func applyWorkspaceSessionPatch(
        workspaceId: WorkspaceDescriptor.ID,
        rememberedFocusToken: WindowToken?,
        transactionEpoch: TransactionEpoch,
        source: WMEventSource
    )
    func commitWorkspaceTransition(
        affectedWorkspaceIds: Set<WorkspaceDescriptor.ID>,
        postAction: @escaping @MainActor () -> Void
    )
    func focusWindow(_ token: WindowToken, source: WMEventSource)
    func clearManagedFocusAfterEmptyWorkspaceTransition(
        transactionEpoch: TransactionEpoch,
        source: WMEventSource
    )
    @discardableResult
    func performControllerAction(
        _ action: WMCommand.ControllerActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult
    @discardableResult
    func performFocusAction(
        _ action: WMCommand.FocusActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult
    @discardableResult
    func performWindowMoveAction(
        _ action: WMCommand.WindowMoveActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult
    @discardableResult
    func performLayoutMutationAction(
        _ action: WMCommand.LayoutMutationActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult
    @discardableResult
    func performWorkspaceNavigationAction(
        _ action: WMCommand.WorkspaceNavigationActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult
    @discardableResult
    func performUIAction(
        _ action: WMCommand.UIActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult
}

@MainActor
final class WMEffectRunner {
    struct ApplyOutcome: Equatable {
        var transaction: Transaction
        var appliedEffects: [WMEffect]
        var rejectedEffects: [Rejection]
        var haltReason: HaltReason?
        var externalCommandResult: ExternalCommandResult?
        var invariantViolations: [ReconcileInvariantViolation] {
            transaction.invariantViolations
        }

        init(
            transaction: Transaction,
            appliedEffects: [WMEffect],
            rejectedEffects: [Rejection],
            haltReason: HaltReason?,
            externalCommandResult: ExternalCommandResult?
        ) {
            self.transaction = transaction
            self.appliedEffects = appliedEffects
            self.rejectedEffects = rejectedEffects
            self.haltReason = haltReason
            self.externalCommandResult = externalCommandResult
        }

        struct Rejection: Equatable {
            let effect: WMEffect
            let reason: RejectionReason
        }

        enum RejectionReason: Equatable {
            case transactionSuperseded
        }

        enum HaltReason: Equatable {
            case activateTargetWorkspaceFailed(
                workspaceId: WorkspaceDescriptor.ID,
                monitorId: Monitor.ID
            )
        }
    }

    private let platform: WMEffectPlatform
    private let log = Logger(subsystem: "com.omniwm.core", category: "WMEffectRunner")

    private(set) var highestAcceptedTransactionEpoch: TransactionEpoch = .invalid

    init(platform: WMEffectPlatform) {
        self.platform = platform
    }

    func noteTransactionCommitted(_ epoch: TransactionEpoch) {
        guard epoch.isValid, epoch > highestAcceptedTransactionEpoch else {
            return
        }
        highestAcceptedTransactionEpoch = epoch
    }

    @discardableResult
    func apply(
        _ transaction: Transaction,
        controllerAction: WMCommand.ControllerActionCommand? = nil,
        focusAction: WMCommand.FocusActionCommand? = nil,
        windowMoveAction: WMCommand.WindowMoveActionCommand? = nil,
        layoutMutationAction: WMCommand.LayoutMutationActionCommand? = nil,
        workspaceNavigationAction: WMCommand.WorkspaceNavigationActionCommand? = nil,
        uiAction: WMCommand.UIActionCommand? = nil,
        postApplySnapshot: (() -> ReconcileSnapshot)? = nil
    ) -> ApplyOutcome {
        if transaction.hasNoEffects {
            noteTransactionCommitted(transaction.transactionEpoch)
            let completed = complete(
                transaction,
                postApplySnapshot: postApplySnapshot
            )
            return .init(
                transaction: completed,
                appliedEffects: [],
                rejectedEffects: [],
                haltReason: nil,
                externalCommandResult: nil
            )
        }

        if transaction.transactionEpoch < highestAcceptedTransactionEpoch {
            let txnValue = transaction.transactionEpoch.value
            let highValue = highestAcceptedTransactionEpoch.value
            let effectCount = transaction.effects.count
            log.debug("transaction_superseded txn=\(txnValue) high=\(highValue) effects=\(effectCount)")
            // Validate even when the transaction was superseded so the supersession
            // path mirrors the legacy "always validate" behavior of the
            // pre-TX-COL-01 inline `InvariantChecks.validate` callsite.
            let completed = complete(
                transaction,
                postApplySnapshot: postApplySnapshot
            )
            return .init(
                transaction: completed,
                appliedEffects: [],
                rejectedEffects: transaction.effects.map {
                    .init(effect: $0, reason: .transactionSuperseded)
                },
                haltReason: nil,
                externalCommandResult: nil
            )
        }

        highestAcceptedTransactionEpoch = transaction.transactionEpoch

        var applied: [WMEffect] = []
        var halt: ApplyOutcome.HaltReason?
        var externalCommandResult: ExternalCommandResult?
        applied.reserveCapacity(transaction.effects.count)

        for effect in transaction.effects {
            if let reason = invoke(
                effect,
                transactionEpoch: transaction.transactionEpoch,
                controllerAction: controllerAction,
                focusAction: focusAction,
                windowMoveAction: windowMoveAction,
                layoutMutationAction: layoutMutationAction,
                workspaceNavigationAction: workspaceNavigationAction,
                uiAction: uiAction,
                externalCommandResult: &externalCommandResult
            ) {
                halt = reason
                applied.append(effect)
                break
            }
            applied.append(effect)
        }

        let completed = complete(
            transaction,
            postApplySnapshot: postApplySnapshot
        )
        return .init(
            transaction: completed,
            appliedEffects: applied,
            rejectedEffects: [],
            haltReason: halt,
            externalCommandResult: externalCommandResult
        )
    }

    private func complete(
        _ transaction: Transaction,
        postApplySnapshot: (() -> ReconcileSnapshot)?
    ) -> Transaction {
        let snapshot = postApplySnapshot?() ?? transaction.snapshot
        return transaction.completedWithValidatedSnapshot(snapshot)
    }

    private func invoke(
        _ effect: WMEffect,
        transactionEpoch: TransactionEpoch,
        controllerAction: WMCommand.ControllerActionCommand?,
        focusAction: WMCommand.FocusActionCommand?,
        windowMoveAction: WMCommand.WindowMoveActionCommand?,
        layoutMutationAction: WMCommand.LayoutMutationActionCommand?,
        workspaceNavigationAction: WMCommand.WorkspaceNavigationActionCommand?,
        uiAction: WMCommand.UIActionCommand?,
        externalCommandResult: inout ExternalCommandResult?
    ) -> ApplyOutcome.HaltReason? {
        switch effect {
        case let .hideKeyboardFocusBorder(reason, _):
            platform.hideKeyboardFocusBorder(reason: reason)
            return nil

        case let .saveWorkspaceViewports(workspaceIds, source, _):
            for workspaceId in workspaceIds {
                platform.saveWorkspaceViewport(
                    for: workspaceId,
                    transactionEpoch: transactionEpoch,
                    source: source
                )
            }
            return nil

        case let .activateTargetWorkspace(workspaceId, monitorId, source, _):
            let activated = platform.activateTargetWorkspace(
                workspaceId: workspaceId,
                monitorId: monitorId,
                transactionEpoch: transactionEpoch,
                source: source
            )
            if !activated {
                return .activateTargetWorkspaceFailed(
                    workspaceId: workspaceId,
                    monitorId: monitorId
                )
            }
            return nil

        case let .setInteractionMonitor(monitorId, source, _):
            platform.setInteractionMonitor(
                monitorId: monitorId,
                transactionEpoch: transactionEpoch,
                source: source
            )
            return nil

        case .syncMonitorsToNiri:
            platform.syncMonitorsToNiri()
            return nil

        case let .stopScrollAnimation(monitorId, _):
            platform.stopScrollAnimation(monitorId: monitorId)
            return nil

        case let .applyWorkspaceSessionPatch(workspaceId, rememberedFocusToken, source, _):
            platform.applyWorkspaceSessionPatch(
                workspaceId: workspaceId,
                rememberedFocusToken: rememberedFocusToken,
                transactionEpoch: transactionEpoch,
                source: source
            )
            return nil

        case let .commitWorkspaceTransition(affectedWorkspaceIds, postAction, source, effectEpoch):
            platform.commitWorkspaceTransition(
                affectedWorkspaceIds: affectedWorkspaceIds
            ) { [weak self] in
                self?.runPostCommitAction(
                    postAction,
                    effectEpoch: effectEpoch,
                    transactionEpoch: transactionEpoch,
                    source: source
                )
            }
            return nil

        case .controllerActionDispatch:
            if let controllerAction {
                externalCommandResult = platform.performControllerAction(
                    controllerAction,
                    transactionEpoch: transactionEpoch
                )
            }
            return nil

        case .focusActionDispatch:
            if let focusAction {
                externalCommandResult = platform.performFocusAction(
                    focusAction,
                    transactionEpoch: transactionEpoch
                )
            }
            return nil

        case .windowMoveActionDispatch:
            if let windowMoveAction {
                externalCommandResult = platform.performWindowMoveAction(
                    windowMoveAction,
                    transactionEpoch: transactionEpoch
                )
            }
            return nil

        case .layoutMutationActionDispatch:
            if let layoutMutationAction {
                externalCommandResult = platform.performLayoutMutationAction(
                    layoutMutationAction,
                    transactionEpoch: transactionEpoch
                )
            }
            return nil

        case .workspaceNavigationActionDispatch:
            if let workspaceNavigationAction {
                externalCommandResult = platform.performWorkspaceNavigationAction(
                    workspaceNavigationAction,
                    transactionEpoch: transactionEpoch
                )
            }
            return nil

        case .uiActionDispatch:
            if let uiAction {
                externalCommandResult = platform.performUIAction(
                    uiAction,
                    transactionEpoch: transactionEpoch
                )
            }
            return nil
        }
    }

    /// Number of post-commit actions dropped because their transaction
    /// epoch was superseded between scheduling and the run. Exposed for
    /// debug instrumentation; tests assert this counter doesn't grow on
    /// the happy path.
    private(set) var supersededPostCommitDropCount: Int = 0

    private func runPostCommitAction(
        _ action: WMEffect.PostWorkspaceTransitionAction,
        effectEpoch: EffectEpoch,
        transactionEpoch: TransactionEpoch,
        source: WMEventSource
    ) {
        guard transactionEpoch >= highestAcceptedTransactionEpoch else {
            let fxValue = effectEpoch.value
            let txnValue = transactionEpoch.value
            let highValue = highestAcceptedTransactionEpoch.value
            supersededPostCommitDropCount += 1
            // Promote from .debug to .notice: a dropped post-commit means
            // the planner-intended focus/clear never ran. Combined with the
            // FocusReducer epoch gate, the WM can land in an inconsistent
            // (desired ≠ observed) state with no recovery, so the drop
            // should be observable in normal-level logs without DEBUG=1.
            log.notice("post_commit_superseded fx=\(fxValue) txn=\(txnValue) high=\(highValue) drops=\(self.supersededPostCommitDropCount)")
            return
        }

        switch action {
        case .none:
            return

        case let .focusWindow(token):
            platform.focusWindow(token, source: source)

        case .clearManagedFocusAfterEmptyWorkspaceTransition:
            platform.clearManagedFocusAfterEmptyWorkspaceTransition(
                transactionEpoch: transactionEpoch,
                source: source
            )
        }
    }
}
