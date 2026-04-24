// SPDX-License-Identifier: GPL-2.0-only

import COmniWMKernels
import Darwin
import Foundation
import Testing

private func makeTemporarySocketDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("omniwm-ipc-sock-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func socketPath(in directory: URL, name: String = "s") -> String {
    directory.appendingPathComponent(name).path
}

private func closeFD(_ fileDescriptor: Int32) {
    if fileDescriptor >= 0 {
        _ = Darwin.close(fileDescriptor)
    }
}


@Suite struct KernelABIIPCSocketMakeListeningTests {
    @Test func returnsValidFileDescriptorAndSetsMode0600() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        let fileDescriptor = path.withCString { omniwm_ipc_socket_make_listening($0) }
        defer { closeFD(fileDescriptor) }
        defer { _ = unlink(path) }

        #expect(fileDescriptor >= 0, "expected non-negative fd, got \(fileDescriptor) errno=\(errno)")

        var status = stat()
        let statResult = path.withCString { lstat($0, &status) }
        #expect(statResult == 0, "lstat failed: errno=\(errno)")
        #expect((status.st_mode & S_IFMT) == S_IFSOCK)
        #expect((status.st_mode & 0o777) == 0o600,
                "expected mode 0600, got 0\(String(status.st_mode & 0o777, radix: 8))")
    }

    @Test func nullPathSetsErrnoToEINVAL() {
        errno = 0
        let result = omniwm_ipc_socket_make_listening(nil)
        #expect(result == -1)
        #expect(errno == EINVAL)
    }
}


@Suite struct KernelABIIPCSocketConnectTests {
    @Test func connectsToActiveListener() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        let listener = path.withCString { omniwm_ipc_socket_make_listening($0) }
        defer { closeFD(listener) }
        defer { _ = unlink(path) }
        try #require(listener >= 0)

        let client = path.withCString { omniwm_ipc_socket_connect($0) }
        defer { closeFD(client) }

        #expect(client >= 0, "expected non-negative fd, got \(client) errno=\(errno)")
    }

    @Test func failsWithECONNREFUSEDWhenNoListener() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        errno = 0
        let result = path.withCString { omniwm_ipc_socket_connect($0) }
        defer { closeFD(result) }

        #expect(result == -1)
        #expect(errno == ENOENT || errno == ECONNREFUSED,
                "expected ENOENT or ECONNREFUSED, got \(errno)")
    }

    @Test func nullPathSetsErrnoToEINVAL() {
        errno = 0
        let result = omniwm_ipc_socket_connect(nil)
        #expect(result == -1)
        #expect(errno == EINVAL)
    }
}


@Suite struct KernelABIIPCSocketIsActiveTests {
    @Test func returnsOneForActiveListener() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        let listener = path.withCString { omniwm_ipc_socket_make_listening($0) }
        defer { closeFD(listener) }
        defer { _ = unlink(path) }
        try #require(listener >= 0)

        let result = path.withCString { omniwm_ipc_socket_is_active($0) }
        #expect(result == 1)
    }

    @Test func returnsZeroForMissingPath() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        let result = path.withCString { omniwm_ipc_socket_is_active($0) }
        #expect(result == 0)
    }

    @Test func nullPathSetsErrnoToEINVAL() {
        errno = 0
        let result = omniwm_ipc_socket_is_active(nil)
        #expect(result == -1)
        #expect(errno == EINVAL)
    }
}


@Suite struct KernelABIIPCSocketRemoveExistingTests {
    @Test func returnsZeroWhenNoFileExists() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        let result = path.withCString { omniwm_ipc_socket_remove_existing_if_needed($0) }
        #expect(result == 0)
    }

    @Test func removesStaleSocketFile() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        let listener = path.withCString { omniwm_ipc_socket_make_listening($0) }
        try #require(listener >= 0)
        closeFD(listener)

        let result = path.withCString { omniwm_ipc_socket_remove_existing_if_needed($0) }
        #expect(result == 0)

        var status = stat()
        let statResult = path.withCString { lstat($0, &status) }
        #expect(statResult == -1, "expected the socket file to be unlinked")
        #expect(errno == ENOENT)
    }

    @Test func failsWithEEXISTForNonSocketFile() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        try Data().write(to: URL(fileURLWithPath: path))
        defer { _ = unlink(path) }

        errno = 0
        let result = path.withCString { omniwm_ipc_socket_remove_existing_if_needed($0) }
        #expect(result == -1)
        #expect(errno == EEXIST)
    }

    @Test func failsWithEADDRINUSEForActiveSocket() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        let listener = path.withCString { omniwm_ipc_socket_make_listening($0) }
        defer { closeFD(listener) }
        defer { _ = unlink(path) }
        try #require(listener >= 0)

        errno = 0
        let result = path.withCString { omniwm_ipc_socket_remove_existing_if_needed($0) }
        #expect(result == -1)
        #expect(errno == EADDRINUSE)
    }

    @Test func nullPathSetsErrnoToEINVAL() {
        errno = 0
        let result = omniwm_ipc_socket_remove_existing_if_needed(nil)
        #expect(result == -1)
        #expect(errno == EINVAL)
    }
}


