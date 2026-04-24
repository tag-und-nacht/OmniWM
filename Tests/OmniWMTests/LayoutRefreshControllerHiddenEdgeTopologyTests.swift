// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct LayoutRefreshControllerHiddenEdgeTopologyTests {
    @Test @MainActor func preferredHideSideEqualsTopologyInstanceResultForTwoMonitors() {
        let bundle = makeTwoMonitorLayoutPlanTestController()
        let controller = bundle.controller

        let topology = MonitorTopologyState.project(
            manager: controller.workspaceManager,
            settings: controller.settings,
            epoch: controller.runtime?.currentTopologyEpoch ?? .invalid,
            insetWorkingFrame: { mon in
                controller.insetWorkingFrame(for: mon)
            }
        )
        let instanceSides = topology.preferredHideSides()

        let primarySide = controller.layoutRefreshController
            .preferredHideSide(for: bundle.primaryMonitor)
        let secondarySide = controller.layoutRefreshController
            .preferredHideSide(for: bundle.secondaryMonitor)

        #expect(primarySide == instanceSides[bundle.primaryMonitor.id])
        #expect(secondarySide == instanceSides[bundle.secondaryMonitor.id])
    }

    @Test @MainActor func preferredHideSideUpdatesAfterMonitorReconfiguration() {
        let bundle = makeTwoMonitorLayoutPlanTestController()
        let controller = bundle.controller

        let dualSide = controller.layoutRefreshController
            .preferredHideSide(for: bundle.primaryMonitor)

        controller.runtime?.applyMonitorConfigurationChange([bundle.primaryMonitor])

        let singleTopology = MonitorTopologyState.project(
            manager: controller.workspaceManager,
            settings: controller.settings,
            epoch: controller.runtime?.currentTopologyEpoch ?? .invalid,
            insetWorkingFrame: { mon in
                controller.insetWorkingFrame(for: mon)
            }
        )
        let expectedSingleSide = singleTopology
            .preferredHideSides()[bundle.primaryMonitor.id]

        let singleSide = controller.layoutRefreshController
            .preferredHideSide(for: bundle.primaryMonitor)

        #expect(singleSide == expectedSingleSide)
        _ = dualSide
    }
}
