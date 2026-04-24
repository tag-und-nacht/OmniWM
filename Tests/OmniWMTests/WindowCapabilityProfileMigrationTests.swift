// SPDX-License-Identifier: GPL-2.0-only
import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct WindowCapabilityProfileMigrationTests {
    @MainActor
    private func makeFacts(bundleId: String?) -> WindowRuleFacts {
        WindowRuleFacts(
            appName: nil,
            ax: AXWindowFacts(
                role: nil,
                subrole: nil,
                title: nil,
                hasCloseButton: false,
                hasFullscreenButton: false,
                fullscreenButtonEnabled: nil,
                hasZoomButton: false,
                hasMinimizeButton: false,
                appPolicy: nil,
                bundleId: bundleId,
                attributeFetchSucceeded: false
            ),
            sizeConstraints: nil,
            windowServer: nil
        )
    }

    @MainActor
    private func makeRecordingOverlayFacts(
        bundleId: String,
        subrole: String = kAXStandardWindowSubrole as String,
        level: Int32 = 103
    ) -> WindowRuleFacts {
        WindowRuleFacts(
            appName: nil,
            ax: AXWindowFacts(
                role: kAXWindowRole as String,
                subrole: subrole,
                title: nil,
                hasCloseButton: false,
                hasFullscreenButton: false,
                fullscreenButtonEnabled: nil,
                hasZoomButton: false,
                hasMinimizeButton: false,
                appPolicy: nil,
                bundleId: bundleId,
                attributeFetchSucceeded: true
            ),
            sizeConstraints: nil,
            windowServer: WindowServerInfo(
                id: 1,
                pid: 1,
                level: level,
                frame: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
        )
    }

    @MainActor
    @Test func ghosttyResolvesToPrefersObservedFrame() {
        let resolver = WindowCapabilityProfileResolver()
        let result = resolver.resolve(for: makeFacts(bundleId: "com.mitchellh.ghostty"), level: nil)
        #expect(result.profile.frameWrite == .prefersObservedFrame)
    }

    @MainActor
    @Test func nonGhosttyAppDoesNotPreferObservedFrame() {
        let resolver = WindowCapabilityProfileResolver()
        let result = resolver.resolve(for: makeFacts(bundleId: "com.example.regular-app"), level: nil)
        #expect(result.profile.frameWrite == .reliable)
    }

    @MainActor
    @Test func wechatMigrationFlagsRequiresActivationRecovery() {
        let resolver = WindowCapabilityProfileResolver()
        let result = resolver.resolve(for: makeFacts(bundleId: "com.tencent.xinWeChat"), level: nil)
        #expect(result.profile.focusActivation == .requiresActivationRecovery)
    }

    @MainActor
    @Test func nonWeChatAppDoesNotRequireActivationRecovery() {
        let resolver = WindowCapabilityProfileResolver()
        let result = resolver.resolve(for: makeFacts(bundleId: "com.apple.calculator"), level: nil)
        #expect(result.profile.focusActivation == .standard)
    }

    @MainActor
    @Test func defaultBundleRulesDoNotExpectNFRReplacement() {
        let resolver = WindowCapabilityProfileResolver()
        for (bundleId, _) in WindowCapabilityProfileResolver.defaultBundleRules {
            let result = resolver.resolve(for: makeFacts(bundleId: bundleId), level: nil)
            #expect(result.profile.nfrReplacement == .none,
                    "Bundle \(bundleId) unexpectedly flagged for NFR replacement")
        }
    }

    @MainActor
    @Test func expectsReplacementProfileAttemptsMatchWithoutPendingTransition() {
        let resolver = WindowCapabilityProfileResolver()
        let bundleId = "com.example.fullscreen-replacement-app"
        let override = WindowCapabilityProfileTOMLOverride(
            bundleId: bundleId,
            frameWrite: nil,
            focusActivation: nil,
            nfrReplacement: .expectsReplacementWindow,
            transient: nil,
            restore: nil
        )
        resolver.applyTOMLOverrides([override])
        let resolved = resolver.resolve(for: makeFacts(bundleId: bundleId), level: nil).profile
        #expect(resolved.shouldAttemptNativeFullscreenReplacementMatch(
            hasPendingTransition: false
        ))
        #expect(resolved.shouldAttemptNativeFullscreenReplacementMatch(
            hasPendingTransition: true
        ))
    }

    @MainActor
    @Test func standardProfileSkipsMatchWithoutPendingTransition() {
        let resolver = WindowCapabilityProfileResolver()
        let resolved = resolver.resolve(
            for: makeFacts(bundleId: "com.example.regular-app"),
            level: nil
        ).profile
        #expect(resolved.nfrReplacement == .none)
        #expect(!resolved.shouldAttemptNativeFullscreenReplacementMatch(
            hasPendingTransition: false
        ))
    }

    @MainActor
    @Test func standardProfileAttemptsMatchWithPendingTransition() {
        let resolver = WindowCapabilityProfileResolver()
        let resolved = resolver.resolve(
            for: makeFacts(bundleId: "com.example.regular-app"),
            level: nil
        ).profile
        #expect(resolved.shouldAttemptNativeFullscreenReplacementMatch(
            hasPendingTransition: true
        ))
    }

    @MainActor
    @Test func skipFrameRestoreProfileReportsSkip() {
        let resolver = WindowCapabilityProfileResolver()
        let bundleId = "com.example.relaunch-repositioner"
        let override = WindowCapabilityProfileTOMLOverride(
            bundleId: bundleId,
            frameWrite: nil,
            focusActivation: nil,
            nfrReplacement: nil,
            transient: nil,
            restore: .skipFrameRestore
        )
        resolver.applyTOMLOverrides([override])
        let resolved = resolver.resolve(for: makeFacts(bundleId: bundleId), level: nil).profile
        #expect(resolved.shouldSkipNativeFullscreenFrameRestore)
    }

    @MainActor
    @Test func standardProfilePreservesFrameRestore() {
        let resolver = WindowCapabilityProfileResolver()
        let resolved = resolver.resolve(
            for: makeFacts(bundleId: "com.example.regular-app"),
            level: nil
        ).profile
        #expect(resolved.restore == .standard)
        #expect(!resolved.shouldSkipNativeFullscreenFrameRestore)
    }

    @MainActor
    private func nativeFullscreenRestoreContext(
        bundleId: String,
        restoreHandling: WindowCapabilityProfile.RestoreHandling,
        windowId: Int
    ) -> NativeFullscreenRestoreContext? {
        let controller = makeLayoutPlanTestController()
        guard let runtime = controller.runtime,
              let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing runtime fixture for CAP-07 restore-context consumer test")
            return nil
        }

        runtime.capabilityProfileResolver.applyTOMLOverrides([
            WindowCapabilityProfileTOMLOverride(
                bundleId: bundleId,
                frameWrite: nil,
                focusActivation: nil,
                nfrReplacement: nil,
                transient: nil,
                restore: restoreHandling
            )
        ])

        let token = addLayoutPlanTestWindow(
            on: controller,
            workspaceId: workspaceId,
            windowId: windowId
        )
        let restorableFrame = CGRect(x: 120, y: 80, width: 900, height: 640)
        let frameStateFrame = FrameState.Frame(
            rect: restorableFrame,
            space: .appKit,
            isVisibleFrame: true
        )
        #expect(controller.workspaceManager.recordDesiredFrame(frameStateFrame, for: token))
        #expect(controller.workspaceManager.recordObservedFrame(frameStateFrame, for: token))

        let restoreSnapshot = WorkspaceManager.NativeFullscreenRecord.RestoreSnapshot(
            frame: restorableFrame,
            topologyProfile: controller.workspaceManager.topologyProfile,
            replacementMetadata: ManagedReplacementMetadata(
                bundleId: bundleId,
                workspaceId: workspaceId,
                mode: .tiling,
                role: "AXWindow",
                subrole: "AXStandardWindow",
                title: "CAP-07 Restore Consumer",
                windowLevel: 0,
                parentWindowId: nil,
                frame: restorableFrame
            )
        )

        _ = controller.workspaceManager.requestNativeFullscreenEnter(
            token,
            in: workspaceId,
            restoreSnapshot: restoreSnapshot
        )
        _ = controller.workspaceManager.markNativeFullscreenSuspended(
            token,
            restoreSnapshot: restoreSnapshot
        )
        _ = controller.workspaceManager.requestNativeFullscreenExit(
            token,
            initiatedByCommand: true
        )
        _ = controller.workspaceManager.beginNativeFullscreenRestore(for: token)
        return controller.workspaceManager.nativeFullscreenRestoreContext(for: token)
    }

    @MainActor
    @Test func skipFrameRestoreOverrideDropsRestoreContextFrame() {
        let context = nativeFullscreenRestoreContext(
            bundleId: "com.example.relaunch-repositioner",
            restoreHandling: .skipFrameRestore,
            windowId: 7_701
        )
        #expect(context != nil)
        #expect(context?.restoreFrame == nil)
    }

    @MainActor
    @Test func standardRestoreHandlingPreservesRestoreContextFrame() {
        let context = nativeFullscreenRestoreContext(
            bundleId: "com.example.standard-restore-app",
            restoreHandling: .standard,
            windowId: 7_702
        )
        #expect(context != nil)
        #expect(context?.restoreFrame == CGRect(x: 120, y: 80, width: 900, height: 640))
    }

    @MainActor
    @Test func defaultBundleRulesDoNotSkipFrameRestore() {
        let resolver = WindowCapabilityProfileResolver()
        for (bundleId, _) in WindowCapabilityProfileResolver.defaultBundleRules {
            let result = resolver.resolve(for: makeFacts(bundleId: bundleId), level: nil)
            #expect(!result.profile.shouldSkipNativeFullscreenFrameRestore,
                    "Bundle \(bundleId) unexpectedly flagged for skipFrameRestore")
        }
    }

    @MainActor
    @Test func tomlOverrideMergesPartialFieldsOnTopOfBuiltIn() {
        let resolver = WindowCapabilityProfileResolver()
        let override = WindowCapabilityProfileTOMLOverride(
            bundleId: "com.mitchellh.ghostty",
            frameWrite: nil,
            focusActivation: .requiresExplicitActivation,
            nfrReplacement: nil,
            transient: nil,
            restore: nil
        )
        resolver.applyTOMLOverrides([override])
        let result = resolver.resolve(for: makeFacts(bundleId: "com.mitchellh.ghostty"), level: nil)
        #expect(result.profile.focusActivation == .requiresExplicitActivation)
        #expect(result.profile.frameWrite == .prefersObservedFrame)
        #expect(result.source == .userOverride(bundleId: "com.mitchellh.ghostty"))
    }

    @MainActor
    @Test func tomlOverrideReplaceClearsRemovedEntries() {
        let resolver = WindowCapabilityProfileResolver()
        let override = WindowCapabilityProfileTOMLOverride(
            bundleId: "com.mitchellh.ghostty",
            frameWrite: nil,
            focusActivation: .requiresExplicitActivation,
            nfrReplacement: nil,
            transient: nil,
            restore: nil
        )
        resolver.applyTOMLOverrides([override])
        resolver.applyTOMLOverrides([])
        let result = resolver.resolve(for: makeFacts(bundleId: "com.mitchellh.ghostty"), level: nil)
        #expect(result.profile.focusActivation == .standard)
        #expect(result.source == .bundleIdRule(bundleId: "com.mitchellh.ghostty"))
    }


    @MainActor
    @Test func userOverrideFlipsBundleToFloatingViaRuleEngine() {
        let resolver = WindowCapabilityProfileResolver()
        let engine = WindowRuleEngine()
        engine.setCapabilityResolver(resolver)
        let bundleId = "com.example.user-floats-this"

        let preDecision = engine.decision(
            for: makeFacts(bundleId: bundleId),
            token: nil,
            appFullscreen: false
        )
        #expect(preDecision.disposition != .floating || preDecision.source != .builtInRule("defaultFloatingApp"))

        resolver.applyTOMLOverrides([
            WindowCapabilityProfileTOMLOverride(
                bundleId: bundleId,
                frameWrite: nil,
                focusActivation: nil,
                nfrReplacement: nil,
                transient: .alwaysFloat,
                restore: nil
            )
        ])
        engine.refreshCapabilityRules()

        let postDecision = engine.decision(
            for: makeFacts(bundleId: bundleId),
            token: nil,
            appFullscreen: false
        )
        #expect(postDecision.disposition == .floating)
        #expect(postDecision.source == .builtInRule("defaultFloatingApp"))
    }

    @MainActor
    @Test func userOverrideRemovesBuiltInFloatingBundle() {
        let resolver = WindowCapabilityProfileResolver()
        let engine = WindowRuleEngine()
        engine.setCapabilityResolver(resolver)
        let calculator = "com.apple.calculator"

        let baseline = engine.decision(
            for: makeFacts(bundleId: calculator),
            token: nil,
            appFullscreen: false
        )
        #expect(baseline.disposition == .floating)
        #expect(baseline.source == .builtInRule("defaultFloatingApp"))

        resolver.applyTOMLOverrides([
            WindowCapabilityProfileTOMLOverride(
                bundleId: calculator,
                frameWrite: nil,
                focusActivation: nil,
                nfrReplacement: nil,
                transient: .standard,
                restore: nil
            )
        ])
        engine.refreshCapabilityRules()

        let after = engine.decision(
            for: makeFacts(bundleId: calculator),
            token: nil,
            appFullscreen: false
        )
        #expect(after.source != .builtInRule("defaultFloatingApp"))
    }

    @MainActor
    @Test func cleanShotRecordingOverlayPreservedThroughResolver() {
        let resolver = WindowCapabilityProfileResolver()
        let engine = WindowRuleEngine()
        engine.setCapabilityResolver(resolver)

        let decision = engine.decision(
            for: makeRecordingOverlayFacts(bundleId: WindowRuleEngine.cleanShotBundleId),
            token: nil,
            appFullscreen: false
        )
        #expect(decision.disposition == .unmanaged)
        #expect(decision.source == .builtInRule("cleanShotRecordingOverlay"))
    }

    @MainActor
    @Test func nonCleanShotBundleAtLevel103IsNotRecordingOverlay() {
        let resolver = WindowCapabilityProfileResolver()
        let engine = WindowRuleEngine()
        engine.setCapabilityResolver(resolver)

        let decision = engine.decision(
            for: makeRecordingOverlayFacts(bundleId: "com.example.unrelated"),
            token: nil,
            appFullscreen: false
        )
        #expect(decision.source != .builtInRule("cleanShotRecordingOverlay"))
    }

    @MainActor
    @Test func userOverrideOnCleanShotFlipsRecordingOverlayBackToManaged() {
        let resolver = WindowCapabilityProfileResolver()
        let engine = WindowRuleEngine()
        engine.setCapabilityResolver(resolver)
        resolver.applyTOMLOverrides([
            WindowCapabilityProfileTOMLOverride(
                bundleId: WindowRuleEngine.cleanShotBundleId,
                frameWrite: nil,
                focusActivation: nil,
                nfrReplacement: nil,
                transient: .standard,
                restore: nil
            )
        ])
        engine.refreshCapabilityRules()

        let decision = engine.decision(
            for: makeRecordingOverlayFacts(bundleId: WindowRuleEngine.cleanShotBundleId),
            token: nil,
            appFullscreen: false
        )
        #expect(decision.source != .builtInRule("cleanShotRecordingOverlay"))
    }

    @MainActor
    @Test func userOverrideUnmanagedAtLevel103IsRecordingOverlay() {
        let resolver = WindowCapabilityProfileResolver()
        let engine = WindowRuleEngine()
        engine.setCapabilityResolver(resolver)
        let bundleId = "com.example.user-unmanaged-overlay"
        resolver.applyTOMLOverrides([
            WindowCapabilityProfileTOMLOverride(
                bundleId: bundleId,
                frameWrite: nil,
                focusActivation: nil,
                nfrReplacement: nil,
                transient: .unmanaged,
                restore: nil
            )
        ])
        engine.refreshCapabilityRules()

        let decision = engine.decision(
            for: makeRecordingOverlayFacts(bundleId: bundleId),
            token: nil,
            appFullscreen: false
        )
        #expect(decision.disposition == .unmanaged)
        #expect(decision.source == .builtInRule("cleanShotRecordingOverlay"))
    }

    @MainActor
    @Test func cleanShotBundleAtNonOverlayLevelIsNotRecordingOverlay() {
        let resolver = WindowCapabilityProfileResolver()
        let engine = WindowRuleEngine()
        engine.setCapabilityResolver(resolver)

        let decision = engine.decision(
            for: makeRecordingOverlayFacts(
                bundleId: WindowRuleEngine.cleanShotBundleId,
                level: 0
            ),
            token: nil,
            appFullscreen: false
        )
        #expect(decision.source != .builtInRule("cleanShotRecordingOverlay"))
    }

    @MainActor
    @Test func cleanShotBundleWithNonStandardSubroleIsNotRecordingOverlay() {
        let resolver = WindowCapabilityProfileResolver()
        let engine = WindowRuleEngine()
        engine.setCapabilityResolver(resolver)

        let decision = engine.decision(
            for: makeRecordingOverlayFacts(
                bundleId: WindowRuleEngine.cleanShotBundleId,
                subrole: kAXFloatingWindowSubrole as String
            ),
            token: nil,
            appFullscreen: false
        )
        #expect(decision.source != .builtInRule("cleanShotRecordingOverlay"))
    }

    @MainActor
    @Test func bareEngineWithoutResolverFallsBackToStaticBuiltInRules() {
        let engine = WindowRuleEngine()
        let canonicalFloatingBundles: Set<String> = [
            "com.apple.systempreferences",
            "com.apple.SystemPreferences",
            "com.apple.iphonesimulator",
            "com.apple.PhotoBooth",
            "com.apple.calculator",
            "com.apple.ScreenSharing",
            "com.apple.remotedesktop"
        ]
        for bundleId in canonicalFloatingBundles {
            let decision = engine.decision(
                for: makeFacts(bundleId: bundleId),
                token: nil,
                appFullscreen: false
            )
            #expect(decision.disposition == .floating,
                    "Static fallback dropped built-in floating for \(bundleId)")
            #expect(decision.source == .builtInRule("defaultFloatingApp"))
        }
    }

    @MainActor
    @Test func runtimeApplyConfigurationPropagatesOverridesToRuleEngine() {
        let runtime = makeMigrationTestRuntime()
        let bundleId = "com.example.runtime-floats-this"

        let preDecision = runtime.controller.windowRuleEngine.decision(
            for: makeFacts(bundleId: bundleId),
            token: nil,
            appFullscreen: false
        )
        #expect(preDecision.source != .builtInRule("defaultFloatingApp"))

        runtime.settings.capabilityOverrides = [
            WindowCapabilityProfileTOMLOverride(
                bundleId: bundleId,
                frameWrite: nil,
                focusActivation: nil,
                nfrReplacement: nil,
                transient: .alwaysFloat,
                restore: nil
            )
        ]
        runtime.applyCurrentConfiguration()

        let postDecision = runtime.controller.windowRuleEngine.decision(
            for: makeFacts(bundleId: bundleId),
            token: nil,
            appFullscreen: false
        )
        #expect(postDecision.disposition == .floating)
        #expect(postDecision.source == .builtInRule("defaultFloatingApp"))
    }
}

@MainActor
private var _retainedMigrationTestRuntimes: [WMRuntime] = []

@MainActor
private func makeMigrationTestRuntime() -> WMRuntime {
    resetSharedControllerStateForTests()
    let suiteName = "com.omniwm.capability-migration.test.\(UUID().uuidString)"
    let settings = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
    settings.workspaceConfigurations = [
        WorkspaceConfiguration(name: "1", monitorAssignment: .main)
    ]
    let runtime = WMRuntime(settings: settings)
    _retainedMigrationTestRuntimes.append(runtime)
    runtime.workspaceManager.applyMonitorConfigurationChange([
        makeLayoutPlanTestMonitor()
    ])
    return runtime
}
