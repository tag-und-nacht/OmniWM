// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct WMEffectRunnerTests {
    @MainActor
    private func makeTransaction(
        transactionEpoch: UInt64,
        effects: [WMEffect]
    ) -> Transaction {
        Transaction(
            transactionEpoch: TransactionEpoch(value: transactionEpoch),
            effects: effects
        )
    }

    @MainActor
    private let monitorA = Monitor.ID(displayId: 10_001)

    @MainActor
    private let workspaceA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

    @MainActor
    private let workspaceB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    @Test @MainActor func invalidEmptyTransactionSentinelIsIgnored() {
        let platform = RecordingEffectPlatform()
        let runner = WMEffectRunner(platform: platform)

        let outcome = runner.apply(.empty)

        #expect(outcome.appliedEffects.isEmpty)
        #expect(outcome.rejectedEffects.isEmpty)
        #expect(platform.events.isEmpty)
        #expect(!runner.highestAcceptedTransactionEpoch.isValid)
    }

    @Test @MainActor func effectsAreAppliedInOrderAndEpochAdvances() {
        let platform = RecordingEffectPlatform()
        let runner = WMEffectRunner(platform: platform)

        let transaction = makeTransaction(
            transactionEpoch: 1,
            effects: [
                .hideKeyboardFocusBorder(reason: "switch workspace", epoch: EffectEpoch(value: 1)),
                .syncMonitorsToNiri(epoch: EffectEpoch(value: 2))
            ]
        )

        let outcome = runner.apply(transaction)

        #expect(outcome.appliedEffects.count == 2)
        #expect(outcome.rejectedEffects.isEmpty)
        #expect(outcome.haltReason == nil)
        #expect(platform.events == [
            .hideKeyboardFocusBorder(reason: "switch workspace"),
            .syncMonitorsToNiri
        ])
        #expect(runner.highestAcceptedTransactionEpoch == TransactionEpoch(value: 1))
    }

    @Test @MainActor func sourceSensitiveEffectsReachPlatformWithSource() {
        let platform = RecordingEffectPlatform()
        let runner = WMEffectRunner(platform: platform)
        let focusToken = WindowToken(pid: 42, windowId: 99)

        let transaction = makeTransaction(
            transactionEpoch: 1,
            effects: [
                .saveWorkspaceViewports(
                    workspaceIds: [workspaceA],
                    source: .ipc,
                    epoch: EffectEpoch(value: 1)
                ),
                .activateTargetWorkspace(
                    workspaceId: workspaceA,
                    monitorId: monitorA,
                    source: .ipc,
                    epoch: EffectEpoch(value: 2)
                ),
                .setInteractionMonitor(
                    monitorId: monitorA,
                    source: .ipc,
                    epoch: EffectEpoch(value: 3)
                ),
                .applyWorkspaceSessionPatch(
                    workspaceId: workspaceA,
                    rememberedFocusToken: focusToken,
                    source: .ipc,
                    epoch: EffectEpoch(value: 4)
                ),
                .commitWorkspaceTransition(
                    affectedWorkspaceIds: [workspaceA],
                    postAction: .clearManagedFocusAfterEmptyWorkspaceTransition,
                    source: .ipc,
                    epoch: EffectEpoch(value: 5)
                ),
                .windowMoveActionDispatch(
                    kindForLog: "move_window_to_workspace_up",
                    source: .ipc,
                    epoch: EffectEpoch(value: 6)
                )
            ]
        )

        _ = runner.apply(transaction, windowMoveAction: .moveWindowToWorkspaceUp(source: .ipc))

        #expect(platform.events == [
            .saveWorkspaceViewport(workspaceId: workspaceA, source: .ipc),
            .activateTargetWorkspace(workspaceId: workspaceA, monitorId: monitorA, source: .ipc),
            .setInteractionMonitor(monitorId: monitorA, source: .ipc),
            .applyWorkspaceSessionPatch(
                workspaceId: workspaceA,
                rememberedFocusToken: focusToken,
                source: .ipc
            ),
            .commitWorkspaceTransition(affectedWorkspaceIds: [workspaceA]),
            .clearManagedFocusAfterEmptyWorkspaceTransition(source: .ipc),
            .performWindowMoveAction(kindForLog: "move_window_to_workspace_up", source: .ipc)
        ])
    }

    @Test @MainActor func controllerActionDispatchSurfacesExternalResult() {
        let platform = RecordingEffectPlatform()
        platform.controllerActionResult = .notFound
        let runner = WMEffectRunner(platform: platform)

        let transaction = makeTransaction(
            transactionEpoch: 1,
            effects: [
                .controllerActionDispatch(
                    kindForLog: "rescue_offscreen_windows",
                    source: .ipc,
                    epoch: EffectEpoch(value: 1)
                )
            ]
        )

        let outcome = runner.apply(
            transaction,
            controllerAction: .rescueOffscreenWindows(source: .ipc)
        )

        #expect(outcome.externalCommandResult == .notFound)
        #expect(platform.events == [
            .performControllerAction(kindForLog: "rescue_offscreen_windows")
        ])
    }

    @Test @MainActor func focusActionDispatchSurfacesExternalResult() {
        let platform = RecordingEffectPlatform()
        platform.focusActionResult = .ignoredOverview
        let runner = WMEffectRunner(platform: platform)

        let transaction = makeTransaction(
            transactionEpoch: 1,
            effects: [
                .focusActionDispatch(
                    kindForLog: "focus_monitor_next",
                    source: .command,
                    epoch: EffectEpoch(value: 1)
                )
            ]
        )

        let outcome = runner.apply(
            transaction,
            focusAction: .focusMonitorNext(source: .command)
        )

        #expect(outcome.externalCommandResult == .ignoredOverview)
        #expect(platform.events == [
            .performFocusAction(kindForLog: "focus_monitor_next", source: .command)
        ])
    }

    @Test @MainActor func windowMoveActionDispatchSurfacesExternalResult() {
        let platform = RecordingEffectPlatform()
        platform.windowMoveActionResult = .executed
        let runner = WMEffectRunner(platform: platform)

        let transaction = makeTransaction(
            transactionEpoch: 1,
            effects: [
                .windowMoveActionDispatch(
                    kindForLog: "move_column_to_workspace",
                    source: .ipc,
                    epoch: EffectEpoch(value: 1)
                )
            ]
        )

        let outcome = runner.apply(
            transaction,
            windowMoveAction: .moveColumnToWorkspace(2, source: .ipc)
        )

        #expect(outcome.externalCommandResult == .executed)
        #expect(platform.events == [
            .performWindowMoveAction(kindForLog: "move_column_to_workspace", source: .ipc)
        ])
    }

    @Test @MainActor func transactionWithSupersededTransactionEpochIsRejectedWholesale() {
        let platform = RecordingEffectPlatform()
        let runner = WMEffectRunner(platform: platform)

        _ = runner.apply(makeTransaction(
            transactionEpoch: 5,
            effects: [.syncMonitorsToNiri(epoch: EffectEpoch(value: 1))]
        ))
        #expect(platform.events.count == 1)

        let staleTransaction = makeTransaction(
            transactionEpoch: 3,
            effects: [
                .hideKeyboardFocusBorder(reason: "stale", epoch: EffectEpoch(value: 2)),
                .setInteractionMonitor(
                    monitorId: monitorA,
                    source: .command,
                    epoch: EffectEpoch(value: 3)
                )
            ]
        )
        let staleOutcome = runner.apply(staleTransaction)

        #expect(staleOutcome.appliedEffects.isEmpty)
        #expect(staleOutcome.rejectedEffects.count == 2)
        #expect(staleOutcome.rejectedEffects.allSatisfy { $0.reason == .transactionSuperseded })
        #expect(platform.events.count == 1, "no new events recorded for superseded transaction")
        #expect(runner.highestAcceptedTransactionEpoch == TransactionEpoch(value: 5))
    }

    @Test @MainActor func activateFailureHaltsTransactionAndReportsReason() {
        let platform = RecordingEffectPlatform()
        platform.activateTargetWorkspaceResult = false
        let runner = WMEffectRunner(platform: platform)

        let transaction = makeTransaction(
            transactionEpoch: 1,
            effects: [
                .hideKeyboardFocusBorder(reason: "switch workspace", epoch: EffectEpoch(value: 1)),
                .activateTargetWorkspace(
                    workspaceId: workspaceA,
                    monitorId: monitorA,
                    source: .command,
                    epoch: EffectEpoch(value: 2)
                ),
                .syncMonitorsToNiri(epoch: EffectEpoch(value: 3))
            ]
        )

        let outcome = runner.apply(transaction)

        #expect(outcome.haltReason == .activateTargetWorkspaceFailed(
            workspaceId: workspaceA,
            monitorId: monitorA
        ))
        #expect(outcome.appliedEffects.count == 2)
        #expect(platform.events == [
            .hideKeyboardFocusBorder(reason: "switch workspace"),
            .activateTargetWorkspace(
                workspaceId: workspaceA,
                monitorId: monitorA,
                source: .command
            )
        ])
    }

    @Test @MainActor func postCommitActionRunsWhenStillCurrent() {
        let platform = RecordingEffectPlatform()
        let runner = WMEffectRunner(platform: platform)

        let focusToken = WindowToken(pid: 42, windowId: 99)
        let transaction = makeTransaction(
            transactionEpoch: 7,
            effects: [
                .commitWorkspaceTransition(
                    affectedWorkspaceIds: [workspaceA],
                    postAction: .focusWindow(focusToken),
                    source: .command,
                    epoch: EffectEpoch(value: 1)
                )
            ]
        )

        _ = runner.apply(transaction)

        #expect(platform.events == [
            .commitWorkspaceTransition(affectedWorkspaceIds: [workspaceA]),
            .focusWindow(token: focusToken, source: .command)
        ])
    }

    @Test @MainActor func postCommitActionRunsWhenLaterTransitionIsDisjoint() {
        let platform = RecordingEffectPlatform()
        platform.synchronousPostActions = false
        let runner = WMEffectRunner(platform: platform)

        let focusToken = WindowToken(pid: 42, windowId: 99)
        _ = runner.apply(makeTransaction(
            transactionEpoch: 3,
            effects: [
                .commitWorkspaceTransition(
                    affectedWorkspaceIds: [workspaceA],
                    postAction: .focusWindow(focusToken),
                    source: .command,
                    epoch: EffectEpoch(value: 1)
                )
            ]
        ))
        #expect(platform.pendingPostActionCount == 1)

        _ = runner.apply(makeTransaction(
            transactionEpoch: 5,
            effects: [
                .commitWorkspaceTransition(
                    affectedWorkspaceIds: [workspaceB],
                    postAction: .none,
                    source: .command,
                    epoch: EffectEpoch(value: 2)
                )
            ]
        ))

        platform.runPendingPostActions()

        let focusEvents = platform.events.filter {
            if case .focusWindow = $0 { true } else { false }
        }
        #expect(focusEvents == [
            .focusWindow(token: focusToken, source: .command)
        ])
        #expect(runner.supersededPostCommitDropCount == 0)
    }

    @Test @MainActor func postCommitActionIsDroppedWhenSameWorkspaceIsSuperseded() {
        let platform = RecordingEffectPlatform()
        platform.synchronousPostActions = false
        let runner = WMEffectRunner(platform: platform)

        let focusToken = WindowToken(pid: 42, windowId: 99)
        _ = runner.apply(makeTransaction(
            transactionEpoch: 3,
            effects: [
                .commitWorkspaceTransition(
                    affectedWorkspaceIds: [workspaceA],
                    postAction: .focusWindow(focusToken),
                    source: .command,
                    epoch: EffectEpoch(value: 1)
                )
            ]
        ))
        #expect(platform.pendingPostActionCount == 1)

        _ = runner.apply(makeTransaction(
            transactionEpoch: 5,
            effects: [
                .commitWorkspaceTransition(
                    affectedWorkspaceIds: [workspaceA],
                    postAction: .none,
                    source: .command,
                    epoch: EffectEpoch(value: 2)
                )
            ]
        ))

        platform.runPendingPostActions()

        let focusEvents = platform.events.filter {
            if case .focusWindow = $0 { true } else { false }
        }
        #expect(focusEvents.isEmpty)
        #expect(runner.supersededPostCommitDropCount == 1)
    }

    @Test @MainActor func idempotentReapplyUsesSameEpoch() {
        let platform = RecordingEffectPlatform()
        let runner = WMEffectRunner(platform: platform)

        let transaction = makeTransaction(
            transactionEpoch: 1,
            effects: [.syncMonitorsToNiri(epoch: EffectEpoch(value: 1))]
        )
        _ = runner.apply(transaction)
        _ = runner.apply(transaction)

        #expect(platform.events.count == 2)
        #expect(runner.highestAcceptedTransactionEpoch == TransactionEpoch(value: 1))
    }

    @Test @MainActor func emptyTransactionAdvancesTheHighWaterMark() {
        let platform = RecordingEffectPlatform()
        let runner = WMEffectRunner(platform: platform)

        _ = runner.apply(Transaction(
            transactionEpoch: TransactionEpoch(value: 7),
            effects: []
        ))

        #expect(runner.highestAcceptedTransactionEpoch == TransactionEpoch(value: 7))
        #expect(platform.events.isEmpty)
    }

    @Test @MainActor func noteTransactionCommittedAdvancesWatermark() {
        let platform = RecordingEffectPlatform()
        let runner = WMEffectRunner(platform: platform)

        runner.noteTransactionCommitted(TransactionEpoch(value: 4))

        #expect(runner.highestAcceptedTransactionEpoch == TransactionEpoch(value: 4))
    }

    @Test @MainActor func noteTransactionCommittedIgnoresStaleOrInvalidEpoch() {
        let platform = RecordingEffectPlatform()
        let runner = WMEffectRunner(platform: platform)

        runner.noteTransactionCommitted(TransactionEpoch(value: 5))
        runner.noteTransactionCommitted(TransactionEpoch(value: 2))
        runner.noteTransactionCommitted(.invalid)

        #expect(runner.highestAcceptedTransactionEpoch == TransactionEpoch(value: 5))
    }

    @Test @MainActor func eventOnlyTransactionDoesNotSupersedePendingPostAction() {
        let platform = RecordingEffectPlatform()
        platform.synchronousPostActions = false
        let runner = WMEffectRunner(platform: platform)

        let focusToken = WindowToken(pid: 7, windowId: 42)
        _ = runner.apply(makeTransaction(
            transactionEpoch: 3,
            effects: [
                .commitWorkspaceTransition(
                    affectedWorkspaceIds: [workspaceA],
                    postAction: .focusWindow(focusToken),
                    source: .command,
                    epoch: EffectEpoch(value: 1)
                )
            ]
        ))

        runner.noteTransactionCommitted(TransactionEpoch(value: 4))
        platform.runPendingPostActions()

        let focusEvents = platform.events.filter {
            if case .focusWindow = $0 { true } else { false }
        }
        #expect(focusEvents == [
            .focusWindow(token: focusToken, source: .command)
        ])
        #expect(runner.supersededPostCommitDropCount == 0)
    }
}
