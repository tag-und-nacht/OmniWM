// SPDX-License-Identifier: GPL-2.0-only
import Foundation

enum MonitorRebindPolicy {
    typealias Decision = MonitorTopologyState.RebindDecision

    static func decide(
        previousOutputs: [OutputId],
        newMonitors: [Monitor],
        workspaces: [WorkspaceDescriptor],
        snapshots: [WorkspaceRestoreSnapshot],
        workspaceConfigurations: [WorkspaceConfiguration] = []
    ) -> Decision {
        MonitorTopologyState.rebindDecision(
            previousOutputs: previousOutputs,
            newMonitors: newMonitors,
            workspaces: workspaces,
            snapshots: snapshots,
            workspaceConfigurations: workspaceConfigurations
        )
    }
}
