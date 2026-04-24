// SPDX-License-Identifier: GPL-2.0-only
import Foundation

/// Owns the two maps that together describe a window in (or in transition
/// out of) native fullscreen: `recordsByLogicalId` (the per-logical-id
/// metadata) and `logicalIdByCurrentToken` (the reverse lookup from the
/// window's current AX token).
///
/// Extracted from `WorkspaceManager` (ExecPlan 01, slice WGT-SS-05).
/// Critical invariant: the two maps must agree — for every entry
/// `recordsByLogicalId[L] = R`, `logicalIdByCurrentToken[R.currentToken]
/// == L`. Previously this invariant was upheld by hand at two callsites
/// (`upsertNativeFullscreenRecord` / `removeNativeFullscreenRecord`); any
/// future caller writing the maps independently could violate it. The
/// ledger forces every mutation through `upsert(_:)`, `remove(logicalId:)`,
/// or `update(logicalId:_:)` so the invariant is type-enforced.
struct NativeFullscreenLedger {
    private(set) var recordsByLogicalId: [LogicalWindowId: WorkspaceManager.NativeFullscreenRecord] = [:]
    private(set) var logicalIdByCurrentToken: [WindowToken: LogicalWindowId] = [:]

    var isEmpty: Bool { recordsByLogicalId.isEmpty }
    var allRecords: Dictionary<LogicalWindowId, WorkspaceManager.NativeFullscreenRecord>.Values {
        recordsByLogicalId.values
    }

    func record(forLogicalId logicalId: LogicalWindowId) -> WorkspaceManager.NativeFullscreenRecord? {
        recordsByLogicalId[logicalId]
    }

    func record(forToken token: WindowToken) -> WorkspaceManager.NativeFullscreenRecord? {
        guard let logicalId = logicalIdByCurrentToken[token] else { return nil }
        return recordsByLogicalId[logicalId]
    }

    func logicalId(forToken token: WindowToken) -> LogicalWindowId? {
        logicalIdByCurrentToken[token]
    }

    /// Insert or update a record. If a previous record for `record.logicalId`
    /// existed and bound a different token, that token's reverse lookup is
    /// dropped before the new binding lands. Returns the previous record (if
    /// any) so callers can react to replacement.
    @discardableResult
    mutating func upsert(
        _ record: WorkspaceManager.NativeFullscreenRecord
    ) -> WorkspaceManager.NativeFullscreenRecord? {
        let previous = recordsByLogicalId[record.logicalId]
        if let prev = previous, prev.currentToken != record.currentToken {
            logicalIdByCurrentToken.removeValue(forKey: prev.currentToken)
        }
        recordsByLogicalId[record.logicalId] = record
        logicalIdByCurrentToken[record.currentToken] = record.logicalId
        return previous
    }

    /// Remove the record at `logicalId`, atomically dropping the matching
    /// reverse-lookup entry. Returns the removed record (if any).
    @discardableResult
    mutating func remove(
        logicalId: LogicalWindowId
    ) -> WorkspaceManager.NativeFullscreenRecord? {
        guard let removed = recordsByLogicalId.removeValue(forKey: logicalId) else {
            return nil
        }
        logicalIdByCurrentToken.removeValue(forKey: removed.currentToken)
        return removed
    }
}
