import CryptoKit
import Darwin
import Foundation

/// A retained descriptor for one immutable transfer root.  All descendants
/// are opened relative to this descriptor and no path component is followed.
final class _TransferDirectoryHandle: @unchecked Sendable {
    let fd: Int32

    init(fd: Int32) { self.fd = fd }

    deinit { Darwin.close(fd) }

    func read(_ name: String, maximum: Int, requirePrivate: Bool = true) throws -> Data? {
        let file = try openLeaf(name, flags: O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard let file else { return nil }
        defer { Darwin.close(file) }
        var initial = stat()
        guard fstat(file, &initial) == 0 else { throw TransferFailure.unavailable }
        try TransferFileIO.validateFile(initial, requirePrivate: requirePrivate)
        guard initial.st_size >= 0, initial.st_size <= off_t(maximum) else { throw TransferFailure.limitExceeded }

        var data = Data(capacity: min(Int(initial.st_size), maximum))
        var buffer = [UInt8](repeating: 0, count: 32 * 1_024)
        while true {
            let requested = min(buffer.count, max(1, maximum + 1 - data.count))
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(file, bytes.baseAddress, requested)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw TransferFailure.unavailable }
            if count == 0 { break }
            guard data.count + count <= maximum else { throw TransferFailure.limitExceeded }
            data.append(contentsOf: buffer.prefix(count))
        }
        try TransferFileIO.validateUnchanged(file, initial: initial, actualSize: data.count)
        return data
    }

    /// Streams a file into a digest without allocating its contents.
    func inspect(_ name: String, maximum: Int, requirePrivate: Bool = true) throws -> (size: Int64, sha256: String)? {
        let file = try openLeaf(name, flags: O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard let file else { return nil }
        defer { Darwin.close(file) }
        var initial = stat()
        guard fstat(file, &initial) == 0 else { throw TransferFailure.unavailable }
        try TransferFileIO.validateFile(initial, requirePrivate: requirePrivate)
        guard initial.st_size >= 0, initial.st_size <= off_t(maximum) else { throw TransferFailure.limitExceeded }

        var digest = SHA256()
        var total = 0
        var buffer = [UInt8](repeating: 0, count: 32 * 1_024)
        while true {
            let requested = min(buffer.count, max(1, maximum + 1 - total))
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(file, bytes.baseAddress, requested)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw TransferFailure.unavailable }
            if count == 0 { break }
            guard total + count <= maximum else { throw TransferFailure.limitExceeded }
            digest.update(data: Data(buffer.prefix(count)))
            total += count
        }
        try TransferFileIO.validateUnchanged(file, initial: initial, actualSize: total)
        let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        return (Int64(total), hash)
    }

    func inventory(maxDepth: Int = 4, maxEntries: Int = 512) throws -> [(String, Bool)] {
        guard maxDepth >= 0, maxEntries >= 1 else { throw TransferFailure.invalidInput }
        var result: [(String, Bool)] = []
        try enumerate(fd, prefix: "", depth: 0, maxDepth: maxDepth, maxEntries: maxEntries, result: &result)
        return result
    }

