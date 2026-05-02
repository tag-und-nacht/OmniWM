// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct FailedFrameWriteRecoveryTests {
    @Test @MainActor func transcriptIsGoldenStable() async throws {
        let context = makeTranscriptRuntimeContext()
        let lhs = FailedFrameWriteRecoveryTranscript.make(in: context)
        let rhs = FailedFrameWriteRecoveryTranscript.make(in: context)
        #expect(lhs == rhs)
        #expect(lhs.steps.count == 3)
    }

    @Test @MainActor func transcriptRunsCleanlyEndToEnd() async throws {
        let context = makeTranscriptRuntimeContext()
        let transcript = FailedFrameWriteRecoveryTranscript.make(in: context)

        let driver = TranscriptReplayDriver(
            transcript: transcript,
            runtime: context.runtime,
            platform: context.platform
        )

        try await driver.run()
    }

    @Test @MainActor func predicateFiresWhenFailedWriteCoexistsWithConfirmedMatchingDesired() async throws {
        let context = makeTranscriptRuntimeContext()
        let workspaceId = context.workspaceId(named: "1")
        let manager = context.runtime.controller.workspaceManager

        let pid: pid_t = 30_021
        let windowId = 22
        let axRef = AXWindowRef(
            element: AXUIElementCreateSystemWide(),
            windowId: windowId
        )
        let token = manager.addWindow(
            axRef,
            pid: pid,
            windowId: windowId,
            to: workspaceId,
            mode: .tiling
        )

        let lookup = manager.logicalWindowRegistry.lookup(token: token)
        if case .current = lookup {
        } else {
            Issue.record("expected .current binding after addWindow; got \(lookup)")
            return
        }

        let frame = FrameState.Frame(
            rect: CGRect(x: 100, y: 120, width: 800, height: 600),
            space: .appKit,
            isVisibleFrame: true
        )
        let didDesired = manager.recordDesiredFrame(frame, for: token)
        let didPending = manager.recordPendingFrameWrite(
            frame,
            requestId: 1,
            since: TransactionEpoch(value: 1),
            for: token
        )
        let didObserved = manager.recordObservedFrame(frame, for: token)
        #expect(didDesired)
        #expect(didPending)
        #expect(didObserved)

        let stateAfterConfirm = manager.frameState(for: token)
        #expect(stateAfterConfirm?.confirmed != nil)
        if case .idle = stateAfterConfirm?.write {
        } else {
            Issue.record("expected write=.idle after confirmation; got \(String(describing: stateAfterConfirm?.write))")
        }

        _ = manager.recordFailedFrameWrite(
            reason: .verificationMismatch,
            attemptedAt: TransactionEpoch(value: 2),
            for: token
        )

        let stateAfterFailure = manager.frameState(for: token)
        guard case .failed = stateAfterFailure?.write else {
            Issue.record("expected write=.failed after recordFailedFrameWrite; got \(String(describing: stateAfterFailure?.write))")
            return
        }
        #expect(stateAfterFailure?.confirmed != nil)

        let violation = TranscriptInvariantRegistry.validate(
            .failedFrameWriteCannotConfirmFrame,
            runtime: context.runtime,
            platform: context.platform,
            outcome: nil,
            previousTopologyEpoch: nil
        )

        #expect(violation != nil)
        if let violation {
            #expect(violation.contains("failed-write"))
            #expect(violation.contains("confirmed frame"))
        }
    }

    @Test @MainActor func predicateDoesNotFireOnHappyPathConfirmation() async throws {
        let context = makeTranscriptRuntimeContext()
        let workspaceId = context.workspaceId(named: "1")
        let manager = context.runtime.controller.workspaceManager

        let pid: pid_t = 30_022
        let windowId = 23
        let axRef = AXWindowRef(
            element: AXUIElementCreateSystemWide(),
            windowId: windowId
        )
        let token = manager.addWindow(
            axRef,
            pid: pid,
            windowId: windowId,
            to: workspaceId,
            mode: .tiling
        )

        let frame = FrameState.Frame(
            rect: CGRect(x: 50, y: 60, width: 400, height: 300),
            space: .appKit,
            isVisibleFrame: true
        )
        _ = manager.recordDesiredFrame(frame, for: token)
        _ = manager.recordPendingFrameWrite(
            frame,
            requestId: 1,
            since: TransactionEpoch(value: 1),
            for: token
        )
        _ = manager.recordObservedFrame(frame, for: token)

        let violation = TranscriptInvariantRegistry.validate(
            .failedFrameWriteCannotConfirmFrame,
            runtime: context.runtime,
            platform: context.platform,
            outcome: nil,
            previousTopologyEpoch: nil
        )

        #expect(violation == nil)
    }
}
