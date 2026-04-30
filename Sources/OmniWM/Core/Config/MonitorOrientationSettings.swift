// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics

struct MonitorOrientationSettings: MonitorSettingsType {
    var id: String { monitorDisplayUUID ?? monitorDisplayId.map(String.init) ?? monitorName }
    var monitorName: String
    var monitorDisplayUUID: String? = nil
    var monitorDisplayId: CGDirectDisplayID? = nil
    var orientation: Monitor.Orientation?

    private enum CodingKeys: String, CodingKey {
        case monitorName, monitorDisplayUUID, monitorDisplayId, orientation
    }

    init(
        monitorName: String,
        monitorDisplayUUID: String? = nil,
        monitorDisplayId: CGDirectDisplayID? = nil,
        orientation: Monitor.Orientation? = nil
    ) {
        self.monitorName = monitorName
        self.monitorDisplayUUID = monitorDisplayUUID
        self.monitorDisplayId = monitorDisplayId
        self.orientation = orientation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitorName = try container.decode(String.self, forKey: .monitorName)
        monitorDisplayUUID = try container.decodeIfPresent(String.self, forKey: .monitorDisplayUUID)
        monitorDisplayId = try container.decodeIfPresent(CGDirectDisplayID.self, forKey: .monitorDisplayId)
        orientation = try container.decodeIfPresent(Monitor.Orientation.self, forKey: .orientation)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(monitorName, forKey: .monitorName)
        try container.encodeIfPresent(monitorDisplayUUID, forKey: .monitorDisplayUUID)
        try container.encodeIfPresent(orientation, forKey: .orientation)
    }
}
