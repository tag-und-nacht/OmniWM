// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

enum TrackedWindowMode: Equatable, Hashable, Sendable {
    case tiling
    case floating
}

struct ManagedReplacementMetadata: Equatable, Sendable {
    struct RestoreIdentity: Equatable, Sendable {
        let bundleId: String?
        let workspaceId: WorkspaceDescriptor.ID
        let mode: TrackedWindowMode
        let role: String?
        let subrole: String?
        let title: String?
        let windowLevel: Int32?
        let parentWindowId: UInt32?
    }

    var bundleId: String?
    var workspaceId: WorkspaceDescriptor.ID
    var mode: TrackedWindowMode
    var role: String?
    var subrole: String?
    var title: String?
    var windowLevel: Int32?
    var parentWindowId: UInt32?
    var frame: CGRect?

    var restoreIdentity: RestoreIdentity {
        RestoreIdentity(
            bundleId: bundleId,
            workspaceId: workspaceId,
            mode: mode,
            role: role,
            subrole: subrole,
            title: title,
            windowLevel: windowLevel,
            parentWindowId: parentWindowId
        )
    }

    func mergingNonNilValues(from overlay: ManagedReplacementMetadata) -> ManagedReplacementMetadata {
        ManagedReplacementMetadata(
            bundleId: overlay.bundleId ?? bundleId,
            workspaceId: overlay.workspaceId,
            mode: overlay.mode,
            role: overlay.role ?? role,
            subrole: overlay.subrole ?? subrole,
            title: overlay.title ?? title,
            windowLevel: overlay.windowLevel ?? windowLevel,
            parentWindowId: overlay.parentWindowId ?? parentWindowId,
            frame: overlay.frame ?? frame
        )
    }
}

struct ManagedWindowRestoreSnapshot: Equatable {
    struct SemanticIdentity: Equatable {
        struct QuantizedFrame: Equatable {
            private let minXBucket: Int
            private let minYBucket: Int
            private let widthBucket: Int
            private let heightBucket: Int

            init(frame: CGRect, tolerance: CGFloat) {
                let step = max(tolerance, 0.000_1)
                minXBucket = Self.bucket(frame.origin.x, step: step)
                minYBucket = Self.bucket(frame.origin.y, step: step)
                widthBucket = Self.bucket(frame.width, step: step)
                heightBucket = Self.bucket(frame.height, step: step)
            }

            private static func bucket(_ value: CGFloat, step: CGFloat) -> Int {
                Int(floor(Double(value / step)))
            }
        }

        let workspaceId: WorkspaceDescriptor.ID
        let frame: QuantizedFrame
        let topologyProfile: TopologyProfile
        let niriState: NiriState?
        let replacementRestoreIdentity: ManagedReplacementMetadata.RestoreIdentity?
    }

    struct NiriState: Equatable {
        struct ColumnSizing: Equatable {
            let width: ProportionalSize
            let cachedWidth: CGFloat
            let presetWidthIdx: Int?
            let isFullWidth: Bool
            let savedWidth: ProportionalSize?
            let hasManualSingleWindowWidthOverride: Bool
            let height: ProportionalSize
            let cachedHeight: CGFloat
            let isFullHeight: Bool
            let savedHeight: ProportionalSize?
        }

        struct WindowSizing: Equatable {
            let height: WeightedSize
            let savedHeight: WeightedSize?
            let windowWidth: WeightedSize
            let sizingMode: SizingMode
        }

        let nodeId: NodeId?
        let columnIndex: Int?
        let tileIndex: Int?
        let columnWindowMembers: [LogicalWindowId]
        let columnSizing: ColumnSizing
        let windowSizing: WindowSizing

        static let defaultSemanticWeightTolerance: CGFloat = 1e-3

