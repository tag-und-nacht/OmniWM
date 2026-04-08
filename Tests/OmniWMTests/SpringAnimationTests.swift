import Foundation
import Testing

@testable import OmniWM

private func expectSpringConfig(
    _ config: SpringConfig,
    matches expected: SpringConfig,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(config.response == expected.response, sourceLocation: sourceLocation)
    #expect(config.dampingFraction == expected.dampingFraction, sourceLocation: sourceLocation)
    #expect(config.blendDuration == expected.blendDuration, sourceLocation: sourceLocation)
    #expect(config.duration == expected.duration, sourceLocation: sourceLocation)
    #expect(config.bounce == expected.bounce, sourceLocation: sourceLocation)
    #expect(config.epsilon == expected.epsilon, sourceLocation: sourceLocation)
    #expect(config.velocityEpsilon == expected.velocityEpsilon, sourceLocation: sourceLocation)
}

@Suite struct SpringAnimationTests {
    @Test func defaultPresetMatchesExactSnappyConfig() {
        expectSpringConfig(.default, matches: .snappy)
        #expect(SpringConfig.snappy.response == 0.22)
        #expect(SpringConfig.snappy.dampingFraction == 0.95)
        #expect(SpringConfig.snappy.epsilon == 0.0001)
        #expect(SpringConfig.snappy.velocityEpsilon == 0.01)
    }

    @Test func reduceMotionResolutionReturnsExactReducedMotionPreset() {
        let resolved = SpringConfig.snappy.resolvedForReduceMotion(true)

        expectSpringConfig(resolved, matches: .reducedMotion)
        #expect(resolved.epsilon == SpringConfig.reducedMotion.epsilon)
        #expect(resolved.velocityEpsilon == SpringConfig.reducedMotion.velocityEpsilon)
    }
}
