// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing
@testable import OmniWM

@Suite("FocusRuntime")
@MainActor
struct FocusRuntimeTests {
    private struct Fixture {
        let focusRuntime: FocusRuntime
        let kernel: RuntimeKernel
        let effectRunner: WMEffectRunner
        let workspaceManager: WorkspaceManager
        let refreshProbe: SnapshotRefreshProbe
    }

    private final class SnapshotRefreshProbe: RuntimeSnapshotPublishing {
        private(set) var refreshCount = 0

        func refreshSnapshotState() {
            refreshCount += 1
        }
    }

    private func makeRuntimeFixture() -> Fixture {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        let workspaceManager = WorkspaceManager(settings: settings)
        let kernel = RuntimeKernel()
        let effectRunner = WMEffectRunner(platform: RecordingEffectPlatform())
        let mutationCoordinator = RuntimeMutationCoordinator(
            kernel: kernel,
            effectRunner: effectRunner,
            workspaceManager: workspaceManager
        )
        let refreshProbe = SnapshotRefreshProbe()
        mutationCoordinator.snapshotPublisher = refreshProbe
        let controllerOperations = RuntimeControllerOperations(controller: nil)
        let focusRuntime = FocusRuntime(
            kernel: kernel,
            effectRunner: effectRunner,
            mutationCoordinator: mutationCoordinator,
            controllerOperations: controllerOperations,
            workspaceManager: workspaceManager
        )
        return Fixture(
            focusRuntime: focusRuntime,
            kernel: kernel,
            effectRunner: effectRunner,
            workspaceManager: workspaceManager,
            refreshProbe: refreshProbe
        )
    }

    private func expectRecordedFocusMutation(
        _ fixture: Fixture,
        baseline: TransactionEpoch,
        kindForLog: String,
        source: WMEventSource
    ) {
        guard let transaction = fixture.workspaceManager.lastRecordedTransaction else {
            Issue.record("expected focus reducer mutation to record a transaction")
            return
        }
        #expect(transaction.isCompleted)
        #expect(transaction.transactionEpoch > baseline)
        #expect(fixture.effectRunner.highestAcceptedTransactionEpoch == transaction.transactionEpoch)
        #expect(fixture.refreshProbe.refreshCount > 0)
        guard case let .commandIntent(recordedKind, recordedSource) = transaction.event else {
            Issue.record("expected runtime mutation commandIntent event")
            return
        }
        #expect(recordedKind == kindForLog)
        #expect(recordedSource == source)
    }

    @Test func observedTokenStartsNil() {
        let fixture = makeRuntimeFixture()
        #expect(fixture.focusRuntime.observedToken == nil)
        #expect(fixture.focusRuntime.hasPendingActivation == false)
    }

    @Test func reduceRatchetsEffectRunnerWatermark() {
        let fixture = makeRuntimeFixture()
        let baseline = fixture.effectRunner.highestAcceptedTransactionEpoch

        let workspaceId = WorkspaceDescriptor.ID()
        let logicalId = LogicalWindowId(value: 7)
        _ = fixture.focusRuntime.reduce(
            .activationRequested(
                desired: .logical(logicalId, workspaceId: workspaceId),
                requestId: 1,
                originatingTransactionEpoch: TransactionEpoch(value: 1)
            )
        )

        #expect(fixture.effectRunner.highestAcceptedTransactionEpoch > baseline)
        #expect(fixture.focusRuntime.hasPendingActivation)
        expectRecordedFocusMutation(
            fixture,
            baseline: baseline,
            kindForLog: "focus_reducer",
            source: .focusPolicy
        )
    }

    @Test func reduceReturningActionExposesRecommendedAction() {
        let fixture = makeRuntimeFixture()
        let workspaceId = WorkspaceDescriptor.ID()
        let logicalId = LogicalWindowId(value: 7)
        // Begin a pending activation, then drive an event that recommends
        // an action — scratchpad-hide with a recovery candidate.
        _ = fixture.focusRuntime.reduce(
            .activationRequested(
                desired: .logical(logicalId, workspaceId: workspaceId),
                requestId: 1,
                originatingTransactionEpoch: TransactionEpoch(value: 1)
            )
        )
        let recoveryCandidate = LogicalWindowId(value: 8)
        let baseline = fixture.effectRunner.highestAcceptedTransactionEpoch
        let result = fixture.focusRuntime.reduceReturningAction(
            .scratchpadHideStarted(
                hiddenLogicalId: logicalId,
                wasFocused: true,
                recoveryCandidate: recoveryCandidate,
                workspaceId: workspaceId,
                txn: TransactionEpoch(value: 2)
            )
        )
        #expect(result.changed)
        if case let .requestFocus(id, ws) = result.action {
            #expect(id == recoveryCandidate)
            #expect(ws == workspaceId)
        } else {
            Issue.record("expected .requestFocus recommended action")
        }
        expectRecordedFocusMutation(
            fixture,
            baseline: baseline,
            kindForLog: "focus_reducer",
            source: .focusPolicy
        )
    }

    @Test func activationFailureRecordsTransactionAndRefreshesSnapshot() {
        let fixture = makeRuntimeFixture()
        let baseline = fixture.effectRunner.highestAcceptedTransactionEpoch

        fixture.focusRuntime.recordActivationFailure(reason: .retryExhausted)

        expectRecordedFocusMutation(
            fixture,
            baseline: baseline,
            kindForLog: "focus_activation_failure",
            source: .ax
        )
    }

    @Test func focusedManagedWindowRemovalRecordsTransactionAndRefreshesSnapshot() {
        let fixture = makeRuntimeFixture()
        let baseline = fixture.effectRunner.highestAcceptedTransactionEpoch

        fixture.focusRuntime.recordFocusedManagedWindowRemoved(LogicalWindowId(value: 700))

        expectRecordedFocusMutation(
            fixture,
            baseline: baseline,
            kindForLog: "focus_managed_window_removed",
            source: .ax
        )
    }

    @Test func focusObservationSettledRecordsTransactionAndRefreshesSnapshot() {
        let fixture = makeRuntimeFixture()
        let baseline = fixture.effectRunner.highestAcceptedTransactionEpoch

        fixture.focusRuntime.recordFocusObservationSettled(WindowToken(pid: 7, windowId: 9))

        expectRecordedFocusMutation(
            fixture,
            baseline: baseline,
            kindForLog: "focus_observation_settled",
            source: .ax
        )
    }
}
