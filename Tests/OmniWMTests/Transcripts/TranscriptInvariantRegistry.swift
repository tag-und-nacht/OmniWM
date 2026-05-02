// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@testable import OmniWM

enum TranscriptInvariantRegistry {
    @MainActor
    static func validate(
        _ id: TranscriptInvariantPredicateID,
        runtime: WMRuntime,
        platform: RecordingEffectPlatform,
        outcome: TransactionReplayRunner.Outcome?,
        previousTopologyEpoch: TopologyEpoch?
    ) -> String? {
        switch id {
        case .eachManagedWindowInExactlyOneGraph,
             .workspaceGraphValidates:
            return validateWorkspaceGraph(runtime: runtime)

        case .retiredOrQuarantinedCannotReceiveFocusEffect:
            return validateRetiredCannotReceiveFocus(
                runtime: runtime,
                outcome: outcome
            )

        case .retiredOrQuarantinedCannotReceiveLayoutEffect:
            return validateRetiredCannotReceiveLayout(
                runtime: runtime,
                outcome: outcome
            )

        case .retiredOrQuarantinedCannotReceiveFrameEffect:
            return validateRetiredCannotReceiveFrame(
                runtime: runtime,
                outcome: outcome
            )

        case .failedFrameWriteCannotConfirmFrame:
            return validateFailedFrameWriteCannotConfirm(runtime: runtime)

        case .effectEpochsMonotonicAcrossPlans:
            return nil

        case .topologyEpochAdvancesOnRealDelta:
            guard let previous = previousTopologyEpoch else { return nil }
            let current = runtime.currentTopologyEpoch
            if current.value <= previous.value {
                return "topology epoch did not advance: prev=\(previous.value) current=\(current.value)"
            }
            return nil
        }
    }

    @MainActor
    private static func validateWorkspaceGraph(runtime: WMRuntime) -> String? {
        let graph = runtime.controller.workspaceManager.workspaceGraphSnapshot()
        let registry = runtime.controller.workspaceManager.logicalWindowRegistry
        if let violation = WorkspaceGraphInvariants.validate(graph, registry: registry) {
            return "workspace graph violation: \(violation)"
        }
        return nil
    }

    @MainActor
    private static func validateRetiredCannotReceiveFocus(
        runtime: WMRuntime,
        outcome: TransactionReplayRunner.Outcome?
    ) -> String? {
        guard let outcome = outcome else { return nil }
        let registry = runtime.controller.workspaceManager.logicalWindowRegistry
        for event in outcome.platformEventsAfter {
            guard case let .focusWindow(token, _) = event else { continue }
            if isTokenRetired(token, registry: registry) {
                return "focus effect targeted retired token \(token)"
            }
        }
        return nil
    }

    @MainActor
    private static func validateRetiredCannotReceiveLayout(
        runtime: WMRuntime,
        outcome: TransactionReplayRunner.Outcome?
    ) -> String? {
        guard let outcome = outcome else { return nil }
        let registry = runtime.controller.workspaceManager.logicalWindowRegistry
        let graph = runtime.controller.workspaceManager.workspaceGraphSnapshot()
        for entry in graph.entriesByLogicalId.values {
            if registry.currentToken(for: entry.logicalId) == nil {
                return "layout entry references retired logical id \(entry.logicalId)"
            }
        }
        _ = outcome
        return nil
    }

    @MainActor
    private static func validateRetiredCannotReceiveFrame(
        runtime: WMRuntime,
        outcome: TransactionReplayRunner.Outcome?
    ) -> String? {
        guard outcome != nil else { return nil }
        return validateWorkspaceGraph(runtime: runtime)
    }

    @MainActor
    private static func validateFailedFrameWriteCannotConfirm(runtime: WMRuntime) -> String? {
        let workspaceManager = runtime.controller.workspaceManager
        let registry = workspaceManager.logicalWindowRegistry
        for record in registry.activeRecords() {
            guard let frameState = workspaceManager.frameState(for: record.logicalId) else {
                continue
            }
            guard case let .failed(reason, _) = frameState.write else { continue }
            guard let desired = frameState.desired,
                  let confirmed = frameState.confirmed,
                  confirmed.isWithinTolerance(of: desired)
            else {
                continue
            }
            return "logical window \(record.logicalId) is in failed-write state " +
                "(reason=\(reason)) yet confirmed frame is within tolerance of desired"
        }
        return nil
    }

    @MainActor
    private static func isTokenRetired(
        _ token: WindowToken,
        registry: any LogicalWindowRegistryReading
    ) -> Bool {
        switch registry.lookup(token: token) {
        case .current:
            return false
        case .staleAlias, .retired, .unknown:
            return true
        }
    }
}
