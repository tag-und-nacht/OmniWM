// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct TransactionTests {
    @Test func emptyTransactionHasInvalidEpochAndNoEffects() {
        let transaction = Transaction.empty
        #expect(transaction.hasNoEffects)
        #expect(transaction.effects.isEmpty)
        #expect(transaction.transactionEpoch == .invalid)
    }

    @Test func effectEpochsAreMonotonicallyComparable() {
        let a = EffectEpoch(value: 1)
        let b = EffectEpoch(value: 2)
        #expect(a < b)
        #expect(!(b < a))
        #expect(a != b)
        #expect(!EffectEpoch.invalid.isValid)
        #expect(EffectEpoch(value: 7).isValid)
    }

    @Test func transactionEpochsAreMonotonicallyComparable() {
        let a = TransactionEpoch(value: 1)
        let b = TransactionEpoch(value: 2)
        #expect(a < b)
        #expect(a.isValid)
        #expect(!TransactionEpoch.invalid.isValid)
    }

    @Test func transactionSummaryReportsEpochsAndEffectKinds() {
        let transaction = Transaction(
            transactionEpoch: TransactionEpoch(value: 4),
            effects: [
                .hideKeyboardFocusBorder(
                    reason: "switch workspace",
                    epoch: EffectEpoch(value: 10)
                ),
                .syncMonitorsToNiri(
                    epoch: EffectEpoch(value: 11)
                )
            ]
        )
        let summary = transaction.summary
        #expect(summary.contains("txn#4"))
        #expect(summary.contains("hide_keyboard_focus_border@10"))
        #expect(summary.contains("sync_monitors_to_niri@11"))
    }

    @Test func effectEpochAccessorReturnsEmbeddedEpoch() {
        let effects: [WMEffect] = [
            .hideKeyboardFocusBorder(reason: "r", epoch: EffectEpoch(value: 1)),
            .syncMonitorsToNiri(epoch: EffectEpoch(value: 2))
        ]
        #expect(effects[0].epoch == EffectEpoch(value: 1))
        #expect(effects[1].epoch == EffectEpoch(value: 2))
        #expect(effects[0].kind == "hide_keyboard_focus_border")
    }
}
