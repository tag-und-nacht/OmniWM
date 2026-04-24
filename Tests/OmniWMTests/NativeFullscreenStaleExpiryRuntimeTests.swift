// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct NativeFullscreenStaleExpiryRuntimeTests {
    @Test @MainActor func staleNFRExpiryAdvancesEffectRunnerWatermarkOnce() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 12001),
            pid: getpid(),
            windowId: 12001,
            to: workspaceId,
            source: .ax
        )
        _ = runtime.requestNativeFullscreenEnter(
            token,
            in: workspaceId,
            restoreSnapshot: nil,
            restoreFailure: nil,
            source: .ax
        )
        _ = runtime.markNativeFullscreenTemporarilyUnavailable(token, source: .ax)

        let baseline = runtime.currentEffectRunnerWatermark
        let staleNow = Date().addingTimeInterval(
            WorkspaceManager.staleUnavailableNativeFullscreenTimeout + 1
        )
        let removed = runtime.expireStaleTemporarilyUnavailableNativeFullscreenRecords(
            now: staleNow,
            source: .ax
        )

        #expect(!removed.isEmpty)
        #expect(runtime.currentEffectRunnerWatermark.value > baseline.value)
        #expect(
            runtime.controller.workspaceManager.nativeFullscreenRecord(for: token) == nil
        )
    }

    @Test @MainActor func staleNFRExpiryReturnsRemovedEntries() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        let tokenA = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 12101),
            pid: getpid(),
            windowId: 12101,
            to: workspaceId,
            source: .ax
        )
        let tokenB = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 12102),
            pid: getpid(),
            windowId: 12102,
            to: workspaceId,
            source: .ax
        )
        _ = runtime.requestNativeFullscreenEnter(
            tokenA,
            in: workspaceId,
            restoreSnapshot: nil,
            restoreFailure: nil,
            source: .ax
        )
        _ = runtime.markNativeFullscreenTemporarilyUnavailable(tokenA, source: .ax)
        _ = runtime.requestNativeFullscreenEnter(
            tokenB,
            in: workspaceId,
            restoreSnapshot: nil,
            restoreFailure: nil,
            source: .ax
        )
        _ = runtime.markNativeFullscreenTemporarilyUnavailable(tokenB, source: .ax)

        let staleNow = Date().addingTimeInterval(
            WorkspaceManager.staleUnavailableNativeFullscreenTimeout + 1
        )
        let removed = runtime.expireStaleTemporarilyUnavailableNativeFullscreenRecords(
            now: staleNow,
            source: .ax
        )

        let removedTokens = Set(removed.map { $0.token })
        #expect(removedTokens.contains(tokenA))
        #expect(removedTokens.contains(tokenB))
    }

    @Test @MainActor func staleNFRExpiryWithFreshRecordsDoesNotRemove() {
        let platform = RecordingEffectPlatform()
        let runtime = makeTransactionTestRuntime(platform: platform)
        let workspaceId = runtime.controller.workspaceManager.workspaceId(
            for: "1",
            createIfMissing: false
        )!

        let token = runtime.admitWindow(
            makeLayoutPlanTestWindow(windowId: 12201),
            pid: getpid(),
            windowId: 12201,
            to: workspaceId,
            source: .ax
        )
        _ = runtime.requestNativeFullscreenEnter(
            token,
            in: workspaceId,
            restoreSnapshot: nil,
            restoreFailure: nil,
            source: .ax
        )
        _ = runtime.markNativeFullscreenTemporarilyUnavailable(token, source: .ax)

        let removed = runtime.expireStaleTemporarilyUnavailableNativeFullscreenRecords(
            source: .ax
        )

        #expect(removed.isEmpty)
        #expect(
            runtime.controller.workspaceManager.nativeFullscreenRecord(for: token) != nil
        )
    }
}
