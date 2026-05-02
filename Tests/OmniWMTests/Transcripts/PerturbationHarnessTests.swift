// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct PerturbationHarnessTests {
    @Test @MainActor func enumeratedRunsCleanForCanonicalVocabulary() async throws {
        let harness = PerturbationHarness()
        try await harness.runEnumerated()
    }

    @Test @MainActor func propertyRunsCleanForFixedSeed() async throws {
        let harness = PerturbationHarness(seed: 0xC0FFEE)
        try await harness.runPropertyOverFixedSeed(length: 3, count: 16)
    }

    @Test @MainActor func dropPerturbationKeepsRunnerOutcomesAtZeroForThatStep() async throws {
        let transcript = Transcript.make(name: "verify-drop") { builder in
            builder
                .event(
                    .activeSpaceChanged(source: .workspaceManager),
                    perturbation: .drop
                )
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        try await driver.run()

        #expect(driver.runner.outcomes.isEmpty)
    }

    @Test @MainActor func duplicatePerturbationProducesTwoOutcomes() async throws {
        let transcript = Transcript.make(name: "verify-duplicate") { builder in
            builder.event(
                .activeSpaceChanged(source: .workspaceManager),
                perturbation: .duplicate
            )
        }
        let driver = TranscriptReplayDriver(transcript: transcript)

        try await driver.run()

        #expect(driver.runner.outcomes.count == 2)
    }

    @Test @MainActor func reorderWithIsCoveredByCanonicalPerturbationSet() async throws {
        let kinds = PerturbationHarness.perturbations
        let hasOffsetOne = kinds.contains { kind in
            if case .reorderWith(1) = kind { return true } else { return false }
        }
        let hasOffsetTwo = kinds.contains { kind in
            if case .reorderWith(2) = kind { return true } else { return false }
        }
        #expect(hasOffsetOne, "expected .reorderWith(1) in PerturbationHarness.perturbations")
        #expect(hasOffsetTwo, "expected .reorderWith(2) in PerturbationHarness.perturbations")
    }
}
