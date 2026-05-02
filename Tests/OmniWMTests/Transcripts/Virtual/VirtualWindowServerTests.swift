// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct VirtualWindowServerTests {
    @MainActor private func makeServer() -> VirtualWindowServer {
        VirtualWindowServer(initialMonitors: [.primary])
    }

    @Test @MainActor func createWindowEmitsAdmittedEvent() {
        let server = makeServer()
        let app = server.registerApp()
        let workspaceId = WorkspaceDescriptor.ID()

        let outcome = server.createWindow(app: app, workspace: workspaceId)

        #expect(outcome.events.count == 1)
        if case let .windowAdmitted(token, ws, _, mode, source) = outcome.events[0] {
            #expect(token == outcome.token)
            #expect(ws == workspaceId)
            #expect(mode == .tiling)
            #expect(source == .ax)
        } else {
            Issue.record("expected windowAdmitted, got \(outcome.events[0])")
        }
    }

    @Test @MainActor func destroyWindowEmitsRemovedEvent() {
        let server = makeServer()
        let app = server.registerApp()
        let workspaceId = WorkspaceDescriptor.ID()
        let outcome = server.createWindow(app: app, workspace: workspaceId)

        let events = server.destroyWindow(outcome.token)

        #expect(events.count == 1)
        if case let .windowRemoved(token, ws, source) = events[0] {
            #expect(token == outcome.token)
            #expect(ws == workspaceId)
            #expect(source == .ax)
        } else {
            Issue.record("expected windowRemoved, got \(events[0])")
        }
    }

    @Test @MainActor func enterNativeFullscreenWithReplacementEmitsRekeyAndTransition() {
        let server = makeServer()
        let app = server.registerApp()
        let workspaceId = WorkspaceDescriptor.ID()
        let outcome = server.createWindow(app: app, workspace: workspaceId)
        let replacementToken = WindowToken(pid: app.pid, windowId: 9_999)

        let events = server.enterNativeFullscreen(outcome.token, replacementToken: replacementToken)

        #expect(events.count == 2)
        if case let .windowRekeyed(from, to, _, _, reason, _) = events[0] {
            #expect(from == outcome.token)
            #expect(to == replacementToken)
            #expect(reason == .nativeFullscreen)
        } else {
            Issue.record("expected first event to be windowRekeyed, got \(events[0])")
        }
        if case let .nativeFullscreenTransition(token, _, _, isActive, _) = events[1] {
            #expect(token == replacementToken)
            #expect(isActive == true)
        } else {
            Issue.record("expected second event to be nativeFullscreenTransition, got \(events[1])")
        }
    }

    @Test @MainActor func exitNativeFullscreenEmitsTransitionInactive() {
        let server = makeServer()
        let app = server.registerApp()
        let workspaceId = WorkspaceDescriptor.ID()
        let outcome = server.createWindow(app: app, workspace: workspaceId)
        _ = server.enterNativeFullscreen(outcome.token)

        let events = server.exitNativeFullscreen(outcome.token)

        #expect(events.count == 1)
        if case let .nativeFullscreenTransition(_, _, _, isActive, _) = events[0] {
            #expect(isActive == false)
        } else {
            Issue.record("expected nativeFullscreenTransition isActive=false, got \(events[0])")
        }
    }

    @Test @MainActor func appendMonitorEmitsTopologyDelta() {
        let server = VirtualWindowServer(initialMonitors: [.primary])
        let secondary = TranscriptMonitorSpec(
            slot: .secondary(slot: 1),
            name: "Secondary",
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        )

        let delta = server.appendMonitor(secondary)

        #expect(delta.monitorsAfter.count == 2)
        if case let .topologyChanged(displays, source) = delta.topologyEvent {
            #expect(displays.count == 2)
            #expect(source == .service)
        } else {
            Issue.record("expected topologyChanged, got \(delta.topologyEvent)")
        }
    }

    @Test @MainActor func removeMonitorEmitsTopologyDeltaWithoutDisplay() {
        let secondary = TranscriptMonitorSpec(
            slot: .secondary(slot: 1),
            name: "Secondary",
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        )
        let server = VirtualWindowServer(initialMonitors: [.primary, secondary])

        let delta = server.removeMonitor { spec in spec.name == "Secondary" }

        #expect(delta.monitorsAfter.count == 1)
        if case let .topologyChanged(displays, _) = delta.topologyEvent {
            #expect(displays.count == 1)
        } else {
            Issue.record("expected topologyChanged, got \(delta.topologyEvent)")
        }
    }

    @Test @MainActor func simulateAXAdmissionDelayDefersAdmission() {
        let server = makeServer()
        server.simulateAXAdmissionDelay = true
        let app = server.registerApp()
        let workspaceId = WorkspaceDescriptor.ID()

        let outcome = server.createWindow(app: app, workspace: workspaceId)
        #expect(outcome.events.isEmpty)

        let drained = server.flushDeferredAdmissions()
        #expect(drained.count == 1)
        if case let .windowAdmitted(token, _, _, _, _) = drained[0] {
            #expect(token == outcome.token)
        } else {
            Issue.record("expected windowAdmitted in drained, got \(drained[0])")
        }
    }

    @Test @MainActor func terminateAppEmitsRemovedEventForEveryWindow() {
        let server = makeServer()
        let app = server.registerApp()
        let workspaceId = WorkspaceDescriptor.ID()
        let outcomeA = server.createWindow(app: app, workspace: workspaceId)
        let outcomeB = server.createWindow(app: app, workspace: workspaceId)

        let events = server.terminateApp(app)

        #expect(events.count == 2)
        let removedTokens: Set<WindowToken> = Set(events.compactMap { event in
            if case let .windowRemoved(token, _, _) = event { return token } else { return nil }
        })
        #expect(removedTokens == [outcomeA.token, outcomeB.token])
    }

    @Test @MainActor func ledgerAllocatesUniqueTokensForOneApp() {
        let server = makeServer()
        let app = server.registerApp()
        let workspaceId = WorkspaceDescriptor.ID()

        var tokens: Set<WindowToken> = []
        for _ in 0..<20 {
            let outcome = server.createWindow(app: app, workspace: workspaceId)
            tokens.insert(outcome.token)
        }
        #expect(tokens.count == 20)
    }

    @Test @MainActor func emitStaleCgsDestroyForReplacementToken() {
        let server = makeServer()
        let workspaceId = WorkspaceDescriptor.ID()
        let stray = WindowToken(pid: 1234, windowId: 5678)

        let events = server.emitStaleCgsDestroy(for: stray, workspaceId: workspaceId)

        #expect(events.count == 1)
        if case let .windowRemoved(token, ws, _) = events[0] {
            #expect(token == stray)
            #expect(ws == workspaceId)
        } else {
            Issue.record("expected windowRemoved for stray, got \(events[0])")
        }
    }

    @Test @MainActor func confirmFrameWriteDefaultsToSuccessOutcome() {
        let server = makeServer()
        let app = server.registerApp()
        let workspaceId = WorkspaceDescriptor.ID()
        let outcome = server.createWindow(app: app, workspace: workspaceId)

        let confirmation = server.confirmFrameWrite(
            outcome.token,
            originatingTransactionEpoch: TransactionEpoch(value: 1)
        )

        if case let .axFrameWriteOutcome(token, axFailure, source, epoch) = confirmation {
            #expect(token == outcome.token)
            #expect(axFailure == nil)
            #expect(source == .ax)
            #expect(epoch.value == 1)
        } else {
            Issue.record("expected axFrameWriteOutcome, got \(confirmation)")
        }
    }

    @Test @MainActor func confirmFrameWriteEmitsFailureWhenFlagSet() {
        let server = makeServer()
        server.simulateAXFrameWriteFailure = true
        let app = server.registerApp()
        let workspaceId = WorkspaceDescriptor.ID()
        let outcome = server.createWindow(app: app, workspace: workspaceId)

        let confirmation = server.confirmFrameWrite(
            outcome.token,
            originatingTransactionEpoch: TransactionEpoch(value: 7)
        )

        if case let .axFrameWriteOutcome(token, axFailure, source, epoch) = confirmation {
            #expect(token == outcome.token)
            #expect(axFailure == .verificationMismatch)
            #expect(source == .ax)
            #expect(epoch.value == 7)
        } else {
            Issue.record("expected axFrameWriteOutcome, got \(confirmation)")
        }
    }
}
