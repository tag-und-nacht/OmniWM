// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct FrameStateTests {
    private let desired = FrameState.Frame(
        rect: CGRect(x: 100, y: 100, width: 800, height: 600),
        space: .appKit,
        isVisibleFrame: true
    )
    private let observedExact = FrameState.Frame(
        rect: CGRect(x: 100, y: 100, width: 800, height: 600),
        space: .appKit,
        isVisibleFrame: true
    )
    private let observedWithinTolerance = FrameState.Frame(
        rect: CGRect(x: 100.5, y: 100.4, width: 800.7, height: 599.6),
        space: .appKit,
        isVisibleFrame: true
    )
    private let observedOutsideTolerance = FrameState.Frame(
        rect: CGRect(x: 105, y: 100, width: 800, height: 600),
        space: .appKit,
        isVisibleFrame: true
    )
    private let observedQuartz = FrameState.Frame(
        rect: CGRect(x: 100, y: 100, width: 800, height: 600),
        space: .quartz,
        isVisibleFrame: true
    )
    private let observedFullFrame = FrameState.Frame(
        rect: CGRect(x: 100, y: 100, width: 800, height: 600),
        space: .appKit,
        isVisibleFrame: false
    )

    @Test func initialStateIsIdleAndUnpopulated() {
        let s = FrameState.initial
        #expect(s.desired == nil)
        #expect(s.pending == nil)
        #expect(s.observed == nil)
        #expect(s.confirmed == nil)
        #expect(s.restorable == nil)
        #expect(s.write == .idle)
        #expect(!s.hasPendingWrite)
        #expect(!s.hasFailedWrite)
    }

    @Test func recordDesiredAndPendingWriteEntersPending() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordPendingWrite(desired, requestId: 7, since: TransactionEpoch(value: 1))
        #expect(s.desired == desired)
        #expect(s.pending == desired)
        #expect(s.write == .pending(requestId: 7, since: TransactionEpoch(value: 1)))
        #expect(s.hasPendingWrite)
    }

    @Test func observedExactWithinTolerancePromotesToConfirmed() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordPendingWrite(desired, requestId: 7, since: TransactionEpoch(value: 1))
        s.recordObserved(observedExact)
        let didConfirm = s.confirmIfObservedMatchesDesired()
        #expect(didConfirm)
        #expect(s.confirmed == observedExact)
        #expect(s.pending == nil)
        #expect(s.write == .idle)
    }

    @Test func observedSubpixelDriftWithinTolerancePromotes() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordObserved(observedWithinTolerance)
        let didConfirm = s.confirmIfObservedMatchesDesired()
        #expect(didConfirm)
        #expect(s.confirmed == observedWithinTolerance)
    }

    @Test func observedOutsideToleranceDoesNotPromote() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordObserved(observedOutsideTolerance)
        let didConfirm = s.confirmIfObservedMatchesDesired()
        #expect(!didConfirm)
        #expect(s.confirmed == nil)
        #expect(s.observed == observedOutsideTolerance)
        #expect(s.desired == desired)
    }

    @Test func crossCoordinateSpaceObservationIsRejected() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordObserved(observedQuartz)
        let didConfirm = s.confirmIfObservedMatchesDesired()
        #expect(!didConfirm)
        #expect(s.confirmed == nil)
    }

    @Test func crossVisibilityObservationIsRejected() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordObserved(observedFullFrame)
        let didConfirm = s.confirmIfObservedMatchesDesired()
        #expect(!didConfirm)
        #expect(s.confirmed == nil)
    }

    @Test func failedWritePreservesDesiredAndPending() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordPendingWrite(desired, requestId: 7, since: TransactionEpoch(value: 1))
        s.recordFailedWrite(
            reason: .verificationMismatch,
            attemptedAt: TransactionEpoch(value: 2)
        )
        #expect(s.write == .failed(reason: .verificationMismatch, attemptedAt: TransactionEpoch(value: 2)))
        #expect(s.desired == desired)
        #expect(s.pending == desired)
        #expect(s.confirmed == nil)
        #expect(s.hasFailedWrite)
    }

    @Test func captureRestorableCopiesConfirmedFrame() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordObserved(observedExact)
        _ = s.confirmIfObservedMatchesDesired()
        #expect(s.confirmed == observedExact)
        s.captureRestorableFromConfirmed()
        #expect(s.restorable == observedExact)
    }

    @Test func captureRestorableIsNoOpWithoutConfirmed() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.captureRestorableFromConfirmed()
        #expect(s.restorable == nil)
    }


    @Test func captureRestorableReturnsFalseWhenNoConfirmed() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordObserved(observedExact)
        #expect(s.confirmed == nil)
        let didCapture = s.captureRestorableFromConfirmed()
        #expect(didCapture == false)
        #expect(s.restorable == nil)
    }

    @Test func captureRestorableReturnsTrueWhenConfirmedExists() {
        var s = FrameState.initial
        s.recordDesired(desired)
        s.recordObserved(observedExact)
        _ = s.confirmIfObservedMatchesDesired()
        let didCapture = s.captureRestorableFromConfirmed()
        #expect(didCapture == true)
        #expect(s.restorable == observedExact)
    }

    @Test func observedAloneDoesNotSeedRestorable() {
        var s = FrameState.initial
        s.recordObserved(observedExact)
        #expect(s.observed == observedExact)
        #expect(s.confirmed == nil)
        s.captureRestorableFromConfirmed()
        #expect(s.restorable == nil)
    }

    @Test func desiredAloneDoesNotSeedRestorable() {
        var s = FrameState.initial
        s.recordDesired(desired)
        #expect(s.desired == desired)
        #expect(s.observed == nil)
        #expect(s.confirmed == nil)
        s.captureRestorableFromConfirmed()
        #expect(s.restorable == nil)
    }

    @Test func captureRestorableLeavesPriorRestorableIntactWhenNoConfirmed() {
        var s = FrameState.initial
        s.restorable = observedExact
        s.confirmed = nil
        let didCapture = s.captureRestorableFromConfirmed()
        #expect(didCapture == false)
        #expect(s.restorable == observedExact)
    }
}
