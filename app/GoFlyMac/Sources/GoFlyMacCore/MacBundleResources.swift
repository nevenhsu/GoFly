import CryptoKit
import Darwin
import Foundation

/// The only files a live Mac bridge may consume from its application bundle.
///
/// The enum is deliberately closed.  Callers cannot turn an arbitrary path
/// into a resource entry and the manifest is checked against this same set.
public enum MacBundleResourceEntry: String, CaseIterable, Sendable {
    case checkScript = "Contents/Resources/Bridge/bridge.py"
    case localConfiguration = "Contents/Resources/LocalConfiguration.json"
    case setupScript = "Contents/Resources/Bridge/Setup/setup_bridge.py"
    case setupInit = "Contents/Resources/Bridge/Setup/__init__.py"
    case setupAdapters = "Contents/Resources/Bridge/Setup/setup_adapters.py"
    case setupConfig = "Contents/Resources/Bridge/Setup/setup_config.py"
    case setupDelivery = "Contents/Resources/Bridge/Setup/setup_delivery.py"
    case setupJournal = "Contents/Resources/Bridge/Setup/setup_journal.py"
    case setupProducer = "Contents/Resources/Bridge/Setup/setup_producer.py"
    case setupProtocol = "Contents/Resources/Bridge/Setup/setup_protocol.py"
    case setupSupport = "Contents/Resources/Bridge/Setup/setup_support.py"
    case setupConfiguration = "Contents/Resources/SetupConfiguration.json"
    case reinstallScript = "Contents/Resources/Bridge/Reinstall/reinstall_bridge.py"
    case reinstallInit = "Contents/Resources/Bridge/Reinstall/__init__.py"
    case reinstallAdapters = "Contents/Resources/Bridge/Reinstall/reinstall_adapters.py"
    case reinstallConfig = "Contents/Resources/Bridge/Reinstall/reinstall_config.py"
    case reinstallJournal = "Contents/Resources/Bridge/Reinstall/reinstall_journal.py"
    case reinstallProducer = "Contents/Resources/Bridge/Reinstall/reinstall_producer.py"
    case reinstallProtocol = "Contents/Resources/Bridge/Reinstall/reinstall_protocol.py"
    case reinstallConfiguration = "Contents/Resources/ReinstallConfiguration.json"
    case managementScript = "Contents/Resources/Bridge/Management/management_bridge.py"
    case managementInit = "Contents/Resources/Bridge/Management/__init__.py"
    case managementAdapters = "Contents/Resources/Bridge/Management/management_adapters.py"
    case managementJournal = "Contents/Resources/Bridge/Management/management_journal.py"
    case managementLineage = "Contents/Resources/Bridge/Management/management_lineage.py"
    case managementPreparation = "Contents/Resources/Bridge/Management/management_preparation.py"
    case managementProducer = "Contents/Resources/Bridge/Management/management_producer.py"
    case managementProtocol = "Contents/Resources/Bridge/Management/management_protocol.py"
    case managementSource = "Contents/Resources/Bridge/Management/management_source.py"
    case managementTarget = "Contents/Resources/Bridge/Management/management_target.py"
    case deviceBoundary = "Contents/Resources/Bridge/Device/gofly_device.py"
    case transferValidator = "Contents/MacOS/GoFlyTransferValidator"
}

public enum MacBundleResourceError: Error, Equatable, Sendable {
    case invalidBundle
    case invalidManifest
    case changed
}

fileprivate struct MacBundleResourceFileStamp: Equatable, Sendable {
    let sha256: String
    let owner: UInt32
    let mode: UInt16
    let linkCount: UInt16
}

/// An opaque point-in-time resource stamp.  Its contents are private so a
/// caller can only retain and compare a stamp through the verifier API.
public struct MacBundleResourceStamp: Equatable, Sendable {
    fileprivate let manifestSHA256: String
    fileprivate let files: [String: MacBundleResourceFileStamp]
}

/// Verifies the fixed, generated app resources before a bridge consumes them.
/// The bundle root is canonicalized once at construction; all later reads walk
/// from that root with O_NOFOLLOW and are checked against the initial stamp.
public struct MacBundleResources: Sendable {
    public static let manifestRelativePath = "Contents/Resources/GoFlyBundleManifest.json"
    public static let manifestVersion = 1

