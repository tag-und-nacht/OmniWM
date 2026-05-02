// SPDX-License-Identifier: GPL-2.0-only
import Foundation

/// In-memory cache of monitor lookups by id and by name. Extracted from
/// `WorkspaceManager` (ExecPlan 01, slice WGT-SS-02) so the index-rebuild
/// path is testable in isolation and can't drift from the source-of-truth
/// `WorkspaceStore.monitors` array.
///
/// Invalidation: callers must call `rebuild(from:)` whenever the monitors
/// list changes. The cache is intentionally write-once-per-rebuild — there
/// is no "patch one entry" surface, because every observed monitor change
/// in macOS goes through a full topology reconfigure callback anyway.
struct MonitorIndexCache: Equatable {
    private(set) var byId: [Monitor.ID: Monitor] = [:]
    private(set) var byName: [String: [Monitor]] = [:]

    /// Rebuild both indexes from the given canonical monitor list. Same-name
    /// monitors are sorted by `Monitor.sortedByPosition` for deterministic
    /// disambiguation in `monitor(named:)`.
    mutating func rebuild(from monitors: [Monitor]) {
        byId = Dictionary(uniqueKeysWithValues: monitors.map { ($0.id, $0) })
        var grouped: [String: [Monitor]] = [:]
        for monitor in monitors {
            grouped[monitor.name, default: []].append(monitor)
        }
        for key in grouped.keys {
            grouped[key] = Monitor.sortedByPosition(grouped[key] ?? [])
        }
        byName = grouped
    }

    /// O(1) lookup by stable monitor ID.
    func monitor(byId id: Monitor.ID) -> Monitor? {
        byId[id]
    }

    /// Returns the monitor with the given name only if exactly one such
    /// monitor exists; ambiguous names return `nil` (callers that want the
    /// disambiguated list should use `monitors(named:)`).
    func monitor(named name: String) -> Monitor? {
        guard let matches = byName[name], matches.count == 1 else { return nil }
        return matches[0]
    }

    /// All monitors sharing the given name, sorted deterministically.
    func monitors(named name: String) -> [Monitor] {
        byName[name] ?? []
    }
}
