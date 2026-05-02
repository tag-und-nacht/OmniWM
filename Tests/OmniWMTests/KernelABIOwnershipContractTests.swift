// SPDX-License-Identifier: GPL-2.0-only

import COmniWMKernels
import Foundation
import Testing


private func bytes<T>(of value: T) -> [UInt8] {
    var local = value
    return withUnsafeBytes(of: &local) { Array($0) }
}

private func areEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
    lhs.count == rhs.count && lhs.elementsEqual(rhs)
}


@Suite struct KernelABIWindowDecisionOwnershipTests {
    private func makeInput() -> omniwm_window_decision_input {
        omniwm_window_decision_input(
            matched_user_rule: omniwm_window_decision_rule_summary(
                action: UInt32(OMNIWM_WINDOW_DECISION_RULE_ACTION_NONE),
                has_match: 0
            ),
            matched_built_in_rule: omniwm_window_decision_built_in_rule_summary(
                action: UInt32(OMNIWM_WINDOW_DECISION_RULE_ACTION_NONE),
                source_kind: UInt32(OMNIWM_WINDOW_DECISION_BUILT_IN_SOURCE_NONE),
                has_match: 0
            ),
            special_case_kind: UInt32(OMNIWM_WINDOW_DECISION_SPECIAL_CASE_NONE),
            activation_policy: UInt32(OMNIWM_WINDOW_DECISION_ACTIVATION_POLICY_REGULAR),
            subrole_kind: UInt32(OMNIWM_WINDOW_DECISION_SUBROLE_KIND_STANDARD),
            fullscreen_button_state: UInt32(OMNIWM_WINDOW_DECISION_FULLSCREEN_BUTTON_STATE_ENABLED),
            title_required: 0,
            title_present: 1,
            attribute_fetch_succeeded: 1,
            app_fullscreen: 0,
            has_close_button: 1,
            has_fullscreen_button: 1,
            has_zoom_button: 1,
            has_minimize_button: 1
        )
    }

    @Test func inputIsNotMutatedByCall() {
        var input = makeInput()
        let before = bytes(of: input)

        var output = omniwm_window_decision_output()
        let status = omniwm_window_decision_solve(&input, &output)

        #expect(status == OMNIWM_KERNELS_STATUS_OK)

        let after = bytes(of: input)
        #expect(areEqual(before, after), "input bytes must not be mutated")
    }

    @Test func twoCallsOnIdenticalInputProduceIdenticalOutput() {
        var input = makeInput()
        var output1 = omniwm_window_decision_output()
        var output2 = omniwm_window_decision_output()

        let status1 = omniwm_window_decision_solve(&input, &output1)
        let status2 = omniwm_window_decision_solve(&input, &output2)

        #expect(status1 == OMNIWM_KERNELS_STATUS_OK)
        #expect(status2 == OMNIWM_KERNELS_STATUS_OK)
        #expect(areEqual(bytes(of: output1), bytes(of: output2)),
                "deterministic kernel must produce identical output bytes")
    }
}


@Suite struct KernelABIAxisSolveOwnershipTests {
    private func makeInputs() -> [omniwm_axis_input] {
        [
            omniwm_axis_input(
                weight: 1, min_constraint: 50, max_constraint: 0, fixed_value: 0,
                has_max_constraint: 0, is_constraint_fixed: 0, has_fixed_value: 0
            ),
            omniwm_axis_input(
                weight: 2, min_constraint: 50, max_constraint: 0, fixed_value: 0,
                has_max_constraint: 0, is_constraint_fixed: 0, has_fixed_value: 0
            ),
        ]
    }

    @Test func inputArrayIsNotMutated() {
        var inputs = makeInputs()
        var outputs = [omniwm_axis_output](
            repeating: omniwm_axis_output(value: 0, was_constrained: 0),
            count: inputs.count
        )

        let inputBytesBefore = inputs.flatMap { bytes(of: $0) }

        let status = inputs.withUnsafeBufferPointer { inputBuffer in
            outputs.withUnsafeMutableBufferPointer { outputBuffer in
                omniwm_axis_solve(
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    300,
                    8,
                    0,
                    outputBuffer.baseAddress
                )
            }
        }

        #expect(status == OMNIWM_KERNELS_STATUS_OK)

        let inputBytesAfter = inputs.flatMap { bytes(of: $0) }
        #expect(areEqual(inputBytesBefore, inputBytesAfter),
                "input array bytes must not be mutated by the solver")
    }

    @Test func deterministicOutputAcrossRepeatedCalls() {
        let firstInputs = makeInputs()
        let secondInputs = makeInputs()
        var firstOutputs = [omniwm_axis_output](
            repeating: omniwm_axis_output(value: 0, was_constrained: 0),
            count: firstInputs.count
        )
        var secondOutputs = [omniwm_axis_output](
            repeating: omniwm_axis_output(value: 0, was_constrained: 0),
            count: secondInputs.count
        )

        _ = firstInputs.withUnsafeBufferPointer { input in
            firstOutputs.withUnsafeMutableBufferPointer { output in
                omniwm_axis_solve(input.baseAddress, input.count, 300, 8, 0, output.baseAddress)
            }
        }
        _ = secondInputs.withUnsafeBufferPointer { input in
            secondOutputs.withUnsafeMutableBufferPointer { output in
                omniwm_axis_solve(input.baseAddress, input.count, 300, 8, 0, output.baseAddress)
            }
        }

        let firstBytes = firstOutputs.flatMap { bytes(of: $0) }
        let secondBytes = secondOutputs.flatMap { bytes(of: $0) }
        #expect(areEqual(firstBytes, secondBytes),
                "axis solve must be deterministic for identical inputs")
    }
}


