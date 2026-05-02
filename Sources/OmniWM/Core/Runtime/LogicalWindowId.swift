// SPDX-License-Identifier: GPL-2.0-only
import Foundation

struct LogicalWindowId: Hashable, Sendable, CustomStringConvertible {
    let value: UInt64

    static let invalid = LogicalWindowId(value: 0)

    init(value: UInt64) {
        self.value = value
    }

    var isValid: Bool { value != 0 }

    var description: String {
        "lwid#\(value)"
    }
}

struct ReplacementEpoch: Hashable, Comparable, Sendable, CustomStringConvertible {
    let value: UInt32

    static let invalid = ReplacementEpoch(value: UInt32.max)

    init(value: UInt32) {
        self.value = value
    }

    var isValid: Bool { value != UInt32.max }

    static func < (lhs: ReplacementEpoch, rhs: ReplacementEpoch) -> Bool {
        lhs.value < rhs.value
    }

    var description: String {
        "repl#\(value)"
    }
}
