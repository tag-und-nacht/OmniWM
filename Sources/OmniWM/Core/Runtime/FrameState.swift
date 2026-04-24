// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation


let frameConfirmationToleranceInPoints: CGFloat = 1.0

struct FrameState: Equatable {
    enum CoordinateSpace: String, Equatable, Sendable {
        case appKit
        case quartz
        case backing
    }

    struct Frame: Equatable {
        var rect: CGRect
        var space: CoordinateSpace
        var isVisibleFrame: Bool

        init(rect: CGRect, space: CoordinateSpace, isVisibleFrame: Bool) {
            self.rect = rect
            self.space = space
            self.isVisibleFrame = isVisibleFrame
        }

        func isWithinTolerance(of other: Frame) -> Bool {
            guard space == other.space, isVisibleFrame == other.isVisibleFrame else {
                return false
            }
            return abs(rect.origin.x - other.rect.origin.x) <= frameConfirmationToleranceInPoints
                && abs(rect.origin.y - other.rect.origin.y) <= frameConfirmationToleranceInPoints
                && abs(rect.width - other.rect.width) <= frameConfirmationToleranceInPoints
                && abs(rect.height - other.rect.height) <= frameConfirmationToleranceInPoints
        }

        init(_ rect: AppKitRect, isVisibleFrame: Bool) {
            self.rect = rect.raw
            self.space = .appKit
            self.isVisibleFrame = isVisibleFrame
        }

        init(_ rect: QuartzRect, isVisibleFrame: Bool) {
            self.rect = rect.raw
            self.space = .quartz
            self.isVisibleFrame = isVisibleFrame
        }

        init(_ rect: BackingRect, isVisibleFrame: Bool) {
            self.rect = rect.raw
            self.space = .backing
            self.isVisibleFrame = isVisibleFrame
        }
    }

    enum WriteStatus: Equatable {
        case idle
        case pending(requestId: AXFrameRequestId, since: TransactionEpoch)
        case failed(reason: AXFrameWriteFailureReason, attemptedAt: TransactionEpoch)
    }

    var desired: Frame?
    var pending: Frame?
    var observed: Frame?
    var confirmed: Frame?
    var restorable: Frame?
    var write: WriteStatus = .idle

    static let initial = FrameState()
}

extension FrameState {
    var hasPendingWrite: Bool {
        if case .pending = write { return true }
        return false
    }

    var hasFailedWrite: Bool {
        if case .failed = write { return true }
        return false
    }


    mutating func recordDesired(_ frame: Frame) {
        desired = frame
    }

    mutating func recordPendingWrite(
        _ frame: Frame,
        requestId: AXFrameRequestId,
        since: TransactionEpoch
    ) {
        pending = frame
        write = .pending(requestId: requestId, since: since)
    }

    mutating func recordObserved(_ frame: Frame) {
        observed = frame
    }

    mutating func confirmIfObservedMatchesDesired() -> Bool {
        guard let desired, let observed, observed.isWithinTolerance(of: desired) else {
            return false
        }
        confirmed = observed
        pending = nil
        if case .pending = write {
            write = .idle
        }
        return true
    }

    mutating func recordFailedWrite(
        reason: AXFrameWriteFailureReason,
        attemptedAt: TransactionEpoch
    ) {
        write = .failed(reason: reason, attemptedAt: attemptedAt)
    }

    @discardableResult
    mutating func captureRestorableFromConfirmed() -> Bool {
        guard let confirmed else { return false }
        restorable = confirmed
        return true
    }
}
