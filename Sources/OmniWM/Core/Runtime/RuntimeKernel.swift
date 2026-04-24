// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import OSLog

/// Shared infrastructure for the runtime: epoch counters, the intake
/// signposter, the intake logger, and the elapsed-time helper.
///
/// Extracted from `WMRuntime` (ExecPlan 02, slice WRT-DS-01) so per-domain
/// runtimes (`FocusRuntime`, `FrameRuntime`, etc.) can share one source of
/// transaction / effect / topology epochs without each carrying its own
/// counter. The kernel is the *only* place epochs are minted; domain
/// runtimes call into it.
///
/// Thread / actor: this type is not @MainActor on its own; it is held
/// privately by `WMRuntime` (which IS @MainActor), so all access is
/// effectively serialized. Counters use `&+=` overflow-wrap for stability;
/// 2^64 epochs in one session is structurally unreachable, but the same
/// "crash on overflow" treatment that `LogicalWindowRegistry` uses is
/// applied here for parity.
@MainActor
final class RuntimeKernel {
    let intakeLog: Logger
    let intakeSignpost: OSSignposter

    private var nextTransactionEpochValue: UInt64 = 1
    private var nextEffectEpochValue: UInt64 = 1
    private var nextTopologyEpochValue: UInt64 = 1
    private(set) var currentTopologyEpoch: TopologyEpoch = .invalid

    init(
        intakeSubsystem: String = "com.omniwm.core",
        intakeCategory: String = "WMRuntime.intake"
    ) {
        intakeLog = Logger(subsystem: intakeSubsystem, category: intakeCategory)
        intakeSignpost = OSSignposter(subsystem: intakeSubsystem, category: intakeCategory)
    }

    /// Mint a strictly-monotonic transaction epoch.
    func allocateTransactionEpoch() -> TransactionEpoch {
        guard nextTransactionEpochValue < UInt64.max else {
            preconditionFailure("TransactionEpoch space exhausted (UInt64 saturation)")
        }
        let value = nextTransactionEpochValue
        nextTransactionEpochValue &+= 1
        return TransactionEpoch(value: value)
    }

    /// Mint a strictly-monotonic effect epoch.
    func allocateEffectEpoch() -> EffectEpoch {
        guard nextEffectEpochValue < UInt64.max else {
            preconditionFailure("EffectEpoch space exhausted (UInt64 saturation)")
        }
        let value = nextEffectEpochValue
        nextEffectEpochValue &+= 1
        return EffectEpoch(value: value)
    }

    /// Mint a strictly-monotonic topology epoch and stamp it as the
    /// `currentTopologyEpoch`. Display-reconfigure paths hold the returned
    /// epoch and pass it down through topology projection so consumers can
    /// detect stale projections.
    @discardableResult
    func allocateTopologyEpoch() -> TopologyEpoch {
        guard nextTopologyEpochValue < UInt64.max else {
            preconditionFailure("TopologyEpoch space exhausted (UInt64 saturation)")
        }
        let value = nextTopologyEpochValue
        nextTopologyEpochValue &+= 1
        let epoch = TopologyEpoch(value: value)
        currentTopologyEpoch = epoch
        return epoch
    }

    /// Microseconds elapsed since `start`, derived from `ContinuousClock`
    /// for monotonic timing (per CLAUDE.md "no wall-clock for latency").
    static func elapsedMicros(since start: ContinuousClock.Instant) -> Int64 {
        let elapsed = ContinuousClock.now - start
        let (seconds, attoseconds) = elapsed.components
        let micros = seconds &* 1_000_000 &+ attoseconds / 1_000_000_000_000
        return micros
    }
}
