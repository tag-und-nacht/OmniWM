import Foundation

enum BorderReconcileCacheOutcome: String, CaseIterable, Hashable, Sendable {
    case fastPathHit = "fast_path_hit"
    case eligibilityCacheHit = "eligibility_cache_hit"
    case fullResolution = "full_resolution"
}

enum BorderReconcileCacheMissComponent: String, CaseIterable, Hashable, Sendable {
    case owner
    case windowInfoKey = "window_info_key"
    case preferredFrame = "preferred_frame"
    case ordering
    case policy
}

struct HotPathDebugSnapshot: Equatable, Sendable {
    var displayLinkTicks = 0
    var frontmostActivationEvents = 0
    var frontmostTerminationEvents = 0
    var runtimeTraceAppendAttempts = 0
    var managedRestoreGeometryCalls = 0
    var managedRestoreGeometryCallsByReason: [ManagedRestoreTriggerReason: Int] = [:]
    var managedRestoreSnapshotShortCircuit = 0
    var managedRestoreSnapshotFromCachedNoOp = 0
    var managedRestoreSnapshotFromConfirmedWrite = 0
    var managedRestoreSnapshotPersistenceAttempts = 0
    var managedRestoreSnapshotPersistenceAttemptsByReason: [ManagedRestoreTriggerReason: Int] = [:]
    var managedRestoreSnapshotWrites = 0
    var managedRestoreSnapshotWritesByReason: [ManagedRestoreTriggerReason: Int] = [:]
    var managedRestoreSnapshotSemanticNoOpCount = 0
    var managedRestoreSnapshotSemanticNoOpCountByReason: [ManagedRestoreTriggerReason: Int] = [:]
    var managedRestoreReplacementMetadataCalls = 0
    var managedRestoreReplacementMetadataCacheReuseCount = 0
    var managedRestoreReplacementMetadataFactFetchCount = 0
    var borderRenderRequestedCalls = 0
    var borderReconcileCacheOutcomeCounts: [BorderReconcileCacheOutcome: Int] = [:]
    var borderReconcileCacheMissComponents: [BorderReconcileCacheMissComponent: Int] = [:]
    var workspaceBarMeasuredWidthCalls = 0
    var screenCacheRefreshCount = 0
    var screenLookupRequests = 0
    var screenLookupCacheHits = 0
    var screenLookupCacheMisses = 0
    var backingScaleRequests = 0
    var backingScaleCacheHits = 0
    var backingScaleCacheMisses = 0
    var axFrameApplyOverrideBatchCount = 0
    var axFrameApplyOverrideFlattenedRequestCount = 0
}

@MainActor
final class HotPathDebugMetrics {
    static let shared = HotPathDebugMetrics()

    private(set) var isEnabled =
        ProcessInfo.processInfo.environment["OMNIWM_DEBUG_HOT_PATH_METRICS"] == "1"
    private(set) var snapshot = HotPathDebugSnapshot()

    private init() {}

    func setEnabledForTests(_ enabled: Bool) {
        isEnabled = enabled
        snapshot = .init()
    }

    func reset() {
        snapshot = .init()
    }

