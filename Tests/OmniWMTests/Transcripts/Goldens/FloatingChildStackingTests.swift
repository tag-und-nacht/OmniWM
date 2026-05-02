// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct FloatingChildStackingTests {
    @Test @MainActor func transcriptIsGoldenStable() async throws {
        let context = makeTranscriptRuntimeContext()
        let lhs = FloatingChildStackingTranscript.make(in: context)
        let rhs = FloatingChildStackingTranscript.make(in: context)
        #expect(lhs == rhs)
        #expect(lhs.steps.count == 5)
    }

    @Test @MainActor func transcriptRunsCleanlyEndToEnd() async throws {
        let context = makeTranscriptRuntimeContext()
        let transcript = FloatingChildStackingTranscript.make(in: context)

        let driver = TranscriptReplayDriver(
            transcript: transcript,
            runtime: context.runtime,
            platform: context.platform
        )

        try await driver.run()
    }
}
