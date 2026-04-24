// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

/// Owns the inner-gap and outer-gap policy for tiled layouts. Extracted from
/// `WorkspaceManager` (ExecPlan 01, slice WGT-SS-01) so the gap configuration
/// can be reasoned about and tested in isolation. The manager retains
/// read-only forwarders (`gaps`, `outerGaps`) plus mutator methods that
/// invoke this type and fan out the `onGapsChanged` notification.
///
/// Values are in points (AppKit coordinate space). The default inner gap
/// tracks macOS HIG inset spacing; tighter values clip native shadows /
/// borders, looser values look conspicuous at common monitor scales. The
/// upper clamp is a sanity bound, not a hardware limit.
struct GapPolicy: Equatable {
    private static let minGapPoints: Double = 0

    static let defaultInnerGapPoints: Double = 8
    static let maxInnerGapPoints: Double = 64

    private(set) var gaps: Double
    private(set) var outerGaps: LayoutGaps.OuterGaps

    init(
        gaps: Double = GapPolicy.defaultInnerGapPoints,
        outerGaps: LayoutGaps.OuterGaps = .zero
    ) {
        self.gaps = GapPolicy.clampedInnerGap(gaps)
        self.outerGaps = GapPolicy.clampedOuterGaps(outerGaps)
    }

    /// Set the inner gap, clamped into `[0, maxInnerGapPoints]`. Returns
    /// `true` if the stored value changed; callers use this signal to decide
    /// whether to fan out a relayout.
    @discardableResult
    mutating func setGaps(to size: Double) -> Bool {
        let clamped = GapPolicy.clampedInnerGap(size)
        guard clamped != gaps else { return false }
        gaps = clamped
        return true
    }

    /// Set the four outer-gap insets, clamped to `>= 0` per side. Returns
    /// `true` if any side changed.
    @discardableResult
    mutating func setOuterGaps(
        left: Double,
        right: Double,
        top: Double,
        bottom: Double
    ) -> Bool {
        let newGaps = GapPolicy.clampedOuterGaps(
            LayoutGaps.OuterGaps(
                left: CGFloat(left),
                right: CGFloat(right),
                top: CGFloat(top),
                bottom: CGFloat(bottom)
            )
        )
        guard newGaps != outerGaps else { return false }
        outerGaps = newGaps
        return true
    }

    private static func clampedInnerGap(_ value: Double) -> Double {
        max(minGapPoints, min(maxInnerGapPoints, value))
    }

    private static func clampedOuterGaps(
        _ outerGaps: LayoutGaps.OuterGaps
    ) -> LayoutGaps.OuterGaps {
        LayoutGaps.OuterGaps(
            left: max(CGFloat(minGapPoints), outerGaps.left),
            right: max(CGFloat(minGapPoints), outerGaps.right),
            top: max(CGFloat(minGapPoints), outerGaps.top),
            bottom: max(CGFloat(minGapPoints), outerGaps.bottom)
        )
    }
}