    func debugDump() -> String {
        guard isEnabled else {
            return "disabled (set OMNIWM_DEBUG_HOT_PATH_METRICS=1 to enable)"
        }

        let snapshot = snapshot
        var lines = [
            "display_link_ticks=\(snapshot.displayLinkTicks)",
            "frontmost.activation_events=\(snapshot.frontmostActivationEvents)",
            "frontmost.termination_events=\(snapshot.frontmostTerminationEvents)",
            "wm_runtime.append_trace.attempts=\(snapshot.runtimeTraceAppendAttempts)",
            "wm_runtime.append_trace.attempts_per_tick=\(Self.perTick(snapshot.runtimeTraceAppendAttempts, ticks: snapshot.displayLinkTicks))",
            "managed_restore.geometry.calls=\(snapshot.managedRestoreGeometryCalls)",
            "managed_restore.geometry.per_tick=\(Self.perTick(snapshot.managedRestoreGeometryCalls, ticks: snapshot.displayLinkTicks))",
            "managed_restore.snapshot.short_circuit=\(snapshot.managedRestoreSnapshotShortCircuit)",
            "managed_restore.snapshot.from_cached_noop=\(snapshot.managedRestoreSnapshotFromCachedNoOp)",
            "managed_restore.snapshot.from_confirmed_write=\(snapshot.managedRestoreSnapshotFromConfirmedWrite)",
            "managed_restore.snapshot.persistence_attempts=\(snapshot.managedRestoreSnapshotPersistenceAttempts)",
            "managed_restore.snapshot.writes=\(snapshot.managedRestoreSnapshotWrites)",
            "managed_restore.snapshot.semantic_noop=\(snapshot.managedRestoreSnapshotSemanticNoOpCount)",
            "managed_restore.replacement_metadata.calls=\(snapshot.managedRestoreReplacementMetadataCalls)",
            "managed_restore.replacement_metadata.cache_reuse=\(snapshot.managedRestoreReplacementMetadataCacheReuseCount)",
            "managed_restore.replacement_metadata.fact_fetches=\(snapshot.managedRestoreReplacementMetadataFactFetchCount)",
            "border.reconcile_render_requested.calls=\(snapshot.borderRenderRequestedCalls)",
            "border.reconcile_render_requested.per_tick=\(Self.perTick(snapshot.borderRenderRequestedCalls, ticks: snapshot.displayLinkTicks))",
            "border.reconcile_render_requested.fast_path_hit=\(snapshot.borderReconcileCacheOutcomeCounts[.fastPathHit, default: 0])",
            "border.reconcile_render_requested.eligibility_cache_hit=\(snapshot.borderReconcileCacheOutcomeCounts[.eligibilityCacheHit, default: 0])",
            "border.reconcile_render_requested.full_resolution=\(snapshot.borderReconcileCacheOutcomeCounts[.fullResolution, default: 0])",
            "workspace_bar.measured_width.calls=\(snapshot.workspaceBarMeasuredWidthCalls)",
            "workspace_bar.measured_width.per_tick=\(Self.perTick(snapshot.workspaceBarMeasuredWidthCalls, ticks: snapshot.displayLinkTicks))",
            "screen_cache.refreshes=\(snapshot.screenCacheRefreshCount)",
            "screen_cache.screen.requests=\(snapshot.screenLookupRequests)",
            "screen_cache.screen.hits=\(snapshot.screenLookupCacheHits)",
            "screen_cache.screen.misses=\(snapshot.screenLookupCacheMisses)",
            "screen_cache.backing_scale.requests=\(snapshot.backingScaleRequests)",
            "screen_cache.backing_scale.hits=\(snapshot.backingScaleCacheHits)",
            "screen_cache.backing_scale.misses=\(snapshot.backingScaleCacheMisses)",
            "ax_manager.frame_apply_override_batches=\(snapshot.axFrameApplyOverrideBatchCount)",
            "ax_manager.frame_apply_override_flattened_requests=\(snapshot.axFrameApplyOverrideFlattenedRequestCount)",
        ]

        for reason in ManagedRestoreTriggerReason.allCases {
            let suffix = reason.rawValue
            lines.append("managed_restore.geometry.calls.\(suffix)=\(snapshot.managedRestoreGeometryCallsByReason[reason, default: 0])")
            lines.append("managed_restore.snapshot.persistence_attempts.\(suffix)=\(snapshot.managedRestoreSnapshotPersistenceAttemptsByReason[reason, default: 0])")
            lines.append("managed_restore.snapshot.writes.\(suffix)=\(snapshot.managedRestoreSnapshotWritesByReason[reason, default: 0])")
            lines.append("managed_restore.snapshot.semantic_noop.\(suffix)=\(snapshot.managedRestoreSnapshotSemanticNoOpCountByReason[reason, default: 0])")
        }

        for component in BorderReconcileCacheMissComponent.allCases {
            lines.append(
                "border.reconcile_render_requested.miss.\(component.rawValue)=\(snapshot.borderReconcileCacheMissComponents[component, default: 0])"
            )
        }

        return lines.joined(separator: "\n")
    }

    func recordDisplayLinkTick() {
        mutate { $0.displayLinkTicks += 1 }
    }

    func recordFrontmostActivationEvent() {
        mutate { $0.frontmostActivationEvents += 1 }
    }

    func recordFrontmostTerminationEvent() {
        mutate { $0.frontmostTerminationEvents += 1 }
    }

