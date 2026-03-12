import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

private final class WarpEffectRecorder: @unchecked Sendable {
    var warpedPoints: [CGPoint] = []
    var postedPoints: [CGPoint] = []
}

private func makeMouseWarpTestDefaults() -> UserDefaults {
    let suiteName = "com.omniwm.mouse-warp.test.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
}

private func makeMouseWarpTestMonitor(
    displayId: CGDirectDisplayID,
    name: String,
    x: CGFloat,
    width: CGFloat = 1920,
    height: CGFloat = 1080
) -> Monitor {
    let frame = CGRect(x: x, y: 0, width: width, height: height)
    return Monitor(
        id: Monitor.ID(displayId: displayId),
        displayId: displayId,
        frame: frame,
        visibleFrame: frame,
        hasNotch: false,
        name: name
    )
}

@MainActor
private func makeMouseWarpTestFixture() -> (
    controller: WMController,
    handler: MouseWarpHandler,
    leftMonitor: Monitor,
    rightMonitor: Monitor,
    recorder: WarpEffectRecorder
) {
    let settings = SettingsStore(defaults: makeMouseWarpTestDefaults())
    settings.mouseWarpEnabled = true
    settings.mouseWarpMonitorOrder = ["Left", "Right"]
    settings.mouseWarpMargin = 2

    let operations = WindowFocusOperations(
        activateApp: { _ in },
        focusSpecificWindow: { _, _, _ in },
        raiseWindow: { _ in }
    )

    let controller = WMController(
        settings: settings,
        windowFocusOperations: operations
    )
    let leftMonitor = makeMouseWarpTestMonitor(displayId: 1, name: "Left", x: 0)
    let rightMonitor = makeMouseWarpTestMonitor(displayId: 2, name: "Right", x: 1920)
    controller.workspaceManager.applyMonitorConfigurationChange([leftMonitor, rightMonitor])

    let recorder = WarpEffectRecorder()
    let handler = controller.mouseWarpHandler
    handler.warpCursor = { point in recorder.warpedPoints.append(point) }
    handler.postMouseMovedEvent = { point in recorder.postedPoints.append(point) }
    return (controller, handler, leftMonitor, rightMonitor, recorder)
}

@MainActor
private func waitForMainRunLoopTurn() async {
    await withCheckedContinuation { continuation in
        let mainRunLoop = CFRunLoopGetMain()
        CFRunLoopPerformBlock(mainRunLoop, CFRunLoopMode.commonModes.rawValue) {
            continuation.resume()
        }
        CFRunLoopWakeUp(mainRunLoop)
    }
}

@MainActor
private func waitUntilMouseWarpDrain(
    handler: MouseWarpHandler,
    iterations: Int = 100,
    condition: () -> Bool
) async {
    for _ in 0..<iterations where !condition() {
        await waitForMainRunLoopTurn()
    }

    if !condition() {
        let snapshot = handler.mouseWarpDebugSnapshot()
        Issue.record("Timed out waiting for scheduled mouse warp drain: \(snapshot)")
    }
}

@Suite struct MouseWarpHandlerTests {
    @Test @MainActor func queuedWarpMovesCollapseToLatestLocation() {
        let fixture = makeMouseWarpTestFixture()
        defer { fixture.handler.cleanup() }

        let firstLocation = CGPoint(x: fixture.leftMonitor.frame.midX, y: fixture.leftMonitor.frame.midY)
        let secondLocation = CGPoint(
            x: fixture.leftMonitor.frame.maxX - CGFloat(fixture.controller.settings.mouseWarpMargin) + 1,
            y: fixture.leftMonitor.frame.midY
        )

        fixture.handler.resetDebugStateForTests()
        fixture.handler.receiveTapMouseWarpMoved(at: firstLocation)
        fixture.handler.receiveTapMouseWarpMoved(at: secondLocation)
        fixture.handler.flushPendingWarpEventsForTests()

        let expectedPoint = ScreenCoordinateSpace.toWindowServer(point: CGPoint(
            x: fixture.rightMonitor.frame.minX + CGFloat(fixture.controller.settings.mouseWarpMargin) + 1,
            y: fixture.rightMonitor.frame.midY
        ))
        let snapshot = fixture.handler.mouseWarpDebugSnapshot()

        #expect(snapshot.queuedTransientEvents == 2)
        #expect(snapshot.coalescedTransientEvents == 1)
        #expect(snapshot.drainedTransientEvents == 1)
        #expect(snapshot.drainRuns == 1)
        #expect(fixture.handler.state.lastMonitorId == fixture.rightMonitor.id)
        #expect(fixture.recorder.warpedPoints.isEmpty)
        #expect(fixture.recorder.postedPoints == [expectedPoint])
    }

