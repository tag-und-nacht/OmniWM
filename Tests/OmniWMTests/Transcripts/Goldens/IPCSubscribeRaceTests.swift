// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OmniWMIPC
import Testing

@testable import OmniWM

@Suite(.serialized) struct IPCSubscribeRaceTests {
    @Test @MainActor func initialSnapshotPrecedesPostChangeStream() async throws {
        let context = makeTranscriptRuntimeContext()

        let observation = await IPCSubscribeRaceTranscript.runRace(
            in: context,
            channel: .activeWorkspace
        )

        #expect(!observation.initialEnvelopes.isEmpty)
        #expect(observation.liveEnvelopes.count <= 1)
    }

    @Test @MainActor func subscribeRaceTranscriptMonotonicEpochs() async throws {
        let context = makeTranscriptRuntimeContext()
        let watermarkBefore = context.runtime.currentEffectRunnerWatermark

        _ = await IPCSubscribeRaceTranscript.runRace(in: context, channel: .activeWorkspace)

        let watermarkAfter = context.runtime.currentEffectRunnerWatermark
        #expect(watermarkAfter.value >= watermarkBefore.value)
    }
}
