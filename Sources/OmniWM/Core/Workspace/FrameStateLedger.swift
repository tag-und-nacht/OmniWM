// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

/// Per-logical-id frame state storage. Extracted from `WorkspaceManager`
/// (ExecPlan 01, slice WGT-SS-03) so the frame-reducer event flow lives
/// behind a focused type that pairs cleanly with `FrameRuntime` once
/// ExecPlan 02 lands. The reducer logic itself stays in `FrameReducer`;
/// this type owns the storage and the read/write contract.
struct FrameStateLedger {
    private var statesByLogicalId: [LogicalWindowId: FrameState] = [:]

    /// Number of logical ids with stored frame state. Diagnostic only.
    var count: Int { statesByLogicalId.count }

    /// Direct read of the stored frame state for a logical id, or `nil` if
    /// none has ever been recorded.
    func state(for logicalId: LogicalWindowId) -> FrameState? {
        statesByLogicalId[logicalId]
    }

    /// Apply a `FrameReducer.Event` to the stored state for the given
    /// logical id. Allocates `.initial` on first touch. Returns the reducer
    /// reduction so callers can observe `didChange` and the next state.
    @discardableResult
    mutating func reduce(
        _ event: FrameReducer.Event,
        forLogicalId logicalId: LogicalWindowId
    ) -> FrameReducer.Reduction {
        let state = statesByLogicalId[logicalId] ?? .initial
        let reduction = FrameReducer.reduce(state: state, event: event)
        statesByLogicalId[logicalId] = reduction.nextState
        return reduction
    }

    /// Drop the stored frame state for the given logical id. Used when a
    /// window is fully retired and its frame history is no longer needed
    /// (e.g., after registry rekey or terminal removal).
    mutating func drop(logicalId: LogicalWindowId) {
        statesByLogicalId.removeValue(forKey: logicalId)
    }

    /// All logical ids currently tracked. Diagnostic / iteration only —
    /// callers should not mutate based on this snapshot.
    var trackedLogicalIds: some Collection<LogicalWindowId> {
        statesByLogicalId.keys
    }
}
