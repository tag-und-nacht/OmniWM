// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct LifecyclePhaseFacetProjectionTests {
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
        windowId: Int,
        mode: TrackedWindowMode = .tiling
    ) -> WindowToken {
        manager.addWindow(
            AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceId,
            mode: mode
        )
    }

    @MainActor
    private func record(
        _ manager: WorkspaceManager,
        for token: WindowToken
    ) -> WindowLifecycleRecord? {
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token) else {
            return nil
        }
        return manager.logicalWindowRegistry.record(for: logicalId)
    }


    @Test func everyFlatPhaseProjectsOntoFacetsDeterministically() {
        let cases: [WindowLifecyclePhase] = [
            .discovered, .admitted, .tiled, .floating, .hidden,
            .offscreen, .restoring, .replacing, .nativeFullscreen,
            .destroyed
        ]
        for phase in cases {
            let projection = phase.facetProjection
            switch phase {
            case .discovered:
                #expect(projection.primary == .candidate)
            case .admitted:
                #expect(projection.primary == .admitted)
            case .destroyed:
                #expect(projection.primary == .retired)
            default:
                #expect(projection.primary == .managed)
            }
        }
    }

    @Test func nativeFullscreenProjectsToFullscreenFacet() {
        let projection = WindowLifecyclePhase.nativeFullscreen.facetProjection
        #expect(projection.primary == .managed)
        #expect(projection.visibility == .visible)
        #expect(projection.fullscreen == .nativeFullscreen)
    }

    @Test func hiddenProjectsToHiddenVisibility() {
        let projection = WindowLifecyclePhase.hidden.facetProjection
        #expect(projection.primary == .managed)
        #expect(projection.visibility == .hidden)
        #expect(projection.fullscreen == .none)
    }


    @Test @MainActor func applyLifecyclePhaseUpdatesEntryAndFacets() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6001)

        manager.applyLifecyclePhase(.nativeFullscreen, for: token)

        #expect(manager.lifecyclePhase(for: token) == .nativeFullscreen)
        let r = record(manager, for: token)
        #expect(r?.primaryPhase == .managed)
        #expect(r?.fullscreenSession == .nativeFullscreen)
        #expect(r?.visibility == .visible)
    }

    @Test @MainActor func applyHiddenSetsHiddenVisibilityFacet() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6002)

        manager.applyLifecyclePhase(.hidden, for: token)
        let r = record(manager, for: token)
        #expect(r?.visibility == .hidden)
        #expect(r?.fullscreenSession == FullscreenSessionState.none)
    }

    @Test @MainActor func applyDestroyedDoesNotPreemptRetirementSequence() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6003)

        manager.applyLifecyclePhase(.destroyed, for: token)
        let r = record(manager, for: token)
        #expect(r?.primaryPhase == .managed)
    }


    @Test @MainActor func addWindowSyncsVisibilityFacetForFreshLogicalId() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6004, mode: .tiling)

        let r = record(manager, for: token)
        #expect(r?.visibility == .visible, "tiled admit should sync visibility=visible")
    }


    @Test @MainActor func projectedLifecyclePhaseRoundTripsTiled() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6101, mode: .tiling)
        manager.applyLifecyclePhase(.tiled, for: token)
        #expect(manager.projectedLifecyclePhase(for: token) == .tiled)
    }

    @Test @MainActor func projectedLifecyclePhaseRoundTripsHidden() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6102, mode: .tiling)
        manager.applyLifecyclePhase(.hidden, for: token)
        #expect(manager.projectedLifecyclePhase(for: token) == .hidden)
    }

    @Test @MainActor func projectedLifecyclePhaseRoundTripsNativeFullscreen() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6103, mode: .tiling)
        manager.applyLifecyclePhase(.nativeFullscreen, for: token)
        #expect(manager.projectedLifecyclePhase(for: token) == .nativeFullscreen)
    }

    @Test @MainActor func projectedLifecyclePhaseReturnsNilForUnknownToken() {
        let (manager, _) = makeManager()
        let stranger = WindowToken(pid: 4242, windowId: 4242)
        #expect(manager.projectedLifecyclePhase(for: stranger) == nil)
    }

    @Test @MainActor func projectedLifecyclePhaseRetiredAfterRemoval() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 6104)
        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)

        guard case let .retired(logicalId) = manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected retired binding after removeWindow")
            return
        }
        let r = manager.logicalWindowRegistry.record(for: logicalId)
        #expect(r?.primaryPhase == .retired)
        #expect(manager.projectedLifecyclePhase(for: token) == .destroyed)
    }
}
