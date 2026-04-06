import Foundation
import Testing

@testable import OmniWM

private func makeContainers(
    widths: [CGFloat],
    heights: [CGFloat]? = nil
) -> [NiriContainer] {
    zip(widths, heights ?? widths).map { width, height in
        let container = NiriContainer()
        container.cachedWidth = width
        container.cachedHeight = height
        return container
    }
}

@Suite struct ViewportGeometryTests {
    @Test func emptyContainersReturnZeroGeometry() {
        let state = ViewportState()

        #expect(state.totalWidth(columns: [], gap: 8) == 0)
        #expect(state.computeCenteredOffset(columnIndex: 0, columns: [], gap: 8, viewportWidth: 300) == 0)
        #expect(
            state.computeVisibleOffset(
                columnIndex: 0,
                columns: [],
                gap: 8,
                viewportWidth: 300,
                currentOffset: 0,
                centerMode: .never
            ) == 0
        )
    }

    @Test func genericSpanHelpersUseRequestedDimensionAndPreserveOutOfRangeSemantics() {
        let state = ViewportState()
        let containers = makeContainers(widths: [10, 20, 30], heights: [50, 70, 90])

        #expect(
            state.containerPosition(
                at: 2,
                containers: containers,
                gap: 5,
                sizeKeyPath: \.cachedHeight
            ) == 130
        )
        #expect(
            state.totalSpan(
                containers: containers,
                gap: 5,
                sizeKeyPath: \.cachedHeight
            ) == 220
        )
        #expect(state.columnX(at: 10, columns: containers, gap: 5) == 75)
        #expect(
            state.computeVisibleOffset(
                containerIndex: -1,
                containers: containers,
                gap: 5,
                viewportSpan: 100,
                sizeKeyPath: \.cachedHeight,
                currentViewStart: 0,
                centerMode: .never
            ) == 0
        )
        #expect(
            state.computeCenteredOffset(
                containerIndex: 10,
                containers: containers,
                gap: 5,
                viewportSpan: 100,
                sizeKeyPath: \.cachedHeight
            ) == 0
        )
    }

    @Test func centeredOffsetCentersWholeContentWhenViewportExceedsTotalSpan() {
        let state = ViewportState()
        let columns = makeContainers(widths: [100, 100])

        let offset = state.computeCenteredOffset(
            columnIndex: 1,
            columns: columns,
            gap: 10,
            viewportWidth: 300
        )

        #expect(abs(offset + 155) < 0.001)
    }

    @Test func centeredOffsetClampsWithinAllowedOverflowRange() {
        let state = ViewportState()
        let columns = makeContainers(widths: [100, 100, 100])

        let offset = state.computeCenteredOffset(
            columnIndex: 2,
            columns: columns,
            gap: 10,
            viewportWidth: 150
        )

        #expect(abs(offset + 50) < 0.001)
    }

    @Test func visibleOffsetKeepsFullyVisibleTargetPinnedInNeverMode() {
        let state = ViewportState()
        let columns = makeContainers(widths: [100, 100, 100])

        let offset = state.computeVisibleOffset(
            containerIndex: 1,
            containers: columns,
            gap: 10,
            viewportSpan: 220,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: 0,
            centerMode: .never
        )

        #expect(abs(offset + 110) < 0.001)
    }

    @Test func visibleOffsetFitsTargetWhenOnOverflowWithoutSourceContainer() {
        let state = ViewportState()
        let columns = makeContainers(widths: [100, 100, 100])

        let offset = state.computeVisibleOffset(
            containerIndex: 1,
            containers: columns,
            gap: 10,
            viewportSpan: 150,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: 0,
            centerMode: .onOverflow
        )

        #expect(abs(offset + 50) < 0.001)
    }

    @Test func visibleOffsetAlwaysModeMatchesCenteredOffset() {
        let state = ViewportState()
        let columns = makeContainers(widths: [100, 100, 100])

        let offset = state.computeVisibleOffset(
            containerIndex: 1,
            containers: columns,
            gap: 10,
            viewportSpan: 150,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: 0,
            centerMode: .always
        )

        #expect(abs(offset + 25) < 0.001)
    }

    @Test func visibleOffsetKeepsFullyVisiblePairsPinnedInOnOverflowMode() {
        let state = ViewportState()
        let columns = makeContainers(widths: [100, 100, 100])

        let offset = state.computeVisibleOffset(
            containerIndex: 1,
            containers: columns,
            gap: 10,
            viewportSpan: 220,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: 0,
            centerMode: .onOverflow,
            fromContainerIndex: 0
        )

        #expect(abs(offset + 110) < 0.001)
    }

    @Test func visibleOffsetCentersWhenOverflowingPairCannotStayVisibleTogether() {
        let state = ViewportState()
        let columns = makeContainers(widths: [100, 100, 100, 100])

        let offset = state.computeVisibleOffset(
            containerIndex: 2,
            containers: columns,
            gap: 10,
            viewportSpan: 150,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: 0,
            centerMode: .onOverflow,
            fromContainerIndex: 0
        )

        #expect(abs(offset + 25) < 0.001)
    }

    @Test func visibleOffsetAlwaysModeUsesCenteredOffset() {
        let state = ViewportState()
        let columns = makeContainers(widths: [100, 100, 100, 100])

        let offset = state.computeVisibleOffset(
            containerIndex: 2,
            containers: columns,
            gap: 10,
            viewportSpan: 150,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: 0,
            centerMode: .always
        )

        #expect(abs(offset + 25) < 0.001)
    }

    @Test func alwaysCenterSingleColumnOverridesNeverCenterMode() {
        let state = ViewportState()
        let columns = makeContainers(widths: [100])

        let offset = state.computeVisibleOffset(
            containerIndex: 0,
            containers: columns,
            gap: 8,
            viewportSpan: 200,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: 0,
            centerMode: .never,
            alwaysCenterSingleColumn: true
        )

        #expect(abs(offset + 50) < 0.001)
    }

    @Test func pixelEpsilonTreatsNearlyVisibleTargetAsVisible() {
        let state = ViewportState()
        let columns = makeContainers(widths: [100])

        let offset = state.computeVisibleOffset(
            containerIndex: 0,
            containers: columns,
            gap: 0,
            viewportSpan: 101,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: 0.4,
            centerMode: .never,
            scale: 2.0
        )

        let strictOffset = state.computeVisibleOffset(
            containerIndex: 0,
            containers: columns,
            gap: 0,
            viewportSpan: 101,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: 0.4,
            centerMode: .never,
            scale: 10.0
        )

        #expect(abs(offset - 0.4) < 0.001)
        #expect(abs(strictOffset) < 0.001)
    }
}
