// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OSLog

@MainActor
protocol LogicalWindowRegistryReading: AnyObject {
    func lookup(token: WindowToken) -> LogicalWindowRegistry.TokenBindingState
    func resolveForRead(token: WindowToken) -> LogicalWindowId?
    func resolveForWrite(token: WindowToken) -> LogicalWindowId?
    func record(for logicalId: LogicalWindowId) -> WindowLifecycleRecord?
    func currentToken(for logicalId: LogicalWindowId) -> WindowToken?
    func activeRecords() -> [WindowLifecycleRecord]
    func retiredRecords() -> [WindowLifecycleRecord]
    func debugRender() -> [String]
}

@MainActor
final class LogicalWindowRegistry: LogicalWindowRegistryReading {
    enum TokenBindingState: Equatable {
        case current(LogicalWindowId)
        case staleAlias(LogicalWindowId)
        case retired(LogicalWindowId)
        case unknown

        var liveLogicalId: LogicalWindowId? {
            switch self {
            case let .current(id), let .staleAlias(id):
                return id
            case .retired, .unknown:
                return nil
            }
        }

        var anyLogicalId: LogicalWindowId? {
            switch self {
            case let .current(id), let .staleAlias(id), let .retired(id):
                return id
            case .unknown:
                return nil
            }
        }
    }

    typealias ReplacementReason = LogicalWindowReplacementReason

    enum WriteOutcome: Equatable {
        case applied
        case noChange
        case rejectedStale(LogicalWindowId)
        case rejectedCollision(requested: LogicalWindowId, currentOwner: LogicalWindowId)
        case rejectedRetired(LogicalWindowId)
        case rejectedUnknown
    }

    private let log = Logger(subsystem: "com.omniwm.core", category: "LogicalWindowRegistry")

    private var nextLogicalIdValue: UInt64 = 1

    private var records: [LogicalWindowId: WindowLifecycleRecord] = [:]

    private var logicalIdByCurrentToken: [WindowToken: LogicalWindowId] = [:]

    private var logicalIdByStaleAlias: [WindowToken: LogicalWindowId] = [:]


    @discardableResult
    func allocate(
        boundTo token: WindowToken,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?
    ) -> LogicalWindowId {
        // Allocate strictly monotonically. 2^64 IDs in one session is
        // structurally unreachable, but if the counter ever did saturate the
        // previous "wrap to 1" path silently overwrote the long-lived record
        // at id 1; we'd rather crash loudly than corrupt identity mappings.
        let logicalId = LogicalWindowId(value: nextLogicalIdValue)
        guard nextLogicalIdValue < UInt64.max else {
            preconditionFailure("LogicalWindowId space exhausted (UInt64 saturation)")
        }
        nextLogicalIdValue += 1

        if let previousLogicalId = logicalIdByCurrentToken[token] {
            logicalIdByCurrentToken.removeValue(forKey: token)
            logicalIdByStaleAlias[token] = previousLogicalId
            if var previousRecord = records[previousLogicalId] {
                previousRecord.currentToken = nil
                previousRecord.replacement = .staleTokenObserved(token: token)
                records[previousLogicalId] = previousRecord
            }
        }

        let record = WindowLifecycleRecord(
            logicalId: logicalId,
            currentToken: token,
            axAdmitted: true,
            primaryPhase: .managed,
            visibility: .unknown,
            fullscreenSession: .none,
            replacement: .stable,
            quarantine: .clear,
            replacementEpoch: ReplacementEpoch(value: 0),
            lastKnownWorkspaceId: workspaceId,
            lastKnownMonitorId: monitorId
        )
        records[logicalId] = record
        logicalIdByCurrentToken[token] = logicalId
        log.debug(
            "allocate \(record.debugSummary, privacy: .public)"
        )
        return logicalId
    }


    func lookup(token: WindowToken) -> TokenBindingState {
        if let logicalId = logicalIdByCurrentToken[token] {
            return .current(logicalId)
        }
        if let logicalId = logicalIdByStaleAlias[token] {
            if let record = records[logicalId], record.primaryPhase == .retired {
                return .retired(logicalId)
            }
            return .staleAlias(logicalId)
        }
        return .unknown
    }

    func resolveForWrite(token: WindowToken) -> LogicalWindowId? {
        if case let .current(logicalId) = lookup(token: token) {
            return logicalId
        }
        return nil
    }

    func resolveForRead(token: WindowToken) -> LogicalWindowId? {
        switch lookup(token: token) {
        case let .current(logicalId), let .staleAlias(logicalId):
            return logicalId
        case .retired, .unknown:
            return nil
        }
    }

    func record(for logicalId: LogicalWindowId) -> WindowLifecycleRecord? {
        records[logicalId]
    }

    func currentToken(for logicalId: LogicalWindowId) -> WindowToken? {
        records[logicalId]?.currentToken
    }


