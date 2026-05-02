// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

@testable import OmniWM

@MainActor
enum MonitorRebindReconnectTranscript {
    static let primarySpec = TranscriptMonitorSpec(
        slot: .primary,
        name: "Main",
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    static let secondarySpec = TranscriptMonitorSpec(
        slot: .secondary(slot: 1),
        name: "Secondary",
        frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
    )

    static func make(
        in context: TranscriptRuntimeContext
    ) -> Transcript {
        var topologyAdvanceCheck = TranscriptStepExpectation()
        topologyAdvanceCheck.perStepInvariants = [.topologyEpochAdvancesOnRealDelta]

        return Transcript.make(name: "monitor-rebind-reconnect") { builder in
            builder
                .displayDelta(
                    monitorsAfter: [primarySpec],
                    expectation: topologyAdvanceCheck
                )
                .command(.workspaceSwitch(.explicit(rawWorkspaceID: "2")))
                .displayDelta(
                    monitorsAfter: [primarySpec, secondarySpec],
                    expectation: topologyAdvanceCheck
                )
                .expectFinal(TranscriptExpectations(
                    topologyEpochStrictlyAdvanced: true,
                    customAssertions: [.workspaceGraphValidates]
                ))
        }
    }
}
