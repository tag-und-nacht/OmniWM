// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct LifecycleFrameFacetTests {
    @MainActor
    private func makeManager() -> (WorkspaceManager, WorkspaceDescriptor.ID) {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let manager = WorkspaceManager(settings: settings)
        manager.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let workspaceId = manager.workspaceId(for: "1", createIfMissing: false)!
        _ = manager.setActiveWorkspace(workspaceId, on: manager.monitors.first!.id)
        return (manager, workspaceId)
    }

    @MainActor
    private func addWindow(
        _ manager: WorkspaceManager,
        workspaceId: WorkspaceDescriptor.ID,
        windowId: Int
    ) -> WindowToken {
        manager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceId
        )
    }

    @Test @MainActor func joinedAccessorReturnsRecordAndNilFrameForFreshAdmission() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7401)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id for fresh admission")
            return
        }
        let joined = manager.lifecycleRecordWithFrame(for: logicalId)
        #expect(joined != nil)
        #expect(joined?.record.logicalId == logicalId)
        #expect(joined?.frame == nil)
    }

    @Test @MainActor func joinedAccessorPicksUpDesiredFrame() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7402)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id")
            return
        }
        let frame = FrameState.Frame(
            rect: CGRect(x: 100, y: 100, width: 800, height: 600),
            space: .appKit,
            isVisibleFrame: true
        )
        _ = manager.recordDesiredFrame(frame, for: token)

        let joined = manager.lifecycleRecordWithFrame(for: logicalId)
        #expect(joined?.frame?.desired == frame)
    }

    @Test @MainActor func joinedAccessorReturnsNilForRetiredId() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7403)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id")
            return
        }
        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)
        let joined = manager.lifecycleRecordWithFrame(for: logicalId)
        #expect(joined?.frame == nil)
    }

    @Test @MainActor func frameStateDroppedOnRetirement() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7404)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id")
            return
        }
        let frame = FrameState.Frame(
            rect: CGRect(x: 50, y: 50, width: 400, height: 300),
            space: .appKit,
            isVisibleFrame: true
        )
        _ = manager.recordDesiredFrame(frame, for: token)
        #expect(manager.frameState(for: logicalId)?.desired == frame)

        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)
        #expect(manager.frameState(for: logicalId) == nil)
    }

    @Test @MainActor func joinedAccessorReturnsTypedProjection() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7405)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id")
            return
        }
        let projection: WindowLifecycleRecordWithFrame? = manager.lifecycleRecordWithFrame(for: logicalId)
        #expect(projection != nil)
        #expect(projection?.record.logicalId == logicalId)
        #expect(projection?.frame == manager.frameState(for: logicalId))
    }

    @Test @MainActor func projectionFrameMatchesAuthoritativeFrameState() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7406)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId else {
            Issue.record("Expected logical id")
            return
        }
        let observed = FrameState.Frame(
            rect: CGRect(x: 10, y: 20, width: 640, height: 480),
            space: .appKit,
            isVisibleFrame: true
        )
        _ = manager.recordObservedFrame(observed, for: token)

        let projection = manager.lifecycleRecordWithFrame(for: logicalId)
        #expect(projection?.frame?.observed == observed)
        #expect(projection?.frame == manager.frameState(for: logicalId))
    }

    @Test @MainActor func recordFrameProjectionViaLookupClosure() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7407)
        guard let logicalId = manager.logicalWindowRegistry.lookup(token: token).liveLogicalId,
              let record = manager.logicalWindowRegistry.record(for: logicalId)
        else {
            Issue.record("Expected logical id and record")
            return
        }
        let frame = FrameState.Frame(
            rect: CGRect(x: 1, y: 2, width: 3, height: 4),
            space: .appKit,
            isVisibleFrame: true
        )
        var seeded = FrameState.initial
        seeded.recordDesired(frame)
        let table: [LogicalWindowId: FrameState] = [logicalId: seeded]
        let projection = record.frameProjection { id in table[id] }
        #expect(projection.record.logicalId == logicalId)
        #expect(projection.frame?.desired == frame)
    }
}
