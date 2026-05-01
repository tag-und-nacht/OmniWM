// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OSLog

/// Per-domain runtime for focus operations. Mirrors `FocusStateLedger`
/// (which owns the storage on the manager side, per ExecPlan 01) and
/// provides the epoch-stamped read/reduce/mutate surface that runtime command
/// and orchestration paths call into.
///
/// Design contract (kept narrow on purpose to avoid drift):
///   - The kernel is the single source of transaction epochs.
///   - The effect runner is the single ratchet for transaction ordering.
///   - WorkspaceManager remains the storage (via `FocusStateLedger`) until
///     [ExecPlan 04](../../docs/exec-plans/04-workspace-graph-ownership-inversion.md)
///     inverts ownership; this type is its read surface today.
@MainActor
final class FocusRuntime {
    private let kernel: RuntimeKernel
    private let effectRunner: WMEffectRunner
    private let mutationCoordinator: RuntimeMutationCoordinator
    private let controllerOperations: RuntimeControllerOperations
    private unowned let workspaceManager: WorkspaceManager

    init(
        kernel: RuntimeKernel,
        effectRunner: WMEffectRunner,
        mutationCoordinator: RuntimeMutationCoordinator,
        controllerOperations: RuntimeControllerOperations,
        workspaceManager: WorkspaceManager
    ) {
        self.kernel = kernel
        self.effectRunner = effectRunner
        self.mutationCoordinator = mutationCoordinator
        self.controllerOperations = controllerOperations
        self.workspaceManager = workspaceManager
    }

    // MARK: Read surface

    /// The currently-observed focused window token, or `nil` if focus is
    /// unmanaged or unobserved.
    var observedToken: WindowToken? {
        workspaceManager.focusedToken
    }

    /// The logical id under the currently-observed focus, or `nil` if the
    /// observed token doesn't map to a tracked logical window.
    var focusedLogicalId: LogicalWindowId? {
        workspaceManager.focusedLogicalId
    }

    /// True iff a managed activation request is in flight.
    var hasPendingActivation: Bool {
        workspaceManager.storedFocusStateSnapshot.hasPendingActivation
    }

    /// Snapshot of the full focus state.
    var stateSnapshot: FocusState {
        workspaceManager.storedFocusStateSnapshot
    }

    @discardableResult
    func perform(
        _ action: WMCommand.FocusActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        mutationCoordinator.performCommandEffect(
            kindForLog: "focus_action:\(action.kindForLog)",
            source: action.source,
            transactionEpoch: transactionEpoch,
            resultNotes: { result in ["external_result=\(String(describing: result))"] }
        ) {
            controllerOperations.performFocusAction(action)
        }
    }

    // MARK: Reduce surface

    /// Apply a `FocusReducer.Event` to the manager-side ledger. The kernel
    /// allocates a transaction epoch and the effect runner ratchets, so any
    /// later supersession comparison sees this commit. Returns `true` if
    /// the reducer reported a state change.
    @discardableResult
    func reduce(_ event: FocusReducer.Event) -> Bool {
        applyFocusReducerEvent(
            kind: .focusReducer,
            source: .focusPolicy
        ) { _ in
            event
        }
    }

    /// Apply a `FocusReducer.Event` and return both the change flag and the
    /// reducer's recommended downstream action (e.g., `requestFocus`,
    /// `clearBorder`). Same epoch stamping as `reduce(_:)`.
    @discardableResult
    func reduceReturningAction(
        _ event: FocusReducer.Event
    ) -> (changed: Bool, action: FocusReducer.RecommendedAction?) {
        applyFocusReducerEventReturningAction(
            kind: .focusReducer,
            source: .focusPolicy
        ) { _ in
            event
        }
    }

