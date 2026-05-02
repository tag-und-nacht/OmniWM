// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct DwindleGestureTests {
    @Test @MainActor func transcriptIsGoldenStable() async throws {
        let context = makeTranscriptRuntimeContext(layouts: ["1": .dwindle])
        let lhs = DwindleGestureTranscript.make(in: context)
        let rhs = DwindleGestureTranscript.make(in: context)
        #expect(lhs == rhs)
        #expect(lhs.steps.count == 3)
    }

    @Test @MainActor func transcriptRunsCleanlyEndToEnd() async throws {
        let context = makeTranscriptRuntimeContext(layouts: ["1": .dwindle])
        let transcript = DwindleGestureTranscript.make(in: context)

        let driver = TranscriptReplayDriver(
            transcript: transcript,
            runtime: context.runtime,
            platform: context.platform
        )

        try await driver.run()
    }
}
