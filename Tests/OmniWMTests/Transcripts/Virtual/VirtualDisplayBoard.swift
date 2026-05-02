// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

@testable import OmniWM

@MainActor
final class VirtualDisplayBoard {
    private(set) var monitors: [Monitor]
    private(set) var specs: [TranscriptMonitorSpec]

    init(initialSpecs: [TranscriptMonitorSpec]) {
        self.specs = initialSpecs
        self.monitors = initialSpecs.map(VirtualDisplayBoard.materialize)
    }

    @discardableResult
    func setMonitors(_ nextSpecs: [TranscriptMonitorSpec]) -> DisplayDelta {
        let materialized = nextSpecs.map(VirtualDisplayBoard.materialize)
        specs = nextSpecs
        monitors = materialized
        let topologyEvent = WMEvent.topologyChanged(
            displays: TopologyProfile(monitors: materialized).displays,
            source: .service
        )
        return DisplayDelta(
            monitorsAfter: materialized,
            specsAfter: nextSpecs,
            topologyEvent: topologyEvent
        )
    }

    @discardableResult
    func appendMonitor(_ spec: TranscriptMonitorSpec) -> DisplayDelta {
        setMonitors(specs + [spec])
    }

    @discardableResult
    func removeMonitor(matching predicate: (TranscriptMonitorSpec) -> Bool) -> DisplayDelta {
        let remaining = specs.filter { !predicate($0) }
        return setMonitors(remaining)
    }

    struct DisplayDelta: Equatable {
        let monitorsAfter: [Monitor]
        let specsAfter: [TranscriptMonitorSpec]
        let topologyEvent: WMEvent
    }

    static func materialize(_ spec: TranscriptMonitorSpec) -> Monitor {
        switch spec.slot {
        case .primary:
            return makeLayoutPlanPrimaryTestMonitor(
                name: spec.name,
                x: spec.frame.origin.x,
                y: spec.frame.origin.y,
                width: spec.frame.size.width,
                height: spec.frame.size.height
            )
        case let .secondary(slot):
            return makeLayoutPlanSecondaryTestMonitor(
                slot: slot,
                name: spec.name,
                x: spec.frame.origin.x,
                y: spec.frame.origin.y,
                width: spec.frame.size.width,
                height: spec.frame.size.height
            )
        }
    }
}
