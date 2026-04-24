// SPDX-License-Identifier: GPL-2.0-only
import Foundation

/// Owns the manager-side `FocusState` snapshot. Extracted from
/// `WorkspaceManager` (ExecPlan 01, slice WGT-SS-04) so the focus-reducer
/// dispatch and the explicit clear path live behind a focused type that
/// pairs cleanly with `FocusRuntime` once ExecPlan 02 lands. The reducer
/// logic itself stays in `FocusReducer`; this type owns the storage and the
/// few direct-write paths that bypass the reducer.
struct FocusStateLedger {
    private(set) var state: FocusState = .initial

    /// Direct read passthroughs for the most common access patterns. Callers
    /// that need the full snapshot use `state` (read-only).
    var observedToken: WindowToken? { state.observedToken }
    var hasPendingActivation: Bool { state.hasPendingActivation }
    var desired: FocusState.DesiredFocus { state.desired }

    /// Apply a `FocusReducer.Event`. Returns the full reduction so callers
    /// can act on `didChange` / `recommendedAction`.
    @discardableResult
    mutating func reduce(_ event: FocusReducer.Event) -> FocusReducer.Reduction {
        let reduction = FocusReducer.reduce(state: state, event: event)
        state = reduction.nextState
        return reduction
    }

    /// Direct write path used by the legacy "clear focus observed token"
    /// surface — bypasses the reducer because the operation is a hard reset
    /// and there is no event currently representing it. Once `FocusRuntime`
    /// is in place (ExecPlan 02), this should be expressed as a reducer
    /// event with epoch stamping.
    mutating func clearObservedAndActivation() {
        state.observedToken = nil
        state.activation = .idle
    }
}
