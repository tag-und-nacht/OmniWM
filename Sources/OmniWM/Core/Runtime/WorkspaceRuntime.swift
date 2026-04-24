// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

/// Per-domain runtime for workspace structure (the workspace store, monitor
/// assignments, session state). Composes with `MonitorRuntime` because the
/// two are tightly coupled (a monitor change invalidates workspace
/// projection caches).
///
/// Owns workspace/session mutations that must be stamped by the runtime
/// transaction boundary.
@MainActor
final class WorkspaceRuntime {
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

    /// The currently-active workspace on the given monitor, or `nil` if
    /// the monitor has no active workspace assignment.
    func activeWorkspace(on monitorId: Monitor.ID) -> WorkspaceDescriptor? {
        workspaceManager.activeWorkspace(on: monitorId)
    }

    /// The interaction monitor identifier (the "where focus is happening
    /// for keyboard / mouse routing").
    var interactionMonitorId: Monitor.ID? {
        workspaceManager.interactionMonitorId
    }

    /// Snapshot of the workspace session state — sub-store contents from
    /// `WorkspaceSessionState` plus per-monitor session info.
    var sessionStateSnapshot: WorkspaceSessionState {
        workspaceManager.sessionStateSnapshot()
    }

    @discardableResult
    func perform(
        _ action: WMCommand.WorkspaceNavigationActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        mutationCoordinator.performCommandEffect(
            kindForLog: "workspace_navigation_action:\(action.kindForLog)",
            source: action.source,
            transactionEpoch: transactionEpoch,
            resultNotes: { result in ["external_result=\(String(describing: result))"] }
        ) {
            controllerOperations.performWorkspaceNavigationAction(action)
        }
    }

    @discardableResult
    func perform(
        _ action: WMCommand.LayoutMutationActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        mutationCoordinator.performCommandEffect(
            kindForLog: "layout_mutation_action:\(action.kindForLog)",
            source: action.source,
            transactionEpoch: transactionEpoch,
            resultNotes: { result in ["external_result=\(String(describing: result))"] }
        ) {
            controllerOperations.performLayoutMutationAction(action)
        }
    }

    // MARK: Workspace mutations (migrated from WMRuntime — ExecPlan 02 surface migration)

    @discardableResult
    func applyWorkspaceSettings(source: WMEventSource = .config) -> Bool {
        mutationCoordinator.perform(
            .applyWorkspaceSettings,
            source: source,
            recordTransaction: true
        ) { _ in
            let before = workspaceManager.reconcileSnapshot()
            workspaceManager.applySettings()
            return before != workspaceManager.reconcileSnapshot()
        }
    }

    @discardableResult
    func materializeWorkspace(
        named rawWorkspaceID: String,
        source: WMEventSource = .command
    ) -> WorkspaceDescriptor.ID? {
        if let existing = workspaceManager.workspaceId(
            for: rawWorkspaceID,
            createIfMissing: false
        ) {
            return existing
        }

        return mutationCoordinator.perform(
            .workspaceMaterialized,
            source: source,
            recordTransaction: true,
            resultNotes: { workspaceId in
                ["materialized=\(workspaceId != nil)"]
            }
        ) { _ in
            workspaceManager.workspaceId(
                for: rawWorkspaceID,
                createIfMissing: true
            )
        }
    }

