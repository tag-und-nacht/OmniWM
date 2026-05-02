// SPDX-License-Identifier: GPL-2.0-only
import Foundation

/// Per-domain runtime for window capability classification (the
/// `WindowCapabilityProfile` resolver, built-in floating list, user
/// override merging). The resolver itself is its own type
/// (`WindowCapabilityProfileResolver`); this runtime is a thin facade that
/// gives the runtime layer a uniform shape with the other domains.
///
/// Scaffold landing for ExecPlan 02 slice WRT-DS-07. Heavier method
/// migrations from `WMRuntime` (`applyConfiguration`, capability-resolver
/// wiring into `WindowRuleEngine`, the configuration reload path) follow
/// as individual mini-slices because they touch the SettingsStore +
/// controller wiring.
@MainActor
final class CapabilityRuntime {
    private let kernel: RuntimeKernel
    private unowned let resolver: WindowCapabilityProfileResolver

    init(
        kernel: RuntimeKernel,
        resolver: WindowCapabilityProfileResolver
    ) {
        self.kernel = kernel
        self.resolver = resolver
    }

    // MARK: Read surface

    /// Resolve the capability profile for the given window facts, with the
    /// optional CG window level applied. Used by the rule engine and the
    /// AX admission path.
    func resolve(
        for facts: WindowRuleFacts,
        level: Int?
    ) -> (profile: WindowCapabilityProfile, source: WindowCapabilityResolutionSource) {
        resolver.resolve(for: facts, level: level)
    }

    /// Bundle ids that the resolver classifies under the given transient
    /// treatment (e.g., `.alwaysFloat`). Used by the rule engine to build
    /// its built-in floating list.
    func bundleIds(withTransient treatment: WindowCapabilityProfile.TransientTreatment) -> [String] {
        resolver.bundleIdsWithTransient(treatment)
    }
}
