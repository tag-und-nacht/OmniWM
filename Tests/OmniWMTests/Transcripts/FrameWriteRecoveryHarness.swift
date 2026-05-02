// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

@testable import OmniWM

@MainActor
enum FrameWriteRecoveryHarness {
    static func failureThenRecovery(
        token: WindowToken,
        failureReason: AXFrameWriteFailureReason = .verificationMismatch,
        failureEpoch: TransactionEpoch = TransactionEpoch(value: 1),
        recoveryEpoch: TransactionEpoch = TransactionEpoch(value: 2)
    ) -> [TranscriptStep] {
        var failedStepExpectation = TranscriptStepExpectation()
        failedStepExpectation.perStepInvariants = [
            .failedFrameWriteCannotConfirmFrame,
            .workspaceGraphValidates
        ]

        let failedConfirmation = WMEffectConfirmation.axFrameWriteOutcome(
            token: token,
            axFailure: failureReason,
            source: .ax,
            originatingTransactionEpoch: failureEpoch
        )
        let recoveryConfirmation = WMEffectConfirmation.axFrameWriteOutcome(
            token: token,
            axFailure: nil,
            source: .ax,
            originatingTransactionEpoch: recoveryEpoch
        )

        return [
            TranscriptStep(
                kind: .effectConfirmation(failedConfirmation),
                perturbation: .none,
                expectation: failedStepExpectation
            ),
            TranscriptStep(
                kind: .effectConfirmation(recoveryConfirmation),
                perturbation: .none
            )
        ]
    }
}
