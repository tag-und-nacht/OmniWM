// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Testing
@testable import OmniWM

@Suite("GapPolicy")
struct GapPolicyTests {
    @Test func defaultsMatchHIGInsetAndZeroOuter() {
        let policy = GapPolicy()
        #expect(policy.gaps == GapPolicy.defaultInnerGapPoints)
        #expect(policy.outerGaps == .zero)
    }

    @Test func setGapsClampsToBounds() {
        var policy = GapPolicy()

        #expect(policy.setGaps(to: -10) == true)
        #expect(policy.gaps == 0)

        #expect(policy.setGaps(to: 1000) == true)
        #expect(policy.gaps == GapPolicy.maxInnerGapPoints)

        #expect(policy.setGaps(to: 12) == true)
        #expect(policy.gaps == 12)
    }

    @Test func setGapsReturnsFalseWhenUnchanged() {
        var policy = GapPolicy()
        _ = policy.setGaps(to: 12)
        #expect(policy.setGaps(to: 12) == false)
    }

    @Test func setGapsEqualClampedReturnsFalseEvenWithRawDifferentValue() {
        var policy = GapPolicy(gaps: GapPolicy.maxInnerGapPoints)
        // Raw 1000 clamps to maxInnerGapPoints; already at that value, so no change.
        #expect(policy.setGaps(to: 1000) == false)
    }

    @Test func setOuterGapsClampsNegativeSidesToZero() {
        var policy = GapPolicy()
        #expect(policy.setOuterGaps(left: -5, right: -5, top: -5, bottom: -5) == false)
        #expect(policy.outerGaps == .zero)
    }

    @Test func setOuterGapsAcceptsAllFourSides() {
        var policy = GapPolicy()
        #expect(policy.setOuterGaps(left: 1, right: 2, top: 3, bottom: 4) == true)
        #expect(policy.outerGaps.left == 1)
        #expect(policy.outerGaps.right == 2)
        #expect(policy.outerGaps.top == 3)
        #expect(policy.outerGaps.bottom == 4)
    }

    @Test func setOuterGapsReturnsFalseWhenUnchanged() {
        var policy = GapPolicy()
        _ = policy.setOuterGaps(left: 1, right: 2, top: 3, bottom: 4)
        #expect(policy.setOuterGaps(left: 1, right: 2, top: 3, bottom: 4) == false)
    }

    @Test func explicitInitClampsInputGaps() {
        let policy = GapPolicy(gaps: -1, outerGaps: .zero)
        #expect(policy.gaps == 0)

        let upper = GapPolicy(gaps: 1000, outerGaps: .zero)
        #expect(upper.gaps == GapPolicy.maxInnerGapPoints)
    }

    @Test func explicitInitClampsOuterGaps() {
        let policy = GapPolicy(
            outerGaps: LayoutGaps.OuterGaps(
                left: -1,
                right: 2,
                top: -3,
                bottom: 4
            )
        )

        #expect(policy.outerGaps.left == 0)
        #expect(policy.outerGaps.right == 2)
        #expect(policy.outerGaps.top == 0)
        #expect(policy.outerGaps.bottom == 4)
    }
}
