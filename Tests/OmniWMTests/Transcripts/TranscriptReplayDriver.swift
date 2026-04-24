// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import OmniWMIPC

@testable import OmniWM

@MainActor
final class TranscriptReplayDriver {
    let transcript: Transcript
    let runtime: WMRuntime
    let platform: RecordingEffectPlatform
    let runner: TransactionReplayRunner

    private(set) var ipcResponses: [(stepIndex: Int, response: IPCResponse)] = []

    private var deferredEvents: [WMEvent] = []
    private var topologyEpochsBeforeStep: [TopologyEpoch] = []
    private var watermarkAtStart: TransactionEpoch = .invalid

    init(transcript: Transcript) {
        let platform = RecordingEffectPlatform()
        let runtime = TranscriptReplayDriver.setUpRuntime(transcript: transcript, platform: platform)
        self.transcript = transcript
        self.runtime = runtime
        self.platform = platform
        self.runner = TransactionReplayRunner(runtime: runtime, platform: platform)
    }

    init(
        transcript: Transcript,
        runtime: WMRuntime,
        platform: RecordingEffectPlatform
    ) {
        self.transcript = transcript
        self.runtime = runtime
        self.platform = platform
        self.runner = TransactionReplayRunner(runtime: runtime, platform: platform)
    }

    struct TranscriptViolation: Error, CustomStringConvertible {
        let stepIndex: Int?
        let phase: Phase
        let message: String

        enum Phase: String, Equatable {
            case perturbation
            case runner
            case invariant
            case transactionEffects
            case ipc
            case displayDelta
            case effectConfirmation
            case final
            case security
        }

        var description: String {
            let where_: String
            if let idx = stepIndex {
                where_ = "step[\(idx)]"
            } else {
                where_ = "final"
            }
            return "transcript violation at \(where_) phase=\(phase.rawValue): \(message)"
        }
    }

    func run() async throws {
        watermarkAtStart = runtime.currentEffectRunnerWatermark

        let resolvedSteps = try preprocessReorders(transcript.steps)

        for (index, step) in resolvedSteps.enumerated() {
            topologyEpochsBeforeStep.append(runtime.currentTopologyEpoch)
            try await processStep(step, index: index)
        }
        try drainDeferredAtEnd()
        try validateFinal()
    }

    private func preprocessReorders(_ steps: [TranscriptStep]) throws -> [TranscriptStep] {
        var result = steps
        for i in result.indices {
            guard case let .reorderWith(offset) = result[i].perturbation else { continue }
            guard offset > 0 else {
                throw TranscriptViolation(
                    stepIndex: i,
                    phase: .perturbation,
                    message: "reorderWith offset must be > 0; got \(offset)"
                )
            }
            let target = i + offset
            guard target < result.count else {
                throw TranscriptViolation(
                    stepIndex: i,
                    phase: .perturbation,
                    message: "reorderWith offset \(offset) places target at \(target), past end of step list (count=\(result.count))"
                )
            }
            let movedForward = result[i]
            let pulledBackward = result[target]
            var pulledExpectation = pulledBackward.expectation
            pulledExpectation.transactionEpochAdvances = true
            var movedExpectation = movedForward.expectation
            movedExpectation.transactionEpochAdvances = true
            result[i] = TranscriptStep(
                kind: pulledBackward.kind,
                perturbation: .none,
                expectation: pulledExpectation
            )
            result[target] = TranscriptStep(
                kind: movedForward.kind,
                perturbation: .none,
                expectation: movedExpectation
            )
        }
        return result
    }


    private static func setUpRuntime(
        transcript: Transcript,
        platform: RecordingEffectPlatform
    ) -> WMRuntime {
        resetSharedControllerStateForTests()

        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())

        var workspaces = transcript.initialWorkspaces.isEmpty
            ? [
                WorkspaceConfiguration(name: "1", monitorAssignment: .main),
                WorkspaceConfiguration(name: "2", monitorAssignment: .main)
            ]
            : transcript.initialWorkspaces
        workspaces = workspaces.map { config in
            if let layout = transcript.layoutByWorkspaceName[config.name] {
                return config.with(layoutType: layout == .niri ? .niri : .dwindle)
            }
            return config
        }
        settings.workspaceConfigurations = workspaces

        let runtime = WMRuntime(settings: settings, effectPlatform: platform)

        let monitors = transcript.initialMonitors.isEmpty
            ? [makeLayoutPlanTestMonitor()]
            : transcript.initialMonitors.map(VirtualDisplayBoard.materialize)
        runtime.controller.workspaceManager.applyMonitorConfigurationChange(monitors)

        let activeName = transcript.activeWorkspaceName ?? workspaces.first?.name
        if let activeName,
           let workspaceId = runtime.controller.workspaceManager.workspaceId(
               for: activeName,
               createIfMissing: false
           ),
           let firstMonitor = runtime.controller.workspaceManager.monitors.first
        {
            _ = runtime.controller.workspaceManager.setActiveWorkspace(
                workspaceId,
                on: firstMonitor.id
            )
        }

