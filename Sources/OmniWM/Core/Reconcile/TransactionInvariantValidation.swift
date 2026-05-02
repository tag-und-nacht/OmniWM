// SPDX-License-Identifier: GPL-2.0-only
import Foundation

extension Transaction {
    /// Mark a transaction complete at a specific reconcile snapshot boundary.
    func completedWithValidatedSnapshot(_ snapshot: ReconcileSnapshot) -> Transaction {
        completed(
            snapshot: snapshot,
            invariantViolations: InvariantChecks.validate(snapshot: snapshot)
        )
    }
}
