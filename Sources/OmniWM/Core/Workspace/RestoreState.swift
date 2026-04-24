// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@MainActor
final class RestoreState {
    let restorePlanner = RestorePlanner()
    let bootPersistedWindowRestoreCatalog: PersistedWindowRestoreCatalog

    // Native-fullscreen storage extracted into `NativeFullscreenLedger`
    // (ExecPlan 01, slice WGT-SS-05). The two raw dictionaries are still
    // exposed read-only for the existing callsites; all writes route
    // through `nativeFullscreenLedger.upsert(_:)` /
    // `.remove(logicalId:)` so the records-by-id ↔ id-by-token invariant
    // can no longer be desynced by independent map mutations.
    var nativeFullscreenLedger = NativeFullscreenLedger()
    var nativeFullscreenRecordsByLogicalId: [LogicalWindowId: WorkspaceManager.NativeFullscreenRecord] {
        nativeFullscreenLedger.recordsByLogicalId
    }
    var nativeFullscreenLogicalIdByCurrentToken: [WindowToken: LogicalWindowId] {
        nativeFullscreenLedger.logicalIdByCurrentToken
    }
    var consumedBootPersistedWindowRestoreKeys: Set<PersistedWindowRestoreKey> = []
    var persistedWindowRestoreCatalogDirty = false
    var persistedWindowRestoreCatalogSaveScheduled = false

    init(settings: SettingsStore) {
        let raw = settings.loadPersistedWindowRestoreCatalog()
        let sanitizedEntries = raw.entries.filter { $0.key.isIdentifying }
        bootPersistedWindowRestoreCatalog = PersistedWindowRestoreCatalog(
            entries: sanitizedEntries
        )
    }
}