        return runtime
    }


    private func processStep(_ step: TranscriptStep, index: Int) async throws {
        if step.perturbation != .delayedAdmission {
            try drainDeferredEventsBeforeRunnerStep(currentKind: step.kind, index: index)
        }

        let outcomesBefore = runner.outcomes.count
        let watermarkBefore = runtime.currentEffectRunnerWatermark

        switch step.perturbation {
        case .none:
            try await driveStep(step, index: index)
        case .duplicate:
            try await driveStep(step, index: index)
            try await driveStep(step, index: index)
        case .drop:
            break
        case .delayedAdmission:
            switch step.kind {
            case let .event(event):
                deferredEvents.append(event)
            default:
                throw TranscriptViolation(
                    stepIndex: index,
                    phase: .perturbation,
                    message: "delayedAdmission is only supported on .event steps"
                )
            }
        case let .reorderWith(offset):
            throw TranscriptViolation(
                stepIndex: index,
                phase: .perturbation,
                message: "internal: reorderWith(\(offset)) reached processStep; preprocessReorders should have consumed it"
            )
        }

        let outcomesAfter = runner.outcomes.count
        let advancedOutcomes = outcomesAfter - outcomesBefore
        if step.expectation.transactionEpochAdvances {
            let expected: Int = (step.perturbation == .duplicate) ? 2 : 1
            if isRunnerDriven(step.kind), advancedOutcomes != expected {
                throw TranscriptViolation(
                    stepIndex: index,
                    phase: .runner,
                    message: "expected runner outcome count to advance by \(expected), got \(advancedOutcomes)"
                )
            }
        } else {
            if advancedOutcomes != 0 {
                throw TranscriptViolation(
                    stepIndex: index,
                    phase: .runner,
                    message: "expected runner outcome count to be unchanged for transactionEpochAdvances=false; got +\(advancedOutcomes)"
                )
            }
            if case .ipcRequest = step.kind {
                let watermarkAfter = runtime.currentEffectRunnerWatermark
                if watermarkAfter != watermarkBefore {
                    throw TranscriptViolation(
                        stepIndex: index,
                        phase: .security,
                        message: "rejected IPC request advanced effect runner watermark from \(watermarkBefore) to \(watermarkAfter)"
                    )
                }
            }
        }

        if let matcher = step.expectation.transactionEffects,
           let lastOutcome = runner.outcomes.last
        {
            let kinds = (lastOutcome.transaction?.effects ?? []).map(\.kind)
            if !matcher.matches(kinds) {
                throw TranscriptViolation(
                    stepIndex: index,
                    phase: .transactionEffects,
                    message: "effect plan kinds \(kinds) did not match expected matcher \(matcher)"
                )
            }
        }

        let previousTopologyEpoch = topologyEpochsBeforeStep[index]
        for invariantId in step.expectation.perStepInvariants {
            if let violation = TranscriptInvariantRegistry.validate(
                invariantId,
                runtime: runtime,
                platform: platform,
                outcome: runner.outcomes.last,
                previousTopologyEpoch: previousTopologyEpoch
            ) {
                throw TranscriptViolation(
                    stepIndex: index,
                    phase: .invariant,
                    message: "[\(invariantId.rawValue)] \(violation)"
                )
            }
        }
    }

    private func isRunnerDriven(_ kind: TranscriptStep.Kind) -> Bool {
        switch kind {
        case .event, .command:
            return true
        case .ipcRequest, .displayDelta, .effectConfirmation:
            return false
        }
    }

    private func driveStep(_ step: TranscriptStep, index: Int) async throws {
        switch step.kind {
        case let .event(event):
            try driveEventThroughRunner(event, index: index)

        case let .command(command):
            try driveCommandThroughRunner(command, index: index)

        case let .ipcRequest(request):
            try await driveIPC(request: request, expectation: step.expectation.ipcResponse, index: index)

        case let .displayDelta(delta):
            try driveDisplayDelta(delta, index: index)

        case let .effectConfirmation(confirmation):
            try driveEffectConfirmation(confirmation, index: index)
        }
    }

    private func drainDeferredEventsBeforeRunnerStep(currentKind: TranscriptStep.Kind, index: Int) throws {
        guard isRunnerDriven(currentKind) else { return }
        for deferred in deferredEvents {
            try driveEventThroughRunner(deferred, index: index)
        }
        deferredEvents.removeAll(keepingCapacity: true)
    }

    private func driveEventThroughRunner(_ event: WMEvent, index: Int) throws {
        do {
            try runner.replay([.event(event)])
        } catch let error as TransactionReplayRunner.InvariantViolation {
            throw TranscriptViolation(
                stepIndex: index,
                phase: .runner,
                message: error.message
            )
        }
    }

    private func driveCommandThroughRunner(_ command: WMCommand, index: Int) throws {
        do {
            try runner.replay([.command(command)])
        } catch let error as TransactionReplayRunner.InvariantViolation {
            throw TranscriptViolation(
                stepIndex: index,
                phase: .runner,
                message: error.message
            )
        }
    }

    private func driveIPC(
        request: IPCRequest,
        expectation: TranscriptIPCStepExpectation?,
        index: Int
    ) async throws {
        let response = await TranscriptIPCDriver.driveDirectly(
            request: request,
            runtime: runtime
        )
        ipcResponses.append((stepIndex: index, response: response))

        guard let expectation else { return }
        if let expectedStatus = expectation.expectedStatus,
           response.status != expectedStatus
        {
            throw TranscriptViolation(
                stepIndex: index,
                phase: .ipc,
                message: "expected IPC status \(expectedStatus), got \(response.status)"
            )
        }
        if let expectedCode = expectation.expectedErrorCode,
           response.code != expectedCode
        {
            throw TranscriptViolation(
                stepIndex: index,
                phase: .ipc,
                message: "expected IPC error code \(expectedCode.rawValue), got \(response.code?.rawValue ?? "nil")"
            )
        }
        if expectation.expectsZeroPlatformEvents, !platform.events.isEmpty {
            throw TranscriptViolation(
                stepIndex: index,
                phase: .security,
                message: "expected zero platform events on rejected IPC, got \(platform.events.count)"
            )
        }
    }

    private func driveDisplayDelta(_ delta: TranscriptDisplayDelta, index: Int) throws {
        let monitors = delta.monitorsAfter.map(VirtualDisplayBoard.materialize)
        runtime.applyMonitorConfigurationChange(monitors, source: .service)
        _ = index
    }

    private func driveEffectConfirmation(_ confirmation: WMEffectConfirmation, index: Int) throws {
        _ = runtime.submit(confirmation)
        _ = index
    }

    private func drainDeferredAtEnd() throws {
        for deferred in deferredEvents {
            try driveEventThroughRunner(deferred, index: transcript.steps.count - 1)
        }
        deferredEvents.removeAll(keepingCapacity: false)
    }


    private func validateFinal() throws {
        let final = transcript.finalExpectations

        if final.topologyEpochStrictlyAdvanced {
            if runtime.currentTopologyEpoch.value <= 0 {
                throw TranscriptViolation(
                    stepIndex: nil,
                    phase: .final,
                    message: "expected topology epoch to advance, but is still \(runtime.currentTopologyEpoch.value)"
                )
            }
        }

        if let expectedCount = final.workspaceCount {
            let actual = runtime.controller.workspaceManager.allWorkspaceDescriptors().count
            if actual != expectedCount {
                throw TranscriptViolation(
                    stepIndex: nil,
                    phase: .final,
                    message: "expected workspace count \(expectedCount), got \(actual)"
                )
            }
        }

        if let assertion = final.focusedToken {
            let focused = runtime.controller.workspaceManager.reconcileSnapshot()
                .focusSession.focusedToken
            switch assertion {
            case .nilToken:
                if focused != nil {
                    throw TranscriptViolation(
                        stepIndex: nil,
                        phase: .final,
                        message: "expected focused token to be nil, got \(String(describing: focused))"
                    )
                }
            case .nonNil:
                if focused == nil {
                    throw TranscriptViolation(
                        stepIndex: nil,
                        phase: .final,
                        message: "expected focused token to be non-nil"
                    )
                }
            case let .exactly(expected):
                if focused != expected {
                    throw TranscriptViolation(
                        stepIndex: nil,
                        phase: .final,
                        message: "expected focused token \(expected), got \(String(describing: focused))"
                    )
                }
            case let .anyOf(set):
                guard let focused else {
                    throw TranscriptViolation(
                        stepIndex: nil,
                        phase: .final,
                        message: "expected focused token in \(set), got nil"
                    )
                }
                if !set.contains(focused) {
                    throw TranscriptViolation(
                        stepIndex: nil,
                        phase: .final,
                        message: "expected focused token in \(set), got \(focused)"
                    )
                }
            }
        }

        for invariantId in final.customAssertions {
            if let violation = TranscriptInvariantRegistry.validate(
                invariantId,
                runtime: runtime,
                platform: platform,
                outcome: runner.outcomes.last,
                previousTopologyEpoch: nil
            ) {
                throw TranscriptViolation(
                    stepIndex: nil,
                    phase: .final,
                    message: "[\(invariantId.rawValue)] \(violation)"
                )
            }
        }

        if let boundary = transcript.securityBoundary,
           boundary.assertsZeroEffectsOnEveryRejection
        {
            let rejections = ipcResponses.filter { !$0.response.ok }
            if !rejections.isEmpty, !platform.events.isEmpty {
                throw TranscriptViolation(
                    stepIndex: nil,
                    phase: .security,
                    message: "security boundary asserts zero platform events on any rejection, but cumulative platform.events == \(platform.events.count)"
                )
            }
        }
    }
}

enum TranscriptIPCDriver {
    @MainActor
    static func driveDirectly(
        request: IPCRequest,
        runtime: WMRuntime
    ) async -> IPCResponse {
        let bridge = IPCApplicationBridge(
            controller: runtime.controller,
            sessionToken: "transcript-session",
            authorizationToken: TranscriptIPCDriver.fixedAuthorizationToken
        )
        return await bridge.response(for: request)
    }

    static let fixedAuthorizationToken = "transcript-authorization-token-0001"
}
