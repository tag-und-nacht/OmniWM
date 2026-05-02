// SPDX-License-Identifier: GPL-2.0-only

import COmniWMKernels
import Darwin
import Foundation
import Testing

private let sentinelByte: UInt8 = 0xAB
private let sentinelPadding = 32

private func makeSentinelBuffer(capacity: Int, padding: Int = sentinelPadding) -> [UInt8] {
    [UInt8](repeating: sentinelByte, count: capacity + padding)
}

private func cstringBytes(_ string: String) -> [UInt8] {
    Array(string.utf8) + [0]
}

private func makeTemporarySecretDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("omniwm-string-helper-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func probeRequiredLength(_ probe: (UnsafeMutablePointer<UInt8>, Int) -> Int64) -> Int64 {
    var scratch = [UInt8](repeating: 0, count: 65536)
    return scratch.withUnsafeMutableBufferPointer { ptr in
        probe(ptr.baseAddress!, ptr.count)
    }
}


@Suite struct KernelABIWorkspaceIdFromNumberOwnershipTests {
    private let workspaceNumber: UInt64 = 17

    @Test func deterministicOutputAndReturnValue() {
        let required = probeRequiredLength { buf, cap in
            buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                omniwm_workspace_id_from_number(workspaceNumber, cbuf, cap)
            }
        }
        #expect(required > 0)

        let capacity = Int(required) + 1
        var first = makeSentinelBuffer(capacity: capacity)
        var second = makeSentinelBuffer(capacity: capacity)

        let returned1 = first.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                omniwm_workspace_id_from_number(workspaceNumber, cbuf, capacity)
            }
        }
        let returned2 = second.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                omniwm_workspace_id_from_number(workspaceNumber, cbuf, capacity)
            }
        }

        #expect(returned1 == required)
        #expect(returned1 == returned2)
        #expect(first == second)
    }

    @Test func nulTerminatedOnSuccess() {
        let required = probeRequiredLength { buf, cap in
            buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                omniwm_workspace_id_from_number(workspaceNumber, cbuf, cap)
            }
        }
        let capacity = Int(required) + 1
        var buffer = makeSentinelBuffer(capacity: capacity)

        let returned = buffer.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                omniwm_workspace_id_from_number(workspaceNumber, cbuf, capacity)
            }
        }

        #expect(returned >= 0)
        #expect(buffer[Int(returned)] == 0)
    }

    @Test func doesNotWritePastCapacity() {
        let required = probeRequiredLength { buf, cap in
            buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                omniwm_workspace_id_from_number(workspaceNumber, cbuf, cap)
            }
        }
        let capacity = Int(required) + 1
        var buffer = makeSentinelBuffer(capacity: capacity)

        _ = buffer.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                omniwm_workspace_id_from_number(workspaceNumber, cbuf, capacity)
            }
        }

        for offset in capacity..<buffer.count {
            #expect(buffer[offset] == sentinelByte,
                    "byte at offset \(offset) (past capacity \(capacity)) was mutated to 0x\(String(buffer[offset], radix: 16))")
        }
    }
}


@Suite struct KernelABIWorkspaceIdNormalizeOwnershipTests {
    private let candidate = "42"

    @Test func inputCStringNotMutated() {
        var inputBytes = cstringBytes(candidate)
        let inputBefore = inputBytes
        var buffer = [UInt8](repeating: 0, count: 64)

        _ = inputBytes.withUnsafeMutableBufferPointer { input in
            buffer.withUnsafeMutableBufferPointer { output in
                input.baseAddress!.withMemoryRebound(to: CChar.self, capacity: input.count) { cInput in
                    output.baseAddress!.withMemoryRebound(to: CChar.self, capacity: output.count) { cOutput in
                        omniwm_workspace_id_normalize(cInput, cOutput, output.count)
                    }
                }
            }
        }

        #expect(inputBytes == inputBefore)
    }

    @Test func deterministicOutputAndReturnValue() {
        let required = candidate.withCString { input in
            probeRequiredLength { buf, cap in
                buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                    omniwm_workspace_id_normalize(input, cbuf, cap)
                }
            }
        }
        #expect(required > 0)

