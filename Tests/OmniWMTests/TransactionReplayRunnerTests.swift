// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct TransactionReplayRunnerTests {
    @Test @MainActor func replayStampsEveryStepWithMonotonicEpochs() throws {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let runner = TransactionReplayRunner(runtime: runtime, platform: platform)

        try runner.replay([
            .event(.activeSpaceChanged(source: .workspaceManager)),
            .command(.workspaceSwitch(.explicit(rawWorkspaceID: "2"))),
            .command(.workspaceSwitch(.explicit(rawWorkspaceID: "1")))
        ])

        let epochs = runner.outcomes.map(\.transactionEpoch.value)
        #expect(epochs == [1, 2, 3])
    }

    @Test @MainActor func replayExposesPlansForInspection() throws {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let runner = TransactionReplayRunner(runtime: runtime, platform: platform)

        try runner.replay([
            .command(.workspaceSwitch(.explicit(rawWorkspaceID: "2")))
        ])

        guard let outcome = runner.outcomes.first,
              let transaction = outcome.transaction
        else {
            Issue.record("expected a command outcome with a transaction")
            return
        }

        #expect(transaction.transactionEpoch == outcome.transactionEpoch)
        #expect(!transaction.effects.isEmpty)
        #expect(!outcome.platformEventsAfter.isEmpty)
    }

    @Test @MainActor func validatorRejectsTransactionWithDriftedTransactionEpoch() throws {
        let drifted = TransactionReplayRunner.Outcome(
            step: .command(.workspaceSwitch(.explicit(rawWorkspaceID: "ignored"))),
            transactionEpoch: TransactionEpoch(value: 2),
            transaction: Transaction(
                transactionEpoch: TransactionEpoch(value: 999),
                effects: [.syncMonitorsToNiri(epoch: EffectEpoch(value: 1))]
            ),
            platformEventsAfter: []
        )

        #expect(throws: TransactionReplayRunner.InvariantViolation.self) {
            try TransactionReplayRunner.validateForTests(
                outcome: drifted,
                index: 0,
                previousTransactionEpoch: .invalid
            )
        }
    }

    @Test @MainActor func validatorRejectsNonMonotonicTransactionEpoch() throws {
        let outcome = TransactionReplayRunner.Outcome(
            step: .event(.activeSpaceChanged(source: .workspaceManager)),
            transactionEpoch: TransactionEpoch(value: 2),
            transaction: nil,
            platformEventsAfter: []
        )

        #expect(throws: TransactionReplayRunner.InvariantViolation.self) {
            try TransactionReplayRunner.validateForTests(
                outcome: outcome,
                index: 1,
                previousTransactionEpoch: TransactionEpoch(value: 5)
            )
        }
    }

    @Test @MainActor func validatorRejectsNonMonotonicEffectEpochsWithinPlan() throws {
        let outcome = TransactionReplayRunner.Outcome(
            step: .command(.workspaceSwitch(.explicit(rawWorkspaceID: "ignored"))),
            transactionEpoch: TransactionEpoch(value: 3),
            transaction: Transaction(
                transactionEpoch: TransactionEpoch(value: 3),
                effects: [
                    .syncMonitorsToNiri(epoch: EffectEpoch(value: 10)),
                    .syncMonitorsToNiri(epoch: EffectEpoch(value: 4))
                ]
            ),
            platformEventsAfter: []
        )

        #expect(throws: TransactionReplayRunner.InvariantViolation.self) {
            try TransactionReplayRunner.validateForTests(
                outcome: outcome,
                index: 0,
                previousTransactionEpoch: .invalid
            )
        }
    }

    @Test @MainActor func validatorRejectsUnstampedEffectEpoch() throws {
        let outcome = TransactionReplayRunner.Outcome(
            step: .command(.workspaceSwitch(.explicit(rawWorkspaceID: "ignored"))),
            transactionEpoch: TransactionEpoch(value: 3),
            transaction: Transaction(
                transactionEpoch: TransactionEpoch(value: 3),
                effects: [.syncMonitorsToNiri(epoch: .invalid)]
            ),
            platformEventsAfter: []
        )

        #expect(throws: TransactionReplayRunner.InvariantViolation.self) {
            try TransactionReplayRunner.validateForTests(
                outcome: outcome,
                index: 0,
                previousTransactionEpoch: .invalid
            )
        }
    }

    @Test @MainActor func validatorRejectsUnstampedTransactionEpoch() throws {
        let outcome = TransactionReplayRunner.Outcome(
            step: .event(.activeSpaceChanged(source: .workspaceManager)),
            transactionEpoch: .invalid,
            transaction: nil,
            platformEventsAfter: []
        )

        #expect(throws: TransactionReplayRunner.InvariantViolation.self) {
            try TransactionReplayRunner.validateForTests(
                outcome: outcome,
                index: 0,
                previousTransactionEpoch: .invalid
            )
        }
    }

    @Test @MainActor func validatorRejectsTxnWithReconcileInvariantViolations() throws {
        let event = WMEvent.activeSpaceChanged(source: .workspaceManager)
        let txn = Transaction(
            timestamp: Date(),
            event: event,
            normalizedEvent: event,
            plan: ActionPlan(),
            transactionEpoch: TransactionEpoch(value: 7),
            effects: [],
            snapshot: ReconcileSnapshot(
                topologyProfile: TopologyProfile(monitors: []),
                focusSession: FocusSessionSnapshot(
                    focusedToken: nil,
                    pendingManagedFocus: .empty,
                    focusLease: nil,
                    isNonManagedFocusActive: false,
                    isAppFullscreenActive: false,
                    interactionMonitorId: nil,
                    previousInteractionMonitorId: nil
                ),
                windows: [],
                workspaceGraph: .empty
            ),
            invariantViolations: [
                .init(code: "test_invariant", message: "synthetic violation")
            ]
        )
        let outcome = TransactionReplayRunner.Outcome(
            step: .event(event),
            transactionEpoch: TransactionEpoch(value: 7),
            transaction: txn,
            platformEventsAfter: []
        )

        #expect(throws: TransactionReplayRunner.InvariantViolation.self) {
            try TransactionReplayRunner.validateForTests(
                outcome: outcome,
                index: 0,
                previousTransactionEpoch: .invalid
            )
        }
    }

    @Test @MainActor func validatorAcceptsWellFormedRuntimeOutcome() throws {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let runner = TransactionReplayRunner(runtime: runtime, platform: platform)

        #expect(throws: Never.self) {
            try runner.replay([
                .command(.workspaceSwitch(.explicit(rawWorkspaceID: "2")))
            ])
        }
        #expect(runner.outcomes.count == 1)
    }
}
