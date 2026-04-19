import Foundation
import Observation

@MainActor @Observable
final class WMRuntime {
    private static let maxTraceRecordCount = 128

    let settings: SettingsStore
    let platform: WMPlatform
    let workspaceManager: WorkspaceManager
    let hiddenBarController: HiddenBarController
    let controller: WMController
    private let effectExecutor: any EffectExecutor
    private let traceMode: WMRuntimeTraceMode
    private(set) var snapshot: WMRuntimeSnapshot
    private(set) var recentTrace: [WMRuntimeTraceRecord] = []
    private var nextEventId: UInt64 = 1

    var state: WMState {
        snapshot.reconcile
    }

    var orchestrationSnapshot: OrchestrationSnapshot {
        snapshot.orchestration
    }

    var refreshSnapshot: RefreshOrchestrationSnapshot {
        snapshot.orchestration.refresh
    }

    var configuration: WMRuntimeConfiguration {
        snapshot.configuration
    }

    init(
        settings: SettingsStore,
        platform: WMPlatform = .live,
        hiddenBarController: HiddenBarController? = nil,
        windowFocusOperations: WindowFocusOperations? = nil,
        effectExecutor: (any EffectExecutor)? = nil,
        traceMode: WMRuntimeTraceMode = .default
    ) {
        self.settings = settings
        self.platform = platform
        self.traceMode = traceMode
        let resolvedHiddenBarController = hiddenBarController ?? HiddenBarController(settings: settings)
        self.hiddenBarController = resolvedHiddenBarController
        let workspaceManager = WorkspaceManager(settings: settings)
        self.workspaceManager = workspaceManager
        controller = WMController(
            settings: settings,
            workspaceManager: workspaceManager,
            hiddenBarController: resolvedHiddenBarController,
            platform: platform,
            windowFocusOperations: windowFocusOperations ?? platform.windowFocusOperations
        )
        self.effectExecutor = effectExecutor ?? WMRuntimeEffectExecutor()
        snapshot = WMRuntimeSnapshot(
            reconcile: workspaceManager.reconcileSnapshot(),
            orchestration: .init(
                refresh: .init(),
                focus: Self.makeFocusSnapshot(
                    controller: controller,
                    workspaceManager: workspaceManager
                )
            ),
            configuration: WMRuntimeConfiguration(settings: settings)
        )
        controller.runtime = self
    }

    func start() {
        HotPathDebugMetrics.shared.reset()
        applyCurrentConfiguration()
    }

    func applyCurrentConfiguration() {
        applyConfiguration(WMRuntimeConfiguration(settings: settings))
    }

    func applyConfiguration(_ configuration: WMRuntimeConfiguration) {
        snapshot.configuration = configuration
        controller.applyConfiguration(configuration)
        refreshSnapshotState()
        appendTrace(
            eventSummary: "configuration_applied",
            decisionSummary: nil,
            actionSummaries: [configuration.summary]
        )
    }

    func flushState() {
        workspaceManager.flushPersistedWindowRestoreCatalogNow()
        settings.flushNow()
    }

    @discardableResult
    func submit(_ event: WMEvent) -> ReconcileTxn {
        let transaction = workspaceManager.recordReconcileEvent(event)
        refreshSnapshotState()
        appendTrace(
            eventSummary: event.summary,
            decisionSummary: transaction.plan.summary,
            actionSummaries: transaction.plan.isEmpty ? [] : [transaction.plan.summary]
        )
        return transaction
    }

    func requestManagedFocus(
        token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID
    ) -> OrchestrationResult {
        apply(
            .focusRequested(
                .init(
                    token: token,
                    workspaceId: workspaceId
                )
            ),
            context: .focusRequest
        )
    }

    func observeActivation(
        _ observation: ManagedActivationObservation,
        observedAXRef: AXWindowRef?,
        managedEntry: WindowModel.Entry?,
        confirmRequest: Bool = true
    ) -> OrchestrationResult {
        apply(
            .activationObserved(observation),
            context: .activationObserved(
                observedAXRef: observedAXRef,
                managedEntry: managedEntry,
                source: observation.source,
                confirmRequest: confirmRequest
            )
        )
    }

    func requestRefresh(
        _ request: RefreshRequestEvent
    ) -> OrchestrationResult {
        apply(
            .refreshRequested(request),
            context: .refresh
        )
    }

