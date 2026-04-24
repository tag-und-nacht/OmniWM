// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@testable import OmniWM

@MainActor
enum NiriFocusedRemovalTranscript {
    static func make(
        in context: TranscriptRuntimeContext,
        pid: pid_t = 30_010
    ) -> Transcript {
        let workspaceId = context.workspaceId(named: "1")
        let monitorId = context.primaryMonitorId
        let t1 = WindowToken(pid: pid, windowId: 11)
        let t2 = WindowToken(pid: pid, windowId: 12)
        let t3 = WindowToken(pid: pid, windowId: 13)

        var validatesGraph = TranscriptStepExpectation()
        validatesGraph.perStepInvariants = [.workspaceGraphValidates]

        var staleDestroyGuard = TranscriptStepExpectation()
        staleDestroyGuard.perStepInvariants = [
            .workspaceGraphValidates,
            .retiredOrQuarantinedCannotReceiveLayoutEffect
        ]

        return Transcript.make(name: "niri-focused-removal") { builder in
            builder
                .event(
                    .windowAdmitted(
                        token: t1,
                        workspaceId: workspaceId,
                        monitorId: monitorId,
                        mode: .tiling,
                        source: .ax
                    ),
                    expectation: validatesGraph
                )
                .event(
                    .windowAdmitted(
                        token: t2,
                        workspaceId: workspaceId,
                        monitorId: monitorId,
                        mode: .tiling,
                        source: .ax
                    ),
                    expectation: validatesGraph
                )
                .event(
                    .windowAdmitted(
                        token: t3,
                        workspaceId: workspaceId,
                        monitorId: monitorId,
                        mode: .tiling,
                        source: .ax
                    ),
                    expectation: validatesGraph
                )
                .event(
                    .windowRemoved(
                        token: t2,
                        workspaceId: workspaceId,
                        source: .ax
                    ),
                    expectation: staleDestroyGuard
                )
                .expectFinal(TranscriptExpectations(
                    customAssertions: [.workspaceGraphValidates]
                ))
        }
    }
}
