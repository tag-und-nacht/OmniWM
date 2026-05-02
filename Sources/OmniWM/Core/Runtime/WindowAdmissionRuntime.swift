// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OSLog

/// Per-domain runtime for window admission and identity — admit a new AX
/// window into the manager, retire it on terminal failure, rekey when its
/// AX token changes, quarantine the windows of a terminated app. Mirrors
/// `WindowRegistry` + `LogicalWindowRegistry` on the manager side.
///
/// Owns the invariant-heavy window identity/admission mutations.
@MainActor
final class WindowAdmissionRuntime {
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

    /// The full logical-window registry (read-only protocol view).
    var logicalWindowRegistry: any LogicalWindowRegistryReading {
        workspaceManager.logicalWindowRegistry
    }

    /// True iff the registry currently tracks a window for `token`.
    func isWindowTracked(_ token: WindowToken) -> Bool {
        workspaceManager.entry(for: token) != nil
    }

    /// Resolve the live logical id for `token`, or `nil` if the token isn't
    /// tracked or has been retired.
    func liveLogicalId(for token: WindowToken) -> LogicalWindowId? {
        workspaceManager.logicalWindowRegistry.lookup(token: token).liveLogicalId
    }

    @discardableResult
    func perform(
        _ action: WMCommand.WindowMoveActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        mutationCoordinator.performCommandEffect(
            kindForLog: "window_move_action:\(action.kindForLog)",
            source: action.source,
            transactionEpoch: transactionEpoch,
            resultNotes: { result in ["external_result=\(String(describing: result))"] }
        ) {
            controllerOperations.performWindowMoveAction(action)
        }
    }

    // MARK: Mutations (migrated from WMRuntime — ExecPlan 02 surface migration)

    @discardableResult
    func admitWindow(
        _ ax: AXWindowRef,
        pid: pid_t,
        windowId: Int,
        to workspace: WorkspaceDescriptor.ID,
        mode: TrackedWindowMode = .tiling,
        ruleEffects: ManagedWindowRuleEffects = .none,
        managedReplacementMetadata: ManagedReplacementMetadata? = nil,
        source: WMEventSource = .ax
    ) -> WindowToken {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "admit_window",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let token = workspaceManager.addWindow(
            ax,
            pid: pid,
            windowId: windowId,
            to: workspace,
            mode: mode,
            ruleEffects: ruleEffects,
            managedReplacementMetadata: managedReplacementMetadata,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("admit_window", signpostState)
        kernel.intakeLog.debug(
            "ax_admit_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) us=\(durationMicros)"
        )
        return token
    }

    @discardableResult
    func rekeyWindow(
        from oldToken: WindowToken,
        to newToken: WindowToken,
        newAXRef: AXWindowRef,
        managedReplacementMetadata: ManagedReplacementMetadata? = nil,
        source: WMEventSource = .ax
    ) -> WindowModel.Entry? {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "rekey_window",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let entry = workspaceManager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: newAXRef,
            managedReplacementMetadata: managedReplacementMetadata,
            transactionEpoch: epoch,
            eventSource: source
        )
        if let entry {
            controllerOperations.rekeyWindowReferences(
                from: oldToken,
                to: newToken,
                axRef: newAXRef,
                workspaceId: entry.workspaceId
            )
        }
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("rekey_window", signpostState)
        kernel.intakeLog.debug(
            "ax_rekey_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) entry_found=\(entry != nil) us=\(durationMicros)"
        )
        return entry
    }

