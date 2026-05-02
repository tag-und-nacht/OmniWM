// SPDX-License-Identifier: GPL-2.0-only
import Foundation

@testable import OmniWM

@MainActor
final class PerturbationHarness {
    private var rng: SimplePRNG

    init(seed: UInt64 = 0xC0FFEE) {
        self.rng = SimplePRNG(seed: seed)
    }

    static let canonicalEvents: [WMEvent] = [
        .activeSpaceChanged(source: .workspaceManager),
        .systemSleep(source: .service),
        .systemWake(source: .service)
    ]

    static let perturbations: [TranscriptPerturbationKind] = [
        .none,
        .duplicate,
        .drop,
        .delayedAdmission,
        .reorderWith(1),
        .reorderWith(2)
    ]

    func runEnumerated() async throws {
        for event in Self.canonicalEvents {
            for perturbation in Self.perturbations {
                let transcript = Transcript.make(name: "enum") { builder in
                    builder
                        .event(event, perturbation: perturbation)
                        .event(.activeSpaceChanged(source: .workspaceManager))
                        .event(.activeSpaceChanged(source: .workspaceManager))
                        .expectFinal(TranscriptExpectations(
                            customAssertions: [.workspaceGraphValidates]
                        ))
                }
                let driver = TranscriptReplayDriver(transcript: transcript)
                try await driver.run()
            }
        }
    }

    func runPropertyOverFixedSeed(
        length: Int = 3,
        count: Int = 256
    ) async throws {
        for _ in 0..<count {
            let transcript = makePropertyTranscript(length: length)
            let driver = TranscriptReplayDriver(transcript: transcript)
            try await driver.run()
        }
    }

    private func makePropertyTranscript(length: Int) -> Transcript {
        Transcript.make(name: "property") { builder in
            let total = length + 1
            for i in 0..<length {
                let event = Self.canonicalEvents[
                    Int(rng.next() % UInt64(Self.canonicalEvents.count))
                ]
                let raw = Self.perturbations[
                    Int(rng.next() % UInt64(Self.perturbations.count))
                ]
                let safe: TranscriptPerturbationKind
                switch raw {
                case let .reorderWith(offset):
                    let maxOffset = total - 1 - i
                    if maxOffset < 1 {
                        safe = .none
                    } else if offset > maxOffset {
                        safe = .reorderWith(maxOffset)
                    } else {
                        safe = raw
                    }
                default:
                    safe = raw
                }
                builder.event(event, perturbation: safe)
            }
            builder.event(.activeSpaceChanged(source: .workspaceManager))
            builder.expectFinal(TranscriptExpectations(
                customAssertions: [.workspaceGraphValidates]
            ))
        }
    }
}

struct SimplePRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF_CAFE_BABE : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}