        static func isSemanticallyEquivalent(
            _ lhs: NiriState?,
            _ rhs: NiriState?,
            frameTolerance: CGFloat,
            weightTolerance: CGFloat = defaultSemanticWeightTolerance
        ) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil):
                return true
            case (nil, _?), (_?, nil):
                return false
            case let (a?, b?):
                return a.isSemanticallyEquivalent(
                    to: b,
                    frameTolerance: frameTolerance,
                    weightTolerance: weightTolerance
                )
            }
        }

        func isSemanticallyEquivalent(
            to other: NiriState,
            frameTolerance: CGFloat,
            weightTolerance: CGFloat = defaultSemanticWeightTolerance
        ) -> Bool {
            guard nodeId == other.nodeId,
                  columnIndex == other.columnIndex,
                  tileIndex == other.tileIndex,
                  columnWindowMembers == other.columnWindowMembers
            else {
                return false
            }
            return columnSizing.isSemanticallyEquivalent(
                to: other.columnSizing,
                frameTolerance: frameTolerance,
                weightTolerance: weightTolerance
            ) && windowSizing.isSemanticallyEquivalent(
                to: other.windowSizing,
                frameTolerance: frameTolerance,
                weightTolerance: weightTolerance
            )
        }
    }

    let workspaceId: WorkspaceDescriptor.ID
    let frame: CGRect
    let topologyProfile: TopologyProfile
    let niriState: NiriState?
    let replacementMetadata: ManagedReplacementMetadata?

    func isSemanticallyEquivalent(
        to other: ManagedWindowRestoreSnapshot,
        frameTolerance: CGFloat,
        weightTolerance: CGFloat = NiriState.defaultSemanticWeightTolerance
    ) -> Bool {
        workspaceId == other.workspaceId
            && frame.approximatelyEqual(to: other.frame, tolerance: frameTolerance)
            && topologyProfile == other.topologyProfile
            && ManagedWindowRestoreSnapshot.NiriState.isSemanticallyEquivalent(
                niriState,
                other.niriState,
                frameTolerance: frameTolerance,
                weightTolerance: weightTolerance
            )
            && replacementMetadata?.restoreIdentity == other.replacementMetadata?.restoreIdentity
    }

    func semanticIdentity(frameTolerance: CGFloat) -> SemanticIdentity {
        SemanticIdentity(
            workspaceId: workspaceId,
            frame: .init(frame: frame, tolerance: frameTolerance),
            topologyProfile: topologyProfile,
            niriState: niriState,
            replacementRestoreIdentity: replacementMetadata?.restoreIdentity
        )
    }

    func withReplacementMetadata(
        _ replacementMetadata: ManagedReplacementMetadata?
    ) -> ManagedWindowRestoreSnapshot {
        ManagedWindowRestoreSnapshot(
            workspaceId: workspaceId,
            frame: frame,
            topologyProfile: topologyProfile,
            niriState: niriState,
            replacementMetadata: replacementMetadata ?? self.replacementMetadata
        )
    }
}

extension ManagedWindowRestoreSnapshot.NiriState.ColumnSizing {
    func isSemanticallyEquivalent(
        to other: ManagedWindowRestoreSnapshot.NiriState.ColumnSizing,
        frameTolerance: CGFloat,
        weightTolerance: CGFloat
    ) -> Bool {
        guard isFullWidth == other.isFullWidth,
              isFullHeight == other.isFullHeight,
              presetWidthIdx == other.presetWidthIdx,
              hasManualSingleWindowWidthOverride == other.hasManualSingleWindowWidthOverride
        else {
            return false
        }
        guard abs(cachedWidth - other.cachedWidth) < frameTolerance,
              abs(cachedHeight - other.cachedHeight) < frameTolerance
        else {
            return false
        }
        return proportionalSizesSemanticallyEquivalent(
            width, other.width,
            frameTolerance: frameTolerance,
            weightTolerance: weightTolerance
        ) && proportionalSizesSemanticallyEquivalent(
            height, other.height,
            frameTolerance: frameTolerance,
            weightTolerance: weightTolerance
        ) && optionalProportionalSizesSemanticallyEquivalent(
            savedWidth, other.savedWidth,
            frameTolerance: frameTolerance,
            weightTolerance: weightTolerance
        ) && optionalProportionalSizesSemanticallyEquivalent(
            savedHeight, other.savedHeight,
            frameTolerance: frameTolerance,
            weightTolerance: weightTolerance
        )
    }
}

