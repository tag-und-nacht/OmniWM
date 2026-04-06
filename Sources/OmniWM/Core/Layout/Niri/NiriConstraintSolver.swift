import COmniWMKernels
import Foundation

enum NiriAxisSolver {
    struct Input {
        let weight: CGFloat
        let minConstraint: CGFloat
        let maxConstraint: CGFloat
        let hasMaxConstraint: Bool
        let isConstraintFixed: Bool
        let hasFixedValue: Bool
        let fixedValue: CGFloat?
    }

    struct Output {
        let value: CGFloat
        let wasConstrained: Bool
    }

    static func solve(
        windows: [Input],
        availableSpace: CGFloat,
        gapSize: CGFloat,
        isTabbed: Bool = false
    ) -> [Output] {
        guard !windows.isEmpty else { return [] }

        return withUnsafeTemporaryAllocation(of: omniwm_axis_input.self, capacity: windows.count) { inputs in
            withUnsafeTemporaryAllocation(of: omniwm_axis_output.self, capacity: windows.count) { outputs in
                for (index, window) in windows.enumerated() {
                    let hasFixedValue = window.hasFixedValue && window.fixedValue != nil
                    inputs[index] = omniwm_axis_input(
                        weight: window.weight,
                        min_constraint: window.minConstraint,
                        max_constraint: window.maxConstraint,
                        fixed_value: window.fixedValue ?? 0,
                        has_max_constraint: window.hasMaxConstraint ? 1 : 0,
                        is_constraint_fixed: window.isConstraintFixed ? 1 : 0,
                        has_fixed_value: hasFixedValue ? 1 : 0
                    )
                }

                let status = omniwm_axis_solve(
                    inputs.baseAddress,
                    inputs.count,
                    availableSpace,
                    gapSize,
                    isTabbed ? 1 : 0,
                    outputs.baseAddress
                )
                precondition(
                    status == OMNIWM_KERNELS_STATUS_OK,
                    "omniwm_axis_solve returned \(status)"
                )

                return outputs.prefix(windows.count).map { output in
                    Output(
                        value: output.value,
                        wasConstrained: output.was_constrained != 0
                    )
                }
            }
        }
    }
}
