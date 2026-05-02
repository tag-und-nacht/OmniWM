// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct AXAdmitRemoveRekeyThroughRuntimeTests {
    @Test @MainActor func admitWindowAllocatesAndStampsTransactionEpoch() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 4242),
            pid: getpid(),
            windowId: 4242,
            to: workspaceId,
            mode: .tiling,
            ruleEffects: .none,
            managedReplacementMetadata: nil,
            source: .ax
        )

        #expect(token.windowId == 4242)
        #expect(runtime.controller.workspaceManager.entry(for: token) != nil)
    }

    @Test @MainActor func consecutiveAXAdmitsAdvanceTransactionEpoch() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        let baseline = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "1"))
        )
        _ = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 5001),
            pid: getpid(),
            windowId: 5001,
            to: workspaceId,
            source: .ax
        )
        _ = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 5002),
            pid: getpid(),
            windowId: 5002,
            to: workspaceId,
            source: .ax
        )
        let after = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "1"))
        )
        let advance = after.transactionEpoch.value - baseline.transactionEpoch.value
        #expect(advance >= 3)
    }

    @Test @MainActor func runtimeAdmitMatchesAddWindowResult() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let runtimeToken = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 7001),
            pid: getpid(),
            windowId: 7001,
            to: workspaceId,
            source: .ax
        )

        let directController = makeLayoutPlanTestController()
        let directWorkspaceId = directController.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let directToken = directController.workspaceManager.addWindow(
            makeLayoutPlanTestWindow(windowId: 7001),
            pid: getpid(),
            windowId: 7001,
            to: directWorkspaceId
        )
        #expect(runtimeToken == directToken)
    }

    @Test @MainActor func rekeyWindowThroughRuntimeReturnsEntry() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let originalToken = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 8001),
            pid: getpid(),
            windowId: 8001,
            to: workspaceId,
            source: .ax
        )

        let newWindowId = 8002
        let entry = runtime.rekeyWindow(
            from: originalToken,
            to: WindowToken(pid: originalToken.pid, windowId: newWindowId),
            newAXRef: makeLayoutPlanTestWindow(windowId: newWindowId),
            source: .ax
        )

        #expect(entry != nil)
        let resolvedNewToken = WindowToken(pid: originalToken.pid, windowId: newWindowId)
        #expect(runtime.controller.workspaceManager.entry(for: resolvedNewToken) != nil)
    }

    @Test @MainActor func removeWindowThroughRuntimeReleasesEntry() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 9001),
            pid: getpid(),
            windowId: 9001,
            to: workspaceId,
            source: .ax
        )

        let removed = runtime.removeWindow(
            pid: token.pid,
            windowId: token.windowId,
            source: .ax
        )

        #expect(removed != nil)
        #expect(runtime.controller.workspaceManager.entry(for: token) == nil)
    }

    @Test @MainActor func removeWindowsForAppThroughRuntimeRemovesAllForPid() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!
        let pid = pid_t(99999)
        _ = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 10001),
            pid: pid,
            windowId: 10001,
            to: workspaceId,
            source: .ax
        )
        _ = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 10002),
            pid: pid,
            windowId: 10002,
            to: workspaceId,
            source: .ax
        )

        let affectedWorkspaces = runtime.removeWindowsForApp(pid: pid, source: .ax)
        #expect(affectedWorkspaces.contains(workspaceId))

        #expect(
            runtime.controller.workspaceManager.entry(
                for: WindowToken(pid: pid, windowId: 10001)
            ) == nil
        )
        #expect(
            runtime.controller.workspaceManager.entry(
                for: WindowToken(pid: pid, windowId: 10002)
            ) == nil
        )
    }

    @Test @MainActor func duplicateAdmitThroughRuntimeIsIdempotent() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        let baselineSwitch = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "1"))
        )

        let firstToken = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 7777),
            pid: getpid(),
            windowId: 7777,
            to: workspaceId,
            source: .ax
        )
        let secondToken = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 7777),
            pid: getpid(),
            windowId: 7777,
            to: workspaceId,
            source: .ax
        )

        #expect(firstToken == secondToken)
        #expect(runtime.controller.workspaceManager.entry(for: firstToken) != nil)

        let probe = runtime.submit(
            command: .workspaceSwitch(.explicit(rawWorkspaceID: "1"))
        )
        #expect(baselineSwitch.transactionEpoch < probe.transactionEpoch)

        let entries = runtime.controller.workspaceManager.entries(in: workspaceId)
        let matching = entries.filter { $0.windowId == 7777 && $0.pid == getpid() }
        #expect(matching.count == 1)
    }

    @Test @MainActor func staleDestroyThroughRuntimeDoesNotRemoveReplacement() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        let originalWindowId = 8881
        let replacementWindowId = 8882

        let originalToken = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: originalWindowId),
            pid: getpid(),
            windowId: originalWindowId,
            to: workspaceId,
            source: .ax
        )
        let newAXRef = makeLayoutPlanTestWindow(windowId: replacementWindowId)
        let replacementToken = WindowToken(pid: originalToken.pid, windowId: replacementWindowId)
        _ = runtime.rekeyWindow(
            from: originalToken,
            to: replacementToken,
            newAXRef: newAXRef,
            source: .ax
        )
        #expect(runtime.controller.workspaceManager.entry(for: replacementToken) != nil)

        let removedEntry = runtime.removeWindow(
            pid: originalToken.pid,
            windowId: originalToken.windowId,
            source: .ax
        )

        #expect(removedEntry == nil)
        #expect(runtime.controller.workspaceManager.entry(for: replacementToken) != nil)
    }

    @Test @MainActor func rekeyWindowRebindsNiriLayoutEngineUnderSameEpoch() async {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let controller = runtime.controller
        guard let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing workspace fixture")
            return
        }

        controller.enableNiriLayout(maxWindowsPerColumn: 1)
        await waitForLayoutPlanRefreshWork(on: controller)
        controller.syncMonitorsToNiriEngine()

        let oldToken = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 13001),
            pid: getpid(),
            windowId: 13001,
            to: workspaceId,
            source: .ax
        )
        _ = controller.niriEngine?.addWindow(
            token: oldToken,
            to: workspaceId,
            afterSelection: nil,
            focusedToken: nil
        )
        #expect(controller.niriEngine?.findNode(for: oldToken) != nil)

        let baseline = runtime.currentEffectRunnerWatermark
        let newToken = WindowToken(pid: oldToken.pid, windowId: 13002)
        let newAXRef = makeLayoutPlanTestWindow(windowId: 13002)
        _ = runtime.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: newAXRef,
            source: .ax
        )

        #expect(controller.niriEngine?.findNode(for: newToken) != nil)
        #expect(controller.niriEngine?.findNode(for: oldToken) == nil)
        #expect(runtime.currentEffectRunnerWatermark.value == baseline.value + 1)
    }

    @Test @MainActor func rekeyWindowRebindsFocusBridgeUnderSameEpoch() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let controller = runtime.controller
        let workspaceId = controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        let oldToken = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 13101),
            pid: getpid(),
            windowId: 13101,
            to: workspaceId,
            source: .ax
        )
        let oldAXRef = makeLayoutPlanTestWindow(windowId: 13101)
        controller.focusBridge.setFocusedTarget(
            KeyboardFocusTarget(
                token: oldToken,
                axRef: oldAXRef,
                workspaceId: workspaceId,
                isManaged: true
            )
        )
        controller.focusBridge.applyOrchestrationState(
            nextManagedRequestId: 100,
            activeManagedRequest: ManagedFocusRequest(
                requestId: 99,
                token: oldToken,
                workspaceId: workspaceId
            )
        )

        let newToken = WindowToken(pid: oldToken.pid, windowId: 13102)
        let newAXRef = makeLayoutPlanTestWindow(windowId: 13102)
        _ = runtime.rekeyWindow(
            from: oldToken,
            to: newToken,
            newAXRef: newAXRef,
            source: .ax
        )

        #expect(controller.focusBridge.focusedTarget?.token == newToken)
        #expect(controller.focusBridge.activeManagedRequest?.token == newToken)
    }
}