extension ManagedWindowRestoreSnapshot.NiriState.WindowSizing {
    func isSemanticallyEquivalent(
        to other: ManagedWindowRestoreSnapshot.NiriState.WindowSizing,
        frameTolerance: CGFloat,
        weightTolerance: CGFloat
    ) -> Bool {
        guard sizingMode == other.sizingMode else { return false }
        return weightedSizesSemanticallyEquivalent(
            height, other.height,
            frameTolerance: frameTolerance,
            weightTolerance: weightTolerance
        ) && weightedSizesSemanticallyEquivalent(
            windowWidth, other.windowWidth,
            frameTolerance: frameTolerance,
            weightTolerance: weightTolerance
        ) && optionalWeightedSizesSemanticallyEquivalent(
            savedHeight, other.savedHeight,
            frameTolerance: frameTolerance,
            weightTolerance: weightTolerance
        )
    }
}

private func proportionalSizesSemanticallyEquivalent(
    _ lhs: ProportionalSize,
    _ rhs: ProportionalSize,
    frameTolerance: CGFloat,
    weightTolerance: CGFloat
) -> Bool {
    switch (lhs, rhs) {
    case let (.proportion(a), .proportion(b)):
        return abs(a - b) < weightTolerance
    case let (.fixed(a), .fixed(b)):
        return abs(a - b) < frameTolerance
    default:
        return false
    }
}

private func optionalProportionalSizesSemanticallyEquivalent(
    _ lhs: ProportionalSize?,
    _ rhs: ProportionalSize?,
    frameTolerance: CGFloat,
    weightTolerance: CGFloat
) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case (nil, _?), (_?, nil):
        return false
    case let (a?, b?):
        return proportionalSizesSemanticallyEquivalent(
            a, b,
            frameTolerance: frameTolerance,
            weightTolerance: weightTolerance
        )
    }
}

private func weightedSizesSemanticallyEquivalent(
    _ lhs: WeightedSize,
    _ rhs: WeightedSize,
    frameTolerance: CGFloat,
    weightTolerance: CGFloat
) -> Bool {
    switch (lhs, rhs) {
    case let (.auto(a), .auto(b)):
        return abs(a - b) < weightTolerance
    case let (.fixed(a), .fixed(b)):
        return abs(a - b) < frameTolerance
    default:
        return false
    }
}

private func optionalWeightedSizesSemanticallyEquivalent(
    _ lhs: WeightedSize?,
    _ rhs: WeightedSize?,
    frameTolerance: CGFloat,
    weightTolerance: CGFloat
) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case (nil, _?), (_?, nil):
        return false
    case let (a?, b?):
        return weightedSizesSemanticallyEquivalent(
            a, b,
            frameTolerance: frameTolerance,
            weightTolerance: weightTolerance
        )
    }
}

final class WindowModel {
    typealias WindowKey = WindowToken

    enum HiddenReason: Equatable {
        case workspaceInactive
        case layoutTransient(HideSide)
        case scratchpad
    }

    struct HiddenState: Equatable {
        let proportionalPosition: CGPoint
        let referenceMonitorId: Monitor.ID?
        let reason: HiddenReason

        var workspaceInactive: Bool {
            if case .workspaceInactive = reason {
                return true
            }
            return false
        }

        var offscreenSide: HideSide? {
            if case let .layoutTransient(side) = reason {
                return side
            }
            return nil
        }

        var isScratchpad: Bool {
            if case .scratchpad = reason {
                return true
            }
            return false
        }

        var restoresViaFloatingState: Bool {
            switch reason {
            case .workspaceInactive, .scratchpad:
                true
            case .layoutTransient:
                false
            }
        }

