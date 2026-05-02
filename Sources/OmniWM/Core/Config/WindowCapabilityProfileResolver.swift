// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OSLog

@MainActor
final class WindowCapabilityProfileResolver {
    private static let log = Logger(subsystem: "com.omniwm.core", category: "WindowCapabilityProfile")

    private struct BuiltInBundleRule {
        let bundleId: String
        let profile: WindowCapabilityProfile
    }

    private struct BuiltInLevelRule {
        let level: Int
        let profile: WindowCapabilityProfile
    }

    private var userOverridesByBundleId: [String: WindowCapabilityProfile] = [:]

    private let builtInBundleRules: [BuiltInBundleRule]
    private let builtInLevelRules: [BuiltInLevelRule]

    init(
        builtInBundleRules: [(String, WindowCapabilityProfile)] = WindowCapabilityProfileResolver.defaultBundleRules,
        builtInLevelRules: [(Int, WindowCapabilityProfile)] = WindowCapabilityProfileResolver.defaultLevelRules
    ) {
        self.builtInBundleRules = builtInBundleRules.map {
            BuiltInBundleRule(bundleId: $0.0, profile: $0.1)
        }
        self.builtInLevelRules = builtInLevelRules.map {
            BuiltInLevelRule(level: $0.0, profile: $0.1)
        }
    }

    func setUserOverride(bundleId: String, profile: WindowCapabilityProfile) {
        userOverridesByBundleId[bundleId] = profile
    }

    func clearUserOverride(bundleId: String) {
        userOverridesByBundleId.removeValue(forKey: bundleId)
    }

    func applyTOMLOverrides(_ overrides: [WindowCapabilityProfileTOMLOverride]) {
        var next: [String: WindowCapabilityProfile] = [:]
        for override in overrides {
            let base = builtInBundleRules.first { $0.bundleId == override.bundleId }?.profile
                ?? .standard
            next[override.bundleId] = override.merged(onTopOf: base)
        }
        userOverridesByBundleId = next
    }

    func bundleIdsWithTransient(_ treatment: WindowCapabilityProfile.TransientTreatment) -> [String] {
        var ids = Set<String>()
        let allBundleIds = Set(builtInBundleRules.map { $0.bundleId })
            .union(userOverridesByBundleId.keys)
        for bundleId in allBundleIds {
            let effective: WindowCapabilityProfile?
            if let override = userOverridesByBundleId[bundleId] {
                effective = override
            } else {
                effective = builtInBundleRules.first { $0.bundleId == bundleId }?.profile
            }
            if effective?.transient == treatment {
                ids.insert(bundleId)
            }
        }
        return ids.sorted()
    }

    static func builtInProfile(forLevel level: Int) -> WindowCapabilityProfile? {
        defaultLevelRules.first { $0.0 == level }?.1
    }

    static func builtInProfile(forBundleId bundleId: String) -> WindowCapabilityProfile? {
        defaultBundleRules.first { $0.0 == bundleId }?.1
    }

    func resolve(
        for facts: WindowRuleFacts,
        level: Int?
    ) -> (profile: WindowCapabilityProfile, source: WindowCapabilityResolutionSource) {
        var matches: [(WindowCapabilityProfile, WindowCapabilityResolutionSource)] = []

        matches.append((.standard, .builtInDefault))

        if let level, let rule = builtInLevelRules.first(where: { $0.level == level }) {
            matches.append((rule.profile, .windowLevelRule(level: level)))
        }

        if let bundleId = facts.ax.bundleId,
           let rule = builtInBundleRules.first(where: { $0.bundleId == bundleId })
        {
            matches.append((rule.profile, .bundleIdRule(bundleId: bundleId)))
        }

        if let bundleId = facts.ax.bundleId,
           let override = userOverridesByBundleId[bundleId]
        {
            let baseProfile = builtInBundleRules.first { $0.bundleId == bundleId }?.profile
                ?? .standard
            let merged = mergedProfile(base: baseProfile, override: override)
            matches.append((merged, .userOverride(bundleId: bundleId)))
        }

        let chosen = matches.max { lhs, rhs in
            if lhs.1.precedence != rhs.1.precedence {
                return lhs.1.precedence < rhs.1.precedence
            }
            return lhs.1.stableKey < rhs.1.stableKey
        }!

        Self.log.info(
            "capability_resolved bundleId=\(facts.ax.bundleId ?? "<nil>", privacy: .public) profile=\(String(describing: chosen.0), privacy: .public) source=\(String(describing: chosen.1), privacy: .public)"
        )

        return (chosen.0, chosen.1)
    }

    private func mergedProfile(
        base: WindowCapabilityProfile,
        override: WindowCapabilityProfile
    ) -> WindowCapabilityProfile {
        return override
    }
}

extension WindowCapabilityProfileResolver {
    static let defaultBundleRules: [(String, WindowCapabilityProfile)] = [
        ("com.mitchellh.ghostty", WindowCapabilityProfile(
            frameWrite: .prefersObservedFrame,
            focusActivation: .standard,
            nfrReplacement: .none,
            transient: .standard,
            restore: .standard
        )),
        ("com.tencent.xinWeChat", WindowCapabilityProfile(
            frameWrite: .reliable,
            focusActivation: .requiresActivationRecovery,
            nfrReplacement: .none,
            transient: .standard,
            restore: .standard
        )),
        ("com.apple.systempreferences", floatingProfile),
        ("com.apple.SystemPreferences", floatingProfile),
        ("com.apple.iphonesimulator", floatingProfile),
        ("com.apple.PhotoBooth", floatingProfile),
        ("com.apple.calculator", floatingProfile),
        ("com.apple.ScreenSharing", floatingProfile),
        ("com.apple.remotedesktop", floatingProfile),
        ("pl.maketheweb.cleanshotx", WindowCapabilityProfile(
            frameWrite: .reliable,
            focusActivation: .standard,
            nfrReplacement: .none,
            transient: .unmanaged,
            restore: .standard
        )),
    ]

    private static let floatingProfile = WindowCapabilityProfile(
        frameWrite: .reliable,
        focusActivation: .standard,
        nfrReplacement: .none,
        transient: .alwaysFloat,
        restore: .standard
    )

    static let defaultLevelRules: [(Int, WindowCapabilityProfile)] = [
        (103, WindowCapabilityProfile(
            frameWrite: .reliable,
            focusActivation: .standard,
            nfrReplacement: .none,
            transient: .unmanaged,
            restore: .standard
        )),
    ]
}
