// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct TopologyFingerprintCompletenessTests {
    private static func makeMonitor(
        displayId: CGDirectDisplayID = 1,
        name: String = "Main",
        frame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect? = nil,
        hasNotch: Bool = false
    ) -> Monitor {
        Monitor(
            id: Monitor.ID(displayId: displayId),
            displayId: displayId,
            frame: frame,
            visibleFrame: visibleFrame ?? frame,
            hasNotch: hasNotch,
            name: name
        )
    }

    @Test func fingerprintsDifferOnVisibleFrameChangeWithIdenticalFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let withoutMenuBar = Self.makeMonitor(frame: frame, visibleFrame: frame)
        let withMenuBar = Self.makeMonitor(
            frame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056)
        )

        let fpA = DisplayFingerprint(monitor: withoutMenuBar)
        let fpB = DisplayFingerprint(monitor: withMenuBar)

        #expect(fpA != fpB)
    }

    @Test func fingerprintsDifferOnHasNotchChange() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let withoutNotch = Self.makeMonitor(frame: frame, hasNotch: false)
        let withNotch = Self.makeMonitor(frame: frame, hasNotch: true)

        let fpA = DisplayFingerprint(monitor: withoutNotch)
        let fpB = DisplayFingerprint(monitor: withNotch)

        #expect(fpA != fpB)
    }

    @Test func fingerprintsAreEqualForIdenticalGeometry() {
        let monitor = Self.makeMonitor()
        let fpA = DisplayFingerprint(monitor: monitor)
        let fpB = DisplayFingerprint(monitor: monitor)
        #expect(fpA == fpB)
    }

    @Test @MainActor func applyMonitorConfigurationChangeBumpsEpochOnVisibleFrameOnlyChange() {
        resetSharedControllerStateForTests()
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let runtime = WMRuntime(settings: settings)

        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let initial = Self.makeMonitor(frame: frame, visibleFrame: frame)
        runtime.applyMonitorConfigurationChange([initial])
        let firstEpoch = runtime.currentTopologyEpoch
        #expect(firstEpoch.isValid)

        let dockShown = Self.makeMonitor(
            frame: frame,
            visibleFrame: CGRect(x: 0, y: 100, width: 1920, height: 980)
        )
        runtime.applyMonitorConfigurationChange([dockShown])
        #expect(runtime.currentTopologyEpoch > firstEpoch)
    }

    @Test @MainActor func applyMonitorConfigurationChangeBumpsEpochOnNotchOnlyChange() {
        resetSharedControllerStateForTests()
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let runtime = WMRuntime(settings: settings)

        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let initial = Self.makeMonitor(frame: frame, hasNotch: false)
        runtime.applyMonitorConfigurationChange([initial])
        let firstEpoch = runtime.currentTopologyEpoch
        #expect(firstEpoch.isValid)

        let withNotch = Self.makeMonitor(frame: frame, hasNotch: true)
        runtime.applyMonitorConfigurationChange([withNotch])
        #expect(runtime.currentTopologyEpoch > firstEpoch)
    }

    @Test @MainActor func applyMonitorConfigurationChangeStillNoOpForFullyIdenticalMonitors() {
        resetSharedControllerStateForTests()
        let settings = SettingsStore(defaults: makeLayoutPlanTestDefaults())
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        let runtime = WMRuntime(settings: settings)

        let monitors = [Self.makeMonitor()]
        runtime.applyMonitorConfigurationChange(monitors)
        let firstEpoch = runtime.currentTopologyEpoch

        runtime.applyMonitorConfigurationChange(monitors)
        #expect(runtime.currentTopologyEpoch == firstEpoch)
    }
}