        init(
            proportionalPosition: CGPoint,
            referenceMonitorId: Monitor.ID?,
            reason: HiddenReason
        ) {
            self.proportionalPosition = proportionalPosition
            self.referenceMonitorId = referenceMonitorId
            self.reason = reason
        }

        init(
            proportionalPosition: CGPoint,
            referenceMonitorId: Monitor.ID?,
            workspaceInactive: Bool,
            offscreenSide: HideSide? = nil
        ) {
            self.proportionalPosition = proportionalPosition
            self.referenceMonitorId = referenceMonitorId
            if workspaceInactive {
                reason = .workspaceInactive
            } else if let offscreenSide {
                reason = .layoutTransient(offscreenSide)
            } else {
                reason = .scratchpad
            }
        }
    }

    struct FloatingState: Equatable {
        var lastFrame: CGRect
        var normalizedOrigin: CGPoint?
        var referenceMonitorId: Monitor.ID?
        var restoreToFloating: Bool

        init(
            lastFrame: CGRect,
            normalizedOrigin: CGPoint?,
            referenceMonitorId: Monitor.ID?,
            restoreToFloating: Bool
        ) {
            self.lastFrame = lastFrame
            self.normalizedOrigin = normalizedOrigin
            self.referenceMonitorId = referenceMonitorId
            self.restoreToFloating = restoreToFloating
        }
    }

    final class Entry {
        let handle: WindowHandle
        var axRef: AXWindowRef
        var workspaceId: WorkspaceDescriptor.ID
        var mode: TrackedWindowMode
        var lifecyclePhase: WindowLifecyclePhase
        var observedState: ObservedWindowState
        var desiredState: DesiredWindowState
        var restoreIntent: RestoreIntent?
        var replacementCorrelation: ReplacementCorrelation?
        var managedReplacementMetadata: ManagedReplacementMetadata?
        var floatingState: FloatingState?
        var manualLayoutOverride: ManualWindowOverride?
        var ruleEffects: ManagedWindowRuleEffects = .none
        var hiddenProportionalPosition: CGPoint?
        var hiddenReferenceMonitorId: Monitor.ID?
        var hiddenReason: HiddenReason?

        var layoutReason: LayoutReason = .standard
        var parentKind: ParentKind = .tilingContainer
        var prevParentKind: ParentKind?
        // Per-window AX size-constraint cache moved out of `Entry` into
        // `WindowConstraintCache` (ExecPlan 01, slice WGT-SS-06) so the TTL
        // logic lives behind a focused type. WindowModel holds the cache as
        // a peer; entry mutations that should invalidate the cache call
        // `constraintCache.invalidate(for: entry.token)` explicitly.

        var token: WindowToken { handle.id }
        var pid: pid_t { token.pid }
        var windowId: Int { token.windowId }

        init(
            handle: WindowHandle,
            axRef: AXWindowRef,
            workspaceId: WorkspaceDescriptor.ID,
            mode: TrackedWindowMode,
            lifecyclePhase: WindowLifecyclePhase? = nil,
            observedState: ObservedWindowState? = nil,
            desiredState: DesiredWindowState? = nil,
            restoreIntent: RestoreIntent? = nil,
            replacementCorrelation: ReplacementCorrelation? = nil,
            managedReplacementMetadata: ManagedReplacementMetadata?,
            floatingState: FloatingState?,
            manualLayoutOverride: ManualWindowOverride?,
            ruleEffects: ManagedWindowRuleEffects,
            hiddenProportionalPosition: CGPoint?
        ) {
            self.handle = handle
            self.axRef = axRef
            self.workspaceId = workspaceId
            self.mode = mode
            self.lifecyclePhase = lifecyclePhase ?? (mode == .floating ? .floating : .tiled)
            self.observedState = observedState ?? .initial(
                workspaceId: workspaceId,
                monitorId: nil
            )
            self.desiredState = desiredState ?? .initial(
                workspaceId: workspaceId,
                monitorId: nil,
                disposition: mode
            )
            self.restoreIntent = restoreIntent
            self.replacementCorrelation = replacementCorrelation
            self.managedReplacementMetadata = managedReplacementMetadata
            self.floatingState = floatingState
            self.manualLayoutOverride = manualLayoutOverride
            self.ruleEffects = ruleEffects
            self.hiddenProportionalPosition = hiddenProportionalPosition
        }
    }