        let capacity = Int(required) + 1
        var first = makeSentinelBuffer(capacity: capacity)
        var second = makeSentinelBuffer(capacity: capacity)

        let returned1 = candidate.withCString { input in
            first.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_workspace_id_normalize(input, cbuf, capacity)
                }
            }
        }
        let returned2 = candidate.withCString { input in
            second.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_workspace_id_normalize(input, cbuf, capacity)
                }
            }
        }

        #expect(returned1 == required)
        #expect(returned1 == returned2)
        #expect(first == second)
    }

    @Test func nulTerminatedOnSuccess() {
        let capacity = 64
        var buffer = makeSentinelBuffer(capacity: capacity)
        let returned = candidate.withCString { input in
            buffer.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_workspace_id_normalize(input, cbuf, capacity)
                }
            }
        }
        #expect(returned >= 0)
        #expect(buffer[Int(returned)] == 0)
    }

    @Test func doesNotWritePastCapacity() {
        let required = candidate.withCString { input in
            probeRequiredLength { buf, cap in
                buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                    omniwm_workspace_id_normalize(input, cbuf, cap)
                }
            }
        }
        let capacity = Int(required) + 1
        var buffer = makeSentinelBuffer(capacity: capacity)

        _ = candidate.withCString { input in
            buffer.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_workspace_id_normalize(input, cbuf, capacity)
                }
            }
        }

        for offset in capacity..<buffer.count {
            #expect(buffer[offset] == sentinelByte)
        }
    }
}


@Suite struct KernelABIAutomationManifestJSONOwnershipTests {
    @Test func deterministicOutputAndReturnValue() {
        let required = probeRequiredLength { buf, cap in
            buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                omniwm_ipc_automation_manifest_json(cbuf, cap)
            }
        }
        #expect(required > 0)

        let capacity = Int(required) + 1
        var first = makeSentinelBuffer(capacity: capacity)
        var second = makeSentinelBuffer(capacity: capacity)

        let returned1 = first.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                omniwm_ipc_automation_manifest_json(cbuf, capacity)
            }
        }
        let returned2 = second.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                omniwm_ipc_automation_manifest_json(cbuf, capacity)
            }
        }

        #expect(returned1 == required)
        #expect(returned1 == returned2)
        #expect(first == second)
    }

    @Test func nulTerminatedOnSuccess() {
        let required = probeRequiredLength { buf, cap in
            buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                omniwm_ipc_automation_manifest_json(cbuf, cap)
            }
        }
        let capacity = Int(required) + 1
        var buffer = makeSentinelBuffer(capacity: capacity)

        let returned = buffer.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                omniwm_ipc_automation_manifest_json(cbuf, capacity)
            }
        }

        #expect(returned >= 0)
        #expect(buffer[Int(returned)] == 0)
    }

    @Test func doesNotWritePastCapacity() {
        let required = probeRequiredLength { buf, cap in
            buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                omniwm_ipc_automation_manifest_json(cbuf, cap)
            }
        }
        let capacity = Int(required) + 1
        var buffer = makeSentinelBuffer(capacity: capacity)

        _ = buffer.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                omniwm_ipc_automation_manifest_json(cbuf, capacity)
            }
        }

        for offset in capacity..<buffer.count {
            #expect(buffer[offset] == sentinelByte)
        }
    }
}


@Suite struct KernelABIResolvedSocketPathOwnershipTests {
    private let homePath = "/Users/test"