@Suite struct KernelABIGeometryOwnershipTests {
    @Test func totalSpan_isDeterministic() {
        let spans: [Double] = [120, 80, 200, 50]
        let first = spans.withUnsafeBufferPointer { buffer in
            omniwm_geometry_total_span(buffer.baseAddress, buffer.count, 8)
        }
        let second = spans.withUnsafeBufferPointer { buffer in
            omniwm_geometry_total_span(buffer.baseAddress, buffer.count, 8)
        }
        #expect(first == second)
    }

    @Test func totalSpan_doesNotMutateInput() {
        var spans: [Double] = [120, 80, 200, 50]
        let before = spans.flatMap { bytes(of: $0) }

        _ = spans.withUnsafeBufferPointer { buffer in
            omniwm_geometry_total_span(buffer.baseAddress, buffer.count, 8)
        }

        let after = spans.flatMap { bytes(of: $0) }
        #expect(areEqual(before, after), "scalar helper must not mutate input array")
    }
}


@Suite struct KernelABIOutputSentinelTests {
    @Test func axisSolveDoesNotWritePastDocumentedCapacity() {
        let solveCount = 2
        let sentinelCount = 4
        var inputs = [
            omniwm_axis_input(
                weight: 1, min_constraint: 0, max_constraint: 0, fixed_value: 0,
                has_max_constraint: 0, is_constraint_fixed: 0, has_fixed_value: 0
            ),
            omniwm_axis_input(
                weight: 1, min_constraint: 0, max_constraint: 0, fixed_value: 0,
                has_max_constraint: 0, is_constraint_fixed: 0, has_fixed_value: 0
            ),
        ]

        let sentinel = omniwm_axis_output(value: -1.0e308, was_constrained: 0xCD)
        var outputs = [omniwm_axis_output](repeating: sentinel, count: solveCount + sentinelCount)

        let sentinelBytesBefore = (solveCount..<outputs.count).flatMap { bytes(of: outputs[$0]) }

        let status = inputs.withUnsafeBufferPointer { inputBuffer in
            outputs.withUnsafeMutableBufferPointer { outputBuffer in
                omniwm_axis_solve(
                    inputBuffer.baseAddress,
                     solveCount,
                     300,
                     8,
                     0,
                    outputBuffer.baseAddress
                )
            }
        }
        #expect(status == OMNIWM_KERNELS_STATUS_OK)

        let sentinelBytesAfter = (solveCount..<outputs.count).flatMap { bytes(of: outputs[$0]) }
        #expect(areEqual(sentinelBytesBefore, sentinelBytesAfter),
                "kernel must not write past the documented `count` capacity")
    }

    @Test func windowDecisionFixedOutputDoesNotOverflow() {
        var input = omniwm_window_decision_input(
            matched_user_rule: omniwm_window_decision_rule_summary(
                action: UInt32(OMNIWM_WINDOW_DECISION_RULE_ACTION_NONE),
                has_match: 0
            ),
            matched_built_in_rule: omniwm_window_decision_built_in_rule_summary(
                action: UInt32(OMNIWM_WINDOW_DECISION_RULE_ACTION_NONE),
                source_kind: UInt32(OMNIWM_WINDOW_DECISION_BUILT_IN_SOURCE_NONE),
                has_match: 0
            ),
            special_case_kind: UInt32(OMNIWM_WINDOW_DECISION_SPECIAL_CASE_NONE),
            activation_policy: UInt32(OMNIWM_WINDOW_DECISION_ACTIVATION_POLICY_REGULAR),
            subrole_kind: UInt32(OMNIWM_WINDOW_DECISION_SUBROLE_KIND_STANDARD),
            fullscreen_button_state: UInt32(OMNIWM_WINDOW_DECISION_FULLSCREEN_BUTTON_STATE_ENABLED),
            title_required: 0, title_present: 1, attribute_fetch_succeeded: 1,
            app_fullscreen: 0, has_close_button: 1, has_fullscreen_button: 1,
            has_zoom_button: 1, has_minimize_button: 1
        )

        struct Wrapped {
            var output: omniwm_window_decision_output
            var sentinel: UInt64
        }
        let sentinelValue: UInt64 = 0xFEED_BABE_DEAD_C0DE
        var wrapped = Wrapped(output: omniwm_window_decision_output(), sentinel: sentinelValue)

        let status = withUnsafeMutablePointer(to: &wrapped.output) { ptr in
            omniwm_window_decision_solve(&input, ptr)
        }
        #expect(status == OMNIWM_KERNELS_STATUS_OK)
        #expect(wrapped.sentinel == sentinelValue,
                "kernel must not write past the documented output struct size")
    }
}
