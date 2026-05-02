// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Testing
@testable import OmniWM

@Suite("MonitorIndexCache")
struct MonitorIndexCacheTests {
    private func makeMonitor(
        displayId: CGDirectDisplayID,
        name: String,
        x: CGFloat = 0,
        y: CGFloat = 0,
        width: CGFloat = 1920,
        height: CGFloat = 1080
    ) -> Monitor {
        let frame = CGRect(x: x, y: y, width: width, height: height)
        return Monitor(
            id: Monitor.ID(displayId: displayId),
            displayId: displayId,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: name
        )
    }

    @Test func rebuildPopulatesByIdAndByName() {
        var cache = MonitorIndexCache()
        let main = makeMonitor(displayId: 1, name: "Main", x: 0, y: 0)
        let aux = makeMonitor(displayId: 2, name: "Aux", x: 1920, y: 0)
        cache.rebuild(from: [main, aux])

        #expect(cache.monitor(byId: main.id) == main)
        #expect(cache.monitor(byId: aux.id) == aux)
        #expect(cache.monitor(named: "Main") == main)
        #expect(cache.monitor(named: "Aux") == aux)
    }

    @Test func ambiguousNameDisambiguates() {
        var cache = MonitorIndexCache()
        let left = makeMonitor(displayId: 1, name: "External", x: 0, y: 0)
        let right = makeMonitor(displayId: 2, name: "External", x: 1920, y: 0)
        cache.rebuild(from: [left, right])

        #expect(cache.monitor(named: "External") == nil)
        #expect(cache.monitors(named: "External").count == 2)
    }

    @Test func sameNameMonitorsSortedByPosition() {
        var cache = MonitorIndexCache()
        let right = makeMonitor(displayId: 2, name: "External", x: 1920, y: 0)
        let left = makeMonitor(displayId: 1, name: "External", x: 0, y: 0)
        cache.rebuild(from: [right, left])

        let sorted = cache.monitors(named: "External")
        #expect(sorted.count == 2)
        #expect(sorted[0].id == left.id)
        #expect(sorted[1].id == right.id)
    }

    @Test func rebuildReplacesPriorState() {
        var cache = MonitorIndexCache()
        let main = makeMonitor(displayId: 1, name: "Main")
        cache.rebuild(from: [main])
        #expect(cache.monitor(byId: main.id) == main)

        let aux = makeMonitor(displayId: 2, name: "Aux")
        cache.rebuild(from: [aux])
        #expect(cache.monitor(byId: main.id) == nil)
        #expect(cache.monitor(byId: aux.id) == aux)
        #expect(cache.monitor(named: "Main") == nil)
    }

    @Test func emptyMonitorListProducesEmptyIndexes() {
        var cache = MonitorIndexCache()
        cache.rebuild(from: [])
        #expect(cache.monitor(byId: Monitor.ID(displayId: 1)) == nil)
        #expect(cache.monitor(named: "Anywhere") == nil)
        #expect(cache.monitors(named: "Anywhere").isEmpty)
    }
}
