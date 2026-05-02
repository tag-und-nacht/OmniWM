// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OSLog

/// Per-domain runtime for monitor topology — display add / remove /
/// reconfigure handling, the monitor-index cache, monitor rebind policy.
/// Mirrors `MonitorIndexCache` (the per-id / per-name lookup table on the
/// manager side, per ExecPlan 01).
///
/// ExecPlan 02 slice WRT-DS-05 owner for `applyMonitorConfigurationChange`
/// and topology-epoch allocation. Restore-assignment dispatch still stays
/// in the manager / workspace layer because it is part of the monitor
/// rebind policy, not runtime orchestration.
@MainActor
final class MonitorRuntime {
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

    /// The currently-known monitor list, in canonical order from
    /// `WorkspaceStore.monitors`.
    var monitors: [Monitor] {
        workspaceManager.monitors
    }

    /// The current topology profile (deterministic fingerprint of the
    /// monitor arrangement) used by reconcile and projection invalidation.
    var topologyProfile: TopologyProfile {
        workspaceManager.currentTopologyProfile
    }

    /// O(1) lookup by stable monitor ID.
    func monitor(byId id: Monitor.ID) -> Monitor? {
        workspaceManager.monitor(byId: id)
    }

    /// Returns the monitor with the given name iff exactly one such monitor
    /// exists; ambiguous names return `nil`.
    func monitor(named name: String) -> Monitor? {
        workspaceManager.monitor(named: name)
    }

    /// All monitors sharing the given name, sorted deterministically.
    func monitors(named name: String) -> [Monitor] {
        workspaceManager.monitors(named: name)
    }

    // MARK: Topology mutations

    func applyMonitorConfigurationChange(
        _ newMonitors: [Monitor],
        source: WMEventSource = .service
    ) {
        let normalizedMonitors = newMonitors.isEmpty ? [Monitor.fallback()] : newMonitors
        let candidateProfile = TopologyProfile(monitors: normalizedMonitors)
        if candidateProfile == workspaceManager.currentTopologyProfile {
            let monitorsNeedingActiveWorkspace = workspaceManager.monitors.filter { monitor in
                workspaceManager.currentActiveWorkspace(on: monitor.id) == nil
                    && workspaceManager.activeWorkspaceOrFirst(on: monitor.id) != nil
            }
            guard !monitorsNeedingActiveWorkspace.isEmpty else {
                kernel.intakeLog.debug(
                    "monitor_topology_intake source=\(source.rawValue, privacy: .public) skipped=unchanged_profile monitors=\(newMonitors.count)"
                )
                return
            }

            let epoch = kernel.allocateTransactionEpoch()
            var inferredCount = 0
            for monitor in monitorsNeedingActiveWorkspace {
                if workspaceManager.activateInferredWorkspaceIfNeeded(
                    on: monitor.id,
                    transactionEpoch: epoch,
                    eventSource: source
                ) {
                    inferredCount += 1
                }
            }
            effectRunner.noteTransactionCommitted(epoch)
            mutationCoordinator.refreshSnapshotState()
            kernel.intakeLog.debug(
                "monitor_topology_intake source=\(source.rawValue, privacy: .public) skipped=unchanged_profile monitors=\(newMonitors.count) inferred_workspaces=\(inferredCount)"
            )
            return
        }

        let epoch = kernel.allocateTransactionEpoch()
        let signpostState = kernel.intakeSignpost.beginInterval(
            "apply_monitor_configuration_change",
            id: kernel.intakeSignpost.makeSignpostID(),
            "source=\(source.rawValue) txn=\(epoch.value)"
        )
        let startTime = ContinuousClock.now
        workspaceManager.applyMonitorConfigurationChange(
            newMonitors,
            transactionEpoch: epoch,
            eventSource: source
        )
        var inferredCount = 0
        for monitor in workspaceManager.monitors {
            if workspaceManager.activateInferredWorkspaceIfNeeded(
                on: monitor.id,
                transactionEpoch: epoch,
                eventSource: source
            ) {
                inferredCount += 1
            }
        }
        let topologyEpoch = kernel.allocateTopologyEpoch()
        effectRunner.noteTransactionCommitted(epoch)
        mutationCoordinator.refreshSnapshotState()
        let durationMicros = RuntimeKernel.elapsedMicros(since: startTime)
        kernel.intakeSignpost.endInterval("apply_monitor_configuration_change", signpostState)
        kernel.intakeLog.debug(
            "monitor_topology_intake source=\(source.rawValue, privacy: .public) txn=\(epoch.value) topology=\(topologyEpoch.value) monitors=\(newMonitors.count) inferred_workspaces=\(inferredCount) us=\(durationMicros)"
        )
    }
}
