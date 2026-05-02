// SPDX-License-Identifier: GPL-2.0-only
import Foundation

struct TransactionEpoch: Hashable, Comparable, Sendable, CustomStringConvertible {
    let value: UInt64

    static let invalid = TransactionEpoch(value: 0)

    init(value: UInt64) {
        self.value = value
    }

    var isValid: Bool {
        value != 0
    }

    static func < (lhs: TransactionEpoch, rhs: TransactionEpoch) -> Bool {
        lhs.value < rhs.value
    }

    var description: String {
        "txn#\(value)"
    }
}

struct EffectEpoch: Hashable, Comparable, Sendable, CustomStringConvertible {
    let value: UInt64

    static let invalid = EffectEpoch(value: 0)

    init(value: UInt64) {
        self.value = value
    }

    var isValid: Bool {
        value != 0
    }

    static func < (lhs: EffectEpoch, rhs: EffectEpoch) -> Bool {
        lhs.value < rhs.value
    }

    var description: String {
        "fx#\(value)"
    }
}
