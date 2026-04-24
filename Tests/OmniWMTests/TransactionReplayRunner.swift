// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@testable import OmniWM

@MainActor
final class TransactionReplayRunner {
    enum Step: Equatable {
        case event(WMEvent)
        case command(WMCommand)
    }

    struct Outcome {
        let step: Step
        let transactionEpoch: TransactionEpoch
        let transaction: Transaction?
        let platformEventsAfter: [RecordingEffectPlatform.Event]
    }

    struct InvariantViolation: Error, Equatable {
        let stepIndex: Int
        let message: String
    }

    private let runtime: WMRuntime
    private let platform: RecordingEffectPlatform
    private(set) var outcomes: [Outcome] = []
    private var lastTransactionEpoch: TransactionEpoch = .invalid

    init(runtime: WMRuntime, platform: RecordingEffectPlatform) {
        self.runtime = runtime
        self.platform = platform
    }

    func replay(_ steps: [Step]) throws {
        for (index, step) in steps.enumerated() {
            let outcome = process(step)
            try validate(outcome: outcome, index: index)
            outcomes.append(outcome)
            lastTransactionEpoch = outcome.transactionEpoch
        }
    }

    private func process(_ step: Step) -> Outcome {
        switch step {
        case let .event(event):
            let beforeCount = platform.events.count
            let txn = runtime.submit(event)
            let delta = Array(platform.events[beforeCount..<platform.events.count])
            return Outcome(
                step: step,
                transactionEpoch: txn.transactionEpoch,
                transaction: txn,
                platformEventsAfter: delta
            )

        case let .command(command):
            let beforeCount = platform.events.count
            let result = runtime.submit(command: command)
            let delta = Array(platform.events[beforeCount..<platform.events.count])
            return Outcome(
                step: step,
                transactionEpoch: result.transactionEpoch,
                transaction: result.transaction,
                platformEventsAfter: delta
            )
        }
    }

    static func validateForTests(
        outcome: Outcome,
        index: Int,
        previousTransactionEpoch: TransactionEpoch
    ) throws {
        try validateInternal(
            outcome: outcome,
            index: index,
            previousTransactionEpoch: previousTransactionEpoch
        )
    }

    private func validate(outcome: Outcome, index: Int) throws {
        try Self.validateInternal(
            outcome: outcome,
            index: index,
            previousTransactionEpoch: lastTransactionEpoch
        )
    }

    private static func validateInternal(
        outcome: Outcome,
        index: Int,
        previousTransactionEpoch: TransactionEpoch
    ) throws {
        guard outcome.transactionEpoch.isValid else {
            throw InvariantViolation(
                stepIndex: index,
                message: "transaction epoch was not stamped by WMRuntime"
            )
        }
        if previousTransactionEpoch.isValid,
           outcome.transactionEpoch <= previousTransactionEpoch
        {
            throw InvariantViolation(
                stepIndex: index,
                message: "transaction epoch did not strictly increase (\(previousTransactionEpoch) -> \(outcome.transactionEpoch))"
            )
        }
        if let transaction = outcome.transaction {
            if transaction.transactionEpoch != outcome.transactionEpoch {
                throw InvariantViolation(
                    stepIndex: index,
                    message: "transaction epoch mismatch"
                )
            }
            var previous: EffectEpoch = .invalid
            for effect in transaction.effects {
                guard effect.epoch.isValid else {
                    throw InvariantViolation(
                        stepIndex: index,
                        message: "effect epoch was not stamped by WMRuntime"
                    )
                }
                if previous.isValid, !(previous < effect.epoch) {
                    throw InvariantViolation(
                        stepIndex: index,
                        message: "effect epochs must strictly increase within a plan"
                    )
                }
                previous = effect.epoch
            }
            if !transaction.invariantViolations.isEmpty {
                let summary = transaction.invariantViolations
                    .map { "[\($0.code)] \($0.message)" }
                    .joined(separator: "; ")
                throw InvariantViolation(
                    stepIndex: index,
                    message: "Transaction carried invariant violations: \(summary)"
                )
            }
        }
    }
}