    private(set) var entries: [WindowToken: Entry] = [:]
    private var entryByWindowId: [Int: Entry] = [:]
    private var tokensByPid: [pid_t: [WindowToken]] = [:]
    private var tokenIndexByPid: [pid_t: [WindowToken: Int]] = [:]
    private var missingDetectionCountByToken: [WindowToken: Int] = [:]
    private var constraintCache = WindowConstraintCache()

    private func appendToken<Key: Hashable>(
        _ token: WindowToken,
        to key: Key,
        tokensByKey: inout [Key: [WindowToken]],
        tokenIndexByKey: inout [Key: [WindowToken: Int]]
    ) {
        var tokens = tokensByKey[key, default: []]
        var indexByToken = tokenIndexByKey[key, default: [:]]
        guard indexByToken[token] == nil else { return }
        indexByToken[token] = tokens.count
        tokens.append(token)
        tokensByKey[key] = tokens
        tokenIndexByKey[key] = indexByToken
    }

    private func removeToken<Key: Hashable>(
        _ token: WindowToken,
        from key: Key,
        tokensByKey: inout [Key: [WindowToken]],
        tokenIndexByKey: inout [Key: [WindowToken: Int]]
    ) {
        guard var tokens = tokensByKey[key],
              var indexByToken = tokenIndexByKey[key],
              let index = indexByToken[token] else { return }

        tokens.remove(at: index)
        indexByToken.removeValue(forKey: token)

        if index < tokens.count {
            for i in index ..< tokens.count {
                indexByToken[tokens[i]] = i
            }
        }

        if tokens.isEmpty {
            tokensByKey.removeValue(forKey: key)
            tokenIndexByKey.removeValue(forKey: key)
        } else {
            tokensByKey[key] = tokens
            tokenIndexByKey[key] = indexByToken
        }
    }

    private func replaceToken<Key: Hashable>(
        from oldToken: WindowToken,
        to newToken: WindowToken,
        in key: Key,
        tokensByKey: inout [Key: [WindowToken]],
        tokenIndexByKey: inout [Key: [WindowToken: Int]]
    ) {
        guard var tokens = tokensByKey[key],
              var indexByToken = tokenIndexByKey[key],
              let index = indexByToken.removeValue(forKey: oldToken)
        else {
            return
        }

        tokens[index] = newToken
        indexByToken[newToken] = index
        tokensByKey[key] = tokens
        tokenIndexByKey[key] = indexByToken
    }

    private func appendIndexes(for entry: Entry) {
        let token = entry.token
        entryByWindowId[entry.windowId] = entry
        appendToken(token, to: entry.pid, tokensByKey: &tokensByPid, tokenIndexByKey: &tokenIndexByPid)
    }

    private func removeIndexes(for entry: Entry, token: WindowToken? = nil, windowId: Int? = nil) {
        let token = token ?? entry.token
        let windowId = windowId ?? entry.windowId

        entryByWindowId.removeValue(forKey: windowId)
        removeToken(token, from: token.pid, tokensByKey: &tokensByPid, tokenIndexByKey: &tokenIndexByPid)
    }

    private func rekeyIndexes(for entry: Entry, from oldToken: WindowToken, to newToken: WindowToken) {
        entryByWindowId.removeValue(forKey: oldToken.windowId)
        entryByWindowId[newToken.windowId] = entry

        if oldToken.pid == newToken.pid {
            replaceToken(
                from: oldToken,
                to: newToken,
                in: oldToken.pid,
                tokensByKey: &tokensByPid,
                tokenIndexByKey: &tokenIndexByPid
            )
        } else {
            removeToken(oldToken, from: oldToken.pid, tokensByKey: &tokensByPid, tokenIndexByKey: &tokenIndexByPid)
            appendToken(newToken, to: newToken.pid, tokensByKey: &tokensByPid, tokenIndexByKey: &tokenIndexByPid)
        }
    }