    private func openLeaf(_ relativePath: String, flags: Int32) throws -> Int32? {
        guard TransferFileIO.validRelativePath(relativePath) else { throw TransferFailure.unsafeFile }
        let components = relativePath.split(separator: "/").map(String.init)
        var current = Darwin.dup(fd)
        guard current >= 0 else { throw TransferFailure.unavailable }
        _ = fcntl(current, F_SETFD, FD_CLOEXEC)
        for (index, component) in components.enumerated() {
            let isFinal = index == components.count - 1
            let nextFlags: Int32 = isFinal ? flags : (O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let next = openat(current, component, nextFlags, 0)
            let openError = errno
            Darwin.close(current)
            if next < 0 {
                if openError == ENOENT { return nil }
                if openError == ELOOP || openError == ENOTDIR { throw TransferFailure.unsafeFile }
                throw TransferFailure.unavailable
            }
            current = next
        }
        return current
    }

    private func enumerate(_ directory: Int32, prefix: String, depth: Int,
                           maxDepth: Int, maxEntries: Int,
                           result: inout [(String, Bool)]) throws {
        guard depth < maxDepth else {
            // A directory at the bound is valid only when it is empty.  Open
            // and inspect it so a hidden descendant cannot bypass inventory.
            let duplicate = Darwin.dup(directory)
            guard duplicate >= 0 else { throw TransferFailure.unavailable }
            defer { Darwin.close(duplicate) }
            guard let stream = fdopendir(duplicate) else { throw TransferFailure.unavailable }
            defer { closedir(stream) }
            while let entry = readdir(stream) {
                let name = TransferFileIO.directoryEntryName(entry)
                if name != "." && name != ".." { throw TransferFailure.limitExceeded }
            }
            return
        }
        let duplicate = Darwin.dup(directory)
        guard duplicate >= 0 else { throw TransferFailure.unavailable }
        guard let stream = fdopendir(duplicate) else {
            Darwin.close(duplicate)
            throw TransferFailure.unavailable
        }
        defer { closedir(stream) }
        while let entry = readdir(stream) {
            let name = TransferFileIO.directoryEntryName(entry)
            if name == "." || name == ".." { continue }
            guard !name.isEmpty, !name.contains("/") else {
                throw TransferFailure.unsafeFile
            }
            result.append((prefix.isEmpty ? name : prefix + "/" + name, false))
            guard result.count <= maxEntries else { throw TransferFailure.limitExceeded }
            let childPath = prefix.isEmpty ? name : prefix + "/" + name
            var info = stat()
            guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw TransferFailure.unavailable }
            let type = info.st_mode & TransferFileIO.regularMask
            if type == mode_t(S_IFDIR) {
                try TransferFileIO.validateDirectory(info)
                result[result.count - 1] = (childPath, true)
                let child = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC, 0)
                guard child >= 0 else { throw TransferFailure.unsafeFile }
                defer { Darwin.close(child) }
                try enumerate(child, prefix: childPath, depth: depth + 1,
                              maxDepth: maxDepth, maxEntries: maxEntries, result: &result)
            } else if type == mode_t(S_IFREG) {
                try TransferFileIO.validateFile(info)
            } else {
                throw TransferFailure.unsafeFile
            }
        }
    }
}

/// Read-only, no-follow file primitives shared by transfer snapshots and
/// package validation. No method creates, chmods, removes or renames paths.
enum TransferFileIO {
    fileprivate static let regularMask = mode_t(S_IFMT)

    static func captureArchive(directory: URL, manifestLimit: Int, payloadLimit: Int,
                               aggregateLimit: Int,
                               emptyManifest: () throws -> Data,
                               payloadNames: (Data) throws -> [String]) throws -> TransferArchiveSnapshot {
        guard let root = try openRoot(directory, allowMissing: true, requirePrivate: true) else {
            return TransferArchiveSnapshot(manifest: try emptyManifest(), payloads: [:])
        }
        guard let manifest = try root.read("manifest.json", maximum: manifestLimit) else {
            return TransferArchiveSnapshot(manifest: try emptyManifest(), payloads: [:])
        }
        let names = try payloadNames(manifest)
        guard Set(names).count == names.count else { throw TransferFailure.artifactMismatch }
        var payloads: [String: Data] = [:]
        var aggregate = 0
        for name in names {
            guard validLeafName(name) else { throw TransferFailure.unsafeFile }
            guard let inspection = try root.inspect(name, maximum: payloadLimit) else {
                throw TransferFailure.artifactMismatch
            }
            guard inspection.size <= Int64(payloadLimit), inspection.size <= Int64(aggregateLimit) - Int64(aggregate) else {
                throw TransferFailure.limitExceeded
            }
            aggregate += Int(inspection.size)
            guard let data = try root.read(name, maximum: payloadLimit) else {
                throw TransferFailure.artifactMismatch
            }
            guard data.count == Int(inspection.size) else { throw TransferFailure.artifactMismatch }
            payloads[name] = data
        }
        return TransferArchiveSnapshot(manifest: manifest, payloads: payloads)
    }

    /// Strict source reader used by route and favorite-place snapshots. A
    /// missing namespace or leaf is a healthy absence; present paths are
    /// current-owner private regular files with one link.
    static func readSourceFile(directory: URL, name: String, maximum: Int) throws -> Data? {
        guard validLeafName(name) else { throw TransferFailure.unsafeFile }
        guard let root = try openRoot(directory, allowMissing: true, requirePrivate: true) else { return nil }
        return try root.read(name, maximum: maximum)
    }

    static func openPackageRoot(_ root: URL) throws -> _TransferDirectoryHandle {
        guard let handle = try openRoot(root, allowMissing: false, requirePrivate: true) else { throw TransferFailure.unavailable }
        return handle
    }

    /// Opens a fixed derived directory chain with O_NOFOLLOW at every
    /// component.  Storage uses this for authoritative roots as well as the
    /// package validator; the returned descriptor remains alive for the
    /// complete read/write/rename operation.
    static func openDirectory(_ root: URL, allowMissing: Bool = false, requirePrivate: Bool = true) throws -> _TransferDirectoryHandle? {
        try openRoot(root, allowMissing: allowMissing, requirePrivate: requirePrivate)
    }

