// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing
@testable import OmniWM

@Suite("FocusStateLedger")
struct FocusStateLedgerTests {
    private let workspaceA = WorkspaceDescriptor.ID()
    private let logicalA = LogicalWindowId(value: 7)

    @Test func defaultStateIsInitial() {
        let ledger = FocusStateLedger()
        #expect(ledger.state == .initial)
        #expect(ledger.observedToken == nil)
        #expect(ledger.hasPendingActivation == false)
        #expect(ledger.desired == .none)
    }

    @Test func reduceActivationRequestedSetsPending() {
        var ledger = FocusStateLedger()
        let reduction = ledger.reduce(
            .activationRequested(
                desired: .logical(logicalA, workspaceId: workspaceA),
                requestId: 42,
                originatingTransactionEpoch: TransactionEpoch(value: 5)
            )
        )

        #expect(reduction.didChange)
        #expect(ledger.hasPendingActivation)
        if case let .logical(id, ws) = ledger.desired {
            #expect(id == logicalA)
            #expect(ws == workspaceA)
        } else {
            Issue.record("expected .logical desired focus")
        }
    }

    @Test func clearObservedAndActivationDirectResetsBoth() {
        var ledger = FocusStateLedger()
        _ = ledger.reduce(
            .activationRequested(
                desired: .logical(logicalA, workspaceId: workspaceA),
                requestId: 1,
                originatingTransactionEpoch: TransactionEpoch(value: 1)
            )
        )
        _ = ledger.reduce(
            .activationConfirmed(
                observedToken: WindowToken(pid: 99, windowId: 1234),
                observedAt: TransactionEpoch(value: 2)
            )
        )
        #expect(ledger.observedToken != nil)

        ledger.clearObservedAndActivation()
        #expect(ledger.observedToken == nil)
        #expect(ledger.hasPendingActivation == false)
        if case .idle = ledger.state.activation {
            // expected
        } else {
            Issue.record("expected .idle activation after clear")
        }
    }

    @Test func reducerSupersessionDropsStaleEvents() {
        var ledger = FocusStateLedger()
        // Begin pending activation at epoch 10.
        _ = ledger.reduce(
            .activationRequested(
                desired: .logical(logicalA, workspaceId: workspaceA),
                requestId: 1,
                originatingTransactionEpoch: TransactionEpoch(value: 10)
            )
        )
        // Stale cancel from epoch 5 must not wipe the pending.
        let stale = ledger.reduce(.activationCancelled(txn: TransactionEpoch(value: 5)))
        #expect(!stale.didChange)
        #expect(ledger.hasPendingActivation)
    }

    @Test func reducerSupersessionAcceptsCurrentEpochCancel() {
        var ledger = FocusStateLedger()
        _ = ledger.reduce(
            .activationRequested(
                desired: .logical(logicalA, workspaceId: workspaceA),
                requestId: 1,
                originatingTransactionEpoch: TransactionEpoch(value: 10)
            )
        )
        let current = ledger.reduce(.activationCancelled(txn: TransactionEpoch(value: 10)))
        #expect(current.didChange)
        #expect(!ledger.hasPendingActivation)
    }
}
