// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import OmniWMIPC

@testable import OmniWM

struct Transcript: Equatable {
    let name: String
    let initialMonitors: [TranscriptMonitorSpec]
    let initialWorkspaces: [WorkspaceConfiguration]
    let activeWorkspaceName: String?
    let layoutByWorkspaceName: [String: TranscriptWorkspaceLayout]
    let steps: [TranscriptStep]
    let finalExpectations: TranscriptExpectations
    let securityBoundary: TranscriptSecurityBoundary?

    init(
        name: String,
        initialMonitors: [TranscriptMonitorSpec],
        initialWorkspaces: [WorkspaceConfiguration],
        activeWorkspaceName: String? = nil,
        layoutByWorkspaceName: [String: TranscriptWorkspaceLayout] = [:],
        steps: [TranscriptStep],
        finalExpectations: TranscriptExpectations = .empty,
        securityBoundary: TranscriptSecurityBoundary? = nil
    ) {
        self.name = name
        self.initialMonitors = initialMonitors
        self.initialWorkspaces = initialWorkspaces
        self.activeWorkspaceName = activeWorkspaceName
        self.layoutByWorkspaceName = layoutByWorkspaceName
        self.steps = steps
        self.finalExpectations = finalExpectations
        self.securityBoundary = securityBoundary
    }
}

struct TranscriptStep: Equatable {
    let kind: Kind
    let perturbation: TranscriptPerturbationKind
    let expectation: TranscriptStepExpectation

    indirect enum Kind: Equatable {
        case event(WMEvent)
        case command(WMCommand)
        case ipcRequest(IPCRequest)
        case displayDelta(TranscriptDisplayDelta)
        case effectConfirmation(WMEffectConfirmation)
    }

    init(
        kind: Kind,
        perturbation: TranscriptPerturbationKind = .none,
        expectation: TranscriptStepExpectation? = nil
    ) {
        self.kind = kind
        self.perturbation = perturbation
        self.expectation = expectation ?? TranscriptStepExpectation.default(forPerturbation: perturbation)
    }
}

enum TranscriptPerturbationKind: Equatable, Sendable {
    case none
    case duplicate
    case drop
    case delayedAdmission
    case reorderWith(Int)
}

struct TranscriptStepExpectation: Equatable {
    var transactionEffects: TranscriptTransactionEffectsMatcher?
    var perStepInvariants: [TranscriptInvariantPredicateID]
    var transactionEpochAdvances: Bool
    var ipcResponse: TranscriptIPCStepExpectation?

    init(
        transactionEffects: TranscriptTransactionEffectsMatcher? = nil,
        perStepInvariants: [TranscriptInvariantPredicateID] = [],
        transactionEpochAdvances: Bool = true,
        ipcResponse: TranscriptIPCStepExpectation? = nil
    ) {
        self.transactionEffects = transactionEffects
        self.perStepInvariants = perStepInvariants
        self.transactionEpochAdvances = transactionEpochAdvances
        self.ipcResponse = ipcResponse
    }

    static func `default`(forPerturbation perturbation: TranscriptPerturbationKind) -> TranscriptStepExpectation {
        var advances: Bool = true
        switch perturbation {
        case .drop, .delayedAdmission:
            advances = false
        case .none, .duplicate, .reorderWith:
            advances = true
        }
        return TranscriptStepExpectation(
            transactionEffects: nil,
            perStepInvariants: [],
            transactionEpochAdvances: advances,
            ipcResponse: nil
        )
    }
}

struct TranscriptTransactionEffectsMatcher: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case exactSequence
        case containsInOrder
        case empty
    }

    let expectedKinds: [String]
    let mode: Mode

    init(expectedKinds: [String] = [], mode: Mode = .exactSequence) {
        self.expectedKinds = expectedKinds
        self.mode = mode
    }

    static let empty = TranscriptTransactionEffectsMatcher(expectedKinds: [], mode: .empty)

    func matches(_ effectKinds: [String]) -> Bool {
        switch mode {
        case .empty:
            return effectKinds.isEmpty
        case .exactSequence:
            return effectKinds == expectedKinds
        case .containsInOrder:
            var iterator = expectedKinds.makeIterator()
            guard var needle = iterator.next() else { return true }
            for kind in effectKinds where kind == needle {
                guard let next = iterator.next() else { return true }
                needle = next
            }
            return false
        }
    }
}

