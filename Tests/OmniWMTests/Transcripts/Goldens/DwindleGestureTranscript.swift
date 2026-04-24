// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@testable import OmniWM

@MainActor
enum DwindleGestureTranscript {
    static func make(
        in context: TranscriptRuntimeContext,
        pid: pid_t = 30_040
    ) -> Transcript {
        let workspaceId = context.workspaceId(named: "1")
        let monitorId = context.primaryMonitorId
        let t1 = WindowToken(pid: pid, windowId: 41)
        let t2 = WindowToken(pid: pid, windowId: 42)
        let t3 = WindowToken(pid: pid, windowId: 43)

        var validatesGraph = TranscriptStepExpectation()
        validatesGraph.perStepInvariants = [.workspaceGraphValidates]

        return Transcript.make(name: "dwindle-gesture") { builder in
            builder
                .event(.windowAdmitted(
                    token: t1,
                    workspaceId: workspaceId,
                    monitorId: monitorId,
                    mode: .tiling,
                    source: .ax
                ))
                .event(.windowAdmitted(
                    token: t2,
                    workspaceId: workspaceId,
                    monitorId: monitorId,
                    mode: .tiling,
                    source: .ax
                ))
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
                .expectFinal(TranscriptExpectations(
                    customAssertions: [.workspaceGraphValidates]
                ))
        }
    }
}
