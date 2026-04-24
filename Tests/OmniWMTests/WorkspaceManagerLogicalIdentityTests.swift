// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct WorkspaceManagerLogicalIdentityTests {
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


    @Test @MainActor func addWindowAllocatesLogicalIdOnceAndPhaseIsManaged() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 4001)

        let binding = manager.logicalWindowRegistry.lookup(token: token)
        guard case let .current(logicalId) = binding else {
            Issue.record("Expected .current binding after addWindow, got \(binding)")
            return
        }
        let record = manager.logicalWindowRegistry.record(for: logicalId)
        #expect(record?.primaryPhase == .managed)
        #expect(record?.currentToken == token)
        #expect(record?.replacementEpoch == ReplacementEpoch(value: 0))
        #expect(record?.lastKnownWorkspaceId == workspaceId)
    }

    @Test @MainActor func setWorkspaceUpdatesLifecycleAssignment() {
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main),
            WorkspaceConfiguration(name: "2", monitorAssignment: .main)
        ]
        let manager = WorkspaceManager(settings: settings)
        manager.applyMonitorConfigurationChange([makeLayoutPlanTestMonitor()])
        let workspaceOne = manager.workspaceId(for: "1", createIfMissing: false)!
        let workspaceTwo = manager.workspaceId(for: "2", createIfMissing: false)!
        _ = manager.setActiveWorkspace(workspaceOne, on: manager.monitors.first!.id)
        let token = addWindow(manager, workspaceId: workspaceOne, windowId: 4003)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Expected current binding")
            return
        }

        manager.setWorkspace(for: token, to: workspaceTwo)

        let record = manager.logicalWindowRegistry.record(for: logicalId)
        #expect(record?.lastKnownWorkspaceId == workspaceTwo)
        #expect(record?.lastKnownMonitorId == manager.monitorId(for: workspaceTwo))
    }

    @Test @MainActor func duplicateAddWindowDoesNotAllocateSecondLogicalId() {
        let (manager, workspaceId) = makeManager()
        let first = addWindow(manager, workspaceId: workspaceId, windowId: 4002)
        let second = addWindow(manager, workspaceId: workspaceId, windowId: 4002)

        #expect(first == second)
        guard case let .current(firstId) = manager.logicalWindowRegistry.lookup(token: first),
              case let .current(secondId) = manager.logicalWindowRegistry.lookup(token: second)
        else {
            Issue.record("Expected .current bindings for both calls")
            return
        }
        #expect(firstId == secondId)
        #expect(manager.logicalWindowRegistry.activeRecords().count == 1)
    }


    @Test @MainActor func rekeyPreservesLogicalIdentityBumpsEpochDemotesOldTokenToStale() {
        let (manager, workspaceId) = makeManager()
        let oldToken = addWindow(manager, workspaceId: workspaceId, windowId: 4010)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: oldToken)
        else {
            Issue.record("Expected current binding for original token")
            return
        }

        let newToken = WindowToken(pid: getpid(), windowId: 4011)
        _ = manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 4011)
        )

        #expect(manager.logicalWindowRegistry.lookup(token: newToken) == .current(logicalId))
        #expect(manager.logicalWindowRegistry.lookup(token: oldToken) == .staleAlias(logicalId))
        #expect(manager.logicalWindowRegistry.record(for: logicalId)?.replacementEpoch
            == ReplacementEpoch(value: 1))
    }


    @Test @MainActor func removeWindowRetiresLogicalIdWhichCannotBeFocusedLaidOutOrRekeyed() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 4020)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Expected current binding")
            return
        }

        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)

        #expect(manager.logicalWindowRegistry.lookup(token: token) == .retired(logicalId))
        let reuse = WindowToken(pid: token.pid, windowId: 9999)
        let rekeyed = manager.rekeyWindow(
            from: token,
            to: reuse,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: reuse.windowId)
        )
        #expect(rekeyed == nil, "retired entries cannot be rekeyed at the manager seam")
    }


    @Test @MainActor func nativeFullscreenRecordIsKeyedByLogicalIdAfterEnter() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 4030)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Missing current binding")
            return
        }

        _ = manager.requestNativeFullscreenEnter(token, in: workspaceId)
        let record = manager.nativeFullscreenRecord(for: token)
        #expect(record != nil)
        #expect(record?.logicalId == logicalId)
        #expect(record?.originalToken == token)
        #expect(record?.currentToken == token)
    }

    @Test @MainActor func fullscreenEnterExitPreservesLogicalIdentityAcrossReplacement() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 4040)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Missing current binding")
            return
        }

        _ = manager.requestNativeFullscreenEnter(token, in: workspaceId)
        _ = manager.markNativeFullscreenSuspended(
            token,
            restoreSnapshot: WorkspaceManager.NativeFullscreenRecord.RestoreSnapshot(
                frame: CGRect(x: 10, y: 10, width: 800, height: 600),
                topologyProfile: manager.topologyProfile
            )
        )

        let replacementToken = WindowToken(pid: token.pid, windowId: 4041)
        _ = manager.rekeyWindow(
            from: token,
            to: replacementToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 4041)
        )
        let afterRekey = manager.nativeFullscreenRecord(for: replacementToken)
        #expect(afterRekey?.logicalId == logicalId)
        #expect(afterRekey?.currentToken == replacementToken)

        _ = manager.requestNativeFullscreenExit(replacementToken, initiatedByCommand: true)
        _ = manager.beginNativeFullscreenRestore(for: replacementToken)
        #expect(
            manager.nativeFullscreenRecord(for: replacementToken)?.logicalId == logicalId
        )

        _ = manager.finalizeNativeFullscreenRestore(for: replacementToken)
        #expect(manager.nativeFullscreenRecord(for: replacementToken) == nil)
        #expect(
            manager.logicalWindowRegistry.lookup(token: replacementToken) == .current(logicalId)
        )
    }

    @Test @MainActor func staleDestroyForOldTokenDoesNotRetireReplacement() {
        let (manager, workspaceId) = makeManager()
        let oldToken = addWindow(manager, workspaceId: workspaceId, windowId: 4050)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: oldToken)
        else {
            Issue.record("Missing current binding")
            return
        }

        let newToken = WindowToken(pid: oldToken.pid, windowId: 4051)
        _ = manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 4051)
        )
        #expect(manager.logicalWindowRegistry.lookup(token: newToken) == .current(logicalId))

        let removedEntry = manager.removeWindow(pid: oldToken.pid, windowId: oldToken.windowId)
        #expect(removedEntry == nil)
        #expect(manager.logicalWindowRegistry.lookup(token: newToken) == .current(logicalId))
        #expect(manager.logicalWindowRegistry.record(for: logicalId)?.primaryPhase == .managed)
    }

    @Test @MainActor func staleTokenNativeFullscreenWritesAreRejected() {
        let (manager, workspaceId) = makeManager()
        let oldToken = addWindow(manager, workspaceId: workspaceId, windowId: 4060)

        _ = manager.requestNativeFullscreenEnter(oldToken, in: workspaceId)
        _ = manager.markNativeFullscreenSuspended(
            oldToken,
            restoreSnapshot: WorkspaceManager.NativeFullscreenRecord.RestoreSnapshot(
                frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                topologyProfile: manager.topologyProfile
            )
        )

        let newToken = WindowToken(pid: oldToken.pid, windowId: 4061)
        _ = manager.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: 4061)
        )

        #expect(manager.nativeFullscreenRecord(for: oldToken)?.currentToken == newToken)

        let exitViaStale = manager.requestNativeFullscreenExit(
            oldToken,
            initiatedByCommand: true
        )
        #expect(exitViaStale == false)
        #expect(manager.nativeFullscreenRecord(for: newToken)?.currentToken == newToken)

        let beginViaStale = manager.beginNativeFullscreenRestore(for: oldToken)
        #expect(beginViaStale == nil)
        #expect(manager.nativeFullscreenRecord(for: newToken)?.currentToken == newToken)

        let restoreViaStale = manager.restoreNativeFullscreenRecord(for: oldToken)
        #expect(restoreViaStale == nil)
        #expect(manager.nativeFullscreenRecord(for: newToken) != nil)

        _ = manager.requestNativeFullscreenExit(newToken, initiatedByCommand: true)
        _ = manager.beginNativeFullscreenRestore(for: newToken)
        _ = manager.finalizeNativeFullscreenRestore(for: newToken)
        #expect(manager.nativeFullscreenRecord(for: newToken) == nil)
    }

    @Test @MainActor func nativeFullscreenWriteRejectsRetiredLogicalId() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 4070)
        _ = manager.removeWindow(pid: token.pid, windowId: token.windowId)

        let entered = manager.requestNativeFullscreenEnter(token, in: workspaceId)
        #expect(entered == false)
        #expect(manager.nativeFullscreenRecord(for: token) == nil)
    }

    @Test @MainActor func nativeFullscreenWriteRejectsUnknownToken() {
        let (manager, workspaceId) = makeManager()
        let phantom = WindowToken(pid: 0xBEEF, windowId: 6000)
        let entered = manager.requestNativeFullscreenEnter(phantom, in: workspaceId)
        #expect(entered == false)
        #expect(manager.nativeFullscreenRecord(for: phantom) == nil)
    }


    @Test @MainActor func nativeFullscreenRecordLogicalIdMatchesRegistryBinding() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 4080)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Missing current binding")
            return
        }
        _ = manager.requestNativeFullscreenEnter(token, in: workspaceId)
        #expect(manager.nativeFullscreenRecord(for: token)?.logicalId == logicalId)
    }


    @Test @MainActor func beginNativeFullscreenRestoreByLogicalIdMatchesTokenPath() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 4090)
        _ = manager.requestNativeFullscreenEnter(token, in: workspaceId)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Missing current binding")
            return
        }

        let viaLogicalId = manager.beginNativeFullscreenRestore(forLogicalId: logicalId)
        #expect(viaLogicalId == nil)
        let viaToken = manager.beginNativeFullscreenRestore(for: token)
        #expect(viaToken == nil)
    }

    @Test @MainActor func finalizeNativeFullscreenRestoreByLogicalIdMatchesTokenPath() {
        let (manager, workspaceId) = makeManager()
        let token = addWindow(manager, workspaceId: workspaceId, windowId: 4091)
        _ = manager.requestNativeFullscreenEnter(token, in: workspaceId)
        guard case let .current(logicalId) = manager.logicalWindowRegistry.lookup(token: token)
        else {
            Issue.record("Missing current binding")
            return
        }
        let viaLogicalId = manager.finalizeNativeFullscreenRestore(forLogicalId: logicalId)
        #expect(viaLogicalId == nil)
        let viaToken = manager.finalizeNativeFullscreenRestore(for: token)
        #expect(viaToken == nil)
    }

    @Test @MainActor func canonicalLogicalIdAccessorRejectsUnknownLogicalId() {
        let (manager, _) = makeManager()
        let phantom = LogicalWindowId(value: 99_999)
        #expect(manager.beginNativeFullscreenRestore(forLogicalId: phantom) == nil)
        #expect(manager.finalizeNativeFullscreenRestore(forLogicalId: phantom) == nil)
    }


}