    @discardableResult
    func applySessionPatch(
        _ patch: WorkspaceSessionPatch,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .applySessionPatch,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.applySessionPatch(patch)
        }
    }

    @discardableResult
    func submit(_ confirmation: WMEffectConfirmation) -> Bool {
        let originatingEpoch = confirmation.originatingTransactionEpoch
        guard confirmationEpochIsCurrent(
            originatingEpoch,
            kindForLog: confirmation.kindForLog,
            source: confirmation.source
        ) else {
            return false
        }

        let reducerEvent = WorkspaceSessionReducer.Event(confirmation: confirmation)
        let preReduction = reducerEvent.map { _ in workspaceManager.sessionStateSnapshot() }
        let predictedReduction = preReduction.flatMap { snapshot in
            reducerEvent.map {
                WorkspaceSessionReducer.reduce(state: snapshot, event: $0)
            }
        }

        let changed: Bool
        switch confirmation {
        case let .targetWorkspaceActivated(workspaceId, monitorId, source, _):
            changed = mutationCoordinator.perform(
                .targetWorkspaceActivated,
                source: source,
                recordTransaction: true,
                transactionEpoch: originatingEpoch
            ) { _ in
                workspaceManager.setActiveWorkspace(workspaceId, on: monitorId)
            }

        case let .interactionMonitorSet(monitorId, source, _):
            changed = mutationCoordinator.perform(
                .interactionMonitorSet,
                source: source,
                recordTransaction: true,
                transactionEpoch: originatingEpoch
            ) { _ in
                workspaceManager.setInteractionMonitor(monitorId)
            }

        case let .workspaceSessionPatched(workspaceId, rememberedFocusToken, source, _):
            changed = mutationCoordinator.perform(
                .workspaceSessionPatched,
                source: source,
                recordTransaction: true,
                transactionEpoch: originatingEpoch
            ) { _ in
                workspaceManager.applySessionPatch(
                    .init(
                        workspaceId: workspaceId,
                        viewportState: nil,
                        rememberedFocusToken: rememberedFocusToken
                    )
                )
            }

        case .axFrameWriteOutcome, .observedFrame:
            preconditionFailure("WorkspaceRuntime received frame confirmation \(confirmation.kindForLog)")
        }

        #if DEBUG
        switch reducerEvent {
        case .some(.targetWorkspaceActivated), .some(.interactionMonitorSet):
            guard let preReduction, let predictedReduction else { break }
            let postReduction = workspaceManager.sessionStateSnapshot()
            let actualSessionChanged = WorkspaceSessionReducer.projectedSessionFieldsChanged(
                from: preReduction,
                to: postReduction
            )
            if !WorkspaceSessionReducer.projectedSessionFieldsEqual(
                predictedReduction.nextState,
                postReduction
            ) {
                kernel.intakeLog.warning(
                    "session_reducer_drift kind=\(confirmation.kindForLog, privacy: .public) predicted=\(predictedReduction.didChange) actual=\(actualSessionChanged) apply_result=\(changed)"
                )
                assertionFailure("WorkspaceSessionReducer disagreed with WorkspaceManager apply")
            }
        case .some(.workspaceSessionPatched), .none:
            break
        }
        #endif

        return changed
    }

    @discardableResult
    func withNiriViewportState<Result>(
        for workspaceId: WorkspaceDescriptor.ID,
        source: WMEventSource = .command,
        _ mutate: (inout ViewportState) -> Result
    ) -> Result {
        mutationCoordinator.perform(
            .niriViewportStateUpdated,
            source: source,
            recordTransaction: true,
            resultNotes: { _ in ["workspace=\(workspaceId.uuidString)"] }
        ) { _ in
            var state = workspaceManager.niriViewportState(for: workspaceId)
            let result = mutate(&state)
            workspaceManager.updateNiriViewportState(state, for: workspaceId)
            return result
        }
    }

    @discardableResult
    func setActiveWorkspace(
        _ workspaceId: WorkspaceDescriptor.ID,
        on monitorId: Monitor.ID,
        updateInteractionMonitor: Bool = true,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .activeWorkspaceSet,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.setActiveWorkspace(
                workspaceId,
                on: monitorId,
                updateInteractionMonitor: updateInteractionMonitor
            )
        }
    }

    @discardableResult
    func setInteractionMonitor(
        _ monitorId: Monitor.ID?,
        preservePrevious: Bool = true,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .interactionMonitorSet,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.setInteractionMonitor(
                monitorId,
                preservePrevious: preservePrevious
            )
        }
    }

    @discardableResult
    func commitWorkspaceSelection(
        nodeId: NodeId?,
        focusedToken: WindowToken?,
        in workspaceId: WorkspaceDescriptor.ID,
        onMonitor monitorId: Monitor.ID? = nil,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .commitWorkspaceSelection,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.commitWorkspaceSelection(
                nodeId: nodeId,
                focusedToken: focusedToken,
                in: workspaceId,
                onMonitor: monitorId
            )
        }
    }

    @discardableResult
    func applySessionTransfer(
        _ transfer: WorkspaceSessionTransfer,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .applySessionTransfer,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.applySessionTransfer(transfer)
        }
    }

    @discardableResult
    func resolveAndSetWorkspaceFocusToken(
        in workspaceId: WorkspaceDescriptor.ID,
        onMonitor monitorId: Monitor.ID? = nil,
        source: WMEventSource = .command
    ) -> WindowToken? {
        _ = monitorId
        return mutationCoordinator.perform(
            .resolveWorkspaceFocus,
            source: source,
            recordTransaction: true,
            resultNotes: { token in ["resolved=\(token != nil)"] }
        ) { epoch in
            guard let plan = workspaceManager.resolveWorkspaceFocusPlan(
                in: workspaceId
            ) else {
                return nil
            }

            if let token = plan.resolvedFocusToken {
                _ = workspaceManager.rememberFocus(token, in: workspaceId)
                return token
            }

            _ = workspaceManager.applyResolvedWorkspaceFocusClearMirror(
                in: workspaceId,
                scope: plan.focusClearAction,
                transactionEpoch: epoch,
                eventSource: source
            )
            return nil
        }
    }

    func setHiddenState(
        _ state: WindowModel.HiddenState?,
        for token: WindowToken,
        source: WMEventSource = .command
    ) {
        mutationCoordinator.perform(
            .hiddenStateChanged,
            source: source,
            recordTransaction: false
        ) { epoch in
            workspaceManager.setHiddenState(
                state,
                for: token,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func setManagedRestoreSnapshot(
        _ snapshot: ManagedWindowRestoreSnapshot,
        for token: WindowToken,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .managedRestoreSnapshotSet,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.setManagedRestoreSnapshot(snapshot, for: token)
        }
    }

    @discardableResult
    func clearManagedRestoreSnapshot(
        for token: WindowToken,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .clearManagedRestoreSnapshot,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.clearManagedRestoreSnapshot(for: token)
        }
    }

    @discardableResult
    func setManagedReplacementMetadata(
        _ metadata: ManagedReplacementMetadata?,
        for token: WindowToken,
        source: WMEventSource = .ax
    ) -> Bool {
        mutationCoordinator.perform(
            .managedReplacementMetadataChanged,
            source: source,
            recordTransaction: false
        ) { epoch in
            workspaceManager.setManagedReplacementMetadata(
                metadata,
                for: token,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func updateManagedReplacementFrame(
        _ frame: CGRect,
        for token: WindowToken,
        source: WMEventSource = .ax
    ) -> Bool {
        mutationCoordinator.perform(
            .managedReplacementMetadataChanged,
            source: source,
            recordTransaction: false
        ) { epoch in
            workspaceManager.updateManagedReplacementFrame(
                frame,
                for: token,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func updateManagedReplacementTitle(
        _ title: String,
        for token: WindowToken,
        source: WMEventSource = .ax
    ) -> Bool {
        mutationCoordinator.perform(
            .managedReplacementMetadataChanged,
            source: source,
            recordTransaction: false
        ) { epoch in
            workspaceManager.updateManagedReplacementTitle(
                title,
                for: token,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    func setWorkspace(
        for token: WindowToken,
        to workspaceId: WorkspaceDescriptor.ID,
        source: WMEventSource = .command
    ) {
        mutationCoordinator.perform(
            .setWorkspace,
            source: source,
            recordTransaction: false
        ) { epoch in
            workspaceManager.setWorkspace(
                for: token,
                to: workspaceId,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func swapTiledWindowOrder(
        _ lhs: WindowToken,
        _ rhs: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .tiledWindowOrderSwap,
            source: source,
            recordTransaction: true,
            resultNotes: { swapped in ["swapped=\(swapped)"] }
        ) { _ in
            workspaceManager.swapTiledWindowOrder(lhs, rhs, in: workspaceId)
        }
    }

    @discardableResult
    func focusWorkspace(
        named name: String,
        source: WMEventSource = .command
    ) -> (workspace: WorkspaceDescriptor, monitor: Monitor)? {
        mutationCoordinator.perform(
            .activeWorkspaceSet,
            source: source,
            recordTransaction: true,
            resultNotes: { result in ["success=\(result != nil)"] }
        ) { _ in
            guard let workspaceId = workspaceManager.workspaceId(for: name, createIfMissing: false),
                  let targetMonitor = workspaceManager.monitorForWorkspace(workspaceId),
                  workspaceManager.setActiveWorkspace(workspaceId, on: targetMonitor.id),
                  let workspace = workspaceManager.descriptor(for: workspaceId)
            else {
                return nil
            }
            return (workspace, targetMonitor)
        }
    }

    func assignWorkspaceToMonitor(
        _ workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID,
        source: WMEventSource = .command
    ) {
        mutationCoordinator.perform(
            .assignWorkspaceToMonitor,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.assignWorkspaceToMonitor(workspaceId, monitorId: monitorId)
        }
    }

    @discardableResult
    func swapWorkspaces(
        _ workspace1Id: WorkspaceDescriptor.ID,
        on monitor1Id: Monitor.ID,
        with workspace2Id: WorkspaceDescriptor.ID,
        on monitor2Id: Monitor.ID,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .workspaceSwap,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.swapWorkspaces(
                workspace1Id,
                on: monitor1Id,
                with: workspace2Id,
                on: monitor2Id
            )
        }
    }

    func setManualLayoutOverride(
        _ override: ManualWindowOverride?,
        for token: WindowToken,
        source: WMEventSource = .command
    ) {
        mutationCoordinator.perform(
            .manualLayoutOverrideSet,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.setManualLayoutOverride(override, for: token)
        }
    }

    func setLayoutReason(
        _ reason: LayoutReason,
        for token: WindowToken,
        source: WMEventSource = .ax
    ) {
        mutationCoordinator.perform(
            .nativeLayoutReasonSet,
            source: source,
            recordTransaction: false
        ) { epoch in
            workspaceManager.setLayoutReason(
                reason,
                for: token,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func setScratchpadToken(
        _ token: WindowToken?,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .setScratchpad,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.setScratchpadToken(token)
        }
    }

    @discardableResult
    func clearScratchpadIfMatches(
        _ token: WindowToken,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .clearScratchpad,
            source: source,
            recordTransaction: true
        ) { _ in
            workspaceManager.clearScratchpadIfMatches(token)
        }
    }

    @discardableResult
    func saveWorkspaceViewport(
        for workspaceId: WorkspaceDescriptor.ID,
        originatingTransactionEpoch: TransactionEpoch,
        source: WMEventSource = .command
    ) -> Bool {
        let signpostState = kernel.intakeSignpost.beginInterval(
            "save_workspace_viewport",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) origin_txn=\(originatingTransactionEpoch.value)"
        )
        let startTime = ContinuousClock.now
        guard originatingTransactionEpoch.isValid,
              originatingTransactionEpoch >= effectRunner.highestAcceptedTransactionEpoch
        else {
            kernel.intakeSignpost.endInterval("save_workspace_viewport", signpostState)
            kernel.intakeLog.debug(
                "save_workspace_viewport_rejected source=\(source.rawValue, privacy: .public) origin_txn=\(originatingTransactionEpoch.value) high=\(self.effectRunner.highestAcceptedTransactionEpoch.value)"
            )
            return false
        }

        let before = workspaceManager.reconcileSnapshot()
        let changed: Bool
        if let focusedToken = workspaceManager.focusedToken,
           workspaceManager.workspace(for: focusedToken) == workspaceId,
           let focusedNode = controllerOperations.niriNode(for: focusedToken)
        {
            changed = workspaceManager.commitWorkspaceSelection(
                nodeId: focusedNode.id,
                focusedToken: focusedToken,
                in: workspaceId
            )
        } else {
            changed = false
        }
        let snapshotChanged = before != workspaceManager.reconcileSnapshot()
        workspaceManager.recordRuntimeTransaction(
            kindForLog: RuntimeMutationKind.commitWorkspaceSelection.rawValue,
            source: source,
            transactionEpoch: originatingTransactionEpoch,
            notes: ["changed=\(snapshotChanged || changed)"]
        )
        effectRunner.noteTransactionCommitted(originatingTransactionEpoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("save_workspace_viewport", signpostState)
        kernel.intakeLog.debug(
            "save_workspace_viewport_intake source=\(source.rawValue, privacy: .public) origin_txn=\(originatingTransactionEpoch.value) changed=\(snapshotChanged || changed) us=\(durationMicros)"
        )
        return snapshotChanged || changed
    }

    @discardableResult
    func activateInferredWorkspaceIfNeeded(
        on monitorId: Monitor.ID,
        source: WMEventSource = .workspaceManager
    ) -> Bool {
        if workspaceManager.activeWorkspace(on: monitorId) != nil {
            return false
        }
        return mutationCoordinator.perform(
            .activateInferredWorkspaceIfNeeded,
            source: source,
            recordTransaction: true,
            resultNotes: { changed in ["activated=\(changed)"] }
        ) { epoch in
            workspaceManager.activateInferredWorkspaceIfNeeded(
                on: monitorId,
                transactionEpoch: epoch,
                eventSource: source
            )
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
                "workspace_confirmation_rejected_invalid_epoch kind=\(kindForLog, privacy: .public) source=\(source.rawValue, privacy: .public) origin_txn=\(originatingEpoch.value)"
            )
            return false
        }
        guard originatingEpoch >= effectRunner.highestAcceptedTransactionEpoch else {
            mutationCoordinator.refreshSnapshotState()
            let highValue = effectRunner.highestAcceptedTransactionEpoch.value
            kernel.intakeLog.debug(
                "workspace_confirmation_rejected_superseded kind=\(kindForLog, privacy: .public) source=\(source.rawValue, privacy: .public) origin_txn=\(originatingEpoch.value) high=\(highValue)"
            )
            return false
        }
        return true
    }
}
