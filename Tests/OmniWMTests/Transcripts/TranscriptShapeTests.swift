// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OmniWMIPC
import Testing

@testable import OmniWM

@Suite(.serialized) struct TranscriptShapeTests {
    @Test func builderEmitsStepsInDeclarationOrder() {
        let event1 = WMEvent.activeSpaceChanged(source: .workspaceManager)
        let event2 = WMEvent.systemSleep(source: .service)
        let event3 = WMEvent.systemWake(source: .service)

        let transcript = Transcript.make(name: "ordering") { builder in
            builder
                .event(event1)
                .event(event2)
                .event(event3)
        }

        #expect(transcript.steps.count == 3)
        guard case let .event(emitted1) = transcript.steps[0].kind,
              case let .event(emitted2) = transcript.steps[1].kind,
              case let .event(emitted3) = transcript.steps[2].kind
        else {
            Issue.record("expected three .event steps")
            return
        }
        #expect(emitted1 == event1)
        #expect(emitted2 == event2)
        #expect(emitted3 == event3)
    }

    @Test func eventStepDefaultsPerturbationToNone() {
        let transcript = Transcript.make(name: "default") { builder in
            builder.event(.activeSpaceChanged(source: .workspaceManager))
        }
        let step = transcript.steps[0]
        #expect(step.perturbation == .none)
    }

    @Test func transactionEffectsMatcherEqualityIsByKindAndMode() {
        let a = TranscriptTransactionEffectsMatcher(
            expectedKinds: ["activate_target_workspace"],
            mode: .containsInOrder
        )
        let b = TranscriptTransactionEffectsMatcher(
            expectedKinds: ["activate_target_workspace"],
            mode: .containsInOrder
        )
        let differentKinds = TranscriptTransactionEffectsMatcher(
            expectedKinds: ["sync_monitors_to_niri"],
            mode: .containsInOrder
        )
        let differentMode = TranscriptTransactionEffectsMatcher(
            expectedKinds: ["activate_target_workspace"],
            mode: .exactSequence
        )

        #expect(a == b)
        #expect(a != differentKinds)
        #expect(a != differentMode)
    }

    @Test func transactionEffectsMatcherMatchesEmptyMode() {
        let matcher = TranscriptTransactionEffectsMatcher.empty
        #expect(matcher.matches([]))
        #expect(!matcher.matches(["activate_target_workspace"]))
    }

    @Test func transactionEffectsMatcherMatchesContainsInOrder() {
        let matcher = TranscriptTransactionEffectsMatcher(
            expectedKinds: ["a", "c"],
            mode: .containsInOrder
        )
        #expect(matcher.matches(["a", "b", "c"]))
        #expect(matcher.matches(["a", "c", "d"]))
        #expect(!matcher.matches(["c", "a"]))
        #expect(!matcher.matches(["a"]))
    }

    @Test func transactionEffectsMatcherMatchesExactSequence() {
        let matcher = TranscriptTransactionEffectsMatcher(
            expectedKinds: ["a", "b"],
            mode: .exactSequence
        )
        #expect(matcher.matches(["a", "b"]))
        #expect(!matcher.matches(["a", "b", "c"]))
        #expect(!matcher.matches(["a"]))
    }

    @Test func transcriptIsEquatable() {
        let lhs = Transcript.make(name: "eq") { builder in
            builder
                .event(.activeSpaceChanged(source: .workspaceManager))
                .event(.systemSleep(source: .service))
        }
        let rhs = Transcript.make(name: "eq") { builder in
            builder
                .event(.activeSpaceChanged(source: .workspaceManager))
                .event(.systemSleep(source: .service))
        }
        #expect(lhs == rhs)
    }

    @Test func transcriptInequalityOnDifferentNames() {
        let lhs = Transcript.make(name: "a") { _ in }
        let rhs = Transcript.make(name: "b") { _ in }
        #expect(lhs != rhs)
    }

    @Test func dropPerturbationDefaultsTransactionEpochAdvanceFalse() {
        let dropped = TranscriptStep(
            kind: .event(.activeSpaceChanged(source: .workspaceManager)),
            perturbation: .drop
        )
        #expect(dropped.expectation.transactionEpochAdvances == false)

        let normal = TranscriptStep(
            kind: .event(.activeSpaceChanged(source: .workspaceManager)),
            perturbation: .none
        )
        #expect(normal.expectation.transactionEpochAdvances == true)
    }

    @Test func ipcRequestStepDefaultsTransactionEpochAdvanceFalse() {
        let request = IPCRequest(
            id: "req-1",
            kind: .ping,
            authorizationToken: nil
        )
        let transcript = Transcript.make(name: "ipc") { builder in
            builder.ipcRequest(request, expectation: TranscriptIPCStepExpectation(
                expectedStatus: nil,
                expectedErrorCode: .unauthorized,
                expectsZeroPlatformEvents: true
            ))
        }
        let step = transcript.steps[0]
        #expect(step.expectation.transactionEpochAdvances == false)
        #expect(step.expectation.ipcResponse?.expectedErrorCode == .unauthorized)
    }

    @Test func builderWithSecurityBoundaryRoundtrips() {
        let transcript = Transcript.make(name: "sb") { builder in
            builder.withSecurityBoundary(.strict)
        }
        #expect(transcript.securityBoundary == TranscriptSecurityBoundary.strict)
    }

    @Test func displayDeltaStepCarriesMonitorList() {
        let transcript = Transcript.make(name: "dd") { builder in
            builder.displayDelta(monitorsAfter: [.primary, .secondary])
        }
        guard case let .displayDelta(delta) = transcript.steps[0].kind else {
            Issue.record("expected displayDelta step")
            return
        }
        #expect(delta.monitorsAfter == [.primary, .secondary])
    }
}
