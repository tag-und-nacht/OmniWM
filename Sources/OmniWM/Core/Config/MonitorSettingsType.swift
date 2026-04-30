// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

protocol MonitorSettingsType: Codable, Identifiable, Equatable {
    var monitorName: String { get set }
    var monitorDisplayUUID: String? { get set }
    var monitorDisplayId: CGDirectDisplayID? { get set }
}

enum MonitorSettingsStore {
    static func get<T: MonitorSettingsType>(for monitor: Monitor, in settings: [T]) -> T? {
        if let monitorUUID = canonicalDisplayUUID(monitor.displayUUID),
           let exact = settings.first(where: { canonicalDisplayUUID($0.monitorDisplayUUID) == monitorUUID }) {
            return exact
        }
        if let exact = settings.first(where: { $0.monitorDisplayId == monitor.displayId }) {
            return exact
        }
        guard !monitor.name.isEmpty else { return nil }
        let nameMatches = settings.filter {
            canonicalDisplayUUID($0.monitorDisplayUUID) == nil &&
                !$0.monitorName.isEmpty &&
                $0.monitorName.caseInsensitiveCompare(monitor.name) == .orderedSame
        }
        guard nameMatches.count == 1 else { return nil }
        return nameMatches[0]
    }

    static func get<T: MonitorSettingsType>(for monitorName: String, in settings: [T]) -> T? {
        settings.first {
            $0.monitorDisplayUUID == nil && $0.monitorDisplayId == nil && $0.monitorName == monitorName
        } ?? settings.first { $0.monitorName == monitorName }
    }

    static func update<T: MonitorSettingsType>(_ item: T, in settings: inout [T]) {
        if let uuid = canonicalDisplayUUID(item.monitorDisplayUUID),
           let index = settings.firstIndex(where: { canonicalDisplayUUID($0.monitorDisplayUUID) == uuid }) {
            settings[index] = item
            return
        }

        if let displayId = item.monitorDisplayId,
           let index = settings.firstIndex(where: { $0.monitorDisplayId == displayId }) {
            settings[index] = item
            return
        }

        if canonicalDisplayUUID(item.monitorDisplayUUID) == nil,
           let index = settings.firstIndex(where: {
               canonicalDisplayUUID($0.monitorDisplayUUID) == nil &&
                   $0.monitorDisplayId == nil &&
                   item.monitorDisplayId == nil &&
                   $0.monitorName == item.monitorName
           }) {
            settings[index] = item
            return
        }

        if item.monitorDisplayUUID != nil || item.monitorDisplayId != nil,
           let index = settings.firstIndex(where: {
               $0.monitorDisplayUUID == nil && $0.monitorDisplayId == nil && $0.monitorName == item.monitorName
           }) {
            settings[index] = item
            return
        }

        settings.append(item)
    }

    static func remove<T: MonitorSettingsType>(for monitor: Monitor, from settings: inout [T]) {
        let monitorUUID = canonicalDisplayUUID(monitor.displayUUID)
        let unboundNameMatches = settings.filter {
            canonicalDisplayUUID($0.monitorDisplayUUID) == nil &&
                $0.monitorDisplayId == nil &&
                !$0.monitorName.isEmpty &&
                $0.monitorName.caseInsensitiveCompare(monitor.name) == .orderedSame
        }
        settings.removeAll { item in
            if let itemUUID = canonicalDisplayUUID(item.monitorDisplayUUID) {
                return itemUUID == monitorUUID
            }
            if let itemDisplayId = item.monitorDisplayId {
                return itemDisplayId == monitor.displayId
            }
            guard !monitor.name.isEmpty,
                  unboundNameMatches.count == 1
            else { return false }
            return item.monitorName.caseInsensitiveCompare(monitor.name) == .orderedSame
        }
    }

    static func remove<T: MonitorSettingsType>(for monitorName: String, from settings: inout [T]) {
        settings.removeAll { $0.monitorName == monitorName }
    }

    private static func canonicalDisplayUUID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed.uppercased()
    }
}
