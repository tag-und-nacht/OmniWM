// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct MonitorRebindReconnectTests {
    @Test @MainActor func transcriptIsGoldenStable() async throws {
        let context = makeTranscriptRuntimeContext(
            workspaceNames: ["1", "2"],
            monitorSpecs: [
                MonitorRebindReconnectTranscript.primarySpec,
                MonitorRebindReconnectTranscript.secondarySpec
            ]
        )
        let lhs = MonitorRebindReconnectTranscript.make(in: context)
        let rhs = MonitorRebindReconnectTranscript.make(in: context)
        #expect(lhs == rhs)
        #expect(lhs.steps.count == 3)
    }

    @Test @MainActor func transcriptRunsCleanlyEndToEnd() async throws {
        let context = makeTranscriptRuntimeContext(
            workspaceNames: ["1", "2"],
            monitorSpecs: [
                MonitorRebindReconnectTranscript.primarySpec,
                MonitorRebindReconnectTranscript.secondarySpec
            ]
        )
        let transcript = MonitorRebindReconnectTranscript.make(in: context)

        let driver = TranscriptReplayDriver(
            transcript: transcript,
            runtime: context.runtime,
            platform: context.platform
        )

        try await driver.run()
    }
}
