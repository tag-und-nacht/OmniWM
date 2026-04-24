// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

@testable import OmniWM

@MainActor
enum FailedFrameWriteRecoveryTranscript {
    static func make(
        in context: TranscriptRuntimeContext,
        pid: pid_t = 30_020
    ) -> Transcript {
        let workspaceId = context.workspaceId(named: "1")
        let monitorId = context.primaryMonitorId
        let token = WindowToken(pid: pid, windowId: 21)

        var afterFailureExpectation = TranscriptStepExpectation()
        afterFailureExpectation.perStepInvariants = [
            .failedFrameWriteCannotConfirmFrame,
            .workspaceGraphValidates
        ]

        let stampedEpoch = TransactionEpoch(value: 1)

        let failedConfirmation = WMEffectConfirmation.axFrameWriteOutcome(
            token: token,
            axFailure: .verificationMismatch,
            source: .ax,
            originatingTransactionEpoch: stampedEpoch
        )
        let successConfirmation = WMEffectConfirmation.axFrameWriteOutcome(
            token: token,
            axFailure: nil,
            source: .ax,
            originatingTransactionEpoch: TransactionEpoch(value: 2)
        )

        return Transcript.make(name: "failed-frame-write-recovery") { builder in
            builder
                .event(.windowAdmitted(
                    token: token,
                    workspaceId: workspaceId,
                    monitorId: monitorId,
                    mode: .tiling,
                    source: .ax
                ))
                .effectConfirmation(
                    failedConfirmation,
                    expectation: afterFailureExpectation
                )
                .effectConfirmation(successConfirmation)
                .expectFinal(TranscriptExpectations(
                    customAssertions: [.workspaceGraphValidates]
                ))
        }
    }
}