    @discardableResult
    func upsert(
        window: AXWindowRef,
        pid: pid_t,
        windowId: Int,
        workspace: WorkspaceDescriptor.ID,
        mode: TrackedWindowMode = .tiling,
        ruleEffects: ManagedWindowRuleEffects = .none,
        managedReplacementMetadata: ManagedReplacementMetadata? = nil
    ) -> WindowToken {
        let token = WindowToken(pid: pid, windowId: windowId)
        if let entry = entries[token] {
            entry.axRef = window
            updateWorkspace(for: token, workspace: workspace)
            setMode(mode, for: token)
            if let managedReplacementMetadata {
                entry.managedReplacementMetadata = managedReplacementMetadata
            }
            if entry.ruleEffects != ruleEffects {
                entry.ruleEffects = ruleEffects
                constraintCache.invalidate(for: entry.token)
            }
            missingDetectionCountByToken.removeValue(forKey: token)
            return token
        }

        let handle = WindowHandle(id: token)
        let entry = Entry(
            handle: handle,
            axRef: window,
            workspaceId: workspace,
            mode: mode,
            managedReplacementMetadata: managedReplacementMetadata,
            floatingState: nil,
            manualLayoutOverride: nil,
            ruleEffects: ruleEffects,
            hiddenProportionalPosition: nil
        )
        entries[token] = entry
        appendIndexes(for: entry)
        missingDetectionCountByToken.removeValue(forKey: token)
        return token
    }

    @discardableResult
    func rekeyWindow(
        from oldToken: WindowToken,
        to newToken: WindowToken,
        newAXRef: AXWindowRef,
        managedReplacementMetadata: ManagedReplacementMetadata? = nil
    ) -> Entry? {
        if oldToken == newToken {
            guard let entry = entries[oldToken] else { return nil }
            entry.axRef = newAXRef
            // AX ref change can invalidate cached constraints (the new ref
            // may report different size limits even at the same token).
            constraintCache.invalidate(for: oldToken)
            if let managedReplacementMetadata {
                entry.managedReplacementMetadata = managedReplacementMetadata
            }
            return entry
        }

        guard entries[newToken] == nil,
              let entry = entries.removeValue(forKey: oldToken)
        else {
            return nil
        }

        entry.handle.id = newToken
        entry.axRef = newAXRef
        // Token rebind: drop the cached constraints under the old token.
        // Don't carry them across the rebind because the AX ref also changed.
        constraintCache.invalidate(for: oldToken)
        if let managedReplacementMetadata {
            entry.managedReplacementMetadata = managedReplacementMetadata
        }
        entries[newToken] = entry
        rekeyIndexes(for: entry, from: oldToken, to: newToken)

        if let missingCount = missingDetectionCountByToken.removeValue(forKey: oldToken) {
            missingDetectionCountByToken[newToken] = missingCount
        }

        return entry
    }

    func handle(for token: WindowToken) -> WindowHandle? {
        entries[token]?.handle
    }

    func updateWorkspace(for token: WindowToken, workspace: WorkspaceDescriptor.ID) {
        guard let entry = entries[token] else { return }
        entry.workspaceId = workspace
    }

    func workspace(for token: WindowToken) -> WorkspaceDescriptor.ID? {
        entries[token]?.workspaceId
    }

    func entry(for token: WindowToken) -> Entry? {
        entries[token]
    }

    func entry(for handle: WindowHandle) -> Entry? {
        entry(for: handle.id)
    }

    func entry(forPid pid: pid_t, windowId: Int) -> Entry? {
        entry(for: WindowToken(pid: pid, windowId: windowId))
    }

    func entries(forPid pid: pid_t) -> [Entry] {
        guard let tokens = tokensByPid[pid] else { return [] }
        return tokens.compactMap { entries[$0] }
    }

