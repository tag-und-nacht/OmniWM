// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@Suite(.serialized) struct AXEventHandlerActivationRetryRegressionTests {
    private static var axEventHandlerSourceURL: URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Sources/OmniWM/Core/Controller/AXEventHandler.swift")
    }

    private static func axEventHandlerSource() throws -> String {
        try String(contentsOf: axEventHandlerSourceURL, encoding: .utf8)
    }

    @Test func axEventHandlerHasNoActivationRetryTask() throws {
        let source = try Self.axEventHandlerSource()
        #expect(!source.contains("pendingActivationRetryTask"))
        #expect(!source.contains("pendingActivationRetryRequestId"))
        #expect(!source.contains("scheduleActivationRetry"))
        #expect(!source.contains("resetActivationRetryState"))
        #expect(!source.contains("private func continueManagedFocusRequest"))
    }

    @Test func axEventHandlerDoesNotReEnterHandleAppActivationFromSleepLoop() throws {
        let source = try Self.axEventHandlerSource()
        let lines = source.split(separator: "\n").map(String.init)
        for (index, line) in lines.enumerated() {
            guard line.contains("Task.sleep(for: Self.stabilizationRetryDelay)") else {
                continue
            }
            let lookaheadEnd = min(index + 12, lines.count)
            let window = lines[index..<lookaheadEnd].joined(separator: "\n")
            #expect(
                !window.contains("self.handleAppActivation"),
                "stabilization sleep at line \(index + 1) re-enters handleAppActivation; the FOC-06-deleted retry loop must not return"
            )
        }
    }
}
