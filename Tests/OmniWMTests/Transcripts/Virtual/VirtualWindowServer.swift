// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

@testable import OmniWM

@MainActor
final class VirtualWindowServer {
    typealias VirtualApp = VirtualAppRoster.VirtualApp

    let displayBoard: VirtualDisplayBoard
    let appRoster: VirtualAppRoster
    let windowLedger: VirtualWindowLedger

    var simulateAXAdmissionDelay: Bool = false

    var simulateAXFrameWriteFailure: Bool = false

    private var deferredAdmissionEvents: [WMEvent] = []

    init(
        initialMonitors: [TranscriptMonitorSpec] = [.primary]
    ) {
        self.displayBoard = VirtualDisplayBoard(initialSpecs: initialMonitors)
        self.appRoster = VirtualAppRoster()
        self.windowLedger = VirtualWindowLedger()
    }


    @discardableResult
    func registerApp(
        bundleIdentifier: String? = nil,
        displayName: String = "VirtualApp"
    ) -> VirtualApp {
        appRoster.registerApp(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
    }

    func terminateApp(_ app: VirtualApp) -> [WMEvent] {
        let tokens = windowLedger.tokens(forPid: app.pid)
        let events: [WMEvent] = tokens.compactMap { token in
            guard let entry = windowLedger.entry(for: token) else { return nil }
            windowLedger.remove(token)
            return WMEvent.windowRemoved(
                token: token,
                workspaceId: entry.workspaceId,
                source: .ax
            )
        }
        appRoster.unregister(app)
        return events
    }


    @discardableResult
    func createWindow(
        app: VirtualApp,
        workspace: WorkspaceDescriptor.ID,
        monitor monitorId: Monitor.ID? = nil,
        mode: TrackedWindowMode = .tiling
    ) -> CreateWindowOutcome {
        let token = windowLedger.allocateToken(pid: app.pid)
        windowLedger.register(
            token: token,
            pid: app.pid,
            workspaceId: workspace,
            monitorId: monitorId,
            mode: mode,
            bundleId: app.bundleIdentifier
        )
        let admissionEvent = WMEvent.windowAdmitted(
            token: token,
            workspaceId: workspace,
            monitorId: monitorId,
            mode: mode,
            source: .ax
        )

        if simulateAXAdmissionDelay {
            deferredAdmissionEvents.append(admissionEvent)
            return CreateWindowOutcome(token: token, events: [])
        }
        return CreateWindowOutcome(token: token, events: [admissionEvent])
    }

    struct CreateWindowOutcome {
        let token: WindowToken
        let events: [WMEvent]
    }

    func flushDeferredAdmissions() -> [WMEvent] {
        defer { deferredAdmissionEvents.removeAll(keepingCapacity: false) }
        return deferredAdmissionEvents
    }

    func destroyWindow(_ token: WindowToken) -> [WMEvent] {
        guard let entry = windowLedger.entry(for: token) else { return [] }
        windowLedger.remove(token)
        return [
            WMEvent.windowRemoved(
                token: token,
                workspaceId: entry.workspaceId,
                source: .ax
            )
        ]
    }

    func focusWindow(_ token: WindowToken) -> [WMEvent] {
        guard let entry = windowLedger.entry(for: token) else { return [] }
        return [
            WMEvent.managedFocusRequested(
                token: token,
                workspaceId: entry.workspaceId,
                monitorId: entry.monitorId,
                source: .focusPolicy
            )
        ]
    }

    func confirmFocus(
        _ token: WindowToken,
        appFullscreen: Bool = false,
        originatingTransactionEpoch: TransactionEpoch
    ) -> [WMEvent] {
        guard let entry = windowLedger.entry(for: token) else { return [] }
        return [
            WMEvent.managedFocusConfirmed(
                token: token,
                workspaceId: entry.workspaceId,
                monitorId: entry.monitorId,
                appFullscreen: appFullscreen,
                source: .ax,
                originatingTransactionEpoch: originatingTransactionEpoch
            )
        ]
    }

    func moveWindow(_ token: WindowToken, frame: CGRect) -> [WMEvent] {
        guard let entry = windowLedger.entry(for: token) else { return [] }
        return [
            WMEvent.floatingGeometryUpdated(
                token: token,
                workspaceId: entry.workspaceId,
                referenceMonitorId: entry.monitorId,
                frame: frame,
                restoreToFloating: entry.mode == .floating,
                source: .ax
            )
        ]
    }

    func confirmFrameWrite(
        _ token: WindowToken,
        originatingTransactionEpoch: TransactionEpoch
    ) -> WMEffectConfirmation {
        let axFailure: AXFrameWriteFailureReason? =
            simulateAXFrameWriteFailure ? .verificationMismatch : nil
        return WMEffectConfirmation.axFrameWriteOutcome(
            token: token,
            axFailure: axFailure,
            source: .ax,
            originatingTransactionEpoch: originatingTransactionEpoch
        )
    }

    func enterNativeFullscreen(
        _ token: WindowToken,
        replacementToken: WindowToken? = nil
    ) -> [WMEvent] {
        guard let entry = windowLedger.entry(for: token) else { return [] }
        var events: [WMEvent] = []
        if let replacement = replacementToken {
            windowLedger.rekey(from: token, to: replacement)
            windowLedger.update(replacement) { $0.isNativeFullscreen = true }
            events.append(.windowRekeyed(
                from: token,
                to: replacement,
                workspaceId: entry.workspaceId,
                monitorId: entry.monitorId,
                reason: .nativeFullscreen,
                source: .ax
            ))
            events.append(.nativeFullscreenTransition(
                token: replacement,
                workspaceId: entry.workspaceId,
                monitorId: entry.monitorId,
                isActive: true,
                source: .ax
            ))
        } else {
            windowLedger.update(token) { $0.isNativeFullscreen = true }
            events.append(.nativeFullscreenTransition(
                token: token,
                workspaceId: entry.workspaceId,
                monitorId: entry.monitorId,
                isActive: true,
                source: .ax
            ))
        }
        return events
    }

    func exitNativeFullscreen(_ token: WindowToken) -> [WMEvent] {
        guard let entry = windowLedger.entry(for: token) else { return [] }
        windowLedger.update(token) { $0.isNativeFullscreen = false }
        return [
            WMEvent.nativeFullscreenTransition(
                token: token,
                workspaceId: entry.workspaceId,
                monitorId: entry.monitorId,
                isActive: false,
                source: .ax
            )
        ]
    }

    func emitStaleCgsDestroy(for token: WindowToken, workspaceId: WorkspaceDescriptor.ID) -> [WMEvent] {
        [
            WMEvent.windowRemoved(
                token: token,
                workspaceId: workspaceId,
                source: .ax
            )
        ]
    }

    func hideWindow(_ token: WindowToken, hiddenState: WindowModel.HiddenState? = nil) -> [WMEvent] {
        guard let entry = windowLedger.entry(for: token) else { return [] }
        windowLedger.update(token) { $0.isHidden = true }
        return [
            WMEvent.hiddenStateChanged(
                token: token,
                workspaceId: entry.workspaceId,
                monitorId: entry.monitorId,
                hiddenState: hiddenState,
                source: .workspaceManager
            )
        ]
    }

    func unhideWindow(_ token: WindowToken) -> [WMEvent] {
        guard let entry = windowLedger.entry(for: token) else { return [] }
        windowLedger.update(token) { $0.isHidden = false }
        return [
            WMEvent.hiddenStateChanged(
                token: token,
                workspaceId: entry.workspaceId,
                monitorId: entry.monitorId,
                hiddenState: nil,
                source: .workspaceManager
            )
        ]
    }


    @discardableResult
    func setMonitors(_ specs: [TranscriptMonitorSpec]) -> VirtualDisplayBoard.DisplayDelta {
        displayBoard.setMonitors(specs)
    }

    @discardableResult
    func appendMonitor(_ spec: TranscriptMonitorSpec) -> VirtualDisplayBoard.DisplayDelta {
        displayBoard.appendMonitor(spec)
    }

    @discardableResult
    func removeMonitor(matching predicate: (TranscriptMonitorSpec) -> Bool) -> VirtualDisplayBoard.DisplayDelta {
        displayBoard.removeMonitor(matching: predicate)
    }
}
