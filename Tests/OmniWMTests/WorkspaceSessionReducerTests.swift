// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite struct WorkspaceSessionReducerTests {
    private static let monitor = Monitor.ID(displayId: 1)
    private static let alternativeMonitor = Monitor.ID(displayId: 2)
    private static let workspaceA = WorkspaceDescriptor.ID()
    private static let workspaceB = WorkspaceDescriptor.ID()

    @Test func targetWorkspaceActivatedMutatesMonitorSession() {
        let initial = WorkspaceSessionState()
        let reduction = WorkspaceSessionReducer.reduce(
            state: initial,
            event: .targetWorkspaceActivated(
                workspaceId: Self.workspaceA,
                monitorId: Self.monitor
            )
        )
        #expect(reduction.didChange == true)
        #expect(reduction.nextState.monitorSessions[Self.monitor]?.visibleWorkspaceId == Self.workspaceA)
        #expect(reduction.nextState.monitorSessions[Self.monitor]?.previousVisibleWorkspaceId == nil)
        #expect(reduction.nextState.interactionMonitorId == Self.monitor)
    }

    @Test func targetWorkspaceActivatedRecordsPreviousVisibleWorkspaceOnReassign() {
        var initial = WorkspaceSessionState()
        initial.monitorSessions[Self.monitor] = .init(
            visibleWorkspaceId: Self.workspaceA,
            previousVisibleWorkspaceId: nil
        )
        let reduction = WorkspaceSessionReducer.reduce(
            state: initial,
            event: .targetWorkspaceActivated(
                workspaceId: Self.workspaceB,
                monitorId: Self.monitor
            )
        )
        #expect(reduction.didChange == true)
        #expect(reduction.nextState.monitorSessions[Self.monitor]?.visibleWorkspaceId == Self.workspaceB)
        #expect(reduction.nextState.monitorSessions[Self.monitor]?.previousVisibleWorkspaceId == Self.workspaceA)
        #expect(reduction.nextState.interactionMonitorId == Self.monitor)
    }

    @Test func targetWorkspaceActivatedNoOpForRepeatedAssignment() {
        var initial = WorkspaceSessionState()
        initial.monitorSessions[Self.monitor] = .init(
            visibleWorkspaceId: Self.workspaceA,
            previousVisibleWorkspaceId: nil
        )
        initial.interactionMonitorId = Self.monitor
        let reduction = WorkspaceSessionReducer.reduce(
            state: initial,
            event: .targetWorkspaceActivated(
                workspaceId: Self.workspaceA,
                monitorId: Self.monitor
            )
        )
        #expect(reduction.didChange == false)
        #expect(reduction.nextState.monitorSessions == initial.monitorSessions)
        #expect(reduction.nextState.interactionMonitorId == initial.interactionMonitorId)
    }

    @Test func targetWorkspaceActivatedUpdatesInteractionMonitorForRepeatedAssignment() {
        var initial = WorkspaceSessionState()
        initial.monitorSessions[Self.monitor] = .init(
            visibleWorkspaceId: Self.workspaceA,
            previousVisibleWorkspaceId: nil
        )
        initial.interactionMonitorId = Self.alternativeMonitor

        let reduction = WorkspaceSessionReducer.reduce(
            state: initial,
            event: .targetWorkspaceActivated(
                workspaceId: Self.workspaceA,
                monitorId: Self.monitor
            )
        )

        #expect(reduction.didChange == true)
        #expect(reduction.nextState.monitorSessions == initial.monitorSessions)
        #expect(reduction.nextState.interactionMonitorId == Self.monitor)
        #expect(reduction.nextState.previousInteractionMonitorId == Self.alternativeMonitor)
    }

    @Test func targetWorkspaceActivatedClearsPreviousMonitorOwnership() {
        var initial = WorkspaceSessionState()
        initial.monitorSessions[Self.monitor] = .init(
            visibleWorkspaceId: Self.workspaceA,
            previousVisibleWorkspaceId: nil
        )
        initial.monitorSessions[Self.alternativeMonitor] = .init(
            visibleWorkspaceId: Self.workspaceB,
            previousVisibleWorkspaceId: nil
        )
        initial.interactionMonitorId = Self.monitor

        let reduction = WorkspaceSessionReducer.reduce(
            state: initial,
            event: .targetWorkspaceActivated(
                workspaceId: Self.workspaceA,
                monitorId: Self.alternativeMonitor
            )
        )

        #expect(reduction.didChange == true)
        #expect(reduction.nextState.monitorSessions[Self.monitor]?.visibleWorkspaceId == nil)
        #expect(reduction.nextState.monitorSessions[Self.monitor]?.previousVisibleWorkspaceId == Self.workspaceA)
        #expect(reduction.nextState.monitorSessions[Self.alternativeMonitor]?.visibleWorkspaceId == Self.workspaceA)
        #expect(reduction.nextState.monitorSessions[Self.alternativeMonitor]?.previousVisibleWorkspaceId == Self.workspaceB)
        #expect(reduction.nextState.interactionMonitorId == Self.alternativeMonitor)
        #expect(reduction.nextState.previousInteractionMonitorId == Self.monitor)
    }

    @Test func interactionMonitorSetRecordsPreviousMonitor() {
        var initial = WorkspaceSessionState()
        initial.interactionMonitorId = Self.monitor

        let reduction = WorkspaceSessionReducer.reduce(
            state: initial,
            event: .interactionMonitorSet(monitorId: Self.alternativeMonitor)
        )
        #expect(reduction.didChange == true)
        #expect(reduction.nextState.interactionMonitorId == Self.alternativeMonitor)
        #expect(reduction.nextState.previousInteractionMonitorId == Self.monitor)
    }

    @Test func interactionMonitorSetIsNoOpForUnchangedMonitor() {
        var initial = WorkspaceSessionState()
        initial.interactionMonitorId = Self.monitor

        let reduction = WorkspaceSessionReducer.reduce(
            state: initial,
            event: .interactionMonitorSet(monitorId: Self.monitor)
        )
        #expect(reduction.didChange == false)
        #expect(reduction.nextState.monitorSessions == initial.monitorSessions)
        #expect(reduction.nextState.interactionMonitorId == initial.interactionMonitorId)
    }

    @Test func interactionMonitorSetPreservesPreviousMonitorWhenCurrentIsMissing() {
        var initial = WorkspaceSessionState()
        initial.previousInteractionMonitorId = Self.alternativeMonitor

        let reduction = WorkspaceSessionReducer.reduce(
            state: initial,
            event: .interactionMonitorSet(monitorId: Self.monitor)
        )

        #expect(reduction.didChange == true)
        #expect(reduction.nextState.interactionMonitorId == Self.monitor)
        #expect(reduction.nextState.previousInteractionMonitorId == Self.alternativeMonitor)
    }

    @Test func workspaceSessionPatchedDefersToManagerForRegistryResolution() {
        let initial = WorkspaceSessionState()
        let reduction = WorkspaceSessionReducer.reduce(
            state: initial,
            event: .workspaceSessionPatched(
                workspaceId: Self.workspaceA,
                rememberedFocusToken: WindowToken(pid: 1234, windowId: 5)
            )
        )
        #expect(reduction.didChange == false)
        #expect(reduction.nextState.monitorSessions == initial.monitorSessions)
        #expect(reduction.nextState.interactionMonitorId == initial.interactionMonitorId)
    }

    @Test func eventInitFromEffectConfirmationProjectsTargetActivation() {
        let event = WorkspaceSessionReducer.Event(
            confirmation: .targetWorkspaceActivated(
                workspaceId: Self.workspaceA,
                monitorId: Self.monitor,
                source: .service,
                originatingTransactionEpoch: TransactionEpoch(value: 7)
            )
        )
        #expect(event == .some(.targetWorkspaceActivated(workspaceId: Self.workspaceA, monitorId: Self.monitor)))
    }

    @Test func eventInitFromEffectConfirmationProjectsInteractionMonitorSet() {
        let event = WorkspaceSessionReducer.Event(
            confirmation: .interactionMonitorSet(
                monitorId: Self.alternativeMonitor,
                source: .service,
                originatingTransactionEpoch: TransactionEpoch(value: 8)
            )
        )
        #expect(event == .some(.interactionMonitorSet(monitorId: Self.alternativeMonitor)))
    }

    @Test func eventInitFromEffectConfirmationIgnoresAXFrameWriteOutcome() {
        let event = WorkspaceSessionReducer.Event(
            confirmation: .axFrameWriteOutcome(
                token: WindowToken(pid: 1, windowId: 2),
                axFailure: .staleElement,
                source: .ax,
                originatingTransactionEpoch: TransactionEpoch(value: 9)
            )
        )
        #expect(event == nil)
    }
}
