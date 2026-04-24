// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

@testable import OmniWM

@MainActor
enum FloatingChildStackingTranscript {
    static func make(
        in context: TranscriptRuntimeContext,
        pid: pid_t = 30_030
    ) -> Transcript {
        let workspaceId = context.workspaceId(named: "1")
        let monitorId = context.primaryMonitorId
        let parent = WindowToken(pid: pid, windowId: 31)
        let childA = WindowToken(pid: pid, windowId: 32)
        let childB = WindowToken(pid: pid, windowId: 33)

        var graphValidates = TranscriptStepExpectation()
        graphValidates.perStepInvariants = [.workspaceGraphValidates]

        let floatingFrameA = CGRect(x: 100, y: 100, width: 400, height: 300)
        let floatingFrameB = CGRect(x: 200, y: 200, width: 500, height: 350)

        return Transcript.make(name: "floating-child-stacking") { builder in
            builder
                .event(.windowAdmitted(
                    token: parent,
                    workspaceId: workspaceId,
                    monitorId: monitorId,
                    mode: .tiling,
                    source: .ax
                ))
                .event(
                    .windowAdmitted(
                        token: childA,
                        workspaceId: workspaceId,
                        monitorId: monitorId,
                        mode: .floating,
                        source: .ax
                    ),
                    expectation: graphValidates
                )
                .event(.floatingGeometryUpdated(
                    token: childA,
                    workspaceId: workspaceId,
                    referenceMonitorId: monitorId,
                    frame: floatingFrameA,
                    restoreToFloating: true,
                    source: .ax
                ))
                .event(
                    .windowAdmitted(
                        token: childB,
                        workspaceId: workspaceId,
                        monitorId: monitorId,
                        mode: .floating,
                        source: .ax
                    ),
                    expectation: graphValidates
                )
                .event(.floatingGeometryUpdated(
                    token: childB,
                    workspaceId: workspaceId,
                    referenceMonitorId: monitorId,
                    frame: floatingFrameB,
                    restoreToFloating: true,
                    source: .ax
                ))
                .expectFinal(TranscriptExpectations(
                    customAssertions: [.workspaceGraphValidates]
                ))
        }
    }
}
