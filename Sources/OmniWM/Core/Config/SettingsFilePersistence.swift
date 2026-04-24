// SPDX-License-Identifier: GPL-2.0-only
import Darwin
import Foundation

@MainActor
final class SettingsFilePersistence {
    struct FileFingerprint: Equatable {
        // Atomic external editors replace the path with a new inode; mtime+size alone
        // can match a just-written file closely enough to suppress a real reload.
        let deviceID: UInt64
        let inode: UInt64
        let modificationTimeNanoseconds: Int64
        let statusChangeTimeNanoseconds: Int64
        let fileSize: UInt64
    }

    private struct FileSnapshot {
        let export: SettingsExport
        let fingerprint: FileFingerprint
    }

    private static let nanosecondsPerSecond: Int64 = 1_000_000_000

    nonisolated static let defaultDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/omniwm", isDirectory: true)
    nonisolated static let fileName = "settings.toml"
    nonisolated static let corruptFileName = "settings.toml.corrupt"
    nonisolated static var fileURL: URL {
        defaultDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    let directoryURL: URL
    let fileURL: URL

    private let deferSaves: Bool
    private var directoryFileDescriptor: CInt = -1
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var pendingExport: SettingsExport?
    private var saveScheduled = false
    private var lastWrittenFingerprint: FileFingerprint?
    private var lastObservedFingerprint: FileFingerprint?
    private var onExternalChange: (@MainActor (SettingsExport) -> Void)?

    init(
        directory: URL = SettingsFilePersistence.defaultDirectoryURL,
        startWatching: Bool = true,
        deferSaves: Bool = true
    ) {
        directoryURL = directory
        fileURL = directory.appendingPathComponent(Self.fileName, isDirectory: false)
        self.deferSaves = deferSaves

        if startWatching {
            startFileWatcher()
        }
    }

    deinit {
        directoryWatcher?.cancel()
        if directoryWatcher == nil, directoryFileDescriptor >= 0 {
            close(directoryFileDescriptor)
        }
    }

    func setExternalChangeHandler(_ handler: @escaping @MainActor (SettingsExport) -> Void) {
        onExternalChange = handler
    }

    func load() -> SettingsExport {
        do {
            try ensureDirectoryExists()
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                let defaults = SettingsExport.defaults()
                save(defaults)
                return defaults
            }

            let snapshot = try readSnapshot()
            lastObservedFingerprint = snapshot.fingerprint
            return snapshot.export
        } catch {
            report("Failed to load \(fileURL.path): \(error.localizedDescription)")
            moveCorruptFileAsideIfPresent()
            let defaults = SettingsExport.defaults()
            save(defaults)
            return defaults
        }
    }

    func save(_ export: SettingsExport) {
        do {
            try ensureDirectoryExists()
            let data = try SettingsTOMLCodec.encode(export)
            try data.write(to: fileURL, options: .atomic)

            let fingerprint = currentFingerprint()
            lastWrittenFingerprint = fingerprint
            lastObservedFingerprint = fingerprint
        } catch {
            report("Failed to save \(fileURL.path): \(error.localizedDescription)")
        }
    }

    func scheduleSave(_ export: @autoclosure () -> SettingsExport) {
        if !deferSaves {
            pendingExport = nil
            save(export())
            return
        }

        pendingExport = export()
        guard !saveScheduled else { return }
        saveScheduled = true

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            saveScheduled = false
            flushNow()
        }
    }

    func flushNow() {
        guard let export = pendingExport else { return }
        pendingExport = nil
        save(export)
    }

    func reloadIfChanged() -> SettingsExport? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            report("Ignoring external reload because \(fileURL.path) no longer exists.")
            return nil
        }

        do {
            let snapshot = try readSnapshot()
            lastObservedFingerprint = snapshot.fingerprint
            return snapshot.export
        } catch {
            report("Ignoring invalid external settings edit at \(fileURL.path): \(error.localizedDescription)")
            return nil
        }
    }

    private func startFileWatcher() {
        do {
            try ensureDirectoryExists()
        } catch {
            report("Failed to create settings directory \(directoryURL.path): \(error.localizedDescription)")
            return
        }

        directoryFileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else {
            report("Failed to watch settings directory \(directoryURL.path).")
            return
        }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: .write,
            queue: .main
        )
        watcher.setEventHandler { [weak self] in
            self?.handleDirectoryWriteEvent()
        }
        watcher.setCancelHandler { [weak self] in
            guard let self, self.directoryFileDescriptor >= 0 else { return }
            close(self.directoryFileDescriptor)
            self.directoryFileDescriptor = -1
        }
        directoryWatcher = watcher
        watcher.resume()
    }

    private func handleDirectoryWriteEvent() {
        let observedFingerprint = currentFingerprint()

        if observedFingerprint == lastWrittenFingerprint {
            lastObservedFingerprint = observedFingerprint
            return
        }

        guard observedFingerprint != lastObservedFingerprint else { return }
        guard let export = reloadIfChanged() else { return }
        onExternalChange?(export)
    }

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func readSnapshot() throws -> FileSnapshot {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        guard let data = try handle.readToEnd() else {
            throw CocoaError(.fileReadUnknown)
        }

        var statBuffer = stat()
        guard Darwin.fstat(handle.fileDescriptor, &statBuffer) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        return FileSnapshot(
            export: try SettingsTOMLCodec.decode(data),
            fingerprint: Self.fingerprint(from: statBuffer)
        )
    }

    private func currentFingerprint() -> FileFingerprint? {
        var statBuffer = stat()
        let result = fileURL.withUnsafeFileSystemRepresentation { path -> CInt in
            guard let path else { return -1 }
            return Darwin.fstatat(AT_FDCWD, path, &statBuffer, 0)
        }

        guard result == 0 else { return nil }
        return Self.fingerprint(from: statBuffer)
    }

    private static func fingerprint(from statBuffer: stat) -> FileFingerprint {
        FileFingerprint(
            deviceID: UInt64(statBuffer.st_dev),
            inode: UInt64(statBuffer.st_ino),
            modificationTimeNanoseconds: nanoseconds(from: statBuffer.st_mtimespec),
            statusChangeTimeNanoseconds: nanoseconds(from: statBuffer.st_ctimespec),
            fileSize: UInt64(statBuffer.st_size)
        )
    }

    private static func nanoseconds(from timestamp: timespec) -> Int64 {
        Int64(timestamp.tv_sec) * nanosecondsPerSecond + Int64(timestamp.tv_nsec)
    }

    private func moveCorruptFileAsideIfPresent() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let corruptURL = directoryURL.appendingPathComponent(Self.corruptFileName, isDirectory: false)
        try? FileManager.default.removeItem(at: corruptURL)

        do {
            try FileManager.default.moveItem(at: fileURL, to: corruptURL)
        } catch {
            report("Failed to move corrupt settings file aside: \(error.localizedDescription)")
        }
    }

    private func report(_ message: String) {
        fputs("[SettingsFilePersistence] \(message)\n", stderr)
    }
}
