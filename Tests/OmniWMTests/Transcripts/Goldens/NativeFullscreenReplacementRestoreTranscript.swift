// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

@testable import OmniWM

@MainActor
enum NativeFullscreenReplacementRestoreTranscript {
    static func make(
        in context: TranscriptRuntimeContext,
        pid: pid_t = 30_000
    ) -> Transcript {
        let workspaceId = context.workspaceId(named: "1")
        let monitorId = context.primaryMonitorId
        let originalToken = WindowToken(pid: pid, windowId: 1)
        let replacementToken = WindowToken(pid: pid, windowId: 2)
        let controlToken = WindowToken(pid: pid, windowId: 3)

        var staleDestroyExpectation = TranscriptStepExpectation()
        staleDestroyExpectation.perStepInvariants = [
            .retiredOrQuarantinedCannotReceiveFocusEffect,
            .workspaceGraphValidates
        ]

        var workspaceGraphAssertion = TranscriptStepExpectation()
        workspaceGraphAssertion.perStepInvariants = [.workspaceGraphValidates]

        return Transcript.make(name: "native-fullscreen-replacement-restore") { builder in
            builder
                .event(.windowAdmitted(
                    token: originalToken,
                    workspaceId: workspaceId,
                    monitorId: monitorId,
                    mode: .tiling,
                    source: .ax
                ))
                .event(.nativeFullscreenTransition(
                    token: originalToken,
                    workspaceId: workspaceId,
                    monitorId: monitorId,
                    isActive: true,
                    source: .ax
                ))
                .event(.windowRekeyed(
                    from: originalToken,
                    to: replacementToken,
                    workspaceId: workspaceId,
                    monitorId: monitorId,
                    reason: .nativeFullscreen,
                    source: .ax
                ))
                .event(
                    .windowRemoved(
                        token: originalToken,
                        workspaceId: workspaceId,
                        source: .ax
                    ),
                    expectation: staleDestroyExpectation
                )
                .event(.nativeFullscreenTransition(
                    token: replacementToken,
                    workspaceId: workspaceId,
                    monitorId: monitorId,
                    isActive: false,
                    source: .ax
                ))
                .event(
                    .windowAdmitted(
                        token: controlToken,
                        workspaceId: workspaceId,
                        monitorId: monitorId,
                        mode: .tiling,
                        source: .ax
                    ),
                    expectation: workspaceGraphAssertion
                )
                .expectFinal(TranscriptExpectations(
                    customAssertions: [.workspaceGraphValidates]
                ))
        }
    }
}
