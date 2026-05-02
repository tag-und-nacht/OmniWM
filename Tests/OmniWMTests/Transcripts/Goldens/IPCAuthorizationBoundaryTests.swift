// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OmniWMIPC
import Testing

@testable import OmniWM

@Suite(.serialized) struct IPCAuthorizationBoundaryTests {
    @Test @MainActor func categoriesAreStable() async throws {
        let categories = IPCAuthorizationBoundaryTranscript.categories
        #expect(categories.map(\.label) == [
            "missing-authorization-token",
            "wrong-authorization-token",
            "protocol-mismatch",
            "malformed-command-payload",
            "unauthorized-subscribe"
        ])
    }

    @Test @MainActor func requestSizeCapIsPinnedAt64KiB() async throws {
        #expect(
            IPCAuthorizationBoundaryTranscript.requestSizeCapBytes
                == IPCAuthorizationBoundaryTranscript.expectedRequestSizeCapBytes
        )
    }

    @Test @MainActor func oversizedRequestLineRejectedByScanLineSeam() async throws {
        let result = IPCAuthorizationBoundaryHarness
            .driveOversizedLineAndExpectOverflow()
        #expect(result == .overflow)
    }

    @Test @MainActor func atCapBufferWithoutNewlineDoesNotOverflow() async throws {
        let cap = IPCAuthorizationBoundaryTranscript.requestSizeCapBytes
        let buffer = Data(repeating: 0x41, count: cap)
        let result = ZigIPCSupport.scanLine(in: buffer, maxLineBytes: cap)
        #expect(result == .noNewline)
    }

    @Test @MainActor func missingTokenRejectsWithUnauthorizedAndZeroEvents() async throws {
        let context = makeTranscriptRuntimeContext()
        let harness = IPCAuthorizationBoundaryHarness(
            runtime: context.runtime,
            platform: context.platform
        )

        _ = await harness.driveAndExpectRejection(
            IPCAuthorizationBoundaryHarness.craftMissingAuthorizationToken(),
            expectedCode: .unauthorized
        )
    }

    @Test @MainActor func wrongTokenRejectsWithUnauthorizedAndZeroEvents() async throws {
        let context = makeTranscriptRuntimeContext()
        let harness = IPCAuthorizationBoundaryHarness(
            runtime: context.runtime,
            platform: context.platform
        )

        _ = await harness.driveAndExpectRejection(
            IPCAuthorizationBoundaryHarness.craftWrongAuthorizationToken(),
            expectedCode: .unauthorized
        )
    }

    @Test @MainActor func protocolMismatchRejectsAndZeroEvents() async throws {
        let context = makeTranscriptRuntimeContext()
        let harness = IPCAuthorizationBoundaryHarness(
            runtime: context.runtime,
            platform: context.platform
        )

        _ = await harness.driveAndExpectRejection(
            IPCAuthorizationBoundaryHarness.craftProtocolMismatch(
                token: TranscriptIPCDriver.fixedAuthorizationToken
            ),
            expectedCode: .protocolMismatch
        )
    }

    @Test @MainActor func malformedCommandRejectsAndZeroEvents() async throws {
        let context = makeTranscriptRuntimeContext()
        let harness = IPCAuthorizationBoundaryHarness(
            runtime: context.runtime,
            platform: context.platform
        )

        _ = await harness.driveAndExpectRejection(
            IPCAuthorizationBoundaryHarness.craftMalformedCommandPayload(
                token: TranscriptIPCDriver.fixedAuthorizationToken
            ),
            expectedCode: .invalidRequest
        )
    }

    @Test @MainActor func authorizedPingPassesAsControlCase() async throws {
        let context = makeTranscriptRuntimeContext()
        let bridge = IPCApplicationBridge(
            controller: context.runtime.controller,
            sessionToken: "transcript-session",
            authorizationToken: TranscriptIPCDriver.fixedAuthorizationToken
        )
        let request = IPCRequest(
            id: "ping-control",
            kind: .ping,
            authorizationToken: TranscriptIPCDriver.fixedAuthorizationToken
        )
        let response = await bridge.response(for: request)
        #expect(response.ok)
    }

    @Test @MainActor func subscribeWithMissingTokenRejectsAndZeroEvents() async throws {
        let context = makeTranscriptRuntimeContext()
        let harness = IPCAuthorizationBoundaryHarness(
            runtime: context.runtime,
            platform: context.platform
        )

        _ = await harness.driveAndExpectRejection(
            IPCAuthorizationBoundaryHarness.craftMissingTokenSubscribe(),
            expectedCode: .unauthorized
        )
    }

    @Test @MainActor func subscribeWithWrongTokenRejectsAndZeroEvents() async throws {
        let context = makeTranscriptRuntimeContext()
        let harness = IPCAuthorizationBoundaryHarness(
            runtime: context.runtime,
            platform: context.platform
        )

        _ = await harness.driveAndExpectRejection(
            IPCAuthorizationBoundaryHarness.craftWrongTokenSubscribe(),
            expectedCode: .unauthorized
        )
    }
}
