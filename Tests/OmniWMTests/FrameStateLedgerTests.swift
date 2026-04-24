// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Testing
@testable import OmniWM

@Suite("FrameStateLedger")
struct FrameStateLedgerTests {
    private let logicalA = LogicalWindowId(value: 1)
    private let logicalB = LogicalWindowId(value: 2)

    private func frame(_ rect: CGRect) -> FrameState.Frame {
        FrameState.Frame(rect: rect, space: .appKit, isVisibleFrame: true)
    }

    @Test func unknownLogicalIdReturnsNil() {
        let ledger = FrameStateLedger()
        #expect(ledger.state(for: logicalA) == nil)
        #expect(ledger.count == 0)
    }

    @Test func reduceAllocatesInitialOnFirstTouch() {
        var ledger = FrameStateLedger()
        let request = frame(CGRect(x: 0, y: 0, width: 200, height: 100))
        let reduction = ledger.reduce(.desiredFrameRequested(request), forLogicalId: logicalA)

        #expect(reduction.didChange)
        #expect(ledger.state(for: logicalA)?.desired == request)
        #expect(ledger.count == 1)
    }

    @Test func reduceUpdatesStoredState() {
        var ledger = FrameStateLedger()
        let firstFrame = frame(CGRect(x: 0, y: 0, width: 200, height: 100))
        let secondFrame = frame(CGRect(x: 50, y: 50, width: 200, height: 100))

        _ = ledger.reduce(.desiredFrameRequested(firstFrame), forLogicalId: logicalA)
        _ = ledger.reduce(.desiredFrameRequested(secondFrame), forLogicalId: logicalA)

        #expect(ledger.state(for: logicalA)?.desired == secondFrame)
    }

    @Test func dropRemovesStoredState() {
        var ledger = FrameStateLedger()
        let request = frame(CGRect(x: 0, y: 0, width: 200, height: 100))
        _ = ledger.reduce(.desiredFrameRequested(request), forLogicalId: logicalA)
        #expect(ledger.state(for: logicalA) != nil)

        ledger.drop(logicalId: logicalA)
        #expect(ledger.state(for: logicalA) == nil)
        #expect(ledger.count == 0)
    }

    @Test func separateLogicalIdsAreIsolated() {
        var ledger = FrameStateLedger()
        let frameA = frame(CGRect(x: 0, y: 0, width: 100, height: 100))
        let frameB = frame(CGRect(x: 200, y: 200, width: 100, height: 100))

        _ = ledger.reduce(.desiredFrameRequested(frameA), forLogicalId: logicalA)
        _ = ledger.reduce(.desiredFrameRequested(frameB), forLogicalId: logicalB)

        #expect(ledger.state(for: logicalA)?.desired == frameA)
        #expect(ledger.state(for: logicalB)?.desired == frameB)
        #expect(ledger.count == 2)
    }

    @Test func dropOfUnknownIdIsNoOp() {
        var ledger = FrameStateLedger()
        ledger.drop(logicalId: logicalA)
        #expect(ledger.count == 0)
    }

    @Test func observedFramePromotesToConfirmedWhenWithinTolerance() {
        var ledger = FrameStateLedger()
        let target = frame(CGRect(x: 100, y: 100, width: 400, height: 300))
        _ = ledger.reduce(.desiredFrameRequested(target), forLogicalId: logicalA)
        let reduction = ledger.reduce(.observedFrameReceived(target), forLogicalId: logicalA)

        #expect(reduction.didPromoteToConfirmed)
        #expect(ledger.state(for: logicalA)?.confirmed == target)
    }
}
