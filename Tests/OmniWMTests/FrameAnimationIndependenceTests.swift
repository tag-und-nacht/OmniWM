// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct FrameAnimationIndependenceTests {
    private let desired = FrameState.Frame(
        rect: CGRect(x: 100, y: 100, width: 800, height: 600),
        space: .appKit,
        isVisibleFrame: true
    )

    @Test func recordingDesiredAloneDoesNotConfirm() {
        var s = FrameState.initial
        s.recordDesired(desired)
        #expect(s.confirmed == nil)
        let didConfirm = s.confirmIfObservedMatchesDesired()
        #expect(!didConfirm)
    }

    @Test func recordingPendingAloneDoesNotConfirm() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordPendingWrite(desired, requestId: 1, since: TransactionEpoch(value: 1))
        #expect(s.confirmed == nil)
        let didConfirm = s.confirmIfObservedMatchesDesired()
        #expect(!didConfirm)
    }

    @Test func failedWriteDoesNotConfirmEvenIfDesiredMatches() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordPendingWrite(desired, requestId: 1, since: TransactionEpoch(value: 1))
        s.recordFailedWrite(reason: .verificationMismatch, attemptedAt: TransactionEpoch(value: 2))
        #expect(s.confirmed == nil)
        let didConfirm = s.confirmIfObservedMatchesDesired()
        #expect(!didConfirm)
    }

    @Test func captureRestorableWithoutConfirmedIsNoOp() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordPendingWrite(desired, requestId: 1, since: TransactionEpoch(value: 1))
        s.captureRestorableFromConfirmed()
        #expect(s.restorable == nil)
    }

    @Test func onlyObservationPromotesConfirmed() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordPendingWrite(desired, requestId: 1, since: TransactionEpoch(value: 1))
        s.recordObserved(desired)
        let didConfirm = s.confirmIfObservedMatchesDesired()
        #expect(didConfirm)
        #expect(s.confirmed == desired)
    }

    @Test func reducerEventOrderingDoesNotPromoteFromAnimationCompletion() {
        let state = FrameState.initial
        let r1 = FrameReducer.reduce(
            state: state,
            event: .desiredFrameRequested(desired)
        )
        let r2 = FrameReducer.reduce(
            state: r1.nextState,
            event: .pendingFrameWriteEmitted(
                desired,
                requestId: 1,
                since: TransactionEpoch(value: 1)
            )
        )
        let r3 = FrameReducer.reduce(
            state: r2.nextState,
            event: .pendingFrameWriteEmitted(
                desired,
                requestId: 2,
                since: TransactionEpoch(value: 2)
            )
        )
        #expect(!r1.didPromoteToConfirmed)
        #expect(!r2.didPromoteToConfirmed)
        #expect(!r3.didPromoteToConfirmed)
        #expect(r3.nextState.confirmed == nil)
    }
}
