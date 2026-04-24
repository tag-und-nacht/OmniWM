// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct NativeFullscreenReplacementRestoreTests {
    @Test @MainActor func transcriptIsGoldenStable() async throws {
        let context = makeTranscriptRuntimeContext()
        let lhs = NativeFullscreenReplacementRestoreTranscript.make(in: context)
        let rhs = NativeFullscreenReplacementRestoreTranscript.make(in: context)
        #expect(lhs == rhs)
        #expect(lhs.name == "native-fullscreen-replacement-restore")
        #expect(lhs.steps.count == 6)
    }

    @Test @MainActor func transcriptRunsCleanlyEndToEnd() async throws {
        let context = makeTranscriptRuntimeContext()
        let transcript = NativeFullscreenReplacementRestoreTranscript.make(in: context)

        let driver = TranscriptReplayDriver(
            transcript: transcript,
            runtime: context.runtime,
            platform: context.platform
        )

        try await driver.run()

        #expect(driver.runner.outcomes.count == 6)
    }
}
