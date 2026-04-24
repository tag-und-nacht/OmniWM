// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@MainActor
final class VirtualAppRoster {
    struct VirtualApp: Equatable, Hashable, Sendable {
        let pid: pid_t
        let bundleIdentifier: String?
        let displayName: String
    }

    private var apps: [pid_t: VirtualApp] = [:]
    private var nextPidSeed: pid_t = 30_000

    init() {}

    func registerApp(
        bundleIdentifier: String? = nil,
        displayName: String = "VirtualApp"
    ) -> VirtualApp {
        let pid = nextPidSeed
        nextPidSeed += 1
        let app = VirtualApp(
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
        apps[pid] = app
        return app
    }

    func app(forPid pid: pid_t) -> VirtualApp? {
        apps[pid]
    }

    func unregister(_ app: VirtualApp) {
        apps.removeValue(forKey: app.pid)
    }
}
