// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OmniWMIPC
import Testing

@testable import OmniWM

@Suite(.serialized) struct TranscriptDriverTests {
    @Test @MainActor func driverDrivesEventThroughRunnerAndAdvancesEpoch() async throws {
        let transcript = Transcript.make(name: "epoch") { builder in
            builder.event(.activeSpaceChanged(source: .workspaceManager))
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        try await driver.run()

        #expect(driver.runner.outcomes.count == 1)
        #expect(driver.runner.outcomes[0].transactionEpoch.value == 1)
    }

    @Test @MainActor func driverDuplicatePerturbationFiresEventTwice() async throws {
        let transcript = Transcript.make(name: "dup") { builder in
            builder.event(
                .activeSpaceChanged(source: .workspaceManager),
                perturbation: .duplicate
            )
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        try await driver.run()

        #expect(driver.runner.outcomes.count == 2)
        let epochs = driver.runner.outcomes.map(\.transactionEpoch.value)
        #expect(epochs == [1, 2])
    }

    @Test @MainActor func driverDropPerturbationProducesZeroOutcomes() async throws {
        let transcript = Transcript.make(name: "drop") { builder in
            builder
                .event(
                    .activeSpaceChanged(source: .workspaceManager),
                    perturbation: .drop
                )
                .event(.systemSleep(source: .service))
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        try await driver.run()

        #expect(driver.runner.outcomes.count == 1)
        #expect(driver.runner.outcomes[0].transactionEpoch.value == 1)
    }

    @Test @MainActor func driverTransactionEffectsMatcherChecksKindContains() async throws {
        var stepExpectation = TranscriptStepExpectation()
        stepExpectation.transactionEffects = TranscriptTransactionEffectsMatcher(
            expectedKinds: ["activate_target_workspace"],
            mode: .containsInOrder
        )

        let transcript = Transcript.make(name: "matcher-ok") { builder in
            builder.command(
                .workspaceSwitch(.explicit(rawWorkspaceID: "2")),
                expectation: stepExpectation
            )
        }
        let driver = TranscriptReplayDriver(transcript: transcript)
        try await driver.run()

        #expect(driver.runner.outcomes.count == 1)
    }

    @Test @MainActor func driverTransactionEffectsMatcherFailsOnMissingKind() async throws {
        var stepExpectation = TranscriptStepExpectation()
        stepExpectation.transactionEffects = TranscriptTransactionEffectsMatcher(
            expectedKinds: ["bogus_effect_kind_that_does_not_exist"],
            mode: .containsInOrder
        )

        let transcript = Transcript.make(name: "matcher-fail") { builder in
            builder.command(
                .workspaceSwitch(.explicit(rawWorkspaceID: "2")),
                expectation: stepExpectation
            )
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        do {
            try await driver.run()
            Issue.record("expected TranscriptViolation")
        } catch let violation as TranscriptReplayDriver.TranscriptViolation {
            #expect(violation.phase == .transactionEffects)
            #expect(violation.stepIndex == 0)
        }
    }

    @Test @MainActor func driverPerStepInvariantRunsAfterEachStep() async throws {
        var stepExpectation = TranscriptStepExpectation()
        stepExpectation.perStepInvariants = [.workspaceGraphValidates]

        let transcript = Transcript.make(name: "invariant") { builder in
            builder.event(
                .activeSpaceChanged(source: .workspaceManager),
                expectation: stepExpectation
            )
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        try await driver.run()
    }

    @Test @MainActor func driverFinalAssertionTopologyAdvanced() async throws {
        let transcript = Transcript.make(name: "topo-final") { builder in
            builder
                .displayDelta(monitorsAfter: [.primary, .secondary])
                .expectFinal(TranscriptExpectations(topologyEpochStrictlyAdvanced: true))
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        try await driver.run()
    }

    @Test @MainActor func driverFinalAssertionWorkspaceCount() async throws {
        let transcript = Transcript.make(name: "ws-count") { builder in
            builder.expectFinal(TranscriptExpectations(workspaceCount: 2))
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        try await driver.run()
    }

    @Test @MainActor func driverFinalAssertionWorkspaceCountMismatchThrows() async throws {
        let transcript = Transcript.make(name: "ws-count-fail") { builder in
            builder.expectFinal(TranscriptExpectations(workspaceCount: 99))
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        do {
            try await driver.run()
            Issue.record("expected final assertion failure")
        } catch let violation as TranscriptReplayDriver.TranscriptViolation {
            #expect(violation.phase == .final)
            #expect(violation.stepIndex == nil)
            #expect(violation.message.contains("workspace count"))
        }
    }

    @Test @MainActor func driverWrappingPreservesPhase1EpochValidation() async throws {
        let transcript = Transcript.make(name: "underlying") { builder in
            builder.command(.workspaceSwitch(.explicit(rawWorkspaceID: "2")))
        }
        let driver = TranscriptReplayDriver(transcript: transcript)
        try await driver.run()

        let drifted = TransactionReplayRunner.Outcome(
            step: .command(.workspaceSwitch(.explicit(rawWorkspaceID: "ignored"))),
            transactionEpoch: TransactionEpoch(value: 99),
            transaction: Transaction(
                transactionEpoch: TransactionEpoch(value: 100),
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

    @Test @MainActor func driverDelayedAdmissionDefersUntilNextStep() async throws {
        let transcript = Transcript.make(name: "delayed") { builder in
            builder
                .event(
                    .activeSpaceChanged(source: .workspaceManager),
                    perturbation: .delayedAdmission
                )
                .event(.systemSleep(source: .service))
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        try await driver.run()

        #expect(driver.runner.outcomes.count == 2)
    }

    @Test @MainActor func driverReorderWithOffsetOneSwapsAdjacentSteps() async throws {
        let transcript = Transcript.make(name: "reorder-1") { builder in
            builder
                .event(
                    .systemSleep(source: .service),
                    perturbation: .reorderWith(1)
                )
                .event(.systemWake(source: .service))
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        try await driver.run()

        #expect(driver.runner.outcomes.count == 2)
        guard
            case let .event(first) = driver.runner.outcomes[0].step,
            case let .event(second) = driver.runner.outcomes[1].step
        else {
            Issue.record("expected both outcomes to be event steps")
            return
        }
        if case .systemWake = first {
        } else {
            Issue.record("expected first outcome to be systemWake; got \(first)")
        }
        if case .systemSleep = second {
        } else {
            Issue.record("expected second outcome to be systemSleep; got \(second)")
        }
    }

    @Test @MainActor func driverReorderWithOffsetTwoSwapsNonAdjacent() async throws {
        let transcript = Transcript.make(name: "reorder-2") { builder in
            builder
                .event(
                    .systemSleep(source: .service),
                    perturbation: .reorderWith(2)
                )
                .event(.activeSpaceChanged(source: .workspaceManager))
                .event(.systemWake(source: .service))
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        try await driver.run()

        #expect(driver.runner.outcomes.count == 3)
        guard
            case let .event(o0) = driver.runner.outcomes[0].step,
            case let .event(o1) = driver.runner.outcomes[1].step,
            case let .event(o2) = driver.runner.outcomes[2].step
        else {
            Issue.record("expected all outcomes to be event steps")
            return
        }
        if case .systemWake = o0 {} else {
            Issue.record("expected outcome[0]=systemWake; got \(o0)")
        }
        if case .activeSpaceChanged = o1 {} else {
            Issue.record("expected outcome[1]=activeSpaceChanged; got \(o1)")
        }
        if case .systemSleep = o2 {} else {
            Issue.record("expected outcome[2]=systemSleep; got \(o2)")
        }
    }

    @Test @MainActor func driverReorderWithOutOfBoundsOffsetThrows() async throws {
        let transcript = Transcript.make(name: "reorder-oob") { builder in
            builder
                .event(
                    .systemSleep(source: .service),
                    perturbation: .reorderWith(99)
                )
                .event(.systemWake(source: .service))
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        do {
            try await driver.run()
            Issue.record("expected TranscriptViolation for out-of-bounds reorderWith")
        } catch let violation as TranscriptReplayDriver.TranscriptViolation {
            #expect(violation.phase == .perturbation)
            #expect(violation.stepIndex == 0)
            #expect(violation.message.contains("past end of step list"))
        }
    }

    @Test @MainActor func driverReorderWithNonPositiveOffsetThrows() async throws {
        let transcript = Transcript.make(name: "reorder-zero") { builder in
            builder
                .event(
                    .systemSleep(source: .service),
                    perturbation: .reorderWith(0)
                )
                .event(.systemWake(source: .service))
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        do {
            try await driver.run()
            Issue.record("expected TranscriptViolation for zero-offset reorderWith")
        } catch let violation as TranscriptReplayDriver.TranscriptViolation {
            #expect(violation.phase == .perturbation)
            #expect(violation.stepIndex == 0)
            #expect(violation.message.contains("must be > 0"))
        }
    }
}