enum TranscriptInvariantPredicateID: String, Equatable, Sendable, CaseIterable {
    case eachManagedWindowInExactlyOneGraph
    case retiredOrQuarantinedCannotReceiveFocusEffect
    case retiredOrQuarantinedCannotReceiveLayoutEffect
    case retiredOrQuarantinedCannotReceiveFrameEffect
    case failedFrameWriteCannotConfirmFrame
    case effectEpochsMonotonicAcrossPlans
    case topologyEpochAdvancesOnRealDelta
    case workspaceGraphValidates
}

struct TranscriptIPCStepExpectation: Equatable, Sendable {
    let expectedStatus: IPCResponseStatus?
    let expectedErrorCode: IPCErrorCode?
    let expectsZeroPlatformEvents: Bool

    init(
        expectedStatus: IPCResponseStatus? = nil,
        expectedErrorCode: IPCErrorCode? = nil,
        expectsZeroPlatformEvents: Bool = false
    ) {
        self.expectedStatus = expectedStatus
        self.expectedErrorCode = expectedErrorCode
        self.expectsZeroPlatformEvents = expectsZeroPlatformEvents
    }

    static let okSuccess = TranscriptIPCStepExpectation(
        expectedStatus: .success,
        expectedErrorCode: nil,
        expectsZeroPlatformEvents: false
    )
}

struct TranscriptDisplayDelta: Equatable {
    let monitorsAfter: [TranscriptMonitorSpec]
}

enum TranscriptWorkspaceLayout: String, Equatable, Sendable {
    case niri
    case dwindle
}

struct TranscriptMonitorSpec: Equatable, Sendable {
    enum Slot: Equatable, Sendable {
        case primary
        case secondary(slot: Int)
    }

    let slot: Slot
    let name: String
    let frame: CGRect

    init(
        slot: Slot,
        name: String,
        frame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    ) {
        self.slot = slot
        self.name = name
        self.frame = frame
    }

    static let primary = TranscriptMonitorSpec(slot: .primary, name: "Main")
    static let secondary = TranscriptMonitorSpec(
        slot: .secondary(slot: 1),
        name: "Secondary",
        frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
    )
}

struct TranscriptExpectations: Equatable {
    var focusedToken: TokenAssertion?
    var workspaceCount: Int?
    var topologyEpochStrictlyAdvanced: Bool
    var managedWindowsCount: Int?
    var customAssertions: [TranscriptInvariantPredicateID]

    init(
        focusedToken: TokenAssertion? = nil,
        workspaceCount: Int? = nil,
        topologyEpochStrictlyAdvanced: Bool = false,
        managedWindowsCount: Int? = nil,
        customAssertions: [TranscriptInvariantPredicateID] = []
    ) {
        self.focusedToken = focusedToken
        self.workspaceCount = workspaceCount
        self.topologyEpochStrictlyAdvanced = topologyEpochStrictlyAdvanced
        self.managedWindowsCount = managedWindowsCount
        self.customAssertions = customAssertions
    }

    static let empty = TranscriptExpectations()

    enum TokenAssertion: Equatable {
        case anyOf([WindowToken])
        case exactly(WindowToken)
        case nonNil
        case nilToken
    }
}

struct TranscriptSecurityBoundary: Equatable, Sendable {
    let assertsZeroEffectsOnEveryRejection: Bool
    let assertsRuntimeWatermarkUnchangedOnRejection: Bool

    init(
        assertsZeroEffectsOnEveryRejection: Bool = true,
        assertsRuntimeWatermarkUnchangedOnRejection: Bool = true
    ) {
        self.assertsZeroEffectsOnEveryRejection = assertsZeroEffectsOnEveryRejection
        self.assertsRuntimeWatermarkUnchangedOnRejection = assertsRuntimeWatermarkUnchangedOnRejection
    }

    static let strict = TranscriptSecurityBoundary()
}
