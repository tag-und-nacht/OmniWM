// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@testable import OmniWM

@MainActor
final class VirtualWindowLedger {
    struct Entry: Equatable {
        var token: WindowToken
        var pid: pid_t
        var workspaceId: WorkspaceDescriptor.ID
        var monitorId: Monitor.ID?
        var mode: TrackedWindowMode
        var isNativeFullscreen: Bool
        var isHidden: Bool
        var bundleId: String?
    }

    private(set) var entries: [WindowToken: Entry] = [:]
    private var nextWindowIdSeed: Int = 1

    init() {}

    func allocateToken(pid: pid_t) -> WindowToken {
        defer { nextWindowIdSeed += 1 }
        return WindowToken(pid: pid, windowId: nextWindowIdSeed)
    }

    func register(
        token: WindowToken,
        pid: pid_t,
        workspaceId: WorkspaceDescriptor.ID,
        monitorId: Monitor.ID?,
        mode: TrackedWindowMode,
        bundleId: String? = nil
    ) {
        entries[token] = Entry(
            token: token,
            pid: pid,
            workspaceId: workspaceId,
            monitorId: monitorId,
            mode: mode,
            isNativeFullscreen: false,
            isHidden: false,
            bundleId: bundleId
        )
    }

    func entry(for token: WindowToken) -> Entry? {
        entries[token]
    }

    func update(_ token: WindowToken, _ mutate: (inout Entry) -> Void) {
        guard var entry = entries[token] else { return }
        mutate(&entry)
        entries[token] = entry
    }

    func rekey(from oldToken: WindowToken, to newToken: WindowToken) {
        guard let entry = entries.removeValue(forKey: oldToken) else { return }
        var copy = entry
        copy.token = newToken
        entries[newToken] = copy
    }

    func remove(_ token: WindowToken) {
        entries.removeValue(forKey: token)
    }

    func tokens(forPid pid: pid_t) -> [WindowToken] {
        entries.values.filter { $0.pid == pid }.map(\.token)
    }
}
