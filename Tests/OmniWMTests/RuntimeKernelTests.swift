// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Testing
@testable import OmniWM

@Suite("RuntimeKernel")
@MainActor
struct RuntimeKernelTests {
    @Test func transactionEpochsAreStrictlyMonotonic() {
        let kernel = RuntimeKernel()
        let first = kernel.allocateTransactionEpoch()
        let second = kernel.allocateTransactionEpoch()
        let third = kernel.allocateTransactionEpoch()

        #expect(first.value == 1)
        #expect(second.value == 2)
        #expect(third.value == 3)
        #expect(first < second)
        #expect(second < third)
    }

    @Test func effectEpochsAreStrictlyMonotonic() {
        let kernel = RuntimeKernel()
        let first = kernel.allocateEffectEpoch()
        let second = kernel.allocateEffectEpoch()
        let third = kernel.allocateEffectEpoch()

        #expect(first.value == 1)
        #expect(second.value == 2)
        #expect(third.value == 3)
        #expect(first < second)
    }

    @Test func transactionAndEffectCountersAreIndependent() {
        let kernel = RuntimeKernel()
        _ = kernel.allocateTransactionEpoch()
        _ = kernel.allocateTransactionEpoch()
        let firstEffect = kernel.allocateEffectEpoch()
        #expect(firstEffect.value == 1)
    }

    @Test func topologyEpochsAdvanceCurrentTopologyEpoch() {
        let kernel = RuntimeKernel()
        #expect(kernel.currentTopologyEpoch == .invalid)

        let first = kernel.allocateTopologyEpoch()
        #expect(first.value == 1)
        #expect(kernel.currentTopologyEpoch == first)

        let second = kernel.allocateTopologyEpoch()
        #expect(second.value == 2)
        #expect(kernel.currentTopologyEpoch == second)
    }

    @Test func elapsedMicrosIsNonNegative() {
        let start = ContinuousClock.now
        let elapsed = RuntimeKernel.elapsedMicros(since: start)
        #expect(elapsed >= 0)
    }

    @Test func separateKernelsHaveIndependentCounters() {
        let kernelA = RuntimeKernel()
        let kernelB = RuntimeKernel()
        let aTxn = kernelA.allocateTransactionEpoch()
        _ = kernelA.allocateTransactionEpoch()
        let bTxn = kernelB.allocateTransactionEpoch()

        #expect(aTxn.value == 1)
        #expect(bTxn.value == 1)
    }
}
