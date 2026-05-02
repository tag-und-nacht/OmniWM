// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct ActivateInferredWorkspaceTransactionTests {
    @MainActor
    private func makeManagerWithoutActiveWorkspace() -> WorkspaceManager {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = []
        let manager = WorkspaceManager(settings: settings)
        manager.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        _ = manager.workspaceId(for: "1", createIfMissing: true)
        return manager
    }

    @Test @MainActor func activeWorkspaceOrFirstDoesNotPersistInferredWorkspace() {
        let manager = makeManagerWithoutActiveWorkspace()
        let monitorId = manager.monitors.first!.id

        #expect(manager.currentActiveWorkspace(on: monitorId) == nil,
                "fixture must start with no persisted active workspace")

        let inferred = manager.activeWorkspaceOrFirst(on: monitorId)
        #expect(inferred != nil, "kernel projection should still resolve a workspace")
        #expect(manager.currentActiveWorkspace(on: monitorId) == nil,
                "read-shaped helper must not mutate durable session state")
    }

    @Test @MainActor func activateInferredWorkspaceIfNeededPersistsWhenNoActiveWorkspace() {
        let manager = makeManagerWithoutActiveWorkspace()
        let monitorId = manager.monitors.first!.id

        let activated = manager.activateInferredWorkspaceIfNeeded(on: monitorId)
        #expect(activated == true)
        #expect(manager.currentActiveWorkspace(on: monitorId) != nil,
                "manager mutator must commit the inferred workspace")
    }

    @Test @MainActor func activateInferredWorkspaceIfNeededIsNoOpWhenAlreadyActive() {
        let manager = makeManagerWithoutActiveWorkspace()
        let monitorId = manager.monitors.first!.id
        _ = manager.activateInferredWorkspaceIfNeeded(on: monitorId)
        let snapshotBefore = manager.reconcileSnapshot()

        let secondCall = manager.activateInferredWorkspaceIfNeeded(on: monitorId)
        #expect(secondCall == false)
        #expect(manager.reconcileSnapshot() == snapshotBefore,
                "no-op call must not perturb session snapshot")
    }

    @Test @MainActor func runtimeAdapterRecordsStampedTransaction() {
        resetSharedControllerStateForTests()
        let platform = RecordingEffectPlatform()
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = []
        let runtime = WMRuntime(
            settings: settings,
            effectPlatform: platform
        )
        runtime.controller.workspaceManager.applyMonitorConfigurationChange(
            [makeLayoutPlanTestMonitor()]
        )
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let manager = runtime.controller.workspaceManager
        _ = manager.workspaceId(for: "1", createIfMissing: true)
        let monitorId = manager.monitors.first!.id
        #expect(manager.currentActiveWorkspace(on: monitorId) == nil)

        let activated = runtime.activateInferredWorkspaceIfNeeded(on: monitorId)

        #expect(activated == true)
        #expect(manager.currentActiveWorkspace(on: monitorId) != nil)
        guard let txn = manager.lastRecordedTransaction else {
            Issue.record("runtime adapter must record a transaction")
            return
        }
        #expect(txn.transactionEpoch.isValid,
                "stamped epoch is the canonical \"went through WMRuntime\" signal")
        switch txn.event {
        case let .commandIntent(kindForLog, _):
            #expect(kindForLog == "activate_inferred_workspace_if_needed")
        default:
            Issue.record("expected commandIntent(activate_inferred_workspace_if_needed) event, got \(txn.event)")
        }
    }

    @Test @MainActor func runtimeAdapterShortCircuitsWhenAlreadyActive() {
        resetSharedControllerStateForTests()
        let platform = RecordingEffectPlatform()
        let runtime = WMRuntime(
            settings: makeTransactionTestRuntimeSettings(),
            effectPlatform: platform
        )
        runtime.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let manager = runtime.controller.workspaceManager
        let monitorId = manager.monitors.first!.id
        #expect(manager.currentActiveWorkspace(on: monitorId) != nil,
                "bootstrap must have committed an active workspace already")
        let txnBefore = manager.lastRecordedTransaction

        let activated = runtime.activateInferredWorkspaceIfNeeded(on: monitorId)

        #expect(activated == false)
        #expect(manager.lastRecordedTransaction?.transactionEpoch
                == txnBefore?.transactionEpoch,
                "no transaction should be appended for a no-op call")
    }

    @Test @MainActor func applyMonitorConfigurationChangeBootstrapsActiveWorkspaces() {
        resetSharedControllerStateForTests()
        let platform = RecordingEffectPlatform()
        let runtime = WMRuntime(
            settings: makeTransactionTestRuntimeSettings(),
            effectPlatform: platform
        )

        runtime.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])

        for monitor in runtime.controller.workspaceManager.monitors {
            #expect(
                runtime.controller.workspaceManager.currentActiveWorkspace(on: monitor.id) != nil,
                "applyMonitorConfigurationChange bootstrap must persist an active workspace per monitor"
            )
        }
    }

    @Test @MainActor func bootstrapIsIdempotentForUnchangedTopology() {
        resetSharedControllerStateForTests()
        let platform = RecordingEffectPlatform()
        let runtime = WMRuntime(
            settings: makeTransactionTestRuntimeSettings(),
            effectPlatform: platform
        )
        runtime.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let snapshotAfterFirst = runtime.controller.workspaceManager.reconcileSnapshot()

        runtime.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])

        #expect(runtime.controller.workspaceManager.reconcileSnapshot() == snapshotAfterFirst,
                "second identical applyMonitorConfigurationChange must be a no-op")
    }
}
