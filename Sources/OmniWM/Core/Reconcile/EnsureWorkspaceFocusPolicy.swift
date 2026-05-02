// SPDX-License-Identifier: GPL-2.0-only
import Foundation

enum EnsureWorkspaceFocusPolicy {
    struct Inputs: Equatable {
        let workspaceId: WorkspaceDescriptor.ID
        let pendingFocusedToken: WindowToken?
        let pendingHasLayoutNode: Bool
        let observedFocusedToken: WindowToken?
        let observedHasLayoutNode: Bool
        let nativeFullscreenSuppressionActive: Bool
        let managedFocusRecoverySuppressed: Bool
    }

    enum Action: Equatable {
        case suppressed(reason: SuppressionReason)
        case keepPendingFocus(token: WindowToken, commitLayoutSelection: Bool)
        case keepObservedFocus(token: WindowToken, commitLayoutSelection: Bool)
        case resolveRememberedFocus
    }

    enum SuppressionReason: Equatable {
        case managedFocusRecoverySuppressed
        case nativeFullscreenTransitionPending
    }

    static func decide(_ inputs: Inputs) -> Action {
        if inputs.managedFocusRecoverySuppressed {
            return .suppressed(reason: .managedFocusRecoverySuppressed)
        }
        if inputs.nativeFullscreenSuppressionActive {
            return .suppressed(reason: .nativeFullscreenTransitionPending)
        }

        if let pendingFocusedToken = inputs.pendingFocusedToken {
            return .keepPendingFocus(
                token: pendingFocusedToken,
                commitLayoutSelection: inputs.pendingHasLayoutNode
            )
        }

        if let observedFocusedToken = inputs.observedFocusedToken {
            return .keepObservedFocus(
                token: observedFocusedToken,
                commitLayoutSelection: inputs.observedHasLayoutNode
            )
        }

        return .resolveRememberedFocus
    }
}