    func recordRuntimeTraceAppendAttempt() {
        mutate { $0.runtimeTraceAppendAttempts += 1 }
    }

    func recordManagedRestoreGeometry(reason: ManagedRestoreTriggerReason = .frameConfirmed) {
        mutate {
            $0.managedRestoreGeometryCalls += 1
            $0.managedRestoreGeometryCallsByReason[reason, default: 0] += 1
        }
    }

    func recordManagedRestoreSnapshotShortCircuit() {
        mutate { $0.managedRestoreSnapshotShortCircuit += 1 }
    }

    func recordManagedRestoreSnapshotFrameConfirmResult(_ result: FrameConfirmResult) {
        mutate {
            switch result {
            case .cachedNoOp:
                $0.managedRestoreSnapshotFromCachedNoOp += 1
            case .confirmedWrite:
                $0.managedRestoreSnapshotFromConfirmedWrite += 1
            }
        }
    }

    func recordManagedRestoreSnapshotPersistenceAttempt(
        reason: ManagedRestoreTriggerReason = .frameConfirmed
    ) {
        mutate {
            $0.managedRestoreSnapshotPersistenceAttempts += 1
            $0.managedRestoreSnapshotPersistenceAttemptsByReason[reason, default: 0] += 1
        }
    }

    func recordManagedRestoreSnapshotWrite(reason: ManagedRestoreTriggerReason = .frameConfirmed) {
        mutate {
            $0.managedRestoreSnapshotWrites += 1
            $0.managedRestoreSnapshotWritesByReason[reason, default: 0] += 1
        }
    }

    func recordManagedRestoreSnapshotSemanticNoOp(
        reason: ManagedRestoreTriggerReason = .frameConfirmed
    ) {
        mutate {
            $0.managedRestoreSnapshotSemanticNoOpCount += 1
            $0.managedRestoreSnapshotSemanticNoOpCountByReason[reason, default: 0] += 1
        }
    }

    func recordManagedRestoreReplacementMetadata(didFetchFacts: Bool) {
        mutate {
            $0.managedRestoreReplacementMetadataCalls += 1
            if didFetchFacts {
                $0.managedRestoreReplacementMetadataFactFetchCount += 1
            } else {
                $0.managedRestoreReplacementMetadataCacheReuseCount += 1
            }
        }
    }

    func recordBorderRenderRequested() {
        mutate { $0.borderRenderRequestedCalls += 1 }
    }

    func recordBorderReconcileCacheOutcome(_ outcome: BorderReconcileCacheOutcome) {
        mutate {
            $0.borderReconcileCacheOutcomeCounts[outcome, default: 0] += 1
        }
    }

    func recordBorderReconcileCacheMissComponent(_ component: BorderReconcileCacheMissComponent) {
        mutate {
            $0.borderReconcileCacheMissComponents[component, default: 0] += 1
        }
    }

    func recordWorkspaceBarMeasurement() {
        mutate { $0.workspaceBarMeasuredWidthCalls += 1 }
    }

    func recordScreenCacheRefresh() {
        mutate { $0.screenCacheRefreshCount += 1 }
    }

    func recordScreenLookup(hit: Bool) {
        mutate {
            $0.screenLookupRequests += 1
            if hit {
                $0.screenLookupCacheHits += 1
            } else {
                $0.screenLookupCacheMisses += 1
            }
        }
    }

    func recordBackingScaleLookup(hit: Bool) {
        mutate {
            $0.backingScaleRequests += 1
            if hit {
                $0.backingScaleCacheHits += 1
            } else {
                $0.backingScaleCacheMisses += 1
            }
        }
    }

    func recordAXFrameApplyOverrideBatch(requestCount: Int) {
        mutate {
            $0.axFrameApplyOverrideBatchCount += 1
            $0.axFrameApplyOverrideFlattenedRequestCount += requestCount
        }
    }

    private func mutate(_ update: (inout HotPathDebugSnapshot) -> Void) {
        guard isEnabled else { return }
        update(&snapshot)
    }

    private static func perTick(_ count: Int, ticks: Int) -> String {
        guard ticks > 0 else { return "n/a" }
        let value = Double(count) / Double(ticks)
        return String(format: "%.2f", value)
    }
}
