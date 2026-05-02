// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct BorderCoordinatorLogicalIdentityTests {
    @MainActor
    private func makeController() -> (WMController, WorkspaceDescriptor.ID) {
        let controller = makeLayoutPlanTestController()
        let workspaceId = controller.activeWorkspace()!.id
        controller.setBordersEnabled(true)
        controller.axEventHandler.windowInfoProvider = { _ in nil }
        controller.axEventHandler.windowFactsProvider = { axRef, _ in
            WindowRuleFacts(
                appName: nil,
                ax: AXWindowFacts(
                    role: kAXWindowRole as String,
                    subrole: kAXStandardWindowSubrole as String,
                    title: "w\(axRef.windowId)",
                    hasCloseButton: true,
                    hasFullscreenButton: true,
                    fullscreenButtonEnabled: true,
                    hasZoomButton: true,
                    hasMinimizeButton: true,
                    appPolicy: .regular,
                    bundleId: "com.example.app",
                    attributeFetchSucceeded: true
                ),
                sizeConstraints: nil,
                windowServer: nil
            )
        }
        controller.axEventHandler.isFullscreenProvider = { _ in false }
        controller.borderCoordinator.minimizedProviderForTests = { _ in false }
        return (controller, workspaceId)
    }

    @MainActor
    private func addWindow(
        _ controller: WMController,
        workspaceId: WorkspaceDescriptor.ID,
        windowId: Int
    ) -> (WindowToken, AXWindowRef) {
        let axRef = AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId)
        let token = controller.workspaceManager.addWindow(
            axRef,
            pid: getpid(),
            windowId: windowId,
            to: workspaceId
        )
        return (token, axRef)
    }

    @MainActor
    private func renderBorder(
        _ controller: WMController,
        for token: WindowToken,
        axRef: AXWindowRef,
        frame: CGRect
    ) {
        let target = controller.keyboardFocusTarget(for: token, axRef: axRef)
        _ = controller.borderCoordinator.reconcile(
            event: .renderRequested(
                source: .manualRender,
                target: target,
                preferredFrame: frame,
                policy: .coordinated
            )
        )
    }


    @Test @MainActor func managedOwnerCarriesLogicalIdAndReplacementEpoch() {
        let (controller, workspaceId) = makeController()
        let (token, axRef) = addWindow(controller, workspaceId: workspaceId, windowId: 2001)
        renderBorder(controller, for: token, axRef: axRef, frame: CGRect(x: 10, y: 10, width: 400, height: 300))

        guard case let .managed(logicalId, replacementEpoch, ownerWorkspaceId)
            = controller.borderCoordinator.ownerStateSnapshotForTests().owner
        else {
            Issue.record("Expected managed border owner after initial render")
            return
        }
        let expectedLogicalId = controller.workspaceManager.logicalWindowRegistry
            .resolveForWrite(token: token)
        #expect(expectedLogicalId == logicalId)
        #expect(replacementEpoch == ReplacementEpoch(value: 0))
        #expect(ownerWorkspaceId == workspaceId)
    }


    @Test @MainActor func rekeyUpdatesOwnerEpochAndResolvesToNewToken() {
        let (controller, workspaceId) = makeController()
        let (oldToken, oldAxRef) = addWindow(controller, workspaceId: workspaceId, windowId: 2011)
        renderBorder(controller, for: oldToken, axRef: oldAxRef, frame: CGRect(x: 10, y: 10, width: 400, height: 300))

        guard case let .managed(logicalIdBefore, epochBefore, _)
            = controller.borderCoordinator.ownerStateSnapshotForTests().owner
        else {
            Issue.record("Pre-rekey owner must be managed")
            return
        }

        let newToken = WindowToken(pid: oldToken.pid, windowId: 2012)
        let newAxRef = AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 2012)
        _ = controller.workspaceManager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: newAxRef
        )
        let registry = controller.workspaceManager.logicalWindowRegistry
        guard let postLogicalId = registry.resolveForWrite(token: newToken),
              let postEpoch = registry.record(for: postLogicalId)?.replacementEpoch
        else {
            Issue.record("Expected current logical-id binding after rekey")
            return
        }
        _ = controller.borderCoordinator.reconcile(
            event: .managedRekey(
                logicalId: postLogicalId,
                replacementEpoch: postEpoch,
                newToken: newToken,
                workspaceId: workspaceId,
                axRef: newAxRef,
                preferredFrame: CGRect(x: 20, y: 20, width: 420, height: 320),
                policy: .coordinated
            )
        )

        let afterOwner = controller.borderCoordinator.ownerStateSnapshotForTests().owner
        guard case let .managed(logicalIdAfter, epochAfter, _) = afterOwner else {
            Issue.record("Post-rekey owner must still be managed; got \(afterOwner)")
            return
        }
        #expect(logicalIdAfter == logicalIdBefore)
        #expect(epochAfter > epochBefore)
    }


    @Test @MainActor func ownerAfterRekeyResolvesToNewTokenEvenWhenProbedWithOldToken() {
        let (controller, workspaceId) = makeController()
        let (oldToken, oldAxRef) = addWindow(controller, workspaceId: workspaceId, windowId: 2021)
        renderBorder(controller, for: oldToken, axRef: oldAxRef, frame: CGRect(x: 10, y: 10, width: 400, height: 300))

        let newToken = WindowToken(pid: oldToken.pid, windowId: 2022)
        let newAxRef = AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 2022)
        _ = controller.workspaceManager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: newAxRef
        )
        let postRegistry = controller.workspaceManager.logicalWindowRegistry
        guard let postLogicalId2 = postRegistry.resolveForWrite(token: newToken),
              let postEpoch2 = postRegistry.record(for: postLogicalId2)?.replacementEpoch
        else {
            Issue.record("Expected current logical-id binding after rekey")
            return
        }
        _ = controller.borderCoordinator.reconcile(
            event: .managedRekey(
                logicalId: postLogicalId2,
                replacementEpoch: postEpoch2,
                newToken: newToken,
                workspaceId: workspaceId,
                axRef: newAxRef,
                preferredFrame: nil,
                policy: .coordinated
            )
        )

        _ = controller.borderCoordinator.reconcile(
            event: .invalidate(
                source: .managedRekey,
                reason: "stale-probe",
                matchingToken: oldToken,
                matchingPid: nil,
                matchingWindowId: nil
            )
        )

        #expect(controller.borderCoordinator.ownerStateSnapshotForTests().owner == .none)
    }


    @Test @MainActor func cgsDestroyedBeforeRetirementTearsDownManagedOwner() {
        let (controller, workspaceId) = makeController()
        let (token, axRef) = addWindow(controller, workspaceId: workspaceId, windowId: 2031)
        renderBorder(controller, for: token, axRef: axRef, frame: CGRect(x: 10, y: 10, width: 400, height: 300))

        _ = controller.borderCoordinator.reconcile(
            event: .cgsDestroyed(windowId: UInt32(token.windowId))
        )
        #expect(controller.borderCoordinator.ownerStateSnapshotForTests().owner == .none)
    }

    @Test @MainActor func retiredLogicalIdCannotBeReadoptedAsManagedOwner() {
        let (controller, workspaceId) = makeController()
        let (token, axRef) = addWindow(controller, workspaceId: workspaceId, windowId: 2032)
        renderBorder(controller, for: token, axRef: axRef, frame: CGRect(x: 10, y: 10, width: 400, height: 300))

        _ = controller.workspaceManager.removeWindow(pid: token.pid, windowId: token.windowId)
        renderBorder(
            controller,
            for: token,
            axRef: axRef,
            frame: CGRect(x: 10, y: 10, width: 400, height: 300)
        )
        let owner = controller.borderCoordinator.ownerStateSnapshotForTests().owner
        #expect(!owner.isManaged)
    }


    @Test @MainActor func fallbackOwnerStillUsesRawPidAndWindowId() {
        let (controller, _) = makeController()
        let unmanagedWid = 2041
        let axRef = AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: unmanagedWid)
        let target = KeyboardFocusTarget(
            token: WindowToken(pid: getpid(), windowId: unmanagedWid),
            axRef: axRef,
            workspaceId: nil,
            isManaged: false
        )
        _ = controller.borderCoordinator.reconcile(
            event: .renderRequested(
                source: .manualRender,
                target: target,
                preferredFrame: CGRect(x: 10, y: 10, width: 400, height: 300),
                policy: .coordinated
            )
        )
        let owner = controller.borderCoordinator.ownerStateSnapshotForTests().owner
        if case let .fallback(pid, wid) = owner {
            #expect(pid == getpid())
            #expect(wid == unmanagedWid)
        } else {
            #expect(owner == .none)
        }
    }
}
