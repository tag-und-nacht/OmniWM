// SPDX-License-Identifier: GPL-2.0-only
import Foundation

enum PrimaryLifecyclePhase: Equatable {
    case candidate
    case admitted
    case managed
    case retiring
    case retired
}

enum LifecycleVisibility: Equatable {
    case visible
    case hidden
    case minimized
    case unknown
}

enum FullscreenSessionState: Equatable {
    case none
    case entering
    case nativeFullscreen
    case exiting
    case unknown
}

enum ReplacementFacet: Equatable {
    case stable
    case replacing(previousToken: WindowToken)
    case replaced(previousToken: WindowToken)
    case staleTokenObserved(token: WindowToken)
}

enum QuarantineReason: Equatable {
    case axReadFailure
    case delayedAdmission
    case staleCGSDestroy
    case appDisappeared

    var suppressesLayout: Bool {
        switch self {
        case .delayedAdmission, .staleCGSDestroy:
            // A rescan miss below the confirmation threshold is provisional; keep
            // layout membership stable until removal is confirmed or the window reappears.
            return false
        case .axReadFailure, .appDisappeared:
            return true
        }
    }
}

enum QuarantineState: Equatable {
    case clear
    case quarantined(reason: QuarantineReason)
    case releasePending

    var suppressesLayout: Bool {
        switch self {
        case .clear:
            return false
        case let .quarantined(reason):
            return reason.suppressesLayout
        case .releasePending:
            return true
        }
    }
}

enum LogicalWindowReplacementReason: String, Equatable {
    case managedReplacement
    case nativeFullscreen
    case manualRekey
}

struct WindowLifecycleRecord: Equatable {
    let logicalId: LogicalWindowId
    var currentToken: WindowToken?
    var axAdmitted: Bool

    var primaryPhase: PrimaryLifecyclePhase
    var visibility: LifecycleVisibility
    var fullscreenSession: FullscreenSessionState
    var replacement: ReplacementFacet
    var quarantine: QuarantineState

    var replacementEpoch: ReplacementEpoch

    var lastKnownWorkspaceId: WorkspaceDescriptor.ID?
    var lastKnownMonitorId: Monitor.ID?

    init(
        logicalId: LogicalWindowId,
        currentToken: WindowToken?,
        axAdmitted: Bool,
        primaryPhase: PrimaryLifecyclePhase,
        visibility: LifecycleVisibility = .unknown,
        fullscreenSession: FullscreenSessionState = .none,
        replacement: ReplacementFacet = .stable,
        quarantine: QuarantineState = .clear,
        replacementEpoch: ReplacementEpoch = ReplacementEpoch(value: 0),
        lastKnownWorkspaceId: WorkspaceDescriptor.ID? = nil,
        lastKnownMonitorId: Monitor.ID? = nil
    ) {
        self.logicalId = logicalId
        self.currentToken = currentToken
        self.axAdmitted = axAdmitted
        self.primaryPhase = primaryPhase
        self.visibility = visibility
        self.fullscreenSession = fullscreenSession
        self.replacement = replacement
        self.quarantine = quarantine
        self.replacementEpoch = replacementEpoch
        self.lastKnownWorkspaceId = lastKnownWorkspaceId
        self.lastKnownMonitorId = lastKnownMonitorId
    }
}

struct WindowLifecycleRecordWithFrame: Equatable {
    let record: WindowLifecycleRecord
    let frame: FrameState?
}

extension WindowLifecycleRecord {
    func frameProjection(
        via lookup: (LogicalWindowId) -> FrameState?
    ) -> WindowLifecycleRecordWithFrame {
        WindowLifecycleRecordWithFrame(
            record: self,
            frame: lookup(logicalId)
        )
    }

    var debugSummary: String {
        let tokenRepresentation: String = if let currentToken {
            "pid=\(currentToken.pid) wid=\(currentToken.windowId)"
        } else {
            "nil"
        }
        let workspaceRepresentation = lastKnownWorkspaceId?.uuidString ?? "nil"
        return "\(logicalId) token=\(tokenRepresentation) "
            + "primary=\(primaryPhase) "
            + "fullscreen=\(fullscreenSession) "
            + "replacement=\(replacement.compactSummary) "
            + "\(replacementEpoch) "
            + "workspace=\(workspaceRepresentation)"
    }
}

extension ReplacementFacet {
    fileprivate var compactSummary: String {
        switch self {
        case .stable:
            "stable"
        case let .replacing(previousToken):
            "replacing<-pid=\(previousToken.pid) wid=\(previousToken.windowId)"
        case let .replaced(previousToken):
            "replaced<-pid=\(previousToken.pid) wid=\(previousToken.windowId)"
        case let .staleTokenObserved(token):
            "stale_observed pid=\(token.pid) wid=\(token.windowId)"
        }
    }
}
