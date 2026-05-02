// SPDX-License-Identifier: GPL-2.0-only
import AppKit
import CoreGraphics
import Foundation

@MainActor
final class DisplayConfigurationObserver: NSObject {
    enum DisplayEvent: Sendable {
        case connected(Monitor)
        case disconnected(Monitor.ID, OutputId)
        case reconfigured(Monitor)
    }

    typealias EventHandler = @MainActor (DisplayEvent) -> Void

    private var onEvent: EventHandler?
    private var previousMonitors: [Monitor.ID: (monitor: Monitor, outputId: OutputId)] = [:]
    private var debounceTask: Task<Void, Never>?

    // 100 ms — `NSApplication.didChangeScreenParametersNotification` fires
    // multiple times per real reconfigure (lid open, resolution change, dock
    // arrangement) within ~50 ms; 100 ms covers the burst with measured
    // headroom and stays well under perceived-input latency.
    private let debounceIntervalNanoseconds: UInt64 = 100_000_000

    override nonisolated init() {
        super.init()
        MainActor.assumeIsolated {
            ScreenCoordinateSpace.invalidateDisplaySnapshot()
            self.updatePreviousMonitors()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setEventHandler(_ handler: @escaping EventHandler) {
        onEvent = handler
    }

    @objc nonisolated private func screensDidChange() {
        Task { @MainActor [weak self] in
            self?.debouncedScreenChange()
        }
    }

    private func debouncedScreenChange() {
        debounceTask?.cancel()

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: debounceIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            handleDisplayChange()
        }
    }

    private func handleDisplayChange() {
        ScreenCoordinateSpace.invalidateDisplaySnapshot()
        let currentMonitors = Monitor.current()
        let currentById = Dictionary(uniqueKeysWithValues: currentMonitors.map { ($0.id, $0) })
        let currentIds = Set(currentById.keys)
        let previousIds = Set(previousMonitors.keys)

        let disconnectedIds = previousIds.subtracting(currentIds)
        for monitorId in disconnectedIds {
            if let prev = previousMonitors[monitorId] {
                onEvent?(.disconnected(monitorId, prev.outputId))
            }
        }

        let connectedIds = currentIds.subtracting(previousIds)
        for monitorId in connectedIds {
            if let monitor = currentById[monitorId] {
                onEvent?(.connected(monitor))
            }
        }

        let existingIds = currentIds.intersection(previousIds)
        for monitorId in existingIds {
            guard let current = currentById[monitorId],
                  let previous = previousMonitors[monitorId]?.monitor else { continue }

            if current.frame != previous.frame || current.visibleFrame != previous.visibleFrame {
                onEvent?(.reconfigured(current))
            }
        }

        updatePreviousMonitors()
    }

    private func updatePreviousMonitors() {
        previousMonitors = Dictionary(uniqueKeysWithValues:
            Monitor.current().map {
                ($0.id, (monitor: $0, outputId: OutputId(from: $0)))
            }
        )
    }
}
