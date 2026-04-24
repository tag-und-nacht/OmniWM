// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct EnsureWorkspaceFocusPolicyTests {
    private let workspaceId = WorkspaceDescriptor.ID()
    private let tokenA = WindowToken(pid: 100, windowId: 7)
    private let tokenB = WindowToken(pid: 100, windowId: 8)

    private func base(
        pendingFocusedToken: WindowToken? = nil,
        pendingHasLayoutNode: Bool = false,
        observedFocusedToken: WindowToken? = nil,
        observedHasLayoutNode: Bool = false,
        nativeFullscreenSuppressionActive: Bool = false,
        managedFocusRecoverySuppressed: Bool = false
    ) -> EnsureWorkspaceFocusPolicy.Inputs {
        EnsureWorkspaceFocusPolicy.Inputs(
            workspaceId: workspaceId,
            pendingFocusedToken: pendingFocusedToken,
            pendingHasLayoutNode: pendingHasLayoutNode,
            observedFocusedToken: observedFocusedToken,
            observedHasLayoutNode: observedHasLayoutNode,
            nativeFullscreenSuppressionActive: nativeFullscreenSuppressionActive,
            managedFocusRecoverySuppressed: managedFocusRecoverySuppressed
        )
    }


    @Test func managedFocusRecoverySuppressionDominatesOtherSignals() {
        let action = EnsureWorkspaceFocusPolicy.decide(
            base(
                pendingFocusedToken: tokenA,
                pendingHasLayoutNode: true,
                observedFocusedToken: tokenB,
                observedHasLayoutNode: true,
                managedFocusRecoverySuppressed: true
            )
        )
        #expect(action == .suppressed(reason: .managedFocusRecoverySuppressed))
    }

    @Test func nativeFullscreenTransitionPendingSuppresses() {
        let action = EnsureWorkspaceFocusPolicy.decide(
            base(
                pendingFocusedToken: tokenA,
                nativeFullscreenSuppressionActive: true
            )
        )
        #expect(action == .suppressed(reason: .nativeFullscreenTransitionPending))
    }

    @Test func managedFocusSuppressionPrecedesNFRSuppression() {
        let action = EnsureWorkspaceFocusPolicy.decide(
            base(
                nativeFullscreenSuppressionActive: true,
                managedFocusRecoverySuppressed: true
            )
        )
        #expect(action == .suppressed(reason: .managedFocusRecoverySuppressed))
    }


    @Test func pendingFocusWithLayoutNodeKeepsPendingAndCommitsLayoutSelection() {
        let action = EnsureWorkspaceFocusPolicy.decide(
            base(pendingFocusedToken: tokenA, pendingHasLayoutNode: true)
        )
        #expect(action == .keepPendingFocus(token: tokenA, commitLayoutSelection: true))
    }

    @Test func pendingFocusWithoutLayoutNodeKeepsPendingAndFallsBackToSessionPatch() {
        let action = EnsureWorkspaceFocusPolicy.decide(
            base(pendingFocusedToken: tokenA, pendingHasLayoutNode: false)
        )
        #expect(action == .keepPendingFocus(token: tokenA, commitLayoutSelection: false))
    }

    @Test func pendingFocusBeatsObservedFocus() {
        let action = EnsureWorkspaceFocusPolicy.decide(
            base(
                pendingFocusedToken: tokenA,
                pendingHasLayoutNode: true,
                observedFocusedToken: tokenB,
                observedHasLayoutNode: true
            )
        )
        #expect(action == .keepPendingFocus(token: tokenA, commitLayoutSelection: true))
    }


    @Test func observedFocusWithLayoutNodeKeepsObservedAndCommitsLayoutSelection() {
        let action = EnsureWorkspaceFocusPolicy.decide(
            base(observedFocusedToken: tokenB, observedHasLayoutNode: true)
        )
        #expect(action == .keepObservedFocus(token: tokenB, commitLayoutSelection: true))
    }

    @Test func observedFocusWithoutLayoutNodeKeepsObservedAndFallsBackToSessionPatch() {
        let action = EnsureWorkspaceFocusPolicy.decide(
            base(observedFocusedToken: tokenB, observedHasLayoutNode: false)
        )
        #expect(action == .keepObservedFocus(token: tokenB, commitLayoutSelection: false))
    }


    @Test func noPendingNoObservedTriggersRememberedResolution() {
        let action = EnsureWorkspaceFocusPolicy.decide(base())
        #expect(action == .resolveRememberedFocus)
    }
}