    @Test func inputCStringsNotMutated() {
        var homeBytes = cstringBytes(homePath)
        let homeBefore = homeBytes
        var buffer = [UInt8](repeating: 0, count: 256)

        _ = homeBytes.withUnsafeMutableBufferPointer { homeBuf in
            buffer.withUnsafeMutableBufferPointer { outBuf in
                homeBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: homeBuf.count) { cHome in
                    outBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: outBuf.count) { cOut in
                        omniwm_ipc_resolved_socket_path(nil, cHome, cOut, outBuf.count)
                    }
                }
            }
        }

        #expect(homeBytes == homeBefore)
    }

    @Test func deterministicOutputAndReturnValue() {
        let required = homePath.withCString { home in
            probeRequiredLength { buf, cap in
                buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                    omniwm_ipc_resolved_socket_path(nil, home, cbuf, cap)
                }
            }
        }
        #expect(required > 0)

        let capacity = Int(required) + 1
        var first = makeSentinelBuffer(capacity: capacity)
        var second = makeSentinelBuffer(capacity: capacity)

        let returned1 = homePath.withCString { home in
            first.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_resolved_socket_path(nil, home, cbuf, capacity)
                }
            }
        }
        let returned2 = homePath.withCString { home in
            second.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_resolved_socket_path(nil, home, cbuf, capacity)
                }
            }
        }

        #expect(returned1 == required)
        #expect(returned1 == returned2)
        #expect(first == second)
    }

    @Test func nulTerminatedOnSuccess() {
        let capacity = 256
        var buffer = makeSentinelBuffer(capacity: capacity)
        let returned = homePath.withCString { home in
            buffer.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_resolved_socket_path(nil, home, cbuf, capacity)
                }
            }
        }
        #expect(returned >= 0)
        #expect(buffer[Int(returned)] == 0)
    }

    @Test func doesNotWritePastCapacity() {
        let required = homePath.withCString { home in
            probeRequiredLength { buf, cap in
                buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                    omniwm_ipc_resolved_socket_path(nil, home, cbuf, cap)
                }
            }
        }
        let capacity = Int(required) + 1
        var buffer = makeSentinelBuffer(capacity: capacity)

        _ = homePath.withCString { home in
            buffer.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_resolved_socket_path(nil, home, cbuf, capacity)
                }
            }
        }

        for offset in capacity..<buffer.count {
            #expect(buffer[offset] == sentinelByte)
        }
    }
}


@Suite struct KernelABISecretPathOwnershipTests {
    private let socketPath = "/tmp/omniwm-test.sock"

    @Test func inputCStringNotMutated() {
        var inputBytes = cstringBytes(socketPath)
        let inputBefore = inputBytes
        var buffer = [UInt8](repeating: 0, count: 256)

        _ = inputBytes.withUnsafeMutableBufferPointer { inBuf in
            buffer.withUnsafeMutableBufferPointer { outBuf in
                inBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: inBuf.count) { cIn in
                    outBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: outBuf.count) { cOut in
                        omniwm_ipc_secret_path(cIn, cOut, outBuf.count)
                    }
                }
            }
        }

        #expect(inputBytes == inputBefore)
    }

    @Test func deterministicOutputAndReturnValue() {
        let required = socketPath.withCString { socket in
            probeRequiredLength { buf, cap in
                buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                    omniwm_ipc_secret_path(socket, cbuf, cap)
                }
            }
        }
        #expect(required > 0)

        let capacity = Int(required) + 1
        var first = makeSentinelBuffer(capacity: capacity)
        var second = makeSentinelBuffer(capacity: capacity)

        let returned1 = socketPath.withCString { socket in
            first.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_secret_path(socket, cbuf, capacity)
                }
            }
        }
        let returned2 = socketPath.withCString { socket in
            second.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_secret_path(socket, cbuf, capacity)
                }
            }
        }

        #expect(returned1 == required)
        #expect(returned1 == returned2)
        #expect(first == second)
    }

    @Test func nulTerminatedOnSuccess() {
        let capacity = 256
        var buffer = makeSentinelBuffer(capacity: capacity)
        let returned = socketPath.withCString { socket in
            buffer.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_secret_path(socket, cbuf, capacity)
                }
            }
        }
        #expect(returned >= 0)
        #expect(buffer[Int(returned)] == 0)
    }

    @Test func doesNotWritePastCapacity() {
        let required = socketPath.withCString { socket in
            probeRequiredLength { buf, cap in
                buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                    omniwm_ipc_secret_path(socket, cbuf, cap)
                }
            }
        }
        let capacity = Int(required) + 1
        var buffer = makeSentinelBuffer(capacity: capacity)

        _ = socketPath.withCString { socket in
            buffer.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_secret_path(socket, cbuf, capacity)
                }
            }
        }

        for offset in capacity..<buffer.count {
            #expect(buffer[offset] == sentinelByte)
        }
    }
}