    private static let maxManifestBytes = 2 * 1024 * 1024
    private static let maxResourceBytes = 64 * 1024 * 1024
    private let bundleRoot: URL
    private let initialStamp: MacBundleResourceStamp

    public init(bundleURL: URL) throws {
        guard bundleURL.isFileURL else { throw MacBundleResourceError.invalidBundle }
        let root = try Self.canonicalRoot(bundleURL)
        guard root.path.hasPrefix("/") else {
            throw MacBundleResourceError.invalidBundle
        }
        self.bundleRoot = root
        self.initialStamp = try Self.makeStamp(root: root)
    }

    /// Returns the initial verified stamp for a caller that needs to retain it.
    /// The value carries no public success flag or filesystem authority.
    public func stamp() throws -> MacBundleResourceStamp {
        try revalidate()
        return initialStamp
    }

    /// Reopens and rehashes every manifest entry, rejecting any changed
    /// manifest, content, ownership, mode, link count, or file type.
    public func revalidate() throws {
        let current = try Self.makeStamp(root: bundleRoot)
        guard current == initialStamp else { throw MacBundleResourceError.changed }
    }

    /// Reads only one of the fixed resource entries after revalidation.
    public func read(_ entry: MacBundleResourceEntry) throws -> Data {
        try revalidate()
        let observed = try Self.readFileAndStamp(root: bundleRoot, relativePath: entry.rawValue,
                                                 maximumBytes: Self.maxResourceBytes)
        guard let expected = initialStamp.files[entry.rawValue], observed.stamp == expected else {
            throw MacBundleResourceError.changed
        }
        return observed.data
    }

    private static func makeStamp(root: URL) throws -> MacBundleResourceStamp {
        let manifestData = try readFile(root: root, relativePath: manifestRelativePath, maximumBytes: maxManifestBytes)
        let expected = try parseManifest(manifestData)
        var fileStamps: [String: MacBundleResourceFileStamp] = [:]
        for entry in MacBundleResourceEntry.allCases {
            let relativePath = entry.rawValue
            guard let expectedHash = expected[relativePath] else { throw MacBundleResourceError.invalidManifest }
            let observed = try hashFile(root: root, relativePath: relativePath)
            guard observed.sha256 == expectedHash else { throw MacBundleResourceError.invalidManifest }
            fileStamps[relativePath] = observed
        }
        return MacBundleResourceStamp(
            manifestSHA256: sha256(manifestData),
            files: fileStamps
        )
    }

    private static func parseManifest(_ data: Data) throws -> [String: String] {
        guard data.count <= maxManifestBytes else { throw MacBundleResourceError.invalidManifest }
        let object: [String: Any]
        do {
            object = try SetupWireJSON.object(data, integerKey: "version", integerValue: "1",
                                               maximumBytes: maxManifestBytes)
        } catch {
            throw MacBundleResourceError.invalidManifest
        }
        guard Set(object.keys) == ["version", "files"],
              let files = object["files"] as? [String: Any],
              Set(files.keys) == Set(MacBundleResourceEntry.allCases.map(\.rawValue)) else {
            throw MacBundleResourceError.invalidManifest
        }
        var result: [String: String] = [:]
        for entry in MacBundleResourceEntry.allCases {
            guard let value = files[entry.rawValue] as? String,
                  value.count == 64,
                  value.unicodeScalars.allSatisfy({
                      ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
                  }) else {
                throw MacBundleResourceError.invalidManifest
            }
            result[entry.rawValue] = value
        }
        return result
    }

