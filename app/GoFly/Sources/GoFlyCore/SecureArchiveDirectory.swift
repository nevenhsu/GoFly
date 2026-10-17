import Darwin
import Foundation

enum SecureArchiveFailure: Error { case unsafeFile, unavailable, writeFailed, limitExceeded }
enum SecureArchiveWriteCheckpoint { case secured, written, flushed }

/// Package-only primitives pinned to a no-follow directory FD. This type knows
/// nothing about archive schemas, owned filenames, cleanup, quotas or undo.
/// Instances stay inside synchronous domain transactions and never cross await.
final class SecureArchiveDirectory {
    private let descriptor: Int32
    private let url: URL
    private init(descriptor: Int32, url: URL) { self.descriptor = descriptor; self.url = url }
    deinit { Darwin.close(descriptor) }

    static func open(_ url: URL, create: Bool, secureDirectory: Bool) throws -> SecureArchiveDirectory? {
        var descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0, errno == ENOENT, create {
            do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            catch { throw SecureArchiveFailure.unavailable }
            descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            if !create, errno == ENOENT { return nil }
            throw pathFailure(errno)
        }
        let directory = SecureArchiveDirectory(descriptor: descriptor, url: url)
        if secureDirectory {
            guard fchmod(descriptor, 0o700) == 0 else { throw SecureArchiveFailure.writeFailed }
            try protect(url)
        }
        return directory
    }

    func attributes(_ name: String) throws -> stat? {
        try requireComponent(name)
        var value = stat()
        guard fstatat(descriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return nil }
            throw Self.pathFailure(errno)
        }
        guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), value.st_size >= 0 else { throw SecureArchiveFailure.unsafeFile }
        return value
    }

    func read(_ name: String, maximum: Int) throws -> Data? {
        try requireComponent(name)
        let fd = openat(descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw Self.pathFailure(errno)
        }
        defer { Darwin.close(fd) }
        var value = stat()
        guard fstat(fd, &value) == 0 else { throw SecureArchiveFailure.unavailable }
        guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw SecureArchiveFailure.unsafeFile }
        guard value.st_size >= 0, value.st_size <= maximum else { throw SecureArchiveFailure.limitExceeded }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, min($0.count, maximum + 1 - data.count)) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw SecureArchiveFailure.unavailable }
            if count == 0 { return data }
            guard data.count + count <= maximum else { throw SecureArchiveFailure.limitExceeded }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    /// A flushed immutable payload survives a later callback failure as an owned
    /// orphan. Before flush, best-effort rollback removes the partial file.
    func writeExclusive(_ data: Data, name: String, checkpoint: (SecureArchiveWriteCheckpoint) throws -> Void) throws {
        try requireComponent(name)
        let fd = openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SecureArchiveFailure.writeFailed }
        var durable = false
        defer { Darwin.close(fd); if !durable { unlinkat(descriptor, name, 0) } }
        guard fchmod(fd, 0o600) == 0 else { throw SecureArchiveFailure.writeFailed }
        try Self.protect(url.appendingPathComponent(name))
        try checkpoint(.secured)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw SecureArchiveFailure.writeFailed }
                offset += count
            }
        }
        try checkpoint(.written)
        guard fsync(fd) == 0 else { throw SecureArchiveFailure.writeFailed }
        durable = true
        try checkpoint(.flushed)
    }

    /// Rename is the final authoritative operation. No throwable work or
    /// callback may follow it, so failure always preserves previous bytes.
    func replaceAtomically(_ data: Data, target: String, staging: String,
                           checkpoint: (SecureArchiveWriteCheckpoint) throws -> Void,
                           beforeCommit: () throws -> Void = {}) throws {
        try requireComponent(target)
        try requireComponent(staging)
        _ = try attributes(target)
        var committed = false
        var ownsStaging = false
        defer { if !committed, ownsStaging { unlinkat(descriptor, staging, 0) } }
        try writeExclusive(data, name: staging) { point in
            // O_EXCL failure must never remove a pre-existing staging path.
            // Earlier securing failures are rolled back by writeExclusive.
            ownsStaging = true
            try checkpoint(point)
        }
        _ = try attributes(target)
        try beforeCommit()
        guard renameat(descriptor, staging, descriptor, target) == 0 else { throw SecureArchiveFailure.writeFailed }
        committed = true
    }

    func names() throws -> [String] {
        let copy = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copy >= 0 else { throw SecureArchiveFailure.unavailable }
        guard let directory = fdopendir(copy) else { Darwin.close(copy); throw SecureArchiveFailure.unavailable }
        defer { closedir(directory) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != ".", name != ".." { names.append(name) }
            errno = 0
        }
        guard errno == 0 else { throw SecureArchiveFailure.unavailable }
        return names
    }

    func removeRegularFile(_ name: String) throws {
        guard try attributes(name) != nil else { return }
        guard unlinkat(descriptor, name, 0) == 0 else { throw SecureArchiveFailure.writeFailed }
    }
    private func requireComponent(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { throw SecureArchiveFailure.unsafeFile }
    }
    private static func pathFailure(_ code: Int32) -> SecureArchiveFailure {
        code == ELOOP || code == ENOTDIR ? .unsafeFile : .unavailable
    }
    private static func protect(_ url: URL) throws {
        #if os(iOS)
        do { try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path) }
        catch { throw SecureArchiveFailure.writeFailed }
        #endif
    }
}