    @discardableResult
    func rebindToken(
        logicalId: LogicalWindowId,
        from oldToken: WindowToken,
        to newToken: WindowToken,
        reason: ReplacementReason
    ) -> WriteOutcome {
        guard var record = records[logicalId] else { return .rejectedUnknown }
        guard record.primaryPhase != .retired else {
            log.notice(
                "rebind rejected: retired \(logicalId, privacy: .public)"
            )
            return .rejectedRetired(logicalId)
        }
        if oldToken == newToken {
            return .noChange
        }
        guard logicalIdByCurrentToken[oldToken] == logicalId else {
            log.notice(
                "rebind rejected: stale-from logicalId=\(logicalId, privacy: .public) from=pid=\(oldToken.pid, privacy: .public) wid=\(oldToken.windowId, privacy: .public)"
            )
            return .rejectedStale(logicalId)
        }
        if let currentOwner = logicalIdByCurrentToken[newToken], currentOwner != logicalId {
            log.notice(
                "rebind rejected: token collision logicalId=\(logicalId, privacy: .public) owner=\(currentOwner, privacy: .public) to=pid=\(newToken.pid, privacy: .public) wid=\(newToken.windowId, privacy: .public)"
            )
            return .rejectedCollision(requested: logicalId, currentOwner: currentOwner)
        }

        logicalIdByCurrentToken.removeValue(forKey: oldToken)
        logicalIdByStaleAlias[oldToken] = logicalId
        logicalIdByCurrentToken[newToken] = logicalId

        if logicalIdByStaleAlias[newToken] == logicalId {
            logicalIdByStaleAlias.removeValue(forKey: newToken)
        }

        record.currentToken = newToken
        record.replacementEpoch = ReplacementEpoch(value: record.replacementEpoch.value &+ 1)
        record.replacement = .replaced(previousToken: oldToken)
        records[logicalId] = record

        log.debug(
            "rebind reason=\(reason.rawValue, privacy: .public) \(record.debugSummary, privacy: .public)"
        )
        return .applied
    }


    @discardableResult
    func updateFullscreenSession(
        logicalId: LogicalWindowId,
        _ session: FullscreenSessionState
    ) -> WriteOutcome {
        guard var record = records[logicalId] else { return .rejectedUnknown }
        guard record.primaryPhase != .retired else {
            return .rejectedRetired(logicalId)
        }
        if record.fullscreenSession == session { return .noChange }
        record.fullscreenSession = session
        records[logicalId] = record
        return .applied
    }

    @discardableResult
    func updatePrimaryPhase(
        logicalId: LogicalWindowId,
        _ phase: PrimaryLifecyclePhase
    ) -> WriteOutcome {
        guard var record = records[logicalId] else { return .rejectedUnknown }
        if record.primaryPhase == .retired, phase != .retired {
            return .rejectedRetired(logicalId)
        }
        if record.primaryPhase == phase { return .noChange }
        record.primaryPhase = phase
        records[logicalId] = record
        return .applied
    }

    @discardableResult
    func updateVisibility(
        logicalId: LogicalWindowId,
        _ visibility: LifecycleVisibility
    ) -> WriteOutcome {
        guard var record = records[logicalId] else { return .rejectedUnknown }
        guard record.primaryPhase != .retired else {
            return .rejectedRetired(logicalId)
        }
        if record.visibility == visibility { return .noChange }
        record.visibility = visibility
        records[logicalId] = record
        return .applied
    }

    @discardableResult
    func updateQuarantine(
        logicalId: LogicalWindowId,
        _ quarantine: QuarantineState
    ) -> WriteOutcome {
        guard var record = records[logicalId] else { return .rejectedUnknown }
        guard record.primaryPhase != .retired else {
            return .rejectedRetired(logicalId)
        }
        if record.quarantine == quarantine { return .noChange }
        record.quarantine = quarantine
        records[logicalId] = record
        return .applied
    }

    @discardableResult
    func updateWorkspaceAssignment(
        logicalId: LogicalWindowId,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?
    ) -> WriteOutcome {
        guard var record = records[logicalId] else { return .rejectedUnknown }
        guard record.primaryPhase != .retired else {
            return .rejectedRetired(logicalId)
        }
        if record.lastKnownWorkspaceId == workspaceId,
           record.lastKnownMonitorId == monitorId
        {
            return .noChange
        }
        record.lastKnownWorkspaceId = workspaceId
        record.lastKnownMonitorId = monitorId
        records[logicalId] = record
        return .applied
    }


    @discardableResult
    func retire(logicalId: LogicalWindowId) -> WriteOutcome {
        guard var record = records[logicalId] else { return .rejectedUnknown }
        if record.primaryPhase == .retired { return .noChange }

        if let current = record.currentToken {
            logicalIdByCurrentToken.removeValue(forKey: current)
            logicalIdByStaleAlias[current] = logicalId
        }
        record.currentToken = nil
        record.primaryPhase = .retired
        record.replacement = .stable
        record.fullscreenSession = .none
        record.quarantine = .clear
        records[logicalId] = record
        log.debug(
            "retire \(record.debugSummary, privacy: .public)"
        )
        return .applied
    }


    func activeRecords() -> [WindowLifecycleRecord] {
        records.values
            .filter { $0.primaryPhase != .retired }
            .sorted { $0.logicalId.value < $1.logicalId.value }
    }

    func retiredRecords() -> [WindowLifecycleRecord] {
        records.values
            .filter { $0.primaryPhase == .retired }
            .sorted { $0.logicalId.value < $1.logicalId.value }
    }

    func debugRender() -> [String] {
        records.values
            .sorted { $0.logicalId.value < $1.logicalId.value }
            .map(\.debugSummary)
    }
}
