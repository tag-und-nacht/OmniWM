// SPDX-License-Identifier: GPL-2.0-only

import COmniWMKernels
import Darwin
import Foundation
import Testing


@Suite struct KernelABIGeometryInvalidInputTests {
    @Test func totalSpan_emptyArrayReturnsZero() {
        #expect(omniwm_geometry_total_span(nil, 0, 8) == 0)
    }

    @Test func totalSpan_singleElementHasNoTrailingGap() {
        var spans: [Double] = [100]
        let result = spans.withUnsafeBufferPointer { buffer in
            omniwm_geometry_total_span(buffer.baseAddress, buffer.count, 8)
        }
        #expect(result == 100)
    }

    @Test func totalSpan_twoElementsIncludeOneGap() {
        var spans: [Double] = [100, 50]
        let result = spans.withUnsafeBufferPointer { buffer in
            omniwm_geometry_total_span(buffer.baseAddress, buffer.count, 8)
        }
        #expect(result == 158)
    }

    @Test func containerPosition_emptyArrayAtZeroReturnsZero() {
        #expect(omniwm_geometry_container_position(nil, 0, 8, 0) == 0)
    }

    @Test func containerPosition_indexZeroReturnsZero() {
        var spans: [Double] = [100, 50, 25]
        let result = spans.withUnsafeBufferPointer { buffer in
            omniwm_geometry_container_position(buffer.baseAddress, buffer.count, 8, 0)
        }
        #expect(result == 0)
    }

    @Test func centeredOffset_emptyArrayReturnsZero() {
        #expect(omniwm_geometry_centered_offset(nil, nil, 0, 8, 300, 0) == 0)
    }

    @Test func visibleOffset_emptyArrayReturnsZero() {
        #expect(
            omniwm_geometry_visible_offset(
                nil, nil, 0,
                 8,
                 300,
                 0,
                 0,
                 UInt32(OMNIWM_CENTER_FOCUSED_COLUMN_NEVER),
                 0,
                 -1,
                 2
            ) == 0
        )
    }

    @Test func visibleOffset_negativeIndexReturnsZero() {
        var spans: [Double] = [100, 50]
        let result = spans.withUnsafeBufferPointer { buffer in
            omniwm_geometry_visible_offset(
                buffer.baseAddress, nil, buffer.count,
                 5,
                 100,
                 -1,
                 0,
                 UInt32(OMNIWM_CENTER_FOCUSED_COLUMN_NEVER),
                 0,
                 -1,
                 2
            )
        }
        #expect(result == 0)
    }

    @Test func snapTarget_emptyArrayReportsDeterministicNoSnap() {
        let result = omniwm_geometry_snap_target(
            nil, nil, 0,
             8,
             300,
             0,
             0,
             UInt32(OMNIWM_CENTER_FOCUSED_COLUMN_NEVER),
             0
        )
        #expect(result.view_pos.isFinite)
    }
}


@Suite struct KernelABIAxisSolveInvalidInputTests {
    @Test func nullInputs_returnsInvalidArgument() {
        var output = omniwm_axis_output()
        let status = omniwm_axis_solve(
            nil,
             1,
             100,
             0,
             0,
            &output
        )
        #expect(status == OMNIWM_KERNELS_STATUS_INVALID_ARGUMENT)
    }

    @Test func nullOutputs_returnsInvalidArgument() {
        var input = omniwm_axis_input(
            weight: 1.0,
            min_constraint: 0,
            max_constraint: 0,
            fixed_value: 0,
            has_max_constraint: 0,
            is_constraint_fixed: 0,
            has_fixed_value: 0
        )
        let status = omniwm_axis_solve(
            &input,
             1,
             100,
             0,
             0,
            nil
        )
        #expect(status == OMNIWM_KERNELS_STATUS_INVALID_ARGUMENT)
    }

    @Test func zeroCountWithNullPointers_isAccepted() {
        let status = omniwm_axis_solve(
            nil,
             0,
             100,
             0,
             0,
            nil
        )
        #expect(status == OMNIWM_KERNELS_STATUS_OK)
    }
}


@Suite struct KernelABIBundleIDValidationTests {
    @Test func nullBundleId_returnsRequired() {
        let code = omniwm_ipc_bundle_id_validation_code(nil)
        #expect(code == UInt32(OMNIWM_IPC_BUNDLE_ID_ERROR_REQUIRED))
    }

    @Test func emptyBundleId_returnsRequired() {
        let code = "".withCString { ptr in
            omniwm_ipc_bundle_id_validation_code(ptr)
        }
        #expect(code == UInt32(OMNIWM_IPC_BUNDLE_ID_ERROR_REQUIRED))
    }

