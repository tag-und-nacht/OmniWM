// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing

@testable import OmniWM

@Suite(.serialized) struct WindowCapabilityProfileTests {
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
    @Test func unknownBundleResolvesToStandardDefault() {
        let resolver = WindowCapabilityProfileResolver()
        let result = resolver.resolve(for: makeFacts(bundleId: "com.example.unknown"), level: nil)
        #expect(result.profile == .standard)
        #expect(result.source == .builtInDefault)
    }

    @MainActor
    @Test func ghosttyBundleResolvesToPrefersObservedFrame() {
        let resolver = WindowCapabilityProfileResolver()
        let result = resolver.resolve(for: makeFacts(bundleId: "com.mitchellh.ghostty"), level: nil)
        #expect(result.profile.frameWrite == .prefersObservedFrame)
        #expect(result.source == .bundleIdRule(bundleId: "com.mitchellh.ghostty"))
    }

    @MainActor
    @Test func wechatBundleResolvesToRequiresActivationRecovery() {
        let resolver = WindowCapabilityProfileResolver()
        let result = resolver.resolve(for: makeFacts(bundleId: "com.tencent.xinWeChat"), level: nil)
        #expect(result.profile.focusActivation == .requiresActivationRecovery)
    }

    @MainActor
    @Test func defaultFloatingAppResolvesToAlwaysFloat() {
        let resolver = WindowCapabilityProfileResolver()
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
            let result = resolver.resolve(for: makeFacts(bundleId: bundleId), level: nil)
            #expect(result.profile.transient == .alwaysFloat,
                    "Expected \(bundleId) to resolve as .alwaysFloat")
        }
    }

    @MainActor
    @Test func cleanShotLevelRuleResolvesToUnmanaged() {
        let resolver = WindowCapabilityProfileResolver()
        let result = resolver.resolve(for: makeFacts(bundleId: nil), level: 103)
        #expect(result.profile.transient == .unmanaged)
        #expect(result.source == .windowLevelRule(level: 103))
    }

    @MainActor
    @Test func userOverrideTakesPrecedenceOverBundleRule() {
        let resolver = WindowCapabilityProfileResolver()
        let custom = WindowCapabilityProfile(
            frameWrite: .reliable,
            focusActivation: .standard,
            nfrReplacement: .none,
            transient: .standard,
            restore: .skipFrameRestore
        )
        resolver.setUserOverride(bundleId: "com.mitchellh.ghostty", profile: custom)
        let result = resolver.resolve(for: makeFacts(bundleId: "com.mitchellh.ghostty"), level: nil)
        #expect(result.profile == custom)
        #expect(result.source == .userOverride(bundleId: "com.mitchellh.ghostty"))
    }

    @MainActor
    @Test func clearOverrideRevertsToBundleRule() {
        let resolver = WindowCapabilityProfileResolver()
        let custom = WindowCapabilityProfile(
            frameWrite: .reliable,
            focusActivation: .standard,
            nfrReplacement: .none,
            transient: .standard,
            restore: .skipFrameRestore
        )
        resolver.setUserOverride(bundleId: "com.mitchellh.ghostty", profile: custom)
        resolver.clearUserOverride(bundleId: "com.mitchellh.ghostty")
        let result = resolver.resolve(for: makeFacts(bundleId: "com.mitchellh.ghostty"), level: nil)
        #expect(result.profile.frameWrite == .prefersObservedFrame)
        #expect(result.source == .bundleIdRule(bundleId: "com.mitchellh.ghostty"))
    }

    @MainActor
    @Test func resolutionIsDeterministicAcrossOrderings() {
        let r1 = WindowCapabilityProfileResolver()
        let r2 = WindowCapabilityProfileResolver()
        let facts = makeFacts(bundleId: "com.mitchellh.ghostty")
        let a = r1.resolve(for: facts, level: nil)
        let b = r2.resolve(for: facts, level: nil)
        #expect(a.profile == b.profile)
        #expect(a.source == b.source)
    }

    @MainActor
    @Test func bundleRuleBeatsWindowLevelRule() {
        let resolver = WindowCapabilityProfileResolver()
        let result = resolver.resolve(
            for: makeFacts(bundleId: "com.mitchellh.ghostty"),
            level: 103
        )
        #expect(result.source == .bundleIdRule(bundleId: "com.mitchellh.ghostty"))
    }

    @MainActor
    @Test func levelRuleAppliesWhenNoBundleMatch() {
        let resolver = WindowCapabilityProfileResolver()
        let result = resolver.resolve(
            for: makeFacts(bundleId: "com.example.unknown"),
            level: 103
        )
        #expect(result.source == .windowLevelRule(level: 103))
    }
}
