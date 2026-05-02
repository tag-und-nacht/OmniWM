// SPDX-License-Identifier: GPL-2.0-only

import COmniWMKernels
import Foundation
import Testing


@Suite struct KernelABIGoldensCoverage {
    @Test func everyTypedefMatchesGoldenLayout() {
        let schemaByName = Dictionary(
            uniqueKeysWithValues: KernelABISchema.currentLayouts().map { ($0.name, $0) }
        )
        for golden in KernelABIGoldens.entries {
            guard let live = schemaByName[golden.name] else {
                Issue.record("\(golden.name): present in goldens but missing from schema")
                continue
            }
            #expect(live.size == golden.size, "\(golden.name) size drifted: \(live.size) vs golden \(golden.size)")
            #expect(live.stride == golden.stride, "\(golden.name) stride drifted: \(live.stride) vs golden \(golden.stride)")
            #expect(live.alignment == golden.alignment, "\(golden.name) alignment drifted: \(live.alignment) vs golden \(golden.alignment)")
        }
    }

    @Test func goldenSetCoversCompleteSchema() {
        let goldenNames = Set(KernelABIGoldens.entries.map(\.name))
        let schemaNames = Set(KernelABISchema.currentLayouts().map(\.name))
        let missingFromGoldens = schemaNames.subtracting(goldenNames)
        let missingFromSchema = goldenNames.subtracting(schemaNames)
        #expect(missingFromGoldens.isEmpty, "schema typedefs without goldens: \(missingFromGoldens.sorted())")
        #expect(missingFromSchema.isEmpty, "goldens without schema entry: \(missingFromSchema.sorted())")
    }

    @Test func goldenCountIsReasonablyLarge() {
        #expect(KernelABIGoldens.entries.count >= 80,
                "kernel ABI golden coverage shrank below 80 entries — schema truncation?")
    }
}


@Suite struct KernelABILayoutCrossLanguageParity {
    @Test func orchestrationAbiLayoutMatchesSwiftMemoryLayout() {
        var layout = omniwm_orchestration_abi_layout_info()
        let status = omniwm_orchestration_get_abi_layout(&layout)
        #expect(status == OMNIWM_KERNELS_STATUS_OK)

        #expect(layout.step_input_size == MemoryLayout<omniwm_orchestration_step_input>.size)
        #expect(layout.step_input_alignment == MemoryLayout<omniwm_orchestration_step_input>.alignment)

        #expect(layout.step_output_size == MemoryLayout<omniwm_orchestration_step_output>.size)
        #expect(layout.step_output_alignment == MemoryLayout<omniwm_orchestration_step_output>.alignment)

        #expect(layout.snapshot_size == MemoryLayout<omniwm_orchestration_snapshot>.size)
        #expect(layout.snapshot_alignment == MemoryLayout<omniwm_orchestration_snapshot>.alignment)
        #expect(layout.event_size == MemoryLayout<omniwm_orchestration_event>.size)
        #expect(layout.event_alignment == MemoryLayout<omniwm_orchestration_event>.alignment)
        #expect(layout.refresh_size == MemoryLayout<omniwm_orchestration_refresh>.size)
        #expect(layout.refresh_alignment == MemoryLayout<omniwm_orchestration_refresh>.alignment)
        #expect(
            layout.managed_request_size == MemoryLayout<omniwm_orchestration_managed_request>.size
        )
        #expect(
            layout.managed_request_alignment
                == MemoryLayout<omniwm_orchestration_managed_request>.alignment
        )
        #expect(layout.action_size == MemoryLayout<omniwm_orchestration_action>.size)
        #expect(layout.action_alignment == MemoryLayout<omniwm_orchestration_action>.alignment)
    }

    @Test func windowTokenPidComesBeforeWindowId() {
        #expect(MemoryLayout<omniwm_window_token>.offset(of: \.pid) == 0)
        #expect(MemoryLayout<omniwm_window_token>.offset(of: \.window_id) == 8)
    }

    @Test func logicalWindowIdIsEightBytes() {
        #expect(MemoryLayout<omniwm_logical_window_id>.size == 8)
        #expect(MemoryLayout<omniwm_logical_window_id>.alignment == 8)
    }
}
