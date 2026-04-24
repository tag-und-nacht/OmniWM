// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OmniWMIPC

@testable import OmniWM

@MainActor
enum IPCAuthorizationBoundaryTranscript {
    struct ExpectedRejection: Equatable {
        let label: String
        let expectedCode: IPCErrorCode
    }

    static let categories: [ExpectedRejection] = [
        ExpectedRejection(label: "missing-authorization-token", expectedCode: .unauthorized),
        ExpectedRejection(label: "wrong-authorization-token", expectedCode: .unauthorized),
        ExpectedRejection(label: "protocol-mismatch", expectedCode: .protocolMismatch),
        ExpectedRejection(label: "malformed-command-payload", expectedCode: .invalidRequest),
        ExpectedRejection(label: "unauthorized-subscribe", expectedCode: .unauthorized)
    ]

    static let requestSizeCapBytes = IPCConnection.maxRequestLineBytes
    static let expectedRequestSizeCapBytes = 64 * 1024
}
