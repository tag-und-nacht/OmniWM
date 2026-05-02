// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct FrameStateSingleWriterTests {
    private let workspaceId = WorkspaceDescriptor.ID()

    private func makeModel() -> WindowModel { WindowModel() }

    private func admit(
        _ model: WindowModel,
        windowId: Int = 9001
    ) -> WindowToken {
        model.upsert(
            window: AXWindowRef(element: AXUIElementCreateSystemWide(), windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            workspace: workspaceId
        )
    }

    @Test func freshAdmissionSeedsObservedFrameNil() {
        let model = makeModel()
        let token = admit(model)
        #expect(model.observedState(for: token)?.frame == nil)
    }

    @Test func freshAdmissionSeedsDesiredFloatingFrameNil() {
        let model = makeModel()
        let token = admit(model)
        #expect(model.desiredState(for: token)?.floatingFrame == nil)
    }

    @Test func setObservedStateDiscardsInputFrame() {
        let model = makeModel()
        let token = admit(model)
        var input = ObservedWindowState.initial(workspaceId: workspaceId, monitorId: nil)
        input.frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        input.isVisible = false

        model.setObservedState(input, for: token)

        #expect(model.observedState(for: token)?.frame == nil)
        #expect(model.observedState(for: token)?.isVisible == false)
    }

    @Test func setDesiredStateDiscardsInputFloatingFrame() {
        let model = makeModel()
        let token = admit(model)
        var input = DesiredWindowState.initial(
            workspaceId: workspaceId,
            monitorId: nil,
            disposition: .floating
        )
        input.floatingFrame = CGRect(x: 50, y: 50, width: 400, height: 300)
        input.rescueEligible = false

        model.setDesiredState(input, for: token)

        #expect(model.desiredState(for: token)?.floatingFrame == nil)
        #expect(model.desiredState(for: token)?.rescueEligible == false)
    }

    @Test func repeatedSetObservedStateNeverMutatesFrameSlot() {
        let model = makeModel()
        let token = admit(model)
        for x: CGFloat in [10, 100, 200, 300] {
            var input = ObservedWindowState.initial(workspaceId: workspaceId, monitorId: nil)
            input.frame = CGRect(x: x, y: 0, width: 100, height: 100)
            model.setObservedState(input, for: token)
        }
        #expect(model.observedState(for: token)?.frame == nil)
    }
}
