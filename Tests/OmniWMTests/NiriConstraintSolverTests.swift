import Foundation
import Testing

@testable import OmniWM

private func makeAxisInput(
    weight: CGFloat = 1,
    minConstraint: CGFloat = 0,
    maxConstraint: CGFloat? = nil,
    isConstraintFixed: Bool = false,
    fixedValue: CGFloat? = nil
) -> NiriAxisSolver.Input {
    NiriAxisSolver.Input(
        weight: weight,
        minConstraint: minConstraint,
        maxConstraint: maxConstraint ?? 0,
        hasMaxConstraint: maxConstraint != nil,
        isConstraintFixed: isConstraintFixed,
        hasFixedValue: fixedValue != nil,
        fixedValue: fixedValue
    )
}

@Suite struct NiriConstraintSolverTests {
    @Test func emptyInputReturnsNoOutputs() {
        let outputs = NiriAxisSolver.solve(
            windows: [],
            availableSpace: 200,
            gapSize: 8
        )

        #expect(outputs.isEmpty)
    }

    @Test func allFixedInputsKeepAssignedValues() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                makeAxisInput(minConstraint: 100, fixedValue: 100),
                makeAxisInput(minConstraint: 80, isConstraintFixed: true),
                makeAxisInput(minConstraint: 60, fixedValue: 60)
            ],
            availableSpace: 240,
            gapSize: 0
        )

        #expect(outputs.map(\.value) == [100, 80, 60])
        #expect(outputs[0].wasConstrained)
        #expect(outputs[1].wasConstrained)
        #expect(outputs[2].wasConstrained)
    }

    @Test func missingOptionalFixedValueDoesNotCreateSyntheticFixedConstraint() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                NiriAxisSolver.Input(
                    weight: 1,
                    minConstraint: 40,
                    maxConstraint: 0,
                    hasMaxConstraint: false,
                    isConstraintFixed: false,
                    hasFixedValue: true,
                    fixedValue: nil
                ),
                makeAxisInput(weight: 1, minConstraint: 20)
            ],
            availableSpace: 120,
            gapSize: 0
        )

        #expect(outputs.count == 2)
        #expect(abs(outputs[0].value - 70) < 0.001)
        #expect(abs(outputs[1].value - 50) < 0.001)
        #expect(!outputs[0].wasConstrained)
        #expect(!outputs[1].wasConstrained)
    }

    @Test func fixedOverflowScalesOnlyFixedInputs() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                makeAxisInput(minConstraint: 80, fixedValue: 80),
                makeAxisInput(weight: 1)
            ],
            availableSpace: 50,
            gapSize: 0
        )

        #expect(outputs.count == 2)
        #expect(abs(outputs[0].value - 50) < 0.001)
        #expect(outputs[0].wasConstrained)
        #expect(outputs[1].value == 0)
        #expect(!outputs[1].wasConstrained)
    }

    @Test func scalesMinimumsWhenMinimumSumExceedsRemainingSpace() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                makeAxisInput(minConstraint: 80),
                makeAxisInput(minConstraint: 120)
            ],
            availableSpace: 100,
            gapSize: 0
        )

        #expect(outputs.count == 2)
        #expect(abs(outputs[0].value - 40) < 0.001)
        #expect(abs(outputs[1].value - 60) < 0.001)
        #expect(!outputs[0].wasConstrained)
        #expect(!outputs[1].wasConstrained)
    }

    @Test func weightedGrowthUsesRelativeWeights() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                makeAxisInput(weight: 1, minConstraint: 50),
                makeAxisInput(weight: 3, minConstraint: 50)
            ],
            availableSpace: 400,
            gapSize: 0
        )

        #expect(outputs.count == 2)
        #expect(abs(outputs[0].value - 125) < 0.001)
        #expect(abs(outputs[1].value - 275) < 0.001)
    }

    @Test func fixedValuesClampToMaximumBeforeDistribution() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                makeAxisInput(minConstraint: 50, maxConstraint: 120, fixedValue: 300),
                makeAxisInput(weight: 1, minConstraint: 20)
            ],
            availableSpace: 260,
            gapSize: 0
        )

        #expect(outputs.count == 2)
        #expect(abs(outputs[0].value - 120) < 0.001)
        #expect(outputs[0].wasConstrained)
        #expect(abs(outputs[1].value - 140) < 0.001)
    }

    @Test func maxCapsRedistributeRemainingSpace() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                makeAxisInput(weight: 1, maxConstraint: 100),
                makeAxisInput(weight: 1, maxConstraint: 400),
                makeAxisInput(weight: 1)
            ],
            availableSpace: 1200,
            gapSize: 0
        )

        #expect(outputs.count == 3)
        #expect(abs(outputs[0].value - 100) < 0.001)
        #expect(abs(outputs[1].value - 400) < 0.001)
        #expect(abs(outputs[2].value - 700) < 0.001)
    }

    @Test func gapSizeReducesUsableSpaceBeforeDistribution() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                makeAxisInput(weight: 1),
                makeAxisInput(weight: 1)
            ],
            availableSpace: 120,
            gapSize: 20
        )

        #expect(outputs.count == 2)
        #expect(abs(outputs[0].value - 50) < 0.001)
        #expect(abs(outputs[1].value - 50) < 0.001)
    }

    @Test func zeroWeightsUseEqualShareGrowthBranch() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                makeAxisInput(weight: -5),
                makeAxisInput(weight: .nan)
            ],
            availableSpace: 120,
            gapSize: 0
        )

        #expect(outputs.count == 2)
        #expect(abs(outputs[0].value - 60) < 0.001)
        #expect(abs(outputs[1].value - 60) < 0.001)
    }

    @Test func tabbedModeUsesSharedValueAcrossWindows() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                makeAxisInput(minConstraint: 100),
                makeAxisInput(minConstraint: 250),
                makeAxisInput(minConstraint: 50, fixedValue: 200)
            ],
            availableSpace: 200,
            gapSize: 0,
            isTabbed: true
        )

        #expect(outputs.count == 3)
        #expect(outputs.map(\.value) == [250, 250, 250])
        #expect(!outputs[0].wasConstrained)
        #expect(outputs[1].wasConstrained)
        #expect(!outputs[2].wasConstrained)
    }

    @Test func tabbedModeClampsToTightestMaximum() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                makeAxisInput(minConstraint: 100, maxConstraint: 180),
                makeAxisInput(minConstraint: 120, maxConstraint: 140)
            ],
            availableSpace: 300,
            gapSize: 0,
            isTabbed: true
        )

        #expect(outputs.count == 2)
        #expect(abs(outputs[0].value - 140) < 0.001)
        #expect(abs(outputs[1].value - 140) < 0.001)
        #expect(!outputs[0].wasConstrained)
        #expect(outputs[1].wasConstrained)
    }

    @Test func sanitizesNegativeAndNonFiniteInputs() {
        let outputs = NiriAxisSolver.solve(
            windows: [
                makeAxisInput(
                    weight: 0,
                    minConstraint: 20,
                    maxConstraint: .nan,
                    fixedValue: -50
                ),
                makeAxisInput(
                    weight: .nan,
                    minConstraint: -10,
                    maxConstraint: -100
                )
            ],
            availableSpace: 100,
            gapSize: 0
        )

        #expect(outputs.count == 2)
        #expect(abs(outputs[0].value - 20) < 0.001)
        #expect(outputs[0].wasConstrained)
        #expect(abs(outputs[1].value - 80) < 0.001)
        #expect(!outputs[1].wasConstrained)
    }
}
