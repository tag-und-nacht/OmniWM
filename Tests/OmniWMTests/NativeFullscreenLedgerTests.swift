// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Testing
@testable import OmniWM

@Suite("NativeFullscreenLedger")
@MainActor
struct NativeFullscreenLedgerTests {
    private let logicalA = LogicalWindowId(value: 1)
    private let logicalB = LogicalWindowId(value: 2)

    private func makeRecord(
        logicalId: LogicalWindowId,
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID = WorkspaceDescriptor.ID()
    ) -> WorkspaceManager.NativeFullscreenRecord {
        WorkspaceManager.NativeFullscreenRecord(
            logicalId: logicalId,
            originalToken: token,
            currentToken: token,
            workspaceId: workspaceId,
            restoreSnapshot: nil,
            restoreFailure: nil,
            exitRequestedByCommand: false,
            transition: .enterRequested,
            availability: .present,
            unavailableSince: nil
        )
    }

    @Test func upsertInsertsBothMaps() {
        var ledger = NativeFullscreenLedger()
        let token = WindowToken(pid: 100, windowId: 200)
        let record = makeRecord(logicalId: logicalA, token: token)

        let previous = ledger.upsert(record)
        #expect(previous == nil)
        #expect(ledger.record(forLogicalId: logicalA)?.logicalId == logicalA)
        #expect(ledger.record(forLogicalId: logicalA)?.currentToken == token)
        #expect(ledger.record(forToken: token)?.logicalId == logicalA)
        #expect(ledger.logicalId(forToken: token) == logicalA)
    }

    @Test func upsertReplacesPriorRecordPreservingInvariant() {
        var ledger = NativeFullscreenLedger()
        let oldToken = WindowToken(pid: 100, windowId: 200)
        let newToken = WindowToken(pid: 100, windowId: 300)

        var record = makeRecord(logicalId: logicalA, token: oldToken)
        _ = ledger.upsert(record)
        #expect(ledger.logicalId(forToken: oldToken) == logicalA)

        record.currentToken = newToken
        let previous = ledger.upsert(record)
        #expect(previous?.currentToken == oldToken)
        // Invariant: the old token's reverse-lookup must be gone.
        #expect(ledger.logicalId(forToken: oldToken) == nil)
        #expect(ledger.logicalId(forToken: newToken) == logicalA)
    }

    @Test func removeReturnsRecordAndDropsBothMaps() {
        var ledger = NativeFullscreenLedger()
        let token = WindowToken(pid: 100, windowId: 200)
        let record = makeRecord(logicalId: logicalA, token: token)
        _ = ledger.upsert(record)

        let removed = ledger.remove(logicalId: logicalA)
        #expect(removed?.logicalId == logicalA)
        #expect(removed?.currentToken == token)
        #expect(ledger.record(forLogicalId: logicalA) == nil)
        #expect(ledger.record(forToken: token) == nil)
        #expect(ledger.logicalId(forToken: token) == nil)
    }

    @Test func removeOfUnknownLogicalIdIsNoOp() {
        var ledger = NativeFullscreenLedger()
        let removed = ledger.remove(logicalId: logicalA)
        #expect(removed == nil)
        #expect(ledger.isEmpty)
    }

    @Test func twoIndependentRecordsAreIsolated() {
        var ledger = NativeFullscreenLedger()
        let tokenA = WindowToken(pid: 100, windowId: 200)
        let tokenB = WindowToken(pid: 100, windowId: 300)
        _ = ledger.upsert(makeRecord(logicalId: logicalA, token: tokenA))
        _ = ledger.upsert(makeRecord(logicalId: logicalB, token: tokenB))

        #expect(ledger.record(forLogicalId: logicalA)?.currentToken == tokenA)
        #expect(ledger.record(forLogicalId: logicalB)?.currentToken == tokenB)

        _ = ledger.remove(logicalId: logicalA)
        #expect(ledger.record(forLogicalId: logicalA) == nil)
        #expect(ledger.record(forLogicalId: logicalB)?.currentToken == tokenB)
    }

    @Test func recordForTokenReturnsNilAfterRebind() {
        var ledger = NativeFullscreenLedger()
        let oldToken = WindowToken(pid: 100, windowId: 200)
        let newToken = WindowToken(pid: 100, windowId: 300)

        var record = makeRecord(logicalId: logicalA, token: oldToken)
        _ = ledger.upsert(record)
        record.currentToken = newToken
        _ = ledger.upsert(record)

        // Old token must no longer resolve.
        #expect(ledger.record(forToken: oldToken) == nil)
        #expect(ledger.record(forToken: newToken)?.logicalId == logicalA)
    }
}
