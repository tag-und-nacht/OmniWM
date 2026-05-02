// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing
@testable import OmniWM

@Suite("WindowConstraintCache")
struct WindowConstraintCacheTests {
    private let tokenA = WindowToken(pid: 100, windowId: 200)
    private let tokenB = WindowToken(pid: 100, windowId: 300)

    private func makeConstraints(min: CGSize, max: CGSize) -> WindowSizeConstraints {
        WindowSizeConstraints(minSize: min, maxSize: max, isFixed: false)
    }

    @Test func emptyCacheReturnsNilForAnyToken() {
        let cache = WindowConstraintCache()
        #expect(cache.cachedConstraints(for: tokenA, maxAge: 5.0) == nil)
        #expect(cache.trackedTokenCount == 0)
    }

    @Test func setThenGetReturnsNormalizedConstraints() {
        var cache = WindowConstraintCache()
        let constraints = makeConstraints(
            min: CGSize(width: 100, height: 100),
            max: CGSize(width: 1000, height: 1000)
        )
        cache.setCachedConstraints(constraints, for: tokenA)

        let cached = cache.cachedConstraints(for: tokenA, maxAge: 5.0)
        #expect(cached == constraints.normalized())
        #expect(cache.trackedTokenCount == 1)
    }

    @Test func setOverwritesPriorConstraints() {
        var cache = WindowConstraintCache()
        let first = makeConstraints(
            min: CGSize(width: 100, height: 100),
            max: CGSize(width: 1000, height: 1000)
        )
        let second = makeConstraints(
            min: CGSize(width: 200, height: 200),
            max: CGSize(width: 800, height: 800)
        )
        cache.setCachedConstraints(first, for: tokenA)
        cache.setCachedConstraints(second, for: tokenA)
        #expect(cache.cachedConstraints(for: tokenA, maxAge: 5.0) == second.normalized())
    }

    @Test func invalidateDropsEntry() {
        var cache = WindowConstraintCache()
        let constraints = makeConstraints(
            min: CGSize(width: 100, height: 100),
            max: CGSize(width: 1000, height: 1000)
        )
        cache.setCachedConstraints(constraints, for: tokenA)
        cache.invalidate(for: tokenA)
        #expect(cache.cachedConstraints(for: tokenA, maxAge: 5.0) == nil)
        #expect(cache.trackedTokenCount == 0)
    }

    @Test func invalidateOfUnknownTokenIsNoOp() {
        var cache = WindowConstraintCache()
        cache.invalidate(for: tokenA)
        #expect(cache.trackedTokenCount == 0)
    }

    @Test func separateTokensAreIsolated() {
        var cache = WindowConstraintCache()
        let constraintsA = makeConstraints(
            min: CGSize(width: 100, height: 100),
            max: CGSize(width: 1000, height: 1000)
        )
        let constraintsB = makeConstraints(
            min: CGSize(width: 200, height: 200),
            max: CGSize(width: 800, height: 800)
        )
        cache.setCachedConstraints(constraintsA, for: tokenA)
        cache.setCachedConstraints(constraintsB, for: tokenB)

        #expect(cache.cachedConstraints(for: tokenA, maxAge: 5.0) == constraintsA.normalized())
        #expect(cache.cachedConstraints(for: tokenB, maxAge: 5.0) == constraintsB.normalized())

        cache.invalidate(for: tokenA)
        #expect(cache.cachedConstraints(for: tokenA, maxAge: 5.0) == nil)
        #expect(cache.cachedConstraints(for: tokenB, maxAge: 5.0) == constraintsB.normalized())
    }

    @Test func staleEntryReturnsNilButStaysInCacheForLazyEviction() {
        var cache = WindowConstraintCache()
        let constraints = makeConstraints(
            min: CGSize(width: 100, height: 100),
            max: CGSize(width: 1000, height: 1000)
        )
        cache.setCachedConstraints(constraints, for: tokenA)

        // 0-second TTL means even an immediate read is stale.
        #expect(cache.cachedConstraints(for: tokenA, maxAge: 0.0) == nil)
        // The cache leaves the stale entry in place so an unrelated read
        // can't mutate the cache from a const context. Eviction is the
        // caller's job (via invalidate or set).
        #expect(cache.trackedTokenCount == 1)
    }

    @Test func rebindMovesEntryWithoutChangingConstraints() {
        var cache = WindowConstraintCache()
        let constraints = makeConstraints(
            min: CGSize(width: 100, height: 100),
            max: CGSize(width: 1000, height: 1000)
        )
        cache.setCachedConstraints(constraints, for: tokenA)
        cache.rebind(from: tokenA, to: tokenB)

        #expect(cache.cachedConstraints(for: tokenA, maxAge: 5.0) == nil)
        #expect(cache.cachedConstraints(for: tokenB, maxAge: 5.0) == constraints.normalized())
    }

    @Test func rebindOfUnknownTokenIsNoOp() {
        var cache = WindowConstraintCache()
        cache.rebind(from: tokenA, to: tokenB)
        #expect(cache.trackedTokenCount == 0)
    }
}
