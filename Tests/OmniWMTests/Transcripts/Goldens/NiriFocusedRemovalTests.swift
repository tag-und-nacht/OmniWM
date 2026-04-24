// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct NiriFocusedRemovalTests {
    @Test @MainActor func transcriptIsGoldenStable() async throws {
        let context = makeTranscriptRuntimeContext(layouts: ["1": .niri])
        let lhs = NiriFocusedRemovalTranscript.make(in: context)
        let rhs = NiriFocusedRemovalTranscript.make(in: context)
        #expect(lhs == rhs)
        #expect(lhs.steps.count == 4)
    }

    @Test @MainActor func transcriptRunsCleanlyEndToEnd() async throws {
        let context = makeTranscriptRuntimeContext(layouts: ["1": .niri])
        let transcript = NiriFocusedRemovalTranscript.make(in: context)

        let driver = TranscriptReplayDriver(
            transcript: transcript,
            runtime: context.runtime,
            platform: context.platform
        )

        try await driver.run()
    }
}
