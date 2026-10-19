import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// One bounded, no-follow, atomic file primitive for local JSON and Data.
public struct AtomicFile: Sendable {
    public let directory: URL
    public let filename: String
    public let maximumBytes: Int

    public init(directory: URL, filename: String, maximumBytes: Int) {
        self.directory = directory.standardizedFileURL
        self.filename = filename
        self.maximumBytes = maximumBytes
    }

    public var url: URL { directory.appendingPathComponent(filename) }

    public func exists() -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    public func loadData() throws -> Data? {
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else {
            if errno == ENOENT { return nil }
            throw CocoaError(.fileReadNoPermission)
        }
        defer { close(directoryFD) }
        let fd = openat(directoryFD, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw CocoaError(.fileReadNoPermission)
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0, data.count + count <= maximumBytes else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    public func saveData(_ data: Data) throws {
        guard data.count <= maximumBytes else { throw CocoaError(.fileWriteFileExists) }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw CocoaError(.fileWriteInvalidFileName) }
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var info = stat()
        if lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) != S_IFREG {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: url.path)
        #endif
    }

    public func loadJSON<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws -> T? {
        guard let data = try loadData() else { return nil }
        return try decoder.decode(type, from: data)
    }

    public func saveJSON<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws {
        try saveData(try encoder.encode(value))
    }
}
