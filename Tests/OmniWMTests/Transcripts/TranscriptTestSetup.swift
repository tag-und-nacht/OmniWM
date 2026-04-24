// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

@testable import OmniWM

@MainActor
struct TranscriptRuntimeContext {
    let runtime: WMRuntime
    let platform: RecordingEffectPlatform
    let workspaceIdsByName: [String: WorkspaceDescriptor.ID]
    let monitorIds: [Monitor.ID]

    func workspaceId(named name: String) -> WorkspaceDescriptor.ID {
        guard let id = workspaceIdsByName[name] else {
            preconditionFailure("transcript test referenced unknown workspace name '\(name)'")
        }
        return id
    }

    var primaryMonitorId: Monitor.ID {
        guard let id = monitorIds.first else {
            preconditionFailure("transcript test runtime has no monitors")
        }
        return id
    }
}

@MainActor
func makeTranscriptRuntimeContext(
    workspaceNames: [String] = ["1", "2"],
    layouts: [String: LayoutType] = [:],
    monitorSpecs: [TranscriptMonitorSpec] = [.primary],
    activeWorkspaceName: String? = "1"
) -> TranscriptRuntimeContext {
    let platform = RecordingEffectPlatform()
    resetSharedControllerStateForTests()

    let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
    settings.workspaceConfigurations = workspaceNames.map { name in
        WorkspaceConfiguration(
            name: name,
            monitorAssignment: .main,
            layoutType: layouts[name] ?? .defaultLayout
        )
    }

    let runtime = WMRuntime(settings: settings, effectPlatform: platform)

    let monitors = monitorSpecs.map(VirtualDisplayBoard.materialize)
    runtime.controller.workspaceManager.applyMonitorConfigurationChange(monitors)

    var workspaceIdsByName: [String: WorkspaceDescriptor.ID] = [:]
    let manager = runtime.controller.workspaceManager
    for name in workspaceNames {
        if let id = manager.workspaceId(for: name, createIfMissing: true) {
            workspaceIdsByName[name] = id
        }
    }

    if let activeName = activeWorkspaceName,
       let activeId = workspaceIdsByName[activeName],
       let firstMonitorId = manager.monitors.first?.id
    {
        _ = manager.setActiveWorkspace(activeId, on: firstMonitorId)
    }

    let monitorIds = manager.monitors.map(\.id)

    return TranscriptRuntimeContext(
        runtime: runtime,
        platform: platform,
        workspaceIdsByName: workspaceIdsByName,
        monitorIds: monitorIds
    )
}
