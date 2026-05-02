// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OmniWMIPC

@testable import OmniWM

@MainActor
enum IPCSubscribeRaceTranscript {
    struct RaceObservation: Equatable {
        let initialEnvelopes: [IPCEventEnvelope]
        let liveEnvelopes: [IPCEventEnvelope]
    }

    static let fixedAuthorizationToken = TranscriptIPCDriver.fixedAuthorizationToken

    static func runRace(
        in context: TranscriptRuntimeContext,
        channel: IPCSubscriptionChannel = .activeWorkspace
    ) async -> RaceObservation {
        let bridge = IPCApplicationBridge(
            controller: context.runtime.controller,
            sessionToken: "transcript-session",
            authorizationToken: fixedAuthorizationToken
        )

        let subscribePayload = IPCSubscribeRequest(
            channels: [channel],
            allChannels: false,
            sendInitial: true
        )
        _ = IPCRequest(
            id: "subscribe-1",
            subscribe: subscribePayload,
            authorizationToken: fixedAuthorizationToken
        )

        let registration = await bridge.registerStream(for: channel)

        let initialEnvelopes = await bridge.initialEvents(for: subscribePayload)

        _ = context.runtime.submit(command: .workspaceSwitch(.explicit(rawWorkspaceID: "2")))
        await bridge.publishEventForTests(channel)

        var liveEnvelopes: [IPCEventEnvelope] = []
        let collector = Task<[IPCEventEnvelope], Never> {
            var collected: [IPCEventEnvelope] = []
            for await event in registration.stream {
                collected.append(event)
                if collected.count == 1 { break }
            }
            return collected
        }
        liveEnvelopes = await collector.value
        await bridge.unregisterStream(registration)

        return RaceObservation(
            initialEnvelopes: initialEnvelopes,
            liveEnvelopes: liveEnvelopes
        )
    }
}
