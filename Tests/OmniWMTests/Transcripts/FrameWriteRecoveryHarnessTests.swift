// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct FrameWriteRecoveryHarnessTests {
    @Test @MainActor func harnessReturnsExpectedStepShape() async throws {
        let token = WindowToken(pid: 30_050, windowId: 51)
        let steps = FrameWriteRecoveryHarness.failureThenRecovery(token: token)

        #expect(steps.count == 2)

        guard case .effectConfirmation = steps[0].kind else {
            Issue.record("expected first step to be effectConfirmation")
            return
        }
        guard case .effectConfirmation = steps[1].kind else {
            Issue.record("expected second step to be effectConfirmation")
            return
        }
    }

    @Test @MainActor func harnessIntegratesWithDriver() async throws {
        let context = makeTranscriptRuntimeContext()
        let token = WindowToken(pid: 30_050, windowId: 52)

        let admit = TranscriptStep(kind: .event(.windowAdmitted(
            token: token,
            workspaceId: context.workspaceId(named: "1"),
            monitorId: context.primaryMonitorId,
            mode: .tiling,
            source: .ax
        )))

        let recoverySteps = FrameWriteRecoveryHarness.failureThenRecovery(token: token)
        let allSteps = [admit] + recoverySteps

        let transcript = Transcript(
            name: "frame-recovery-integration",
            initialMonitors: [],
            initialWorkspaces: [],
            steps: allSteps,
            finalExpectations: TranscriptExpectations(
                customAssertions: [.workspaceGraphValidates]
            )
        )

        let driver = TranscriptReplayDriver(
            transcript: transcript,
            runtime: context.runtime,
            platform: context.platform
        )

        try await driver.run()
    }
}
