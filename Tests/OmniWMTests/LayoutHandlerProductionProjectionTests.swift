// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct LayoutHandlerProductionProjectionTests {
    @Test @MainActor func niriLayoutPipelineWarmsConstraintsCacheForTiledEntries() async throws {
        let controller = makeLayoutPlanTestController()
        guard let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing monitor or workspace for Niri cache-warming test")
            return
        }
        _ = controller.workspaceManager.setActiveWorkspace(workspaceId, on: monitor.id)
        controller.enableNiriLayout(maxWindowsPerColumn: 1)
        controller.syncMonitorsToNiriEngine()

        let token = addLayoutPlanTestWindow(
            on: controller,
            workspaceId: workspaceId,
            windowId: 4001
        )

        _ = try await controller.niriLayoutHandler.layoutWithNiriEngine(
            activeWorkspaces: [workspaceId]
        )

        #expect(controller.workspaceManager.cachedConstraints(for: token) != nil)
    }
}
