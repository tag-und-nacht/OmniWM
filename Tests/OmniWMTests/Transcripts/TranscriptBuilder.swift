// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import OmniWMIPC

@testable import OmniWM

final class TranscriptBuilder {
    private var name: String
    private var monitors: [TranscriptMonitorSpec]
    private var workspaces: [WorkspaceConfiguration]
    private var activeWorkspaceName: String?
    private var layoutByWorkspaceName: [String: TranscriptWorkspaceLayout]
    private var steps: [TranscriptStep]
    private var finalExpectations: TranscriptExpectations
    private var securityBoundary: TranscriptSecurityBoundary?

    init(name: String) {
        self.name = name
        self.monitors = []
        self.workspaces = []
        self.activeWorkspaceName = nil
        self.layoutByWorkspaceName = [:]
        self.steps = []
        self.finalExpectations = .empty
        self.securityBoundary = nil
    }

    @discardableResult
    func withMonitors(_ specs: [TranscriptMonitorSpec]) -> Self {
        monitors = specs
        return self
    }

    @discardableResult
    func withWorkspaces(_ configs: [WorkspaceConfiguration]) -> Self {
        workspaces = configs
        return self
    }

    @discardableResult
    func activatingWorkspace(named name: String) -> Self {
        activeWorkspaceName = name
        return self
    }

    @discardableResult
    func withLayout(_ layout: TranscriptWorkspaceLayout, forWorkspaceNamed wsName: String) -> Self {
        layoutByWorkspaceName[wsName] = layout
        return self
    }

    @discardableResult
    func event(
        _ event: WMEvent,
        perturbation: TranscriptPerturbationKind = .none,
        expectation: TranscriptStepExpectation? = nil
    ) -> Self {
        steps.append(TranscriptStep(
            kind: .event(event),
            perturbation: perturbation,
            expectation: expectation
        ))
        return self
    }

    @discardableResult
    func command(
        _ command: WMCommand,
        perturbation: TranscriptPerturbationKind = .none,
        expectation: TranscriptStepExpectation? = nil
    ) -> Self {
        steps.append(TranscriptStep(
            kind: .command(command),
            perturbation: perturbation,
            expectation: expectation
        ))
        return self
    }

    @discardableResult
    func ipcRequest(
        _ request: IPCRequest,
        expectation: TranscriptIPCStepExpectation
    ) -> Self {
        steps.append(TranscriptStep(
            kind: .ipcRequest(request),
            perturbation: .none,
            expectation: TranscriptStepExpectation(
                transactionEffects: nil,
                perStepInvariants: [],
                transactionEpochAdvances: false,
                ipcResponse: expectation
            )
        ))
        return self
    }

    @discardableResult
    func displayDelta(monitorsAfter: [TranscriptMonitorSpec], expectation: TranscriptStepExpectation? = nil) -> Self {
        steps.append(TranscriptStep(
            kind: .displayDelta(TranscriptDisplayDelta(monitorsAfter: monitorsAfter)),
            perturbation: .none,
            expectation: expectation
        ))
        return self
    }

    @discardableResult
    func effectConfirmation(
        _ confirmation: WMEffectConfirmation,
        expectation: TranscriptStepExpectation? = nil
    ) -> Self {
        steps.append(TranscriptStep(
            kind: .effectConfirmation(confirmation),
            perturbation: .none,
            expectation: expectation
        ))
        return self
    }

    @discardableResult
    func expectFinal(_ expectations: TranscriptExpectations) -> Self {
        finalExpectations = expectations
        return self
    }

    @discardableResult
    func withSecurityBoundary(_ boundary: TranscriptSecurityBoundary) -> Self {
        securityBoundary = boundary
        return self
    }

    func build() -> Transcript {
        Transcript(
            name: name,
            initialMonitors: monitors,
            initialWorkspaces: workspaces,
            activeWorkspaceName: activeWorkspaceName,
            layoutByWorkspaceName: layoutByWorkspaceName,
            steps: steps,
            finalExpectations: finalExpectations,
            securityBoundary: securityBoundary
        )
    }
}

extension Transcript {
    static func make(name: String, _ build: (TranscriptBuilder) -> Void) -> Transcript {
        let builder = TranscriptBuilder(name: name)
        build(builder)
        return builder.build()
    }
}