private struct SecretTokenFixture {
    let directory: URL
    let socketPath: String
    let secretPath: String
    let token: String

    init(token: String) throws {
        self.directory = try makeTemporarySecretDirectory()
        self.socketPath = directory.appendingPathComponent("s").path
        self.secretPath = "\(socketPath).secret"
        self.token = token

        let body = (token + "\n").data(using: .utf8)!
        try body.write(to: URL(fileURLWithPath: secretPath))
        let chmodResult = secretPath.withCString { Darwin.chmod($0, 0o600) }
        guard chmodResult == 0 else {
            throw POSIXError(.EPERM)
        }
    }

    func cleanup() {
        _ = unlink(secretPath)
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite struct KernelABIReadSecretTokenOwnershipTests {
    @Test func inputCStringNotMutated() throws {
        let fixture = try SecretTokenFixture(token: "abc123")
        defer { fixture.cleanup() }

        var pathBytes = cstringBytes(fixture.socketPath)
        let pathBefore = pathBytes
        var buffer = [UInt8](repeating: 0, count: 1024)

        _ = pathBytes.withUnsafeMutableBufferPointer { pathBuf in
            buffer.withUnsafeMutableBufferPointer { outBuf in
                pathBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: pathBuf.count) { cPath in
                    outBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: outBuf.count) { cOut in
                        omniwm_ipc_read_secret_token_for_socket(cPath, cOut, outBuf.count)
                    }
                }
            }
        }

        #expect(pathBytes == pathBefore)
    }

    @Test func deterministicOutputAndReturnValue() throws {
        let fixture = try SecretTokenFixture(token: "abc123")
        defer { fixture.cleanup() }

        let required = fixture.socketPath.withCString { path in
            probeRequiredLength { buf, cap in
                buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                    omniwm_ipc_read_secret_token_for_socket(path, cbuf, cap)
                }
            }
        }
        try #require(required > 0)

        let capacity = Int(required) + 1
        var first = makeSentinelBuffer(capacity: capacity)
        var second = makeSentinelBuffer(capacity: capacity)

        let returned1 = fixture.socketPath.withCString { path in
            first.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_read_secret_token_for_socket(path, cbuf, capacity)
                }
            }
        }
        let returned2 = fixture.socketPath.withCString { path in
            second.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_read_secret_token_for_socket(path, cbuf, capacity)
                }
            }
        }

        #expect(returned1 == required)
        #expect(returned1 == returned2)
        #expect(first == second)
    }

    @Test func nulTerminatedOnSuccess() throws {
        let fixture = try SecretTokenFixture(token: "abc123")
        defer { fixture.cleanup() }

        let capacity = 256
        var buffer = makeSentinelBuffer(capacity: capacity)
        let returned = fixture.socketPath.withCString { path in
            buffer.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_read_secret_token_for_socket(path, cbuf, capacity)
                }
            }
        }
        try #require(returned >= 0)
        #expect(buffer[Int(returned)] == 0)
    }

    @Test func doesNotWritePastCapacity() throws {
        let fixture = try SecretTokenFixture(token: "abc123")
        defer { fixture.cleanup() }

        let required = fixture.socketPath.withCString { path in
            probeRequiredLength { buf, cap in
                buf.withMemoryRebound(to: CChar.self, capacity: cap) { cbuf in
                    omniwm_ipc_read_secret_token_for_socket(path, cbuf, cap)
                }
            }
        }
        try #require(required > 0)

        let capacity = Int(required) + 1
        var buffer = makeSentinelBuffer(capacity: capacity)

        _ = fixture.socketPath.withCString { path in
            buffer.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: capacity) { cbuf in
                    omniwm_ipc_read_secret_token_for_socket(path, cbuf, capacity)
                }
            }
        }

        for offset in capacity..<buffer.count {
            #expect(buffer[offset] == sentinelByte)
        }
    }
}
