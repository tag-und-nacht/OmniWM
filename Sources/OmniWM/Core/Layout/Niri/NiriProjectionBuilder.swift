// SPDX-License-Identifier: GPL-2.0-only
import AppKit
import CoreGraphics
import Foundation

struct NiriProjectionBuilder {
    let graph: WorkspaceGraph
    let topology: MonitorTopologyState
    let lifecycle: LayoutLifecycleProvider

    @MainActor
    // swiftlint:disable:next function_parameter_count
    func buildSnapshot(
        for workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID,
        viewportState: ViewportState,
        preferredFocusToken: WindowToken?,
        confirmedFocusedToken: WindowToken?,
        pendingFocusedToken: WindowToken?,
        pendingFocusedWorkspaceId: WorkspaceDescriptor.ID?,
        isNonManagedFocusActive: Bool,
        hasCompletedInitialRefresh: Bool,
        useScrollAnimationPath: Bool,
        removalSeed: NiriWindowRemovalSeed?,
        gap: CGFloat,
        outerGaps: LayoutGaps.OuterGaps,
        displayRefreshRate: Double,
        isActiveWorkspace: Bool,
        isInteractionWorkspace: Bool,
        orientationOverride: Monitor.Orientation? = nil
    ) -> NiriWorkspaceSnapshot? {
        guard let monitorNode = topology.node(monitorId) else { return nil }
        guard graph.node(for: workspaceId) != nil else { return nil }

        let monitorSnapshot = LayoutMonitorSnapshot(
            monitorId: monitorNode.monitorId,
            displayId: monitorNode.displayId,
            frame: monitorNode.frame.raw,
            visibleFrame: monitorNode.visibleFrame.raw,
            workingFrame: monitorNode.workingFrame.raw,
            scale: monitorNode.scale,
            orientation: orientationOverride ?? monitorNode.orientation
        )

        let tiledEntries = graph.tiledMembership(in: workspaceId)
        let windows: [LayoutWindowSnapshot] = tiledEntries.map { entry in
            LayoutWindowSnapshot.projected(from: entry, lifecycle: lifecycle)
        }

        return NiriWorkspaceSnapshot(
            workspaceId: workspaceId,
            monitor: monitorSnapshot,
            windows: windows,
            viewportState: viewportState,
            preferredFocusToken: preferredFocusToken,
            confirmedFocusedToken: confirmedFocusedToken,
            pendingFocusedToken: pendingFocusedToken,
            pendingFocusedWorkspaceId: pendingFocusedWorkspaceId,
            isNonManagedFocusActive: isNonManagedFocusActive,
            hasCompletedInitialRefresh: hasCompletedInitialRefresh,
            useScrollAnimationPath: useScrollAnimationPath,
            removalSeed: removalSeed,
            gap: gap,
            outerGaps: outerGaps,
            displayRefreshRate: displayRefreshRate,
            isActiveWorkspace: isActiveWorkspace,
            isInteractionWorkspace: isInteractionWorkspace
        )
    }
}

enum NiriSnapshotParity {
    enum Drift: Equatable {
        case windowCountDiffers(legacy: Int, projection: Int)
        case windowTokenOrderDiffers(index: Int, legacy: WindowToken, projection: WindowToken)
        case windowFieldDiffers(index: Int, token: WindowToken, field: String)
        case monitorFieldDiffers(field: String)
        case workspaceIdDiffers
    }

    static func diff(
        legacy: NiriWorkspaceSnapshot,
        projection: NiriWorkspaceSnapshot
    ) -> Drift? {
        if legacy.workspaceId != projection.workspaceId {
            return .workspaceIdDiffers
        }
        if let drift = monitorDrift(legacy: legacy.monitor, projection: projection.monitor) {
            return drift
        }
        if legacy.windows.count != projection.windows.count {
            return .windowCountDiffers(legacy: legacy.windows.count, projection: projection.windows.count)
        }
        for (index, (legacyWindow, projectionWindow)) in zip(legacy.windows, projection.windows).enumerated() {
            if legacyWindow.token != projectionWindow.token {
                return .windowTokenOrderDiffers(
                    index: index,
                    legacy: legacyWindow.token,
                    projection: projectionWindow.token
                )
            }
            if legacyWindow.constraints != projectionWindow.constraints {
                return .windowFieldDiffers(index: index, token: legacyWindow.token, field: "constraints")
            }
            if legacyWindow.hiddenState != projectionWindow.hiddenState {
                return .windowFieldDiffers(index: index, token: legacyWindow.token, field: "hiddenState")
            }
            if legacyWindow.layoutReason != projectionWindow.layoutReason {
                return .windowFieldDiffers(index: index, token: legacyWindow.token, field: "layoutReason")
            }
            if legacyWindow.nativeFullscreenRestore != projectionWindow.nativeFullscreenRestore {
                return .windowFieldDiffers(
                    index: index,
                    token: legacyWindow.token,
                    field: "nativeFullscreenRestore"
                )
            }
        }
        return nil
    }

    private static func monitorDrift(
        legacy: LayoutMonitorSnapshot,
        projection: LayoutMonitorSnapshot
    ) -> Drift? {
        if legacy.monitorId != projection.monitorId { return .monitorFieldDiffers(field: "monitorId") }
        if legacy.displayId != projection.displayId { return .monitorFieldDiffers(field: "displayId") }
        if legacy.frame != projection.frame { return .monitorFieldDiffers(field: "frame") }
        if legacy.visibleFrame != projection.visibleFrame { return .monitorFieldDiffers(field: "visibleFrame") }
        if legacy.workingFrame != projection.workingFrame { return .monitorFieldDiffers(field: "workingFrame") }
        if legacy.scale != projection.scale { return .monitorFieldDiffers(field: "scale") }
        if legacy.orientation != projection.orientation { return .monitorFieldDiffers(field: "orientation") }
        return nil
    }
}
