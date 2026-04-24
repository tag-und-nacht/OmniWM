// SPDX-License-Identifier: GPL-2.0-only
@MainActor protocol LayoutFocusable: AnyObject {
    func focusNeighbor(direction: Direction, source: WMEventSource)
}

@MainActor protocol LayoutSizable: AnyObject {
    func cycleSize(forward: Bool, source: WMEventSource)
    func balanceSizes(source: WMEventSource)
}