    private static func hashFile(root: URL, relativePath: String) throws -> MacBundleResourceFileStamp {
        let descriptor = try openFile(root: root, relativePath: relativePath)
        defer { close(descriptor.fd) }
        var hasher = SHA256()
        var total = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor.fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw MacBundleResourceError.invalidBundle }
            if count == 0 { break }
            total += count
            guard total <= maxResourceBytes else { throw MacBundleResourceError.invalidBundle }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        let final = try finalStamp(fd: descriptor.fd, initial: descriptor)
        return MacBundleResourceFileStamp(sha256: hex(hasher.finalize()), owner: final.owner,
                                          mode: final.mode, linkCount: final.linkCount)
    }

    private static func readFile(root: URL, relativePath: String, maximumBytes: Int) throws -> Data {
        try readFileAndStamp(root: root, relativePath: relativePath, maximumBytes: maximumBytes).data
    }

    private static func readFileAndStamp(root: URL, relativePath: String, maximumBytes: Int) throws -> (data: Data, stamp: MacBundleResourceFileStamp) {
        let descriptor = try openFile(root: root, relativePath: relativePath)
        defer { close(descriptor.fd) }
        var data = Data()
        data.reserveCapacity(min(descriptor.size, maximumBytes))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor.fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw MacBundleResourceError.invalidBundle }
            if count == 0 { break }
            guard data.count + count <= maximumBytes else { throw MacBundleResourceError.invalidBundle }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == descriptor.size else { throw MacBundleResourceError.changed }
        let final = try finalStamp(fd: descriptor.fd, initial: descriptor)
        return (data, MacBundleResourceFileStamp(sha256: sha256(data), owner: final.owner,
                                                 mode: final.mode, linkCount: final.linkCount))
    }

    private static func finalStamp(fd: Int32, initial: OpenFile) throws -> OpenFile {
        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size == off_t(initial.size),
              info.st_nlink == 1,
              acceptableOwner(info.st_uid),
              info.st_mode & mode_t(S_IWGRP | S_IWOTH) == 0,
              info.st_uid == initial.owner,
              UInt16(info.st_mode & 0o7777) == initial.mode,
              UInt16(info.st_nlink) == initial.linkCount else {
            throw MacBundleResourceError.changed
        }
        return OpenFile(fd: fd, size: Int(info.st_size), owner: info.st_uid,
                        mode: UInt16(info.st_mode & 0o7777), linkCount: UInt16(info.st_nlink))
    }

    private struct OpenFile {
        let fd: Int32
        let size: Int
        let owner: UInt32
        let mode: UInt16
        let linkCount: UInt16
    }

    private static func openFile(root: URL, relativePath: String) throws -> OpenFile {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw MacBundleResourceError.invalidBundle
        }
        var directory = try openDirectoryPath(root.path)
        defer { close(directory) }
        for component in components.dropLast() {
            let next = component.withCString {
                openat(directory, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard next >= 0 else { throw MacBundleResourceError.invalidBundle }
            close(directory)
            directory = next
            try validateDirectory(directory)
        }
        let fd = components.last!.withCString {
            openat(directory, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard fd >= 0 else { throw MacBundleResourceError.invalidBundle }
        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_nlink == 1,
              acceptableOwner(info.st_uid),
              info.st_mode & mode_t(S_IWGRP | S_IWOTH) == 0,
              info.st_size >= 0, info.st_size <= off_t(maxResourceBytes) else {
            close(fd)
            throw MacBundleResourceError.invalidBundle
        }
        return OpenFile(fd: fd, size: Int(info.st_size), owner: info.st_uid,
                        mode: UInt16(info.st_mode & 0o7777), linkCount: UInt16(info.st_nlink))
    }

    private static func openDirectoryPath(_ path: String) throws -> Int32 {
        let components = path.split(separator: "/").map(String.init)
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw MacBundleResourceError.invalidBundle }
        do {
            for component in components {
                let next = component.withCString {
                    openat(fd, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                }
                guard next >= 0 else { throw MacBundleResourceError.invalidBundle }
                close(fd)
                fd = next
                try validateDirectory(fd)
            }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    private static func validateDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              acceptableOwner(info.st_uid),
              info.st_mode & mode_t(S_IWGRP | S_IWOTH) == 0 else {
            throw MacBundleResourceError.invalidBundle
        }
    }

    private static func acceptableOwner(_ uid: uid_t) -> Bool {
        uid == getuid() || uid == 0
    }

    private static func canonicalRoot(_ url: URL) throws -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let resolved: String? = buffer.withUnsafeMutableBufferPointer { storage in
            url.standardizedFileURL.path.withCString { path in
                realpath(path, storage.baseAddress).map { String(cString: $0) }
            }
        }
        guard let resolved, !resolved.isEmpty else { throw MacBundleResourceError.invalidBundle }
        return URL(fileURLWithPath: resolved, isDirectory: true)
    }

    private static func sha256(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