    func entry(forWindowId windowId: Int) -> Entry? {
        entryByWindowId[windowId]
    }

    func entry(forWindowId windowId: Int, inVisibleWorkspaces visibleIds: Set<WorkspaceDescriptor.ID>) -> Entry? {
        guard let entry = entryByWindowId[windowId],
              visibleIds.contains(entry.workspaceId) else { return nil }
        return entry
    }

    func allEntries() -> [Entry] {
        Array(entries.values)
    }

    func mode(for token: WindowToken) -> TrackedWindowMode? {
        entries[token]?.mode
    }

    func setMode(_ mode: TrackedWindowMode, for token: WindowToken) {
        guard let entry = entries[token], entry.mode != mode else { return }
        entry.mode = mode
    }

    func floatingState(for token: WindowToken) -> FloatingState? {
        entries[token]?.floatingState
    }

    func setFloatingState(_ state: FloatingState?, for token: WindowToken) {
        entries[token]?.floatingState = state
    }

    func manualLayoutOverride(for token: WindowToken) -> ManualWindowOverride? {
        entries[token]?.manualLayoutOverride
    }

    func setManualLayoutOverride(_ override: ManualWindowOverride?, for token: WindowToken) {
        entries[token]?.manualLayoutOverride = override
    }

    func lifecyclePhase(for token: WindowToken) -> WindowLifecyclePhase? {
        entries[token]?.lifecyclePhase
    }

    func setLifecyclePhase(_ phase: WindowLifecyclePhase, for token: WindowToken) {
        entries[token]?.lifecyclePhase = phase
    }

    func observedState(for token: WindowToken) -> ObservedWindowState? {
        entries[token]?.observedState
    }

    func setObservedState(_ state: ObservedWindowState, for token: WindowToken) {
        guard let entry = entries[token] else { return }
        var next = state
        next.frame = entry.observedState.frame
        entry.observedState = next
    }

    func desiredState(for token: WindowToken) -> DesiredWindowState? {
        entries[token]?.desiredState
    }

    func setDesiredState(_ state: DesiredWindowState, for token: WindowToken) {
        guard let entry = entries[token] else { return }
        var next = state
        next.floatingFrame = entry.desiredState.floatingFrame
        entry.desiredState = next
    }

    func restoreIntent(for token: WindowToken) -> RestoreIntent? {
        entries[token]?.restoreIntent
    }

    func setRestoreIntent(_ intent: RestoreIntent?, for token: WindowToken) {
        entries[token]?.restoreIntent = intent
    }

    func replacementCorrelation(for token: WindowToken) -> ReplacementCorrelation? {
        entries[token]?.replacementCorrelation
    }

    func setReplacementCorrelation(_ correlation: ReplacementCorrelation?, for token: WindowToken) {
        entries[token]?.replacementCorrelation = correlation
    }

    func managedReplacementMetadata(for token: WindowToken) -> ManagedReplacementMetadata? {
        entries[token]?.managedReplacementMetadata
    }

    func setManagedReplacementMetadata(_ metadata: ManagedReplacementMetadata?, for token: WindowToken) {
        entries[token]?.managedReplacementMetadata = metadata
    }


    func setHiddenState(_ state: HiddenState?, for token: WindowToken) {
        guard let entry = entries[token] else { return }
        if let state {
            entry.hiddenProportionalPosition = state.proportionalPosition
            entry.hiddenReferenceMonitorId = state.referenceMonitorId
            entry.hiddenReason = state.reason
        } else {
            entry.hiddenProportionalPosition = nil
            entry.hiddenReferenceMonitorId = nil
            entry.hiddenReason = nil
        }
    }

    func hiddenState(for token: WindowToken) -> HiddenState? {
        guard let entry = entries[token],
              let proportionalPosition = entry.hiddenProportionalPosition,
              let hiddenReason = entry.hiddenReason
        else { return nil }
        return HiddenState(
            proportionalPosition: proportionalPosition,
            referenceMonitorId: entry.hiddenReferenceMonitorId,
            reason: hiddenReason
        )
    }