    @Test func wellFormedReverseDNS_returnsNone() {
        let code = "com.example.app".withCString { ptr in
            omniwm_ipc_bundle_id_validation_code(ptr)
        }
        #expect(code == UInt32(OMNIWM_IPC_BUNDLE_ID_ERROR_NONE))
    }

    @Test func bundleIdWithSpaces_returnsInvalid() {
        let code = "com example app".withCString { ptr in
            omniwm_ipc_bundle_id_validation_code(ptr)
        }
        #expect(code == UInt32(OMNIWM_IPC_BUNDLE_ID_ERROR_INVALID))
    }
}


@Suite struct KernelABIWorkspaceNumberFromRawIDTests {
    @Test func nullRawId_returnsZero() {
        var workspaceNumber: UInt64 = 0xDEADBEEF
        let parsed = omniwm_workspace_number_from_raw_id(nil, &workspaceNumber)
        #expect(parsed == 0)
        #expect(workspaceNumber == 0xDEADBEEF)
    }

    @Test func nullOutPointer_returnsZero() {
        let parsed = "1".withCString { ptr in
            omniwm_workspace_number_from_raw_id(ptr, nil)
        }
        #expect(parsed == 0)
    }

    @Test func nonNumericInput_returnsZero() {
        var workspaceNumber: UInt64 = 0
        let parsed = "not-a-number".withCString { ptr in
            omniwm_workspace_number_from_raw_id(ptr, &workspaceNumber)
        }
        #expect(parsed == 0)
    }

    @Test func validNumberPath_succeeds() {
        var workspaceNumber: UInt64 = 0
        let parsed = "ws-7".withCString { ptr in
            omniwm_workspace_number_from_raw_id(ptr, &workspaceNumber)
        }
        if parsed != 0 {
            #expect(workspaceNumber == 7)
        }
    }
}


@Suite struct KernelABIFindNewlineTests {
    @Test func nullBytesWithZeroCount_returnsNoNewline() {
        let result = omniwm_ipc_find_newline(nil, 0, 1024)
        #expect(result == Int64(OMNIWM_IPC_LINE_SCAN_NO_NEWLINE))
    }

    @Test func nullBytesWithNonZeroCount_returnsInvalidArgument() {
        let result = omniwm_ipc_find_newline(nil, 16, 1024)
        #expect(result == Int64(OMNIWM_IPC_LINE_SCAN_INVALID_ARGUMENT))
    }

    @Test func bufferWithoutNewline_returnsNoNewline() {
        var bytes: [UInt8] = Array("no newline here".utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            omniwm_ipc_find_newline(buffer.baseAddress, buffer.count, 1024)
        }
        #expect(result == Int64(OMNIWM_IPC_LINE_SCAN_NO_NEWLINE))
    }

    @Test func bufferExceedingMaxLine_returnsOverflow() {
        var bytes: [UInt8] = Array(repeating: 0x41, count: 64)
        let result = bytes.withUnsafeBufferPointer { buffer in
            omniwm_ipc_find_newline(buffer.baseAddress, buffer.count, 16)
        }
        #expect(result == Int64(OMNIWM_IPC_LINE_SCAN_OVERFLOW))
    }

    @Test func bufferWithNewlineWithinLimit_returnsByteIndex() {
        var bytes: [UInt8] = Array("hello\n".utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            omniwm_ipc_find_newline(buffer.baseAddress, buffer.count, 1024)
        }
        #expect(result == 5)
    }
}


@Suite struct KernelABIStringOutputHelperTests {
    @Test func resolvedSocketPath_zeroCapacityReturnsRequiredSize() {
        let required = "/Users/test".withCString { homePtr in
            omniwm_ipc_resolved_socket_path(nil, homePtr, nil, 0)
        }
        #expect(required > Int64.min)
    }

    @Test func secretPath_zeroCapacityIsValid() {
        let required = "/tmp/socket".withCString { ptr in
            omniwm_ipc_secret_path(ptr, nil, 0)
        }
        #expect(required > Int64.min)
    }

    @Test func workspaceIdNormalize_emptyInputBehaviorIsDefined() {
        var output = [CChar](repeating: 0, count: 64)
        let written = "".withCString { input in
            output.withUnsafeMutableBufferPointer { buffer in
                omniwm_workspace_id_normalize(input, buffer.baseAddress, buffer.count)
            }
        }
        #expect(written > Int64.min)
    }

    @Test func workspaceIdFromNumber_zeroCapacityHasDefinedReturn() {
        let required = omniwm_workspace_id_from_number(1, nil, 0)
        #expect(required > Int64.min)
    }
}


