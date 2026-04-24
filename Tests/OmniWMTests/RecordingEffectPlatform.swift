// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@testable import OmniWM

@MainActor
final class RecordingEffectPlatform: WMEffectPlatform {
    enum Event: Equatable {
        case hideKeyboardFocusBorder(reason: String)
        case saveWorkspaceViewport(
            workspaceId: WorkspaceDescriptor.ID,
            source: WMEventSource
        )
        case activateTargetWorkspace(
            workspaceId: WorkspaceDescriptor.ID,
            monitorId: Monitor.ID,
            source: WMEventSource
        )
        case setInteractionMonitor(
            monitorId: Monitor.ID,
            source: WMEventSource
        )
        case syncMonitorsToNiri
        case stopScrollAnimation(monitorId: Monitor.ID)
        case applyWorkspaceSessionPatch(
            workspaceId: WorkspaceDescriptor.ID,
            rememberedFocusToken: WindowToken?,
            source: WMEventSource
        )
        case commitWorkspaceTransition(
            affectedWorkspaceIds: Set<WorkspaceDescriptor.ID>
        )
        case focusWindow(token: WindowToken, source: WMEventSource)
        case clearManagedFocusAfterEmptyWorkspaceTransition(source: WMEventSource)
        case performControllerAction(kindForLog: String)
        case performFocusAction(kindForLog: String, source: WMEventSource)
        case performWindowMoveAction(kindForLog: String, source: WMEventSource)
        case performLayoutMutationAction(kindForLog: String, source: WMEventSource)
        case performWorkspaceNavigationAction(kindForLog: String, source: WMEventSource)
        case performUIAction(kindForLog: String, source: WMEventSource)
    }

    private(set) var events: [Event] = []

    var activateTargetWorkspaceResult: Bool = true

    var synchronousPostActions: Bool = true
    private var pendingPostActions: [@MainActor () -> Void] = []

    func hideKeyboardFocusBorder(reason: String) {
        events.append(.hideKeyboardFocusBorder(reason: reason))
    }

    func saveWorkspaceViewport(
        for workspaceId: WorkspaceDescriptor.ID,
        transactionEpoch _: TransactionEpoch,
        source: WMEventSource
    ) {
        events.append(.saveWorkspaceViewport(
            workspaceId: workspaceId,
            source: source
        ))
    }

    @discardableResult
    func activateTargetWorkspace(
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID,
        transactionEpoch _: TransactionEpoch,
        source: WMEventSource
    ) -> Bool {
        events.append(.activateTargetWorkspace(
            workspaceId: workspaceId,
            monitorId: monitorId,
            source: source
        ))
        return activateTargetWorkspaceResult
    }

    func setInteractionMonitor(
        monitorId: Monitor.ID,
        transactionEpoch _: TransactionEpoch,
        source: WMEventSource
    ) {
        events.append(.setInteractionMonitor(
            monitorId: monitorId,
            source: source
        ))
    }

    func syncMonitorsToNiri() {
        events.append(.syncMonitorsToNiri)
    }

    func stopScrollAnimation(monitorId: Monitor.ID) {
        events.append(.stopScrollAnimation(monitorId: monitorId))
    }

    func applyWorkspaceSessionPatch(
        workspaceId: WorkspaceDescriptor.ID,
        rememberedFocusToken: WindowToken?,
        transactionEpoch _: TransactionEpoch,
        source: WMEventSource
    ) {
        events.append(.applyWorkspaceSessionPatch(
            workspaceId: workspaceId,
            rememberedFocusToken: rememberedFocusToken,
            source: source
        ))
    }

    func commitWorkspaceTransition(
        affectedWorkspaceIds: Set<WorkspaceDescriptor.ID>,
        postAction: @escaping @MainActor () -> Void
    ) {
        events.append(.commitWorkspaceTransition(
            affectedWorkspaceIds: affectedWorkspaceIds
        ))
        if synchronousPostActions {
            postAction()
        } else {
            pendingPostActions.append(postAction)
        }
    }

    func focusWindow(_ token: WindowToken, source: WMEventSource) {
        events.append(.focusWindow(token: token, source: source))
    }

    func clearManagedFocusAfterEmptyWorkspaceTransition(
        transactionEpoch _: TransactionEpoch,
        source: WMEventSource
    ) {
        events.append(.clearManagedFocusAfterEmptyWorkspaceTransition(source: source))
    }

    var controllerActionResult: ExternalCommandResult = .executed

    @discardableResult
    func performControllerAction(
        _ action: WMCommand.ControllerActionCommand,
        transactionEpoch _: TransactionEpoch
    ) -> ExternalCommandResult {
        events.append(.performControllerAction(kindForLog: action.kindForLog))
        return controllerActionResult
    }

    var focusActionResult: ExternalCommandResult = .executed

    @discardableResult
    func performFocusAction(
        _ action: WMCommand.FocusActionCommand,
        transactionEpoch _: TransactionEpoch
    ) -> ExternalCommandResult {
        events.append(.performFocusAction(
            kindForLog: action.kindForLog,
            source: action.source
        ))
        return focusActionResult
    }

    var windowMoveActionResult: ExternalCommandResult = .executed

    @discardableResult
    func performWindowMoveAction(
        _ action: WMCommand.WindowMoveActionCommand,
        transactionEpoch _: TransactionEpoch
    ) -> ExternalCommandResult {
        events.append(.performWindowMoveAction(
            kindForLog: action.kindForLog,
            source: action.source
        ))
        return windowMoveActionResult
    }

    var layoutMutationActionResult: ExternalCommandResult = .executed

    @discardableResult
    func performLayoutMutationAction(
        _ action: WMCommand.LayoutMutationActionCommand,
        transactionEpoch _: TransactionEpoch
    ) -> ExternalCommandResult {
        events.append(.performLayoutMutationAction(
            kindForLog: action.kindForLog,
            source: action.source
        ))
        return layoutMutationActionResult
    }

    var workspaceNavigationActionResult: ExternalCommandResult = .executed

    @discardableResult
    func performWorkspaceNavigationAction(
        _ action: WMCommand.WorkspaceNavigationActionCommand,
        transactionEpoch _: TransactionEpoch
    ) -> ExternalCommandResult {
        events.append(.performWorkspaceNavigationAction(
            kindForLog: action.kindForLog,
            source: action.source
        ))
        return workspaceNavigationActionResult
    }

    var uiActionResult: ExternalCommandResult = .executed

    @discardableResult
    func performUIAction(
        _ action: WMCommand.UIActionCommand,
        transactionEpoch _: TransactionEpoch
    ) -> ExternalCommandResult {
        events.append(.performUIAction(
            kindForLog: action.kindForLog,
            source: action.source
        ))
        return uiActionResult
    }

    func runPendingPostActions() {
        let drained = pendingPostActions
        pendingPostActions.removeAll(keepingCapacity: true)
        for action in drained {
            action()
        }
    }

    var pendingPostActionCount: Int { pendingPostActions.count }
}
