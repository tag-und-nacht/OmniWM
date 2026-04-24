// SPDX-License-Identifier: GPL-2.0-only
import Foundation

/// Per-window AX size-constraint cache. AX size-constraint queries are slow
/// cross-process calls (often 5–20 ms), so the cache amortizes them across
/// quick interactive operations like dragging a column edge.
///
/// Extracted from `WindowModel.Entry` (ExecPlan 01, slice WGT-SS-06) so the
/// TTL-keyed cache lives behind a focused type with a single test surface.
/// The previous design embedded `cachedConstraints` + `constraintsCacheTime`
/// on every `Entry` — five separate read/write/invalidate sites in
/// `WindowModel` that had to remember to keep both fields in sync.
struct WindowConstraintCache {
    private struct CacheEntry {
        let constraints: WindowSizeConstraints
        let cachedAt: Date
    }

    private var entriesByToken: [WindowToken: CacheEntry] = [:]

    /// Returns cached constraints for `token` if present and younger than
    /// `maxAge` seconds. Stale or missing entries return `nil` without
    /// auto-eviction; callers (or `invalidate(for:)`) handle the eviction
    /// explicitly so an unrelated read can't leave the cache in a partially
    /// pruned state during iteration.
    func cachedConstraints(
        for token: WindowToken,
        maxAge: TimeInterval
    ) -> WindowSizeConstraints? {
        guard let entry = entriesByToken[token],
              Date().timeIntervalSince(entry.cachedAt) < maxAge
        else {
            return nil
        }
        return entry.constraints
    }

    /// Store the normalized form of `constraints` for `token`, stamped with
    /// the current wall-clock time.
    mutating func setCachedConstraints(
        _ constraints: WindowSizeConstraints,
        for token: WindowToken
    ) {
        entriesByToken[token] = CacheEntry(
            constraints: constraints.normalized(),
            cachedAt: Date()
        )
    }

    /// Drop the cached entry for `token`. No-op if the token is unknown.
    mutating func invalidate(for token: WindowToken) {
        entriesByToken.removeValue(forKey: token)
    }

    /// Drop the cached entry under `oldToken` and re-bind it to `newToken`
    /// without changing the stored constraints — used when a window's AX
    /// token changes but its size invariants don't. If `oldToken` is
    /// unknown, leaves the cache untouched.
    mutating func rebind(from oldToken: WindowToken, to newToken: WindowToken) {
        guard oldToken != newToken,
              let entry = entriesByToken.removeValue(forKey: oldToken)
        else { return }
        entriesByToken[newToken] = entry
    }

    var trackedTokenCount: Int { entriesByToken.count }
}