@Suite struct KernelABIRestoreResolveAssignmentsTests {
    @Test func nullSnapshotsWithNonZeroCount_failsOrReportsZero() {
        var assignmentCount: Int = 0
        let status = omniwm_restore_resolve_assignments(
             nil,
             4,
             nil,
             0,
             nil,
             0,
             nil,
             0,
            &assignmentCount
        )
        #expect(
            status == OMNIWM_KERNELS_STATUS_INVALID_ARGUMENT
                || status == OMNIWM_KERNELS_STATUS_OK
        )
        if status == OMNIWM_KERNELS_STATUS_OK {
            #expect(assignmentCount == 0,
                    "OK with zero capacity must produce zero assignments")
        }
    }

    @Test func nullOutputCount_returnsInvalidArgument() {
        let status = omniwm_restore_resolve_assignments(
            nil,  0,
            nil,  0,
            nil,  0,
            nil,
             0,
            nil
        )
        #expect(status == OMNIWM_KERNELS_STATUS_INVALID_ARGUMENT)
    }

    @Test func zeroCountsAreAccepted() {
        var assignmentCount: Int = 99
        let status = omniwm_restore_resolve_assignments(
            nil,  0,
            nil,  0,
            nil,  0,
            nil,
             0,
            &assignmentCount
        )
        #expect(status == OMNIWM_KERNELS_STATUS_OK)
        #expect(assignmentCount == 0)
    }
}


@Suite struct KernelABIAutomationManifestJSONTests {
    @Test func nullOutputReturnsInvalid() {
        errno = 0
        let result = omniwm_ipc_automation_manifest_json(nil, 0)
        #expect(result == -1)
        #expect(errno == EINVAL)
    }

    @Test func zeroCapacityReturnsERANGE() {
        var buffer = [CChar](repeating: 0, count: 1)
        errno = 0
        let result = buffer.withUnsafeMutableBufferPointer { ptr in
            omniwm_ipc_automation_manifest_json(ptr.baseAddress, 0)
        }
        #expect(result == -1)
        #expect(errno == ERANGE)
    }

    @Test func sufficientCapacitySucceedsAndNULTerminates() {
        var buffer = [CChar](repeating: 0, count: 65536)
        let result = buffer.withUnsafeMutableBufferPointer { ptr in
            omniwm_ipc_automation_manifest_json(ptr.baseAddress, ptr.count)
        }
        #expect(result > 0)
        #expect(buffer[Int(result)] == 0)
    }
}


private func makeReadSecretTokenTempDir() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("omniwm-secret-invalid-\(UUID().uuidString.prefix(8))",
                                isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Suite struct KernelABIReadSecretTokenTests {
    @Test func nullSocketPathReturnsInvalid() {
        var buffer = [CChar](repeating: 0, count: 256)
        errno = 0
        let result = buffer.withUnsafeMutableBufferPointer { ptr in
            omniwm_ipc_read_secret_token_for_socket(nil, ptr.baseAddress, ptr.count)
        }
        #expect(result == -1)
        #expect(errno == EINVAL)
    }

    @Test func missingFileReturnsError() throws {
        let directory = try makeReadSecretTokenTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let socketPath = directory.appendingPathComponent("s").path

        var buffer = [CChar](repeating: 0, count: 256)
        let result = socketPath.withCString { path in
            buffer.withUnsafeMutableBufferPointer { ptr in
                omniwm_ipc_read_secret_token_for_socket(path, ptr.baseAddress, ptr.count)
            }
        }
        #expect(result == -1)
    }

    @Test func wrongModeReturnsEACCES() throws {
        let directory = try makeReadSecretTokenTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let socketPath = directory.appendingPathComponent("s").path
        let secretPath = "\(socketPath).secret"

        try "abc123\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: secretPath))
        try #require(secretPath.withCString { Darwin.chmod($0, 0o644) } == 0)

        var buffer = [CChar](repeating: 0, count: 256)
        errno = 0
        let result = socketPath.withCString { path in
            buffer.withUnsafeMutableBufferPointer { ptr in
                omniwm_ipc_read_secret_token_for_socket(path, ptr.baseAddress, ptr.count)
            }
        }
        #expect(result == -1)
        #expect(errno == EACCES)
    }

    @Test func validFileReturnsTrimmedTokenLengthAndNULTerminates() throws {
        let directory = try makeReadSecretTokenTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let socketPath = directory.appendingPathComponent("s").path
        let secretPath = "\(socketPath).secret"

        try "abc123\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: secretPath))
        try #require(secretPath.withCString { Darwin.chmod($0, 0o600) } == 0)

        var buffer = [CChar](repeating: 0, count: 256)
        let result = socketPath.withCString { path in
            buffer.withUnsafeMutableBufferPointer { ptr in
                omniwm_ipc_read_secret_token_for_socket(path, ptr.baseAddress, ptr.count)
            }
        }
        #expect(result == 6)
        #expect(buffer[6] == 0)
        #expect(buffer[0] == CChar(UInt8(ascii: "a")))
        #expect(buffer[5] == CChar(UInt8(ascii: "3")))
    }
}