    static func packageRoot(_ root: URL) throws {
        _ = try openPackageRoot(root)
    }

    static func readPackageFile(_ root: URL, relativePath: String, maximum: Int) throws -> Data {
        let handle = try openPackageRoot(root)
        guard let data = try handle.read(relativePath, maximum: maximum) else { throw TransferFailure.artifactMismatch }
        return data
    }

    static func inventory(_ root: URL, maxDepth: Int = 4, maxEntries: Int = 512) throws -> [(String, Bool)] {
        let handle = try openPackageRoot(root)
        return try handle.inventory(maxDepth: maxDepth, maxEntries: maxEntries)
    }

    static func isRegularPrivateFile(_ url: URL) throws -> Bool {
        var info = stat()
        guard Darwin.lstat(url.absoluteURL.path, &info) == 0 else {
            if errno == ENOENT { return false }
            throw errno == ELOOP || errno == ENOTDIR ? TransferFailure.unsafeFile : TransferFailure.unavailable
        }
        try validateFile(info)
        return true
    }

    fileprivate static func validateDirectory(_ value: stat) throws {
        guard value.st_mode & regularMask == mode_t(S_IFDIR),
              value.st_nlink >= 1, value.st_uid == getuid(),
              value.st_mode & 0o7777 == 0o700 else { throw TransferFailure.unsafeFile }
    }

    fileprivate static func validateFile(_ value: stat, requirePrivate: Bool = true) throws {
        guard value.st_mode & regularMask == mode_t(S_IFREG), value.st_nlink == 1,
              value.st_uid == getuid(), !requirePrivate || value.st_mode & 0o7777 == 0o600 else { throw TransferFailure.unsafeFile }
    }

    fileprivate static func validateUnchanged(_ fd: Int32, initial: stat, actualSize: Int) throws {
        var ended = stat()
        guard fstat(fd, &ended) == 0 else { throw TransferFailure.unavailable }
        try validateFile(ended)
        guard ended.st_dev == initial.st_dev, ended.st_ino == initial.st_ino,
              ended.st_size == initial.st_size, actualSize == Int(initial.st_size) else {
            throw TransferFailure.artifactMismatch
        }
    }

    fileprivate static func validRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"), !value.contains("%") else { return false }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func validLeafName(_ value: String) -> Bool {
        validRelativePath(value) && !value.contains("/")
    }

    static func directoryEntryName(_ entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafeBytes(of: entry.pointee.d_name) { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let end = bytes.firstIndex(of: 0) ?? bytes.count
            return String(decoding: bytes[..<end], as: UTF8.self)
        }
    }

    private static func openRoot(_ directory: URL, allowMissing: Bool, requirePrivate: Bool) throws -> _TransferDirectoryHandle? {
        let path = directory.absoluteURL.path
        guard path.hasPrefix("/") else { throw TransferFailure.unsafeFile }
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard current >= 0 else { throw TransferFailure.unavailable }
        let components = path.split(separator: "/").map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            Darwin.close(current)
            throw TransferFailure.unsafeFile
        }
        if components.isEmpty {
            var info = stat()
            do {
                guard fstat(current, &info) == 0 else { throw TransferFailure.unavailable }
                if requirePrivate { try validateDirectory(info) }
                else { try validateDirectoryOwner(info) }
                return _TransferDirectoryHandle(fd: current)
            } catch {
                Darwin.close(current)
                throw error
            }
        }
        for (index, component) in components.enumerated() {
            let next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC, 0)
            let openError = errno
            Darwin.close(current)
            if next < 0 {
                if openError == ENOENT && allowMissing { return nil }
                if openError == ELOOP || openError == ENOTDIR { throw TransferFailure.unsafeFile }
                throw TransferFailure.unavailable
            }
            current = next
            if index == components.count - 1 {
                do {
                    var info = stat()
                    guard fstat(current, &info) == 0 else { throw TransferFailure.unavailable }
                    if requirePrivate { try validateDirectory(info) }
                    else { try validateDirectoryOwner(info) }
                } catch {
                    Darwin.close(current)
                    throw error
                }
            }
        }
        return _TransferDirectoryHandle(fd: current)
    }

    private static func validateDirectoryOwner(_ value: stat) throws {
        guard value.st_mode & regularMask == mode_t(S_IFDIR), value.st_nlink >= 1,
              value.st_uid == getuid(), (value.st_mode & 0o7777 == 0o700 || value.st_mode & 0o7777 == 0o755) else {
            throw TransferFailure.unsafeFile
        }
    }
}