@Suite struct KernelABIIPCSocketConfigureTests {
    @Test func setsNonBlockingFlagOnValidFd() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        let fileDescriptor = path.withCString { omniwm_ipc_socket_make_listening($0) }
        defer { closeFD(fileDescriptor) }
        defer { _ = unlink(path) }
        try #require(fileDescriptor >= 0)

        let baselineFlags = fcntl(fileDescriptor, F_GETFL, 0)
        try #require(baselineFlags >= 0)
        _ = fcntl(fileDescriptor, F_SETFL, baselineFlags & ~O_NONBLOCK)

        let result = omniwm_ipc_socket_configure(fileDescriptor, 1)
        #expect(result == 0)

        let updatedFlags = fcntl(fileDescriptor, F_GETFL, 0)
        #expect(updatedFlags >= 0)
        #expect((updatedFlags & O_NONBLOCK) == O_NONBLOCK,
                "expected O_NONBLOCK to be set, flags=\(updatedFlags)")
    }

    @Test func badFdSetsErrnoToEBADF() {
        errno = 0
        let result = omniwm_ipc_socket_configure(-1, 1)
        #expect(result == -1)
        #expect(errno == EBADF)
    }
}


@Suite struct KernelABIIPCSocketIsCurrentUserTests {
    @Test func returnsOneForOwnConnectedSocket() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        let listener = path.withCString { omniwm_ipc_socket_make_listening($0) }
        defer { closeFD(listener) }
        defer { _ = unlink(path) }
        try #require(listener >= 0)

        let client = path.withCString { omniwm_ipc_socket_connect($0) }
        defer { closeFD(client) }
        try #require(client >= 0)

        var peerAddress = sockaddr()
        var peerAddressLength = socklen_t(MemoryLayout<sockaddr>.size)
        let serverSide = accept(listener, &peerAddress, &peerAddressLength)
        defer { closeFD(serverSide) }
        try #require(serverSide >= 0)

        let result = omniwm_ipc_socket_is_current_user(serverSide)
        #expect(result == 1)
    }

    @Test func returnsNegativeOneForBadFd() {
        let result = omniwm_ipc_socket_is_current_user(-1)
        #expect(result == -1)
    }
}


@Suite struct KernelABIIPCWriteSecretTokenTests {
    @Test func writesTokenWithMode0600() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)
        let secretPath = path + ".secret"

        let token = "abcdef0123456789"
        let result = path.withCString { socketPathPointer in
            token.withCString { tokenPointer in
                omniwm_ipc_write_secret_token(socketPathPointer, tokenPointer)
            }
        }
        defer { _ = unlink(secretPath) }

        #expect(result == 0)

        var status = stat()
        let statResult = secretPath.withCString { lstat($0, &status) }
        #expect(statResult == 0)
        #expect((status.st_mode & S_IFMT) == S_IFREG)
        #expect((status.st_mode & 0o777) == 0o600,
                "expected mode 0600, got 0\(String(status.st_mode & 0o777, radix: 8))")

        let contents = try Data(contentsOf: URL(fileURLWithPath: secretPath))
        #expect(contents == Data((token + "\n").utf8))
    }

    @Test func overwritesExistingSecretFile() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)
        let secretPath = path + ".secret"

        for token in ["first", "second"] {
            let result = path.withCString { socketPathPointer in
                token.withCString { tokenPointer in
                    omniwm_ipc_write_secret_token(socketPathPointer, tokenPointer)
                }
            }
            #expect(result == 0)
        }
        defer { _ = unlink(secretPath) }

        let contents = try Data(contentsOf: URL(fileURLWithPath: secretPath))
        #expect(contents == Data("second\n".utf8))
    }

    @Test func nullSocketPathSetsErrnoToEINVAL() {
        errno = 0
        let result = omniwm_ipc_write_secret_token(nil, "token")
        #expect(result == -1)
        #expect(errno == EINVAL)
    }

    @Test func nullTokenSetsErrnoToEINVAL() throws {
        let directory = try makeTemporarySocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = socketPath(in: directory)

        errno = 0
        let result = path.withCString { omniwm_ipc_write_secret_token($0, nil) }
        #expect(result == -1)
        #expect(errno == EINVAL)
    }
}
