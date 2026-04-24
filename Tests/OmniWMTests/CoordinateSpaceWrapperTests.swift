// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite struct CoordinateSpaceWrapperTests {
    @Test func appKitToQuartzRoundTripPreservesValue() {
        let original = CGRect(x: 100, y: 200, width: 400, height: 300)
        let appKit = AppKitRect(original)
        let roundTrip = appKit.toQuartz().toAppKit()
        #expect(roundTrip.raw == original)
    }

    @Test func quartzToAppKitMatchesScreenCoordinateSpace() {
        let original = CGRect(x: 50, y: 50, width: 200, height: 100)
        let viaWrapper = QuartzRect(original).toAppKit().raw
        let direct = ScreenCoordinateSpace.toAppKit(rect: original)
        #expect(viaWrapper == direct)
    }

    @Test func backingRectScalesProportionalToBackingScale() {
        let original = CGRect(x: 10, y: 20, width: 30, height: 40)
        let backing = AppKitRect(original).toBacking(scale: 2.0)
        #expect(backing.raw == CGRect(x: 20, y: 40, width: 60, height: 80))
    }

    @Test @MainActor func monitorTopologyVisibleFrameIsAppKitTagged() {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let manager = WorkspaceManager(settings: settings)
        let primary = makeLayoutPlanTestMonitor()
        manager.applyMonitorConfigurationChange([primary])
        let topology = MonitorTopologyState.project(
            manager: manager,
            settings: settings,
            epoch: TopologyEpoch(value: 1)
        )
        let node = topology.node(primary.id)
        #expect(type(of: node!.frame) == AppKitRect.self)
        #expect(type(of: node!.visibleFrame) == AppKitRect.self)
        #expect(type(of: node!.workingFrame) == AppKitRect.self)
        #expect(node!.visibleFrame.raw == primary.visibleFrame)
    }
}