    @Test @MainActor func scheduledDrainProcessesOneBurstWithoutManualFlush() async {
        let fixture = makeMouseWarpTestFixture()
        defer { fixture.handler.cleanup() }

        let location = CGPoint(
            x: fixture.leftMonitor.frame.maxX - CGFloat(fixture.controller.settings.mouseWarpMargin) + 1,
            y: fixture.leftMonitor.frame.midY
        )

        fixture.handler.resetDebugStateForTests()
        fixture.handler.receiveTapMouseWarpMoved(at: location)
        fixture.handler.receiveTapMouseWarpMoved(at: location)

        await waitUntilMouseWarpDrain(handler: fixture.handler) {
            fixture.handler.mouseWarpDebugSnapshot().drainedTransientEvents == 1
        }

        let snapshot = fixture.handler.mouseWarpDebugSnapshot()
        #expect(snapshot.queuedTransientEvents == 2)
        #expect(snapshot.coalescedTransientEvents == 1)
        #expect(snapshot.drainedTransientEvents == 1)
        #expect(snapshot.drainRuns == 1)
        #expect(fixture.recorder.postedPoints.count == 1)
    }

    @Test @MainActor func latestDrainedLocationWarpsToCorrectNeighborMonitorAtEdge() {
        let fixture = makeMouseWarpTestFixture()
        defer { fixture.handler.cleanup() }

        let location = CGPoint(
            x: fixture.leftMonitor.frame.maxX - CGFloat(fixture.controller.settings.mouseWarpMargin) + 1,
            y: fixture.leftMonitor.frame.minY + 270
        )

        fixture.handler.resetDebugStateForTests()
        fixture.handler.receiveTapMouseWarpMoved(at: location)
        fixture.handler.flushPendingWarpEventsForTests()

        let yRatio = (fixture.leftMonitor.frame.maxY - location.y) / fixture.leftMonitor.frame.height
        let expectedPoint = ScreenCoordinateSpace.toWindowServer(point: CGPoint(
            x: fixture.rightMonitor.frame.minX + CGFloat(fixture.controller.settings.mouseWarpMargin) + 1,
            y: fixture.rightMonitor.frame.maxY - (yRatio * fixture.rightMonitor.frame.height)
        ))

        #expect(fixture.handler.state.lastMonitorId == fixture.rightMonitor.id)
        #expect(fixture.recorder.postedPoints == [expectedPoint])
    }

    @Test @MainActor func isWarpingSuppressesDrainedHandlerPath() {
        let fixture = makeMouseWarpTestFixture()
        defer { fixture.handler.cleanup() }

        let location = CGPoint(
            x: fixture.leftMonitor.frame.maxX - CGFloat(fixture.controller.settings.mouseWarpMargin) + 1,
            y: fixture.leftMonitor.frame.midY
        )

        fixture.handler.resetDebugStateForTests()
        fixture.handler.state.isWarping = true
        fixture.handler.receiveTapMouseWarpMoved(at: location)
        fixture.handler.flushPendingWarpEventsForTests()

        let snapshot = fixture.handler.mouseWarpDebugSnapshot()
        #expect(snapshot.queuedTransientEvents == 1)
        #expect(snapshot.coalescedTransientEvents == 0)
        #expect(snapshot.drainedTransientEvents == 1)
        #expect(snapshot.drainRuns == 1)
        #expect(fixture.handler.state.lastMonitorId == nil)
        #expect(fixture.recorder.warpedPoints.isEmpty)
        #expect(fixture.recorder.postedPoints.isEmpty)
    }

    @Test @MainActor func cleanupClearsPendingWarpStateBeforeScheduledDrain() async {
        let fixture = makeMouseWarpTestFixture()

        let location = CGPoint(
            x: fixture.leftMonitor.frame.maxX - CGFloat(fixture.controller.settings.mouseWarpMargin) + 1,
            y: fixture.leftMonitor.frame.midY
        )

        fixture.handler.resetDebugStateForTests()
        fixture.handler.receiveTapMouseWarpMoved(at: location)
        fixture.handler.cleanup()
        await waitForMainRunLoopTurn()

        let snapshot = fixture.handler.mouseWarpDebugSnapshot()
        #expect(snapshot.queuedTransientEvents == 0)
        #expect(snapshot.coalescedTransientEvents == 0)
        #expect(snapshot.drainedTransientEvents == 0)
        #expect(snapshot.drainRuns == 0)
        #expect(fixture.handler.state.pendingWarpEvents.pendingLocation == nil)
        #expect(fixture.handler.state.pendingWarpEvents.drainScheduled == false)
        #expect(fixture.handler.state.lastMonitorId == nil)
        #expect(fixture.handler.state.isWarping == false)
        #expect(fixture.recorder.warpedPoints.isEmpty)
        #expect(fixture.recorder.postedPoints.isEmpty)
    }
}
