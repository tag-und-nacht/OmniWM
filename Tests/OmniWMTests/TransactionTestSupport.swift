// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@testable import OmniWM

@MainActor
func makeTransactionTestRuntimeSettings() -> SettingsStore {
    let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
    settings.workspaceConfigurations = [
        WorkspaceConfiguration(name: "1", monitorAssignment: .main),
        WorkspaceConfiguration(name: "2", monitorAssignment: .main)
    ]
    return settings
}

@MainActor
func makeTransactionTestRuntime(
    platform: RecordingEffectPlatform
) -> WMRuntime {
    resetSharedControllerStateForTests()
    let runtime = WMRuntime(
        settings: makeTransactionTestRuntimeSettings(),
        effectPlatform: platform
    )
    runtime.controller.workspaceManager.applyMonitorConfigurationChange([
        makeLayoutPlanTestMonitor()
    ])
    if let workspaceOne = runtime.controller.workspaceManager.workspaceId(
        for: "1",
        createIfMissing: false
    ) {
        _ = runtime.controller.workspaceManager.setActiveWorkspace(
            workspaceOne,
            on: runtime.controller.workspaceManager.monitors.first!.id
        )
    }
    return runtime
}

extension Transaction {
    init(
        transactionEpoch: TransactionEpoch,
        effects: [WMEffect]
    ) {
        let event = WMEvent.commandIntent(kindForLog: "test_transaction", source: .command)
        self.init(
            event: event,
            normalizedEvent: event,
            transactionEpoch: transactionEpoch,
            effects: effects,
            snapshot: .empty,
            invariantViolations: []
        )
    }
}
