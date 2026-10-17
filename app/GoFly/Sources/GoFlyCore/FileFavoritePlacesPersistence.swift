import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum FavoritePlacesWriteCheckpoint: CaseIterable, Equatable, Sendable {
    case stagingSecured, contentsWritten, stagingFlushed
}

/// A private, normal-backup-eligible favorites archive. All throwable work is
/// precommit; the final rename is the single authoritative commit operation.
public struct FileFavoritePlacesPersistence: FavoritePlacesPersistence {
    public let fileURL: URL
    private let directory: URL
    private let checkpoint: @Sendable (FavoritePlacesWriteCheckpoint) throws -> Void
    private static let filename = "favorites.json"

    public init(directory: URL,
                checkpoint: @escaping @Sendable (FavoritePlacesWriteCheckpoint) throws -> Void = { _ in }) {
        self.directory = directory.standardizedFileURL
        fileURL = directory.standardizedFileURL.appendingPathComponent(Self.filename)
        self.checkpoint = checkpoint
    }

    public func read() throws -> Data? {
        #if canImport(Darwin)
        guard let directoryFD = try openDirectory(create: false) else { return nil }
        defer { Darwin.close(directoryFD) }
        let descriptor = openat(directoryFD, Self.filename, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw pathFailure(errno)
        }
        defer { Darwin.close(descriptor) }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else { throw FavoritePlacesFailure.unavailable }
        guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw FavoritePlacesFailure.unsafeFile }
        guard attributes.st_size >= 0, attributes.st_size <= FavoritePlacesLimits.fileBytes else {
            throw FavoritePlacesFailure.limitExceeded
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count == -1, errno == EINTR { continue }
            guard count >= 0 else { throw FavoritePlacesFailure.unavailable }
            if count == 0 { return data }
            guard data.count + count <= FavoritePlacesLimits.fileBytes else { throw FavoritePlacesFailure.limitExceeded }
            data.append(contentsOf: buffer.prefix(count))
        }
        #else
        throw FavoritePlacesFailure.unavailable
        #endif
    }

    public func replaceAtomically(with data: Data) throws {
        guard data.count <= FavoritePlacesLimits.fileBytes else { throw FavoritePlacesFailure.limitExceeded }
        #if canImport(Darwin)
        guard let directoryFD = try openDirectory(create: true) else { throw FavoritePlacesFailure.unavailable }
        defer { Darwin.close(directoryFD) }
        guard fchmod(directoryFD, 0o700) == 0 else { throw FavoritePlacesFailure.writeFailed }
        try protect(directory)
        try requireRegularTarget(directoryFD)
        let stagingName = ".favorites-\(UUID().uuidString).staging"
        let stagingURL = directory.appendingPathComponent(stagingName)
        let descriptor = openat(directoryFD, stagingName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw FavoritePlacesFailure.writeFailed }
        var committed = false
        defer {
            Darwin.close(descriptor)
            if !committed { unlinkat(directoryFD, stagingName, 0) }
        }
        guard fchmod(descriptor, 0o600) == 0 else { throw FavoritePlacesFailure.writeFailed }
        try protect(stagingURL)
        try checkpoint(.stagingSecured)
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count == -1, errno == EINTR { continue }
                guard count > 0 else { throw FavoritePlacesFailure.writeFailed }
                offset += count
            }
        }
        try checkpoint(.contentsWritten)
        guard fsync(descriptor) == 0 else { throw FavoritePlacesFailure.writeFailed }
        try checkpoint(.stagingFlushed)
        try requireRegularTarget(directoryFD)
        guard renameat(directoryFD, stagingName, directoryFD, Self.filename) == 0 else {
            throw FavoritePlacesFailure.writeFailed
        }
        committed = true
        // No throwing attributes, protection, synchronization or readback after commit.
        #else
        throw FavoritePlacesFailure.unavailable
        #endif
    }

    #if canImport(Darwin)
    private func openDirectory(create: Bool) throws -> Int32? {
        if create {
            let existing = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if existing >= 0 { return existing }
            guard errno == ENOENT else { throw pathFailure(errno) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if !create, errno == ENOENT { return nil }
            throw pathFailure(errno)
        }
        return descriptor
    }
    private func requireRegularTarget(_ directoryFD: Int32) throws {
        var attributes = stat()
        guard fstatat(directoryFD, Self.filename, &attributes, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return }
            throw pathFailure(errno)
        }
        guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw FavoritePlacesFailure.unsafeFile }
    }
    private func pathFailure(_ code: Int32) -> FavoritePlacesFailure {
        code == ELOOP || code == ENOTDIR ? .unsafeFile : .unavailable
    }
    #endif

    private func protect(_ url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes([
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ], ofItemAtPath: url.path)
        #endif
    }
}
