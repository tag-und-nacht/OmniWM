// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct ManagedRestoreSnapshotLogicalIdentityTests {
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

    @MainActor
    private func makeSnapshot(
        manager: WorkspaceManager,
        workspaceId: WorkspaceDescriptor.ID,
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        columnMemberTokens: [WindowToken],
        columnIndex: Int = 0,
        tileIndex: Int = 0
    ) -> ManagedWindowRestoreSnapshot {
        let registry = manager.logicalWindowRegistry
        let columnMembers = columnMemberTokens.compactMap {
            registry.resolveForWrite(token: $0)
        }
        let niri = ManagedWindowRestoreSnapshot.NiriState(
            nodeId: nil,
            columnIndex: columnIndex,
            tileIndex: tileIndex,
            columnWindowMembers: columnMembers,
            columnSizing: .init(
                width: .proportion(0.5),
                cachedWidth: 400,
                presetWidthIdx: nil,
                isFullWidth: false,
                savedWidth: nil,
                hasManualSingleWindowWidthOverride: false,
                height: .proportion(1.0),
                cachedHeight: 600,
                isFullHeight: false,
                savedHeight: nil
            ),
            windowSizing: .init(
                height: .auto(weight: 1.0),
                savedHeight: nil,
                windowWidth: .auto(weight: 1.0),
                sizingMode: .normal
            )
        )
        return ManagedWindowRestoreSnapshot(
            workspaceId: workspaceId,
            frame: frame,
            topologyProfile: manager.topologyProfile,
            niriState: niri,
            replacementMetadata: nil
        )
    }


    @Test @MainActor func snapshotDoesNotCarryAnEphemeralToken() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7001)
        let snapshot = makeSnapshot(
            manager: manager,
            workspaceId: workspaceId,
            columnMemberTokens: [token]
        )
        #expect(snapshot.workspaceId == workspaceId)
        #expect(snapshot.niriState?.columnWindowMembers.count == 1)
    }


    @Test @MainActor func columnMembersIdentitySurvivesSiblingRekey() {
        let (manager, workspaceId) = makeManager()
        let aToken = addWindow(manager, workspaceId: workspaceId, windowId: 7011)
        let bToken = addWindow(manager, workspaceId: workspaceId, windowId: 7012)
        let snapshotA = makeSnapshot(
            manager: manager,
            workspaceId: workspaceId,
            columnMemberTokens: [aToken, bToken]
        )
        _ = manager.setManagedRestoreSnapshot(snapshotA, for: aToken)

        let bNewToken = WindowToken(pid: bToken.pid, windowId: 7013)
        _ = manager.rekeyWindow(
            from: bToken,
            to: bNewToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 7013)
        )

        let storedSnapshot = manager.managedRestoreSnapshot(for: aToken)
        #expect(storedSnapshot != nil)
        #expect(storedSnapshot?.niriState?.columnWindowMembers
            == snapshotA.niriState?.columnWindowMembers)
    }


    @Test @MainActor func snapshotEqualityStableAcrossOwnerRekey() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7021)
        let original = makeSnapshot(
            manager: manager,
            workspaceId: workspaceId,
            columnMemberTokens: [token]
        )
        _ = manager.setManagedRestoreSnapshot(original, for: token)

        let newToken = WindowToken(pid: token.pid, windowId: 7022)
        _ = manager.rekeyWindow(
            from: token,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 7022)
        )

        let after = manager.managedRestoreSnapshot(for: newToken)
        #expect(after == original)
    }


    @Test @MainActor func rekeyOnlyUpdatesReplacementMetadataField() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7031)
        let original = makeSnapshot(
            manager: manager,
            workspaceId: workspaceId,
            columnMemberTokens: [token]
        )
        _ = manager.setManagedRestoreSnapshot(original, for: token)

        let newToken = WindowToken(pid: token.pid, windowId: 7032)
        let metadata = ManagedReplacementMetadata(
            bundleId: "com.example.app",
            workspaceId: workspaceId,
            mode: .tiling,
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            title: "After",
            windowLevel: 0,
            parentWindowId: nil,
            frame: original.frame
        )
        _ = manager.rekeyWindow(
            from: token,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 7032),
            managedReplacementMetadata: metadata
        )

        let after = manager.managedRestoreSnapshot(for: newToken)
        #expect(after?.workspaceId == original.workspaceId)
        #expect(after?.frame == original.frame)
        #expect(after?.niriState == original.niriState)
        #expect(after?.topologyProfile == original.topologyProfile)
        #expect(after?.replacementMetadata?.title == "After")
    }


    @Test @MainActor func snapshotIsAddressableByLogicalIdAfterStorageMove() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7101)
        let snapshot = makeSnapshot(
            manager: manager,
            workspaceId: workspaceId,
            columnMemberTokens: [token]
        )
        _ = manager.setManagedRestoreSnapshot(snapshot, for: token)

        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current logical-id binding")
            return
        }
        #expect(manager.managedRestoreSnapshot(forLogicalId: logicalId) == snapshot)
        #expect(manager.managedRestoreSnapshot(for: token) == snapshot)
    }

    @Test @MainActor func snapshotSurvivesOwnerRekeyWithoutCopy() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7111)
        let original = makeSnapshot(
            manager: manager,
            workspaceId: workspaceId,
            columnMemberTokens: [token]
        )
        _ = manager.setManagedRestoreSnapshot(original, for: token)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current logical-id binding")
            return
        }

        let newToken = WindowToken(pid: token.pid, windowId: 7112)
        _ = manager.rekeyWindow(
            from: token,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 7112)
        )

        #expect(manager.managedRestoreSnapshot(forLogicalId: logicalId) == original)
        #expect(manager.managedRestoreSnapshot(for: newToken) == original)
        #expect(manager.managedRestoreSnapshot(for: token) == original)
    }

    @Test @MainActor func snapshotEntryDroppedOnRetirement() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 7121)
        let snapshot = makeSnapshot(
            manager: manager,
            workspaceId: workspaceId,
            columnMemberTokens: [token]
        )
        _ = manager.setManagedRestoreSnapshot(snapshot, for: token)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token) else {
            Issue.record("Expected current logical-id binding")
            return
        }
        #expect(manager.managedRestoreSnapshot(forLogicalId: logicalId) != nil)

        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)

        #expect(manager.managedRestoreSnapshot(forLogicalId: logicalId) == nil)
        #expect(manager.managedRestoreSnapshot(for: token) == nil)
    }
}
