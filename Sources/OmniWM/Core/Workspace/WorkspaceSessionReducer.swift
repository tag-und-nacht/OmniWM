// SPDX-License-Identifier: GPL-2.0-only
import Foundation

enum WorkspaceSessionReducer {
    enum Event: Equatable {
        case targetWorkspaceActivated(
            workspaceId: WorkspaceDescriptor.ID,
            monitorId: Monitor.ID
        )
        case interactionMonitorSet(monitorId: Monitor.ID)
        case workspaceSessionPatched(
            workspaceId: WorkspaceDescriptor.ID,
            rememberedFocusToken: WindowToken?
        )
    }

    struct Reduction {
        let nextState: WorkspaceSessionState
        let didChange: Bool
    }

    static func reduce(
        state: WorkspaceSessionState,
        event: Event
    ) -> Reduction {
        var next = state
        var changed = false

        switch event {
        case let .targetWorkspaceActivated(workspaceId, monitorId):
            for (existingMonitorId, existingSession) in next.monitorSessions
                where existingMonitorId != monitorId && existingSession.visibleWorkspaceId == workspaceId
            {
                var session = existingSession
                session.previousVisibleWorkspaceId = workspaceId
                session.visibleWorkspaceId = nil
                next.monitorSessions[existingMonitorId] = session
                changed = true
            }

            var session = next.monitorSessions[monitorId] ?? .init()
            if session.visibleWorkspaceId != workspaceId {
                session.previousVisibleWorkspaceId = session.visibleWorkspaceId
                session.visibleWorkspaceId = workspaceId
                next.monitorSessions[monitorId] = session
                changed = true
            }
            changed = setInteractionMonitor(monitorId, in: &next) || changed

        case let .interactionMonitorSet(monitorId):
            changed = setInteractionMonitor(monitorId, in: &next) || changed

        case .workspaceSessionPatched:
            break
        }

        return Reduction(nextState: next, didChange: changed)
    }

    static func projectedSessionFieldsEqual(
        _ lhs: WorkspaceSessionState,
        _ rhs: WorkspaceSessionState
    ) -> Bool {
        lhs.monitorSessions == rhs.monitorSessions
            && lhs.interactionMonitorId == rhs.interactionMonitorId
            && lhs.previousInteractionMonitorId == rhs.previousInteractionMonitorId
    }

    static func projectedSessionFieldsChanged(
        from oldState: WorkspaceSessionState,
        to newState: WorkspaceSessionState
    ) -> Bool {
        !projectedSessionFieldsEqual(oldState, newState)
    }

    private static func setInteractionMonitor(
        _ monitorId: Monitor.ID,
        in state: inout WorkspaceSessionState
    ) -> Bool {
        guard state.interactionMonitorId != monitorId else {
            return false
        }

        if let previousInteractionMonitorId = state.interactionMonitorId {
            state.previousInteractionMonitorId = previousInteractionMonitorId
        }
        state.interactionMonitorId = monitorId
        return true
    }
}

extension WorkspaceSessionReducer.Event {
    init?(confirmation: WMEffectConfirmation) {
        switch confirmation {
        case let .targetWorkspaceActivated(workspaceId, monitorId, _, _):
            self = .targetWorkspaceActivated(workspaceId: workspaceId, monitorId: monitorId)
        case let .interactionMonitorSet(monitorId, _, _):
            self = .interactionMonitorSet(monitorId: monitorId)
        case let .workspaceSessionPatched(workspaceId, token, _, _):
            self = .workspaceSessionPatched(
                workspaceId: workspaceId,
                rememberedFocusToken: token
            )
        case .axFrameWriteOutcome:
            return nil
        case .observedFrame:
            return nil
        }
    }
}