    func completeRefresh(
        _ completion: RefreshCompletionEvent
    ) -> OrchestrationResult {
        apply(
            .refreshCompleted(completion),
            context: .refresh
        )
    }

    func resetRefreshOrchestration() {
        snapshot.orchestration.refresh = .init()
        appendTrace(
            eventSummary: "refresh_reset",
            decisionSummary: nil,
            actionSummaries: []
        )
    }

    private func apply(
        _ event: OrchestrationEvent,
        context: WMRuntimeEffectContext
    ) -> OrchestrationResult {
        synchronizeOrchestrationInputs()

        let result = OrchestrationCore.step(
            snapshot: snapshot.orchestration,
            event: event
        )
        snapshot.orchestration = result.snapshot

        effectExecutor.execute(
            result,
            on: controller,
            context: context
        )

        refreshSnapshotState()
        appendTrace(
            eventSummary: traceEventSummary(for: event),
            decisionSummary: traceDecisionSummary(for: result.decision),
            actionSummaries: traceActionSummaries(for: result.plan.actions)
        )
        return result
    }

    private func synchronizeOrchestrationInputs() {
        snapshot.reconcile = workspaceManager.reconcileSnapshot()
        snapshot.orchestration.focus = Self.makeFocusSnapshot(
            controller: controller,
            workspaceManager: workspaceManager
        )
    }

    private func refreshSnapshotState() {
        snapshot.reconcile = workspaceManager.reconcileSnapshot()
        snapshot.orchestration.focus = Self.makeFocusSnapshot(
            controller: controller,
            workspaceManager: workspaceManager
        )
    }

    private static func makeFocusSnapshot(
        controller: WMController,
        workspaceManager: WorkspaceManager
    ) -> FocusOrchestrationSnapshot {
        .init(
            nextManagedRequestId: controller.focusBridge.nextManagedRequestId,
            activeManagedRequest: controller.focusBridge.activeManagedRequest,
            pendingFocusedToken: workspaceManager.pendingFocusedToken,
            pendingFocusedWorkspaceId: workspaceManager.pendingFocusedWorkspaceId,
            isNonManagedFocusActive: workspaceManager.isNonManagedFocusActive,
            isAppFullscreenActive: workspaceManager.isAppFullscreenActive
        )
    }

    private func appendTrace(
        eventSummary: @autoclosure () -> String,
        decisionSummary: @autoclosure () -> String?,
        actionSummaries: @autoclosure () -> [String]
    ) {
        HotPathDebugMetrics.shared.recordRuntimeTraceAppendAttempt()
        guard traceMode.isEnabled else { return }

        let record = WMRuntimeTraceRecord(
            eventId: nextEventId,
            timestamp: Date(),
            eventSummary: eventSummary(),
            decisionSummary: decisionSummary(),
            actionSummaries: actionSummaries(),
            focusedToken: snapshot.reconcile.focusSession.focusedToken,
            pendingFocusedToken: snapshot.reconcile.focusSession.pendingManagedFocus.token,
            activeRefreshCycleId: snapshot.orchestration.refresh.activeRefresh?.cycleId,
            pendingRefreshCycleId: snapshot.orchestration.refresh.pendingRefresh?.cycleId
        )
        nextEventId &+= 1
        recentTrace.append(record)
        if recentTrace.count > Self.maxTraceRecordCount {
            recentTrace.removeFirst(recentTrace.count - Self.maxTraceRecordCount)
        }
    }

    private func traceEventSummary(for event: OrchestrationEvent) -> String {
        switch traceMode {
        case .disabled:
            return ""
        case .summary:
            return event.summary
        case .detailed:
            return String(describing: event)
        }
    }

    private func traceDecisionSummary(for decision: OrchestrationDecision) -> String {
        switch traceMode {
        case .disabled:
            return ""
        case .summary:
            return decision.summary
        case .detailed:
            return String(describing: decision)
        }
    }

    private func traceActionSummaries(for actions: [OrchestrationPlan.Action]) -> [String] {
        switch traceMode {
        case .disabled:
            return []
        case .summary:
            return actions.map(\.summary)
        case .detailed:
            return actions.map { String(describing: $0) }
        }
    }
}
