// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct MouseWarpTopologyTests {
    private static func makeMouseWarpTestDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.omniwm.mouse-warp-topology.test.\(UUID().uuidString)")!
    }

    @MainActor
    private static func makeMonitor(
        displayId: CGDirectDisplayID,
        name: String,
        x: CGFloat,
        width: CGFloat = 1920,
        height: CGFloat = 1080,
        menuBarHeight: CGFloat = 0
    ) -> Monitor {
        let frame = CGRect(x: x, y: 0, width: width, height: height)
        let visibleFrame = menuBarHeight > 0
            ? CGRect(x: x, y: 0, width: width, height: height - menuBarHeight)
            : frame
        return Monitor(
            id: Monitor.ID(displayId: displayId),
            displayId: displayId,
            frame: frame,
            visibleFrame: visibleFrame,
            hasNotch: false,
            name: name
        )
    }

    @MainActor
    private static func makeFixture(
        monitors: [Monitor],
        monitorOrder: [String]
    ) -> (
        runtime: WMRuntime,
        controller: WMController,
        handler: MouseWarpHandler,
        warpedPoints: () -> [CGPoint]
    ) {
        resetSharedControllerStateForTests()
        let settings = SettingsStore(defaults: makeMouseWarpTestDefaults())
        var remainingByName = Dictionary(grouping: monitors, by: \.name)
        settings.mouseWarpMonitorOrder = monitorOrder.compactMap { name in
            guard var matches = remainingByName[name], !matches.isEmpty else { return nil }
            let monitor = matches.removeFirst()
            remainingByName[name] = matches
            return OutputId(from: monitor)
        }
        settings.mouseWarpAxis = .horizontal
        settings.mouseWarpMargin = 2

        let operations = WindowFocusOperations(
            activateApp: { _ in },
            focusSpecificWindow: { _, _, _ in },
            raiseWindow: { _ in }
        )
        let runtime = WMRuntime(settings: settings, windowFocusOperations: operations)
        let controller = runtime.controller
        controller.lockScreenObserver.frontmostSnapshotProvider = { nil }
        controller.workspaceManager.applyMonitorConfigurationChange(monitors)

        var captured: [CGPoint] = []
        let handler = controller.mouseWarpHandler
        handler.warpCursor = { point in
            captured.append(point)
        }
        handler.postMouseMovedEvent = { _ in }
        return (runtime, controller, handler, { captured })
    }

    @Test @MainActor func warpDestinationLandsInsideVisibleFrameAvoidingMenuBar() {
        let leftMonitor = Self.makeMonitor(displayId: 1, name: "Left", x: 0)
        let rightMonitor = Self.makeMonitor(
            displayId: 2,
            name: "Right",
            x: 1920,
            menuBarHeight: 24
        )
        let fixture = Self.makeFixture(
            monitors: [leftMonitor, rightMonitor],
            monitorOrder: ["Left", "Right"]
        )
        defer { fixture.handler.cleanup() }

        let location = CGPoint(
            x: leftMonitor.frame.maxX - CGFloat(fixture.controller.settings.mouseWarpMargin) + 1,
            y: 1.0
        )
        fixture.handler.resetDebugStateForTests()
        fixture.handler.receiveTapMouseWarpMoved(at: location)
        fixture.handler.flushPendingWarpEventsForTests()

        let warpedPoints = fixture.warpedPoints()
        guard let warpAppKit = warpedPoints.last else {
            Issue.record("Expected a warp event")
            return
        }
        let warpAppKitPoint = ScreenCoordinateSpace.toAppKit(point: warpAppKit)
        #expect(warpAppKitPoint.y <= rightMonitor.visibleFrame.maxY)
        #expect(warpAppKitPoint.y >= rightMonitor.visibleFrame.minY)
    }

    @Test @MainActor func warpDestinationMatchesTopologyVisibleFrame() {
        let leftMonitor = Self.makeMonitor(displayId: 1, name: "Left", x: 0)
        let rightMonitor = Self.makeMonitor(
            displayId: 2,
            name: "Right",
            x: 1920,
            menuBarHeight: 24
        )
        let fixture = Self.makeFixture(
            monitors: [leftMonitor, rightMonitor],
            monitorOrder: ["Left", "Right"]
        )
        defer { fixture.handler.cleanup() }

        let topology = MonitorTopologyState.project(
            manager: fixture.controller.workspaceManager,
            settings: fixture.controller.settings,
            epoch: fixture.runtime.currentTopologyEpoch,
            insetWorkingFrame: { mon in
                fixture.controller.insetWorkingFrame(for: mon)
            }
        )
        guard let rightNode = topology.node(rightMonitor.id) else {
            Issue.record("Topology missing right monitor")
            return
        }
        let topologyVisibleFrame = rightNode.visibleFrame.raw

        let location = CGPoint(
            x: leftMonitor.frame.maxX - CGFloat(fixture.controller.settings.mouseWarpMargin) + 1,
            y: 1.0
        )
        fixture.handler.resetDebugStateForTests()
        fixture.handler.receiveTapMouseWarpMoved(at: location)
        fixture.handler.flushPendingWarpEventsForTests()

        guard let warpAppKit = fixture.warpedPoints().last else {
            Issue.record("Expected a warp event")
            return
        }
        let warpAppKitPoint = ScreenCoordinateSpace.toAppKit(point: warpAppKit)
        #expect(topologyVisibleFrame.contains(warpAppKitPoint))
    }

    @Test @MainActor func warpOrderMatchesTopologyMouseWarpOrder() {
        let leftMonitor = Self.makeMonitor(displayId: 1, name: "Left", x: 0)
        let rightMonitor = Self.makeMonitor(displayId: 2, name: "Right", x: 1920)
        let fixture = Self.makeFixture(
            monitors: [leftMonitor, rightMonitor],
            monitorOrder: ["Left", "Right"]
        )
        defer { fixture.handler.cleanup() }

        let topology = MonitorTopologyState.project(
            manager: fixture.controller.workspaceManager,
            settings: fixture.controller.settings,
            epoch: fixture.runtime.currentTopologyEpoch,
            insetWorkingFrame: { mon in
                fixture.controller.insetWorkingFrame(for: mon)
            }
        )
        let topologyOrder = topology.mouseWarpOrder(
            axis: .horizontal,
            settings: fixture.controller.settings
        )
        let settingsOrder = fixture.controller.settings.effectiveMouseWarpMonitorOrder(
            for: fixture.controller.workspaceManager.monitors,
            axis: .horizontal
        )

        #expect(topologyOrder == settingsOrder)
        #expect(topologyOrder == [leftMonitor.id, rightMonitor.id])
    }
}