    func isHiddenInCorner(_ token: WindowToken) -> Bool {
        entries[token]?.hiddenProportionalPosition != nil
    }

    func layoutReason(for token: WindowToken) -> LayoutReason {
        entries[token]?.layoutReason ?? .standard
    }

    func isNativeFullscreenSuspended(_ token: WindowToken) -> Bool {
        entries[token]?.layoutReason == .nativeFullscreen
    }

    func setLayoutReason(_ reason: LayoutReason, for token: WindowToken) {
        guard let entry = entries[token] else { return }
        if reason != .standard, entry.layoutReason == .standard {
            entry.prevParentKind = entry.parentKind
        }
        entry.layoutReason = reason
    }

    func restoreFromNativeState(for token: WindowToken) -> ParentKind? {
        guard let entry = entries[token],
              entry.layoutReason != .standard,
              let prevKind = entry.prevParentKind else { return nil }
        entry.layoutReason = .standard
        entry.parentKind = prevKind
        entry.prevParentKind = nil
        return prevKind
    }

    struct MissingKeyDelta {
        var confirmed: [WindowKey]
        var delayed: [WindowKey]
        var cleared: [WindowKey]
    }

    func confirmedMissingKeysWithDelta(
        keys activeKeys: Set<WindowKey>,
        requiredConsecutiveMisses: Int = 1
    ) -> MissingKeyDelta {
        let threshold = max(1, requiredConsecutiveMisses)
        let knownTokens = Array(entries.keys)

        var cleared: [WindowKey] = []
        for token in knownTokens where activeKeys.contains(token) {
            if missingDetectionCountByToken.removeValue(forKey: token) != nil {
                cleared.append(token)
            }
        }

        let missingTokens = knownTokens.filter { !activeKeys.contains($0) }
        var confirmedMissing: [WindowKey] = []
        var delayed: [WindowKey] = []
        confirmedMissing.reserveCapacity(missingTokens.count)
        delayed.reserveCapacity(missingTokens.count)

        for token in missingTokens {
            if entries[token]?.layoutReason == .nativeFullscreen {
                if missingDetectionCountByToken.removeValue(forKey: token) != nil {
                    cleared.append(token)
                }
                continue
            }
            let misses = (missingDetectionCountByToken[token] ?? 0) + 1
            if misses >= threshold {
                confirmedMissing.append(token)
                missingDetectionCountByToken.removeValue(forKey: token)
            } else {
                missingDetectionCountByToken[token] = misses
                delayed.append(token)
            }
        }

        if !missingDetectionCountByToken.isEmpty {
            missingDetectionCountByToken = missingDetectionCountByToken.filter { entries[$0.key] != nil }
        }

        return MissingKeyDelta(
            confirmed: confirmedMissing,
            delayed: delayed,
            cleared: cleared
        )
    }

    func confirmedMissingKeys(keys activeKeys: Set<WindowKey>, requiredConsecutiveMisses: Int = 1) -> [WindowKey] {
        confirmedMissingKeysWithDelta(
            keys: activeKeys,
            requiredConsecutiveMisses: requiredConsecutiveMisses
        ).confirmed
    }

    @discardableResult
    func removeWindow(key: WindowKey) -> Entry? {
        missingDetectionCountByToken.removeValue(forKey: key)
        guard let entry = entries[key] else { return nil }
        removeIndexes(for: entry, token: key, windowId: key.windowId)
        entries.removeValue(forKey: key)
        constraintCache.invalidate(for: key)
        return entry
    }

    func cachedConstraints(for token: WindowToken, maxAge: TimeInterval = 5.0) -> WindowSizeConstraints? {
        guard entries[token] != nil else { return nil }
        return constraintCache.cachedConstraints(for: token, maxAge: maxAge)
    }

    func setCachedConstraints(_ constraints: WindowSizeConstraints, for token: WindowToken) {
        guard entries[token] != nil else { return }
        constraintCache.setCachedConstraints(constraints, for: token)
    }
}