    @discardableResult
    func reduceScratchpadHide(
        hiddenLogicalId: LogicalWindowId,
        wasFocused: Bool,
        recoveryCandidate: LogicalWindowId?,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID? = nil
    ) -> FocusReducer.RecommendedAction? {
        let (_, action) = applyFocusReducerEventReturningAction(
            kind: .focusReducer,
            source: .focusPolicy
        ) { txn in
            .scratchpadHideStarted(
                hiddenLogicalId: hiddenLogicalId,
                wasFocused: wasFocused,
                recoveryCandidate: recoveryCandidate,
                workspaceId: workspaceId,
                txn: txn
            )
        }
        if case let .resolveWorkspaceLastFocused(workspaceId, _) = action {
            return .resolveWorkspaceLastFocused(workspaceId: workspaceId, monitorId: monitorId)
        }
        return action
    }

    // MARK: Managed-focus mutations (migrated from WMRuntime — ExecPlan 02 surface migration)

    @discardableResult
    func confirmManagedFocus(
        _ token: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        onMonitor monitorId: Monitor.ID? = nil,
        appFullscreen: Bool,
        activateWorkspaceOnMonitor: Bool,
        originatingTransactionEpoch: TransactionEpoch,
        source: WMEventSource = .ax
    ) -> Bool {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "confirm_managed_focus",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        if let rejected = mutationCoordinator.rejectInvalidOriginIfNeeded(
            originatingTransactionEpoch,
            kind: "confirm_managed_focus",
            txn: epoch,
            source: source,
            signpostName: "confirm_managed_focus",
            signpostState: signpostState,
            startTime: startTime
        ) {
            return rejected
        }
        if let reason = managedFocusConfirmationRejectionReason(
            token: token,
            workspaceId: workspaceId,
            monitorId: monitorId,
            originatingTransactionEpoch: originatingTransactionEpoch
        ) {
            return rejectScopedFocusMutation(
                kind: "confirm_managed_focus",
                reason: reason,
                txn: epoch,
                originatingTransactionEpoch: originatingTransactionEpoch,
                source: source,
                signpostName: "confirm_managed_focus",
                signpostState: signpostState,
                startTime: startTime
            )
        }
        let changed = workspaceManager.confirmManagedFocus(
            token,
            in: workspaceId,
            onMonitor: monitorId,
            appFullscreen: appFullscreen,
            activateWorkspaceOnMonitor: activateWorkspaceOnMonitor,
            originatingTransactionEpoch: originatingTransactionEpoch,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("confirm_managed_focus", signpostState)
        kernel.intakeLog.debug(
            "focus_confirm_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) origin_txn=\(originatingTransactionEpoch.value) changed=\(changed) us=\(durationMicros)"
        )
        return changed
    }

    @discardableResult
    func setManagedFocus(
        _ token: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        onMonitor monitorId: Monitor.ID? = nil,
        originatingTransactionEpoch: TransactionEpoch,
        source: WMEventSource = .ax
    ) -> Bool {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "set_managed_focus",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        if let rejected = mutationCoordinator.rejectInvalidOriginIfNeeded(
            originatingTransactionEpoch,
            kind: "set_managed_focus",
            txn: epoch,
            source: source,
            signpostName: "set_managed_focus",
            signpostState: signpostState,
            startTime: startTime
        ) {
            return rejected
        }
        if let reason = managedFocusConfirmationRejectionReason(
            token: token,
            workspaceId: workspaceId,
            monitorId: monitorId,
            originatingTransactionEpoch: originatingTransactionEpoch
        ) {
            return rejectScopedFocusMutation(
                kind: "set_managed_focus",
                reason: reason,
                txn: epoch,
                originatingTransactionEpoch: originatingTransactionEpoch,
                source: source,
                signpostName: "set_managed_focus",
                signpostState: signpostState,
                startTime: startTime
            )
        }
        let changed = workspaceManager.setManagedFocus(
            token,
            in: workspaceId,
            onMonitor: monitorId,
            originatingTransactionEpoch: originatingTransactionEpoch,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("set_managed_focus", signpostState)
        kernel.intakeLog.debug(
            "focus_set_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) origin_txn=\(originatingTransactionEpoch.value) changed=\(changed) us=\(durationMicros)"
        )
        return changed
    }

    @discardableResult
    func beginManagedFocusRequest(
        _ token: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        onMonitor monitorId: Monitor.ID? = nil,
        source: WMEventSource = .ax
    ) -> Bool {
        beginManagedFocusRequestTransaction(
            token,
            in: workspaceId,
            onMonitor: monitorId,
            source: source
        ).changed
    }

    func beginManagedFocusRequestTransaction(
        _ token: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        onMonitor monitorId: Monitor.ID? = nil,
        source: WMEventSource = .ax
    ) -> WMRuntime.ManagedFocusRequestBeginResult {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "begin_managed_focus_request",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let changed = workspaceManager.beginManagedFocusRequest(
            token,
            in: workspaceId,
            onMonitor: monitorId,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("begin_managed_focus_request", signpostState)
        kernel.intakeLog.debug(
            "focus_request_begin_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) changed=\(changed) us=\(durationMicros)"
        )
        return .init(changed: changed, transactionEpoch: epoch)
    }

    @discardableResult
    func cancelManagedFocusRequest(
        matching token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        originatingTransactionEpoch: TransactionEpoch,
        source: WMEventSource = .ax
    ) -> Bool {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "cancel_managed_focus_request",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        if let rejected = mutationCoordinator.rejectInvalidOriginIfNeeded(
            originatingTransactionEpoch,
            kind: "cancel_managed_focus_request",
            txn: epoch,
            source: source,
            signpostName: "cancel_managed_focus_request",
            signpostState: signpostState,
            startTime: startTime
        ) {
            return rejected
        }
        if let reason = managedFocusCancellationRejectionReason(
            matching: token,
            workspaceId: workspaceId,
            originatingTransactionEpoch: originatingTransactionEpoch
        ) {
            return rejectScopedFocusMutation(
                kind: "cancel_managed_focus_request",
                reason: reason,
                txn: epoch,
                originatingTransactionEpoch: originatingTransactionEpoch,
                source: source,
                signpostName: "cancel_managed_focus_request",
                signpostState: signpostState,
                startTime: startTime
            )
        }
        let changed = workspaceManager.cancelManagedFocusRequest(
            matching: token,
            workspaceId: workspaceId,
            originatingTransactionEpoch: originatingTransactionEpoch,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("cancel_managed_focus_request", signpostState)
        kernel.intakeLog.debug(
            "focus_cancel_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) origin_txn=\(originatingTransactionEpoch.value) changed=\(changed) us=\(durationMicros)"
        )
        return changed
    }

    @discardableResult
    func observeExternalManagedFocus(
        _ token: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        onMonitor monitorId: Monitor.ID? = nil,
        appFullscreen: Bool,
        activateWorkspaceOnMonitor: Bool,
        source: WMEventSource = .ax
    ) -> Bool {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "observe_external_managed_focus",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let changed = workspaceManager.confirmManagedFocus(
            token,
            in: workspaceId,
            onMonitor: monitorId,
            appFullscreen: appFullscreen,
            activateWorkspaceOnMonitor: activateWorkspaceOnMonitor,
            originatingTransactionEpoch: epoch,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("observe_external_managed_focus", signpostState)
        kernel.intakeLog.debug(
            "focus_observe_intake kind=confirm source=\(source.rawValue, privacy: .public) txn=\(epoch.value) changed=\(changed) us=\(durationMicros)"
        )
        return changed
    }

    @discardableResult
    func observeExternalManagedFocusSet(
        _ token: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        onMonitor monitorId: Monitor.ID? = nil,
        source: WMEventSource = .ax
    ) -> Bool {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "observe_external_managed_focus_set",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let changed = workspaceManager.setManagedFocus(
            token,
            in: workspaceId,
            onMonitor: monitorId,
            originatingTransactionEpoch: epoch,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("observe_external_managed_focus_set", signpostState)
        kernel.intakeLog.debug(
            "focus_observe_intake kind=set source=\(source.rawValue, privacy: .public) txn=\(epoch.value) changed=\(changed) us=\(durationMicros)"
        )
        return changed
    }

    @discardableResult
    func observeExternalManagedFocusCancellation(
        matching token: WindowToken? = nil,
        workspaceId: WorkspaceDescriptor.ID? = nil,
        source: WMEventSource = .ax
    ) -> Bool {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "observe_external_managed_focus_cancellation",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let changed = workspaceManager.cancelManagedFocusRequest(
            matching: token,
            workspaceId: workspaceId,
            originatingTransactionEpoch: epoch,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("observe_external_managed_focus_cancellation", signpostState)
        kernel.intakeLog.debug(
            "focus_observe_intake kind=cancel source=\(source.rawValue, privacy: .public) txn=\(epoch.value) changed=\(changed) us=\(durationMicros)"
        )
        return changed
    }

    @discardableResult
    private func clearManagedFocusAfterEmptyWorkspaceTransition(
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .clearManagedFocusAfterEmptyWorkspaceTransition,
            source: source,
            recordTransaction: false
        ) { epoch in
            controllerOperations.cancelManagedFocusRequestAndDiscardPending()
            controllerOperations.clearKeyboardFocusTarget()
            let changed = workspaceManager.enterNonManagedFocus(
                appFullscreen: false,
                transactionEpoch: epoch,
                eventSource: source
            )
            controllerOperations.hideKeyboardFocusBorder(
                source: .workspaceActivation,
                reason: "cleared focus after empty workspace transition"
            )
            return changed
        }
    }

    @discardableResult
    func clearManagedFocusAfterEmptyWorkspaceTransition(
        originatingTransactionEpoch: TransactionEpoch,
        source: WMEventSource = .command
    ) -> Bool {
        let signpostState = kernel.intakeSignpost.beginInterval(
            "clear_managed_focus_after_empty_workspace_transition",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) origin_txn=\(originatingTransactionEpoch.value)"
        )
        let startTime = ContinuousClock.now
        guard originatingTransactionEpoch.isValid else {
            kernel.intakeSignpost.endInterval(
                "clear_managed_focus_after_empty_workspace_transition",
                signpostState
            )
            kernel.intakeLog.debug(
                "clear_managed_focus_after_empty_workspace_transition_rejected_invalid_epoch source=\(source.rawValue, privacy: .public) origin_txn=\(originatingTransactionEpoch.value)"
            )
            return false
        }

        let before = workspaceManager.reconcileSnapshot()
        controllerOperations.cancelManagedFocusRequestAndDiscardPending()
        controllerOperations.clearKeyboardFocusTarget()
        let changed = workspaceManager.enterNonManagedFocus(
            appFullscreen: false,
            transactionEpoch: originatingTransactionEpoch,
            eventSource: source
        )
        controllerOperations.hideKeyboardFocusBorder(
            source: .workspaceActivation,
            reason: "cleared focus after empty workspace transition"
        )
        let snapshotChanged = before != workspaceManager.reconcileSnapshot()
        if !changed && !snapshotChanged {
            workspaceManager.recordRuntimeTransaction(
                kindForLog: RuntimeMutationKind.clearManagedFocusAfterEmptyWorkspaceTransition.rawValue,
                source: source,
                transactionEpoch: originatingTransactionEpoch,
                notes: ["changed=false"]
            )
        }
        effectRunner.noteTransactionCommitted(originatingTransactionEpoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval(
            "clear_managed_focus_after_empty_workspace_transition",
            signpostState
        )
        kernel.intakeLog.debug(
            "clear_managed_focus_after_empty_workspace_transition_intake source=\(source.rawValue, privacy: .public) origin_txn=\(originatingTransactionEpoch.value) changed=\(changed || snapshotChanged) us=\(durationMicros)"
        )
        return changed || snapshotChanged
    }

    @discardableResult
    func enterNonManagedFocus(
        appFullscreen: Bool,
        preserveFocusedToken: Bool = false,
        source: WMEventSource = .ax
    ) -> Bool {
        mutationCoordinator.perform(
            .enterNonManagedFocus,
            source: source,
            recordTransaction: false
        ) { epoch in
            workspaceManager.enterNonManagedFocus(
                appFullscreen: appFullscreen,
                preserveFocusedToken: preserveFocusedToken,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func applyOrchestrationFocusState(
        _ focusSnapshot: FocusOrchestrationSnapshot,
        source: WMEventSource = .focusPolicy
    ) -> Bool {
        mutationCoordinator.perform(
            .applyOrchestrationFocusState,
            source: source,
            recordTransaction: true
        ) { epoch in
            workspaceManager.applyOrchestrationFocusState(
                focusSnapshot,
                transactionEpoch: epoch
            )
        }
    }

    func recordActivationFailure(
        reason: FocusState.FocusFailureReason,
        requestId: UInt64? = nil,
        token: WindowToken? = nil,
        source: WMEventSource = .ax
    ) {
        var txn: TransactionEpoch = .invalid
        applyFocusReducerEvent(
            kind: .focusActivationFailure,
            source: source
        ) { epoch in
            txn = epoch
            return .activationFailed(reason: reason, attemptedAt: epoch)
        }
        kernel.intakeLog.debug(
            """
            focus_activation_failure_intake \
            reason=\(String(describing: reason), privacy: .public) \
            request=\(requestId ?? 0, privacy: .public) \
            pid=\(token?.pid ?? 0, privacy: .public) \
            wid=\(token?.windowId ?? 0, privacy: .public) \
            source=\(source.rawValue, privacy: .public) \
            txn=\(txn.value)
            """
        )
    }

    func recordFocusedManagedWindowRemoved(_ removedLogicalId: LogicalWindowId) {
        applyFocusReducerEvent(
            kind: .focusManagedWindowRemoved,
            source: .ax
        ) { txn in
            .focusedManagedWindowRemoved(removedLogicalId: removedLogicalId, txn: txn)
        }
    }

    func recordFocusObservationSettled(_ observedToken: WindowToken) {
        applyFocusReducerEvent(
            kind: .focusObservationSettled,
            source: .ax
        ) { txn in
            .observationSettled(observedToken: observedToken, txn: txn)
        }
    }

    func scopedFocusEventRejectionReason(for event: WMEvent) -> String? {
        switch event {
        case let .managedFocusConfirmed(
            token,
            workspaceId,
            monitorId,
            _,
            _,
            originatingTransactionEpoch
        ):
            managedFocusConfirmationRejectionReason(
                token: token,
                workspaceId: workspaceId,
                monitorId: monitorId,
                originatingTransactionEpoch: originatingTransactionEpoch
            )

        case let .managedFocusCancelled(token, workspaceId, _, originatingTransactionEpoch):
            managedFocusCancellationRejectionReason(
                matching: token,
                workspaceId: workspaceId,
                originatingTransactionEpoch: originatingTransactionEpoch
            )

        case .windowAdmitted,
             .windowRekeyed,
             .windowRemoved,
             .workspaceAssigned,
             .windowModeChanged,
             .floatingGeometryUpdated,
             .hiddenStateChanged,
             .nativeFullscreenTransition,
             .managedReplacementMetadataChanged,
             .topologyChanged,
             .activeSpaceChanged,
             .focusLeaseChanged,
             .managedFocusRequested,
             .nonManagedFocusChanged,
             .systemSleep,
             .systemWake,
             .commandIntent:
            nil
        }
    }

    private func managedFocusConfirmationRejectionReason(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?,
        originatingTransactionEpoch: TransactionEpoch
    ) -> String? {
        guard let pendingOrigin = pendingActivationOriginEpoch() else {
            return "no_pending_activation"
        }
        guard pendingOrigin == originatingTransactionEpoch else {
            return "superseded_focus_request"
        }
        guard workspaceManager.pendingFocusedToken == token else {
            return "unmatched_focus_token"
        }
        guard workspaceManager.pendingFocusedWorkspaceId == workspaceId else {
            return "unmatched_focus_workspace"
        }
        if let pendingMonitorId = workspaceManager.pendingFocusedMonitorId,
           let monitorId,
           pendingMonitorId != monitorId
        {
            return "unmatched_focus_monitor"
        }
        guard let logicalId = workspaceManager.logicalWindowRegistry
            .lookup(token: token).liveLogicalId
        else {
            return "unmatched_focus_logical_id"
        }
        guard case let .logical(desiredLogicalId, desiredWorkspaceId) =
                workspaceManager.storedFocusStateSnapshot.desired,
              desiredLogicalId == logicalId,
              desiredWorkspaceId == workspaceId
        else {
            return "unmatched_focus_desired_target"
        }
        return nil
    }

    private func managedFocusCancellationRejectionReason(
        matching token: WindowToken?,
        workspaceId: WorkspaceDescriptor.ID?,
        originatingTransactionEpoch: TransactionEpoch
    ) -> String? {
        guard let pendingOrigin = pendingActivationOriginEpoch() else {
            return "no_pending_activation"
        }
        guard pendingOrigin == originatingTransactionEpoch else {
            return "superseded_focus_request"
        }
        guard let token else {
            return "missing_focus_token"
        }
        guard let workspaceId else {
            return "missing_focus_workspace"
        }
        if workspaceManager.pendingFocusedToken != token {
            return "unmatched_focus_token"
        }
        if workspaceManager.pendingFocusedWorkspaceId != workspaceId {
            return "unmatched_focus_workspace"
        }
        if let logicalId = workspaceManager.logicalWindowRegistry.lookup(token: token).liveLogicalId,
           case let .logical(desiredLogicalId, desiredWorkspaceId) =
                workspaceManager.storedFocusStateSnapshot.desired
        {
            if desiredLogicalId != logicalId {
                return "unmatched_focus_logical_id"
            }
            if desiredWorkspaceId != workspaceId {
                return "unmatched_focus_desired_target"
            }
        }
        return nil
    }

    private func pendingActivationOriginEpoch() -> TransactionEpoch? {
        guard case let .pending(_, origin) = workspaceManager.storedFocusStateSnapshot.activation
        else {
            return nil
        }
        return origin
    }

    private func rejectScopedFocusMutation(
        kind: String,
        reason: String,
        txn: TransactionEpoch,
        originatingTransactionEpoch: TransactionEpoch,
        source: WMEventSource,
        signpostName: StaticString,
        signpostState: OSSignpostIntervalState,
        startTime: ContinuousClock.Instant
    ) -> Bool {
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval(signpostName, signpostState)
        kernel.intakeLog.debug(
            "focus_mutation_rejected kind=\(kind, privacy: .public) reason=\(reason, privacy: .public) source=\(source.rawValue, privacy: .public) txn=\(txn.value) origin_txn=\(originatingTransactionEpoch.value) us=\(durationMicros)"
        )
        return false
    }

    @discardableResult
    private func applyFocusReducerEvent(
        kind: RuntimeMutationKind,
        source: WMEventSource,
        makeEvent: (TransactionEpoch) -> FocusReducer.Event
    ) -> Bool {
        mutationCoordinator.perform(
            kind,
            source: source,
            recordTransaction: true
        ) { epoch in
            workspaceManager.applyFocusReducerEvent(makeEvent(epoch))
        }
    }

    @discardableResult
    private func applyFocusReducerEventReturningAction(
        kind: RuntimeMutationKind,
        source: WMEventSource,
        makeEvent: (TransactionEpoch) -> FocusReducer.Event
    ) -> (changed: Bool, action: FocusReducer.RecommendedAction?) {
        mutationCoordinator.perform(
            kind,
            source: source,
            recordTransaction: true,
            resultNotes: { result in
                if let action = result.action {
                    return ["recommended_action=\(String(describing: action))"]
                }
                return []
            }
        ) { epoch in
            workspaceManager.applyFocusReducerEventReturningAction(makeEvent(epoch))
        }
    }
}
