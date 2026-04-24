// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@MainActor
enum WorkspaceSwitchEffectPlanner {
    struct Inputs {
        let controller: WMController
        let allocateEffectEpoch: () -> EffectEpoch
    }

    static func makeEffects(
        for command: WMCommand.WorkspaceSwitchCommand,
        inputs: Inputs
    ) -> [WMEffect] {
        let intent = makeIntent(for: command, controller: inputs.controller)
        let kernelPlan = WorkspaceNavigationKernel.plan(
            .capture(controller: inputs.controller, intent: intent)
        )
        guard kernelPlan.outcome == .execute else {
            return []
        }
        let hideReason = hideBorderReason(for: command)
        let source = source(for: command)
        return assembleEffects(
            from: kernelPlan,
            hideReason: hideReason,
            source: source,
            allocateEffectEpoch: inputs.allocateEffectEpoch
        )
    }

    private static func makeIntent(
        for command: WMCommand.WorkspaceSwitchCommand,
        controller: WMController
    ) -> WorkspaceNavigationKernel.Intent {
        switch command {
        case let .explicit(rawWorkspaceID),
             let .explicitFrom(rawWorkspaceID, _):
            return .init(
                operation: .switchWorkspaceExplicit,
                currentWorkspaceId: controller.activeWorkspace()?.id,
                targetWorkspaceId: controller.workspaceManager.workspaceId(
                    for: rawWorkspaceID,
                    createIfMissing: false
                )
            )

        case let .relative(isNext, wrapAround),
             let .relativeFrom(isNext, wrapAround, _):
            return .init(
                operation: .switchWorkspaceRelative,
                direction: isNext ? .right : .left,
                currentWorkspaceId: controller.activeWorkspace()?.id,
                currentMonitorId: interactionMonitorId(for: controller),
                wrapAround: wrapAround
            )
        }
    }

    private static func hideBorderReason(
        for command: WMCommand.WorkspaceSwitchCommand
    ) -> String {
        switch command {
        case .explicit, .explicitFrom:
            "switch workspace"
        case .relative, .relativeFrom:
            "switch workspace relative"
        }
    }

    private static func source(
        for command: WMCommand.WorkspaceSwitchCommand
    ) -> WMEventSource {
        switch command {
        case .explicit, .relative:
            .command
        case let .explicitFrom(_, source),
             let .relativeFrom(_, _, source):
            source
        }
    }

    private static func interactionMonitorId(
        for controller: WMController
    ) -> Monitor.ID? {
        controller.workspaceManager.interactionMonitorId
            ?? controller.monitorForInteraction()?.id
    }

    private static func assembleEffects(
        from plan: WorkspaceNavigationKernel.Plan,
        hideReason: String,
        source: WMEventSource,
        allocateEffectEpoch: () -> EffectEpoch
    ) -> [WMEffect] {
        var effects: [WMEffect] = []

        if plan.shouldHideFocusBorder {
            effects.append(.hideKeyboardFocusBorder(
                reason: hideReason,
                epoch: allocateEffectEpoch()
            ))
        }

        if !plan.saveWorkspaceIds.isEmpty {
            effects.append(.saveWorkspaceViewports(
                workspaceIds: plan.saveWorkspaceIds,
                source: source,
                epoch: allocateEffectEpoch()
            ))
        }

        if let targetMonitorId = plan.targetMonitorId {
            if plan.shouldActivateTargetWorkspace,
               let targetWorkspaceId = plan.targetWorkspaceId
            {
                effects.append(.activateTargetWorkspace(
                    workspaceId: targetWorkspaceId,
                    monitorId: targetMonitorId,
                    source: source,
                    epoch: allocateEffectEpoch()
                ))
            } else if plan.shouldSetInteractionMonitor {
                effects.append(.setInteractionMonitor(
                    monitorId: targetMonitorId,
                    source: source,
                    epoch: allocateEffectEpoch()
                ))
            }
        }

        if plan.shouldSyncMonitorsToNiri {
            effects.append(.syncMonitorsToNiri(
                epoch: allocateEffectEpoch()
            ))
        }

        if plan.shouldCommitWorkspaceTransition {
            appendCommitEffects(
                plan: plan,
                into: &effects,
                source: source,
                allocateEffectEpoch: allocateEffectEpoch
            )
        }

        return effects
    }

    private static func appendCommitEffects(
        plan: WorkspaceNavigationKernel.Plan,
        into effects: inout [WMEffect],
        source: WMEventSource,
        allocateEffectEpoch: () -> EffectEpoch
    ) {
        switch plan.focusAction {
        case .workspaceHandoff:
            appendWorkspaceCommit(
                plan: plan,
                stopScrollOnTargetMonitor: true,
                into: &effects,
                source: source,
                allocateEffectEpoch: allocateEffectEpoch
            )

        case .resolveTargetIfPresent, .clearManagedFocus:
            appendWorkspaceCommit(
                plan: plan,
                stopScrollOnTargetMonitor: false,
                into: &effects,
                source: source,
                allocateEffectEpoch: allocateEffectEpoch
            )

        case .subject, .recoverSource, .none:
            return
        }
    }

    private static func appendWorkspaceCommit(
        plan: WorkspaceNavigationKernel.Plan,
        stopScrollOnTargetMonitor: Bool,
        into effects: inout [WMEffect],
        source: WMEventSource,
        allocateEffectEpoch: () -> EffectEpoch
    ) {
        if stopScrollOnTargetMonitor, let targetMonitorId = plan.targetMonitorId {
            effects.append(.stopScrollAnimation(
                monitorId: targetMonitorId,
                epoch: allocateEffectEpoch()
            ))
        }
        if let targetWorkspaceId = plan.targetWorkspaceId,
           let resolvedFocusToken = plan.resolvedFocusToken
        {
            effects.append(.applyWorkspaceSessionPatch(
                workspaceId: targetWorkspaceId,
                rememberedFocusToken: resolvedFocusToken,
                source: source,
                epoch: allocateEffectEpoch()
            ))
        }
        let postAction = makePostAction(plan: plan)
        effects.append(.commitWorkspaceTransition(
            affectedWorkspaceIds: plan.affectedWorkspaceIds,
            postAction: postAction,
            source: source,
            epoch: allocateEffectEpoch()
        ))
    }

    private static func makePostAction(
        plan: WorkspaceNavigationKernel.Plan
    ) -> WMEffect.PostWorkspaceTransitionAction {
        if let resolvedFocusToken = plan.resolvedFocusToken {
            return .focusWindow(resolvedFocusToken)
        }
        if plan.focusAction == .clearManagedFocus {
            return .clearManagedFocusAfterEmptyWorkspaceTransition
        }
        return .none
    }
}
