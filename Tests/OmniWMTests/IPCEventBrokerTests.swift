// SPDX-License-Identifier: GPL-2.0-only
import Testing

import OmniWMIPC
@testable import OmniWM

@Suite struct IPCEventBrokerTests {
    @Test func slowSubscribersKeepBufferedEventsWithinBurstLimit() async throws {
        let broker = IPCEventBroker()
        let stream = await broker.stream(for: .focus)

        for index in 1...IPCEventBroker.streamBufferEventCountLimit {
            await broker.publish(
                IPCEventEnvelope.success(
                    id: "evt-\(index)",
                    channel: .focus,
                    result: IPCResult(
                        focusedWindow: IPCFocusedWindowQueryResult(
                            window: IPCFocusedWindowSnapshot(
                                id: "ow_\(index)",
                                workspace: IPCWorkspaceRef(id: "ws-1", rawName: "1", displayName: "One", number: 1),
                                display: IPCDisplayRef(id: "display:1", name: "Main", isMain: true),
                                app: IPCAppRef(name: "App \(index)", bundleId: "com.example.app\(index)"),
                                title: "Window \(index)",
                                frame: nil
                            )
                        )
                    )
                )
            )
        }

        var iterator = stream.makeAsyncIterator()
        for index in 1...IPCEventBroker.streamBufferEventCountLimit {
            let event = try #require(await iterator.next())

            #expect(event.id == "evt-\(index)")
            if case let .focusedWindow(payload) = event.result.payload {
                #expect(payload.window?.id == "ow_\(index)")
                #expect(payload.window?.title == "Window \(index)")
            } else {
                Issue.record("Expected focused-window payload")
            }
        }
    }
}
