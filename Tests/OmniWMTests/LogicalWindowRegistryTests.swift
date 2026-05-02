// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct LogicalWindowRegistryTests {
    @MainActor
    private func makeWorkspaceId() -> WorkspaceDescriptor.ID {
        WorkspaceDescriptor(name: "ws").id
    }

    @MainActor
    private func token(pid: pid_t = 4242, wid: Int = 1) -> WindowToken {
        WindowToken(pid: pid, windowId: wid)
    }

    @Test @MainActor func allocateProducesIncreasingIdsAndCurrentBinding() {
        let registry = LogicalWindowRegistry()
        let workspaceId = makeWorkspaceId()

        let tokenA = token(wid: 1)
        let tokenB = token(wid: 2)

        let idA = registry.allocate(
            boundTo: tokenA,
            workspaceId: workspaceId,
            monitorId: nil
        )
        let idB = registry.allocate(
            boundTo: tokenB,
            workspaceId: workspaceId,
            monitorId: nil
        )

        #expect(idA.isValid)
        #expect(idB.isValid)
        #expect(idA.value < idB.value)
        #expect(registry.lookup(token: tokenA) == .current(idA))
        #expect(registry.lookup(token: tokenB) == .current(idB))
    }

    @Test @MainActor func duplicateObservationsPreserveOneLogicalId() {
        let registry = LogicalWindowRegistry()
        let workspaceId = makeWorkspaceId()
        let t = token()

        let id = registry.allocate(
            boundTo: t,
            workspaceId: workspaceId,
            monitorId: nil
        )

        #expect(registry.resolveForWrite(token: t) == id)
    }

    @Test @MainActor func rebindDemotesOldTokenToStaleAliasAndBumpsEpoch() {
        let registry = LogicalWindowRegistry()
        let workspaceId = makeWorkspaceId()
        let oldToken = token(wid: 1)
        let newToken = token(wid: 2)

        let id = registry.allocate(
            boundTo: oldToken,
            workspaceId: workspaceId,
            monitorId: nil
        )
        #expect(registry.record(for: id)?.replacementEpoch == ReplacementEpoch(value: 0))

        let outcome = registry.rebindToken(
            logicalId: id,
            from: oldToken,
            to: newToken,
            reason: .managedReplacement
        )
        #expect(outcome == .applied)

        #expect(registry.lookup(token: newToken) == .current(id))
        #expect(registry.lookup(token: oldToken) == .staleAlias(id))
        #expect(registry.record(for: id)?.replacementEpoch == ReplacementEpoch(value: 1))
        if case let .replaced(previous) = registry.record(for: id)?.replacement {
            #expect(previous == oldToken)
        } else {
            Issue.record("Expected .replaced replacement facet")
        }
    }

    @Test @MainActor func rebindRejectedForStaleFromToken() {
        let registry = LogicalWindowRegistry()
        let workspaceId = makeWorkspaceId()
        let t1 = token(wid: 1)
        let t2 = token(wid: 2)
        let t3 = token(wid: 3)

        let id = registry.allocate(
            boundTo: t1,
            workspaceId: workspaceId,
            monitorId: nil
        )
        _ = registry.rebindToken(logicalId: id, from: t1, to: t2, reason: .managedReplacement)

        let outcome = registry.rebindToken(
            logicalId: id,
            from: t1,
            to: t3,
            reason: .managedReplacement
        )
        #expect(outcome == .rejectedStale(id))
        #expect(registry.lookup(token: t2) == .current(id))
        #expect(registry.lookup(token: t3) == .unknown)
        #expect(registry.record(for: id)?.replacementEpoch == ReplacementEpoch(value: 1))
    }

    @Test @MainActor func rebindRejectedWhenNewTokenAlreadyHasDifferentCurrentOwner() {
        let registry = LogicalWindowRegistry()
        let workspaceId = makeWorkspaceId()
        let firstToken = token(wid: 1)
        let secondToken = token(wid: 2)
        let replacementToken = token(wid: 3)

        let firstId = registry.allocate(
            boundTo: firstToken,
            workspaceId: workspaceId,
            monitorId: nil
        )
        let secondId = registry.allocate(
            boundTo: replacementToken,
            workspaceId: workspaceId,
            monitorId: nil
        )

        let outcome = registry.rebindToken(
            logicalId: firstId,
            from: firstToken,
            to: replacementToken,
            reason: .managedReplacement
        )

        #expect(outcome == .rejectedCollision(requested: firstId, currentOwner: secondId))
        #expect(registry.lookup(token: firstToken) == .current(firstId))
        #expect(registry.lookup(token: replacementToken) == .current(secondId))
        #expect(registry.lookup(token: secondToken) == .unknown)
        #expect(registry.record(for: firstId)?.currentToken == firstToken)
        #expect(registry.record(for: firstId)?.replacementEpoch == ReplacementEpoch(value: 0))
    }

    @Test @MainActor func retireBlocksFurtherWritesAndSurfacesAsRetiredLookup() {
        let registry = LogicalWindowRegistry()
        let workspaceId = makeWorkspaceId()
        let t = token()

        let id = registry.allocate(
            boundTo: t,
            workspaceId: workspaceId,
            monitorId: nil
        )
        _ = registry.retire(logicalId: id)

        #expect(registry.lookup(token: t) == .retired(id))

        #expect(registry.resolveForWrite(token: t) == nil)
        let rebind = registry.rebindToken(
            logicalId: id,
            from: t,
            to: token(wid: 99),
            reason: .managedReplacement
        )
        #expect(rebind == .rejectedRetired(id))

        let fullscreenUpdate = registry.updateFullscreenSession(
            logicalId: id,
            .nativeFullscreen
        )
        #expect(fullscreenUpdate == .rejectedRetired(id))
    }

    @Test @MainActor func rebindIntoNewTokenClearsPreviousStaleAliasForSameLogicalId() {
        let registry = LogicalWindowRegistry()
        let workspaceId = makeWorkspaceId()
        let t1 = token(wid: 1)
        let t2 = token(wid: 2)

        let id = registry.allocate(
            boundTo: t1,
            workspaceId: workspaceId,
            monitorId: nil
        )
        _ = registry.rebindToken(logicalId: id, from: t1, to: t2, reason: .managedReplacement)
        _ = registry.rebindToken(logicalId: id, from: t2, to: t1, reason: .managedReplacement)

        #expect(registry.lookup(token: t1) == .current(id))
        #expect(registry.lookup(token: t2) == .staleAlias(id))
        #expect(registry.record(for: id)?.replacementEpoch == ReplacementEpoch(value: 2))
    }

    @Test @MainActor func reallocatingOnReusedTokenDemotesOldLogicalIdToStale() {
        let registry = LogicalWindowRegistry()
        let workspaceId = makeWorkspaceId()
        let t = token()

        let id1 = registry.allocate(
            boundTo: t,
            workspaceId: workspaceId,
            monitorId: nil
        )
        let id2 = registry.allocate(
            boundTo: t,
            workspaceId: workspaceId,
            monitorId: nil
        )

        #expect(id1 != id2)
        #expect(registry.lookup(token: t) == .current(id2))
        let id1Record = registry.record(for: id1)
        #expect(id1Record != nil)
        #expect(id1Record?.currentToken == nil)
        if case let .staleTokenObserved(observedToken) = id1Record?.replacement {
            #expect(observedToken == t)
        } else {
            Issue.record("Expected .staleTokenObserved on the demoted record")
        }
    }

    @Test @MainActor func quarantineMarksDelayedAdmissionWithoutAffectingBinding() {
        let registry = LogicalWindowRegistry()
        let workspaceId = makeWorkspaceId()
        let t = token()

        let id = registry.allocate(
            boundTo: t,
            workspaceId: workspaceId,
            monitorId: nil
        )
        let outcome = registry.updateQuarantine(
            logicalId: id,
            .quarantined(reason: .delayedAdmission)
        )
        #expect(outcome == .applied)
        #expect(registry.record(for: id)?.quarantine == .quarantined(reason: .delayedAdmission))
        #expect(registry.lookup(token: t) == .current(id))
    }

    @Test @MainActor func debugRenderIsRedactedAndStable() {
        let registry = LogicalWindowRegistry()
        let workspaceId = makeWorkspaceId()
        let t = token(pid: 7, wid: 42)

        _ = registry.allocate(
            boundTo: t,
            workspaceId: workspaceId,
            monitorId: nil
        )
        let lines = registry.debugRender()
        #expect(lines.count == 1)
        #expect(lines[0].contains("lwid#"))
        #expect(lines[0].contains("pid=7"))
        #expect(lines[0].contains("wid=42"))
        #expect(lines[0].contains("repl#0"))
        #expect(lines[0].contains("primary=managed"))
        #expect(lines[0].contains("replacement=stable"))
    }
}