    @discardableResult
    func removeWindow(
        pid: pid_t,
        windowId: Int,
        source: WMEventSource = .ax
    ) -> WindowModel.Entry? {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "remove_window",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let entry = workspaceManager.removeWindow(
            pid: pid,
            windowId: windowId,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("remove_window", signpostState)
        kernel.intakeLog.debug(
            "ax_remove_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) entry_found=\(entry != nil) us=\(durationMicros)"
        )
        return entry
    }

    @discardableResult
    func removeWindowsForApp(
        pid: pid_t,
        source: WMEventSource = .ax
    ) -> Set<WorkspaceDescriptor.ID> {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "remove_windows_for_app",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let affectedWorkspaces = workspaceManager.removeWindowsForApp(
            pid: pid,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("remove_windows_for_app", signpostState)
        kernel.intakeLog.debug(
            "ax_remove_app_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) affected_workspaces=\(affectedWorkspaces.count) us=\(durationMicros)"
        )
        return affectedWorkspaces
    }

    @discardableResult
    func setWindowMode(
        _ mode: TrackedWindowMode,
        for token: WindowToken,
        source: WMEventSource = .command
    ) -> Bool {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "set_window_mode",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let changed = workspaceManager.setWindowMode(
            mode,
            for: token,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("set_window_mode", signpostState)
        kernel.intakeLog.debug(
            "window_mode_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) changed=\(changed) us=\(durationMicros)"
        )
        return changed
    }

    @discardableResult
    func recordStaleCGSDestroy(
        probeToken: WindowToken,
        source: WMEventSource = .ax
    ) -> LogicalWindowId? {
        var recorded: LogicalWindowId?
        mutationCoordinator.perform(
            .staleCGSDestroyAudit,
            source: source,
            recordTransaction: true,
            resultNotes: { (logicalId: LogicalWindowId?) in
                guard let logicalId else { return ["recorded=none"] }
                return ["recorded=\(logicalId)"]
            }
        ) { _ -> LogicalWindowId? in
            recorded = workspaceManager.quarantineStaleCGSDestroyIfApplicable(
                probeToken: probeToken
            )
            return recorded
        }
        return recorded
    }

    @discardableResult
    func quarantineWindowsForTerminatedApp(
        pid: pid_t,
        source: WMEventSource = .ax
    ) -> [LogicalWindowId] {
        var quarantined: [LogicalWindowId] = []
        mutationCoordinator.perform(
            .appDisappearedQuarantineSweep,
            source: source,
            recordTransaction: true,
            resultNotes: { (ids: [LogicalWindowId]) in
                ["count=\(ids.count)"]
            }
        ) { _ -> [LogicalWindowId] in
            quarantined = workspaceManager.quarantineWindowsForTerminatedApp(pid: pid)
            return quarantined
        }
        return quarantined
    }

    func removeMissingWindows(
        keys activeKeys: Set<WindowModel.WindowKey>,
        requiredConsecutiveMisses: Int,
        source: WMEventSource = .service
    ) {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "remove_missing_windows",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let before = workspaceManager.reconcileSnapshot()
        workspaceManager.removeMissing(
            keys: activeKeys,
            requiredConsecutiveMisses: requiredConsecutiveMisses
        )
        let changed = before != workspaceManager.reconcileSnapshot()
        workspaceManager.recordRuntimeTransaction(
            kindForLog: "remove_missing_windows",
            source: source,
            transactionEpoch: epoch,
            notes: ["changed=\(changed)"]
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("remove_missing_windows", signpostState)
        kernel.intakeLog.debug(
            "remove_missing_windows_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) changed=\(changed) us=\(durationMicros)"
        )
    }

    func garbageCollectUnusedWorkspaces(
        focusedWorkspaceId: WorkspaceDescriptor.ID?,
        source: WMEventSource = .service
    ) {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "garbage_collect_unused_workspaces",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let before = workspaceManager.reconcileSnapshot()
        workspaceManager.garbageCollectUnusedWorkspaces(focusedWorkspaceId: focusedWorkspaceId)
        let changed = before != workspaceManager.reconcileSnapshot()
        workspaceManager.recordRuntimeTransaction(
            kindForLog: "garbage_collect_unused_workspaces",
            source: source,
            transactionEpoch: epoch,
            notes: ["changed=\(changed)"]
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("garbage_collect_unused_workspaces", signpostState)
        kernel.intakeLog.debug(
            "gc_unused_workspaces_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) changed=\(changed) us=\(durationMicros)"
        )
    }
}
