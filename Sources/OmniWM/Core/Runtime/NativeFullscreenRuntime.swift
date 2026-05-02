// SPDX-License-Identifier: GPL-2.0-only
import Foundation

/// Per-domain runtime for native-fullscreen lifecycle. Mirrors
/// `NativeFullscreenLedger` (which atomically owns the
/// `recordsByLogicalId` ↔ `logicalIdByCurrentToken` invariant on the manager
/// side, per ExecPlan 01) and provides the epoch-stamped mutation surface
/// that the rest of the runtime calls into.
@MainActor
final class NativeFullscreenRuntime {
    private let kernel: RuntimeKernel
    private let effectRunner: WMEffectRunner
    private let mutationCoordinator: RuntimeMutationCoordinator
    private unowned let workspaceManager: WorkspaceManager

    init(
        kernel: RuntimeKernel,
        effectRunner: WMEffectRunner,
        mutationCoordinator: RuntimeMutationCoordinator,
        workspaceManager: WorkspaceManager
    ) {
        self.kernel = kernel
        self.effectRunner = effectRunner
        self.mutationCoordinator = mutationCoordinator
        self.workspaceManager = workspaceManager
    }

    // MARK: Read surface

    /// True iff the manager is currently coordinating any native-fullscreen
    /// lifecycle work (either an active app-fullscreen state or any tracked
    /// record). Used by paths that branch based on whether native-fullscreen
    /// is in flight.
    var hasLifecycleContext: Bool {
        workspaceManager.hasNativeFullscreenLifecycleContext
    }

    /// Lookup the native-fullscreen record for `token` via the reverse
    /// (token → logical-id) map, or `nil` if the token isn't tracked.
    func record(forToken token: WindowToken) -> WorkspaceManager.NativeFullscreenRecord? {
        workspaceManager.nativeFullscreenRecord(for: token)
    }

    // MARK: Lifecycle mutations (migrated from WMRuntime — ExecPlan 02 surface migration)

