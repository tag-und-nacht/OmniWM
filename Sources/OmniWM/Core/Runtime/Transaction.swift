// SPDX-License-Identifier: GPL-2.0-only
import Foundation

/// A single ordered commit through the runtime.
///
/// `Transaction` is the sole envelope for both sides of the commit: the
/// triggering event and reconcile action plan, the runtime effects selected
/// for that event, and the post-apply snapshot/violations recorded once the
/// effect runner completes. The post-apply fields are mutable so callers can
/// construct the transaction before effect dispatch and let `WMEffectRunner`
/// stamp the final snapshot at the transaction boundary.
struct Transaction: Equatable {
    let timestamp: Date
    let event: WMEvent
    let normalizedEvent: WMEvent
    var plan: ActionPlan
    let transactionEpoch: TransactionEpoch
    var effects: [WMEffect]
    var snapshot: ReconcileSnapshot
    var invariantViolations: [ReconcileInvariantViolation]
    private(set) var isCompleted: Bool

    static let empty = Transaction(
        timestamp: Date(timeIntervalSinceReferenceDate: 0),
        event: .commandIntent(kindForLog: "empty", source: .command),
        normalizedEvent: .commandIntent(kindForLog: "empty", source: .command),
        transactionEpoch: .invalid,
        effects: [],
        snapshot: .empty,
        invariantViolations: []
    )

    var hasNoEffects: Bool { effects.isEmpty }

    init(
        timestamp: Date = Date(),
        event: WMEvent,
        normalizedEvent: WMEvent? = nil,
        plan: ActionPlan = ActionPlan(),
        transactionEpoch: TransactionEpoch,
        effects: [WMEffect] = [],
        snapshot: ReconcileSnapshot,
        invariantViolations: [ReconcileInvariantViolation] = [],
        isCompleted: Bool = false
    ) {
        self.timestamp = timestamp
        self.event = event
        self.normalizedEvent = normalizedEvent ?? event
        self.plan = plan
        self.transactionEpoch = transactionEpoch
        self.effects = effects
        self.snapshot = snapshot
        self.invariantViolations = invariantViolations
        self.isCompleted = isCompleted
    }

    var summary: String {
        if effects.isEmpty {
            return "transaction \(transactionEpoch) empty"
        }
        let joined = effects
            .map { "\($0.kind)@\($0.epoch.value)" }
            .joined(separator: ",")
        return "transaction \(transactionEpoch) effects=[\(joined)]"
    }

    func completed(
        snapshot: ReconcileSnapshot,
        invariantViolations: [ReconcileInvariantViolation]
    ) -> Transaction {
        var transaction = self
        transaction.snapshot = snapshot
        transaction.invariantViolations = invariantViolations
        transaction.isCompleted = true
        return transaction
    }
}

extension ReconcileSnapshot {
    static let empty = ReconcileSnapshot(
        topologyProfile: TopologyProfile(monitors: []),
        focusSession: FocusSessionSnapshot(
            focusedToken: nil,
            pendingManagedFocus: .empty,
            focusLease: nil,
            isNonManagedFocusActive: false,
            isAppFullscreenActive: false,
            interactionMonitorId: nil,
            previousInteractionMonitorId: nil
        ),
        windows: [],
        workspaceGraph: .empty
    )
}
