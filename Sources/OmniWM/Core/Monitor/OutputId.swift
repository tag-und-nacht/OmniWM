// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

struct OutputId: Hashable, Codable {
    private static let noRuntimeDisplayId: CGDirectDisplayID = 0

    struct OrderedResolution {
        let reboundOutputs: [OutputId]
        let resolvedMonitorIds: [Monitor.ID]
        let claimedMonitorIds: Set<Monitor.ID>
        let resolvedSlotIndices: Set<Int>
    }

    let displayUUID: String?

    let displayId: CGDirectDisplayID
    let name: String

    var runtimeDisplayId: CGDirectDisplayID? {
        displayId == Self.noRuntimeDisplayId ? nil : displayId
    }

    init(displayUUID: String? = nil, displayId: CGDirectDisplayID = noRuntimeDisplayId, name: String) {
        self.displayUUID = Self.canonicalDisplayUUID(displayUUID)
        self.displayId = displayId
        self.name = name
    }

    init(from monitor: Monitor) {
        displayUUID = Self.canonicalDisplayUUID(monitor.displayUUID)
        displayId = monitor.displayId
        name = monitor.name
    }

    func resolveMonitor(in monitors: [Monitor]) -> Monitor? {
        resolvedMonitor(in: monitors, claimedMonitorIds: [])
    }

    func rebound(in monitors: [Monitor]) -> OutputId? {
        resolveMonitor(in: monitors).map(OutputId.init(from:))
    }

    static func == (lhs: OutputId, rhs: OutputId) -> Bool {
        let lhsUUID = canonicalDisplayUUID(lhs.displayUUID)
        let rhsUUID = canonicalDisplayUUID(rhs.displayUUID)
        if lhsUUID != nil || rhsUUID != nil {
            return lhsUUID == rhsUUID
        }
        return lhs.displayId == rhs.displayId && lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        if let uuid = Self.canonicalDisplayUUID(displayUUID) {
            hasher.combine(uuid)
            return
        }
        hasher.combine(displayId)
        hasher.combine(name)
    }

    private enum CodingKeys: String, CodingKey {
        case displayUUID, displayId, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayUUID = Self.canonicalDisplayUUID(try container.decodeIfPresent(String.self, forKey: .displayUUID))
        displayId = try container.decodeIfPresent(CGDirectDisplayID.self, forKey: .displayId) ?? Self.noRuntimeDisplayId
        name = try container.decode(String.self, forKey: .name)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(Self.canonicalDisplayUUID(displayUUID), forKey: .displayUUID)
        try container.encode(name, forKey: .name)
    }

    static func resolveOrderedPreservingUnresolved(
        _ outputs: [OutputId],
        in monitors: [Monitor]
    ) -> OrderedResolution {
        var claimedMonitorIds: Set<Monitor.ID> = []
        var resolvedMonitorIds: [Monitor.ID] = []
        var reboundOutputs: [OutputId] = []
        var resolvedSlotIndices: Set<Int> = []

        reboundOutputs.reserveCapacity(outputs.count)
        resolvedMonitorIds.reserveCapacity(outputs.count)

        for (index, output) in outputs.enumerated() {
            if let exact = output.resolvedMonitor(in: monitors, claimedMonitorIds: claimedMonitorIds),
               claimedMonitorIds.insert(exact.id).inserted
            {
                reboundOutputs.append(OutputId(from: exact))
                resolvedMonitorIds.append(exact.id)
                resolvedSlotIndices.insert(index)
                continue
            }

            reboundOutputs.append(output)
        }

        return OrderedResolution(
            reboundOutputs: reboundOutputs,
            resolvedMonitorIds: resolvedMonitorIds,
            claimedMonitorIds: claimedMonitorIds,
            resolvedSlotIndices: resolvedSlotIndices
        )
    }

    private func resolvedMonitor(
        in monitors: [Monitor],
        claimedMonitorIds: Set<Monitor.ID>
    ) -> Monitor? {
        let candidates = monitors.filter { !claimedMonitorIds.contains($0.id) }
        if let uuid = Self.canonicalDisplayUUID(displayUUID),
           let exact = candidates.first(where: { Self.canonicalDisplayUUID($0.displayUUID) == uuid }) {
            return exact
        }
        if displayId != Self.noRuntimeDisplayId, let exact = candidates.first(where: { $0.displayId == displayId }) {
            return exact
        }
        guard !name.isEmpty else { return nil }
        let nameMatches = candidates.filter {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        guard nameMatches.count == 1 else { return nil }
        return nameMatches[0]
    }

    private static func canonicalDisplayUUID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed.uppercased()
    }
}