    @discardableResult
    func seedNativeFullscreenRestoreSnapshot(
        _ snapshot: WorkspaceManager.NativeFullscreenRecord.RestoreSnapshot,
        for token: WindowToken,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .nativeFullscreenRestoreSnapshotSeeded,
            source: source,
            recordTransaction: true
        ) { epoch in
            workspaceManager.seedNativeFullscreenRestoreSnapshot(
                snapshot,
                for: token,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func requestNativeFullscreenEnter(
        _ token: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        restoreSnapshot: WorkspaceManager.NativeFullscreenRecord.RestoreSnapshot?,
        restoreFailure: WorkspaceManager.NativeFullscreenRecord.RestoreFailure?,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .nativeFullscreenEnterRequested,
            source: source,
            recordTransaction: true
        ) { epoch in
            workspaceManager.requestNativeFullscreenEnter(
                token,
                in: workspaceId,
                restoreSnapshot: restoreSnapshot,
                restoreFailure: restoreFailure,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func markNativeFullscreenSuspended(
        _ token: WindowToken,
        restoreSnapshot: WorkspaceManager.NativeFullscreenRecord.RestoreSnapshot?,
        restoreFailure: WorkspaceManager.NativeFullscreenRecord.RestoreFailure?,
        source: WMEventSource = .ax
    ) -> Bool {
        mutationCoordinator.perform(
            .nativeFullscreenSuspended,
            source: source,
            recordTransaction: true
        ) { epoch in
            workspaceManager.markNativeFullscreenSuspended(
                token,
                restoreSnapshot: restoreSnapshot,
                restoreFailure: restoreFailure,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func requestNativeFullscreenExit(
        _ token: WindowToken,
        initiatedByCommand: Bool,
        source: WMEventSource = .command
    ) -> Bool {
        mutationCoordinator.perform(
            .nativeFullscreenExitRequested,
            source: source,
            recordTransaction: true
        ) { epoch in
            workspaceManager.requestNativeFullscreenExit(
                token,
                initiatedByCommand: initiatedByCommand,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func markNativeFullscreenTemporarilyUnavailable(
        _ token: WindowToken,
        source: WMEventSource = .ax
    ) -> WorkspaceManager.NativeFullscreenRecord? {
        mutationCoordinator.perform(
            .nativeFullscreenTemporarilyUnavailable,
            source: source,
            recordTransaction: true,
            resultNotes: { record in ["unavailable=\(record != nil)"] }
        ) { epoch in
            workspaceManager.markNativeFullscreenTemporarilyUnavailable(
                token,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func expireStaleTemporarilyUnavailableNativeFullscreenRecords(
        now: Date = Date(),
        staleInterval: TimeInterval = WorkspaceManager.staleUnavailableNativeFullscreenTimeout,
        source: WMEventSource = .ax
    ) -> [WindowModel.Entry] {
        mutationCoordinator.perform(
            .nativeFullscreenStaleExpiry,
            source: source,
            recordTransaction: true,
            resultNotes: { entries in ["removed=\(entries.count)"] }
        ) { epoch in
            workspaceManager.expireStaleTemporarilyUnavailableNativeFullscreenRecords(
                now: now,
                staleInterval: staleInterval,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func restoreFromNativeState(
        for token: WindowToken,
        source: WMEventSource = .ax
    ) -> ParentKind? {
        mutationCoordinator.perform(
            .nativeStateRestored,
            source: source,
            recordTransaction: false,
            resultNotes: { parent in ["restored=\(parent != nil)"] }
        ) { epoch in
            workspaceManager.restoreFromNativeState(
                for: token,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    @discardableResult
    func setManagedAppFullscreen(
        _ active: Bool,
        source: WMEventSource = .ax
    ) -> Bool {
        mutationCoordinator.perform(
            .managedAppFullscreenSet,
            source: source,
            recordTransaction: false
        ) { epoch in
            workspaceManager.setManagedAppFullscreen(
                active,
                transactionEpoch: epoch,
                eventSource: source
            )
        }
    }

    /// "Begin native-fullscreen restore" path — uses manual signpost / log
    /// / epoch wiring rather than `performRuntimeMutation` because it
    /// doesn't record a runtime transaction (the actual transaction is
    /// recorded later when the restore finalizes).
    @discardableResult
    func beginNativeFullscreenRestore(
        for token: WindowToken,
        source: WMEventSource = .ax
    ) -> WorkspaceManager.NativeFullscreenRecord? {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "begin_native_fullscreen_restore",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let record = workspaceManager.beginNativeFullscreenRestore(
            for: token,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("begin_native_fullscreen_restore", signpostState)
        kernel.intakeLog.debug(
            "nfr_begin_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) restored=\(record != nil) us=\(durationMicros)"
        )
        return record
    }

    @discardableResult
    func restoreNativeFullscreenRecord(
        for token: WindowToken,
        source: WMEventSource = .ax
    ) -> ParentKind? {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "restore_native_fullscreen_record",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let parent = workspaceManager.restoreNativeFullscreenRecord(
            for: token,
            transactionEpoch: epoch,
            eventSource: source
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("restore_native_fullscreen_record", signpostState)
        kernel.intakeLog.debug(
            "nfr_restore_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) restored=\(parent != nil) us=\(durationMicros)"
        )
        return parent
    }

    func finalizeNativeFullscreenRestore(
        for token: WindowToken,
        source: WMEventSource = .ax
    ) -> ParentKind? {
        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "finalize_native_fullscreen_restore",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        let parent = workspaceManager.finalizeNativeFullscreenRestore(
            for: token,
            transactionEpoch: epoch,
            eventSource: source
        )
        workspaceManager.recordRuntimeTransaction(
            kindForLog: "finalize_native_fullscreen_restore",
            source: source,
            transactionEpoch: epoch,
            notes: ["restored=\(parent != nil)"]
        )
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("finalize_native_fullscreen_restore", signpostState)
        kernel.intakeLog.debug(
            "nfr_finalize_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) restored=\(parent != nil) us=\(durationMicros)"
        )
        return parent
    }
}
