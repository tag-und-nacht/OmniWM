// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OmniWMIPC

@testable import OmniWM

@MainActor
struct IPCAuthorizationBoundaryHarness {
    let runtime: WMRuntime
    let platform: RecordingEffectPlatform
    let authorizationToken: String

    init(
        runtime: WMRuntime,
        platform: RecordingEffectPlatform,
        authorizationToken: String = TranscriptIPCDriver.fixedAuthorizationToken
    ) {
        self.runtime = runtime
        self.platform = platform
        self.authorizationToken = authorizationToken
    }

    private func makeBridge() -> IPCApplicationBridge {
        IPCApplicationBridge(
            controller: runtime.controller,
            sessionToken: "transcript-session",
            authorizationToken: authorizationToken
        )
    }

    func driveAndExpectRejection(
        _ request: IPCRequest,
        expectedCode: IPCErrorCode
    ) async -> IPCResponse {
        let bridge = makeBridge()
        let watermarkBefore = runtime.currentEffectRunnerWatermark
        let platformEventsBefore = platform.events.count

        let response = await bridge.response(for: request)

        precondition(
            !response.ok,
            "expected rejection, got ok=true response \(response)"
        )
        precondition(
            response.code == expectedCode,
            "expected error code \(expectedCode.rawValue), got \(response.code?.rawValue ?? "nil")"
        )
        precondition(
            platform.events.count == platformEventsBefore,
            "platform events advanced by \(platform.events.count - platformEventsBefore) on rejected request \(request.id)"
        )
        precondition(
            runtime.currentEffectRunnerWatermark == watermarkBefore,
            "effect runner watermark advanced from \(watermarkBefore) to \(runtime.currentEffectRunnerWatermark) on rejected request"
        )
        return response
    }

    static func craftMissingAuthorizationToken() -> IPCRequest {
        IPCRequest(
            id: "auth-missing",
            kind: .ping,
            authorizationToken: nil
        )
    }

    static func craftWrongAuthorizationToken() -> IPCRequest {
        IPCRequest(
            id: "auth-wrong",
            kind: .ping,
            authorizationToken: "definitely-not-the-real-token"
        )
    }

    static func craftProtocolMismatch(token: String) -> IPCRequest {
        IPCRequest(
            version: OmniWMIPCProtocol.version &+ 100,
            id: "proto-mismatch",
            kind: .command,
            authorizationToken: token,
            payload: .none(IPCNoPayload())
        )
    }

    static func craftMalformedCommandPayload(token: String) -> IPCRequest {
        IPCRequest(
            version: OmniWMIPCProtocol.version,
            id: "malformed",
            kind: .command,
            authorizationToken: token,
            payload: .none(IPCNoPayload())
        )
    }

    static func craftMissingTokenSubscribe() -> IPCRequest {
        IPCRequest(
            id: "subscribe-missing-token",
            subscribe: IPCSubscribeRequest(channels: [], allChannels: true),
            authorizationToken: nil
        )
    }

    static func craftWrongTokenSubscribe() -> IPCRequest {
        IPCRequest(
            id: "subscribe-wrong-token",
            subscribe: IPCSubscribeRequest(channels: [], allChannels: true),
            authorizationToken: "definitely-not-the-real-token"
        )
    }

    static func driveOversizedLineAndExpectOverflow(
        capBytes: Int = IPCConnection.maxRequestLineBytes
    ) -> ZigIPCSupport.LineScanResult {
        let buffer = Data(repeating: 0x41, count: capBytes + 1)
        return ZigIPCSupport.scanLine(in: buffer, maxLineBytes: capBytes)
    }
}
