// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@MainActor
final class WMLiveEffectPlatform: WMEffectPlatform {
    private weak var controller: WMController?

    init(controller: WMController) {
        self.controller = controller
    }

    private func requiredRuntime(_ context: String) -> WMRuntime {
        guard let runtime = controller?.runtime else {
            preconditionFailure("\(context) requires WMRuntime to be attached")
        }
        return runtime
    }

    func hideKeyboardFocusBorder(reason: String) {
        controller?.hideKeyboardFocusBorder(
            source: .workspaceActivation,
            reason: reason
        )
    }

    func saveWorkspaceViewport(
        for workspaceId: WorkspaceDescriptor.ID,
        transactionEpoch: TransactionEpoch,
        source: WMEventSource
    ) {
        _ = requiredRuntime("WMLiveEffectPlatform.saveWorkspaceViewport").saveWorkspaceViewport(
            for: workspaceId,
            originatingTransactionEpoch: transactionEpoch,
            source: source
        )
    }

    @discardableResult
    func activateTargetWorkspace(
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID,
        transactionEpoch: TransactionEpoch,
        source: WMEventSource
    ) -> Bool {
        requiredRuntime("WMLiveEffectPlatform.activateTargetWorkspace").submit(
            .targetWorkspaceActivated(
                workspaceId: workspaceId,
                monitorId: monitorId,
                source: source,
                originatingTransactionEpoch: transactionEpoch
            )
        )
    }

    func setInteractionMonitor(
        monitorId: Monitor.ID,
        transactionEpoch: TransactionEpoch,
        source: WMEventSource
    ) {
        _ = requiredRuntime("WMLiveEffectPlatform.setInteractionMonitor").submit(
            .interactionMonitorSet(
                monitorId: monitorId,
                source: source,
                originatingTransactionEpoch: transactionEpoch
            )
        )
    }

    func syncMonitorsToNiri() {
        controller?.syncMonitorsToNiriEngine()
    }

    func stopScrollAnimation(monitorId: Monitor.ID) {
        guard let controller,
              let monitor = controller.workspaceManager.monitor(byId: monitorId)
        else { return }
        controller.layoutRefreshController.stopScrollAnimation(for: monitor.displayId)
    }

    func applyWorkspaceSessionPatch(
        workspaceId: WorkspaceDescriptor.ID,
        rememberedFocusToken: WindowToken?,
        transactionEpoch: TransactionEpoch,
        source: WMEventSource
    ) {
        _ = requiredRuntime("WMLiveEffectPlatform.applyWorkspaceSessionPatch").submit(
            .workspaceSessionPatched(
                workspaceId: workspaceId,
                rememberedFocusToken: rememberedFocusToken,
                source: source,
                originatingTransactionEpoch: transactionEpoch
            )
        )
    }

    func commitWorkspaceTransition(
        affectedWorkspaceIds: Set<WorkspaceDescriptor.ID>,
        postAction: @escaping @MainActor () -> Void
    ) {
        controller?.layoutRefreshController.commitWorkspaceTransition(
            affectedWorkspaces: affectedWorkspaceIds,
            reason: .workspaceTransition,
            postLayout: postAction
        )
    }

    func focusWindow(_ token: WindowToken, source: WMEventSource) {
        controller?.focusWindow(token, source: source)
    }

    func clearManagedFocusAfterEmptyWorkspaceTransition(
        transactionEpoch: TransactionEpoch,
        source: WMEventSource
    ) {
        _ = requiredRuntime(
            "WMLiveEffectPlatform.clearManagedFocusAfterEmptyWorkspaceTransition"
        ).clearManagedFocusAfterEmptyWorkspaceTransition(
            originatingTransactionEpoch: transactionEpoch,
            source: source
        )
    }

    @discardableResult
    func performControllerAction(
        _ action: WMCommand.ControllerActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        guard let runtime = controller?.runtime else { return .invalidArguments }
        return runtime.controllerActionRuntime.perform(action, transactionEpoch: transactionEpoch)
    }

    @discardableResult
    func performFocusAction(
        _ action: WMCommand.FocusActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        guard let runtime = controller?.runtime else { return .invalidArguments }
        return runtime.focusRuntime.perform(action, transactionEpoch: transactionEpoch)
    }

    @discardableResult
    func performWindowMoveAction(
        _ action: WMCommand.WindowMoveActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        guard let runtime = controller?.runtime else { return .invalidArguments }
        return runtime.windowAdmissionRuntime.perform(action, transactionEpoch: transactionEpoch)
    }

    @discardableResult
    func performLayoutMutationAction(
        _ action: WMCommand.LayoutMutationActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        guard let runtime = controller?.runtime else { return .invalidArguments }
        return runtime.workspaceRuntime.perform(action, transactionEpoch: transactionEpoch)
    }

    @discardableResult
    func performWorkspaceNavigationAction(
        _ action: WMCommand.WorkspaceNavigationActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        guard let runtime = controller?.runtime else { return .invalidArguments }
        return runtime.workspaceRuntime.perform(action, transactionEpoch: transactionEpoch)
    }

    @discardableResult
    func performUIAction(
        _ action: WMCommand.UIActionCommand,
        transactionEpoch: TransactionEpoch
    ) -> ExternalCommandResult {
        guard let runtime = controller?.runtime else { return .invalidArguments }
        return runtime.uiActionRuntime.perform(action, transactionEpoch: transactionEpoch)
    }

}
