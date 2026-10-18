import CryptoKit
import Darwin
import Foundation

/// Private, no-follow storage for formal setup data and its support generations.
/// The directory is intentionally a value supplied by the containing app; this
/// type never discovers or follows an arbitrary path from an input manifest.
public final class SetupActivationStore: @unchecked Sendable {
    public let directory: URL
    private let checkpoint: @Sendable (SetupWriteCheckpoint) throws -> Void
    private static let inputName = "incoming.json"
    private static let requestName = "readback-request.json"
    private static let responseName = "readback-response.json"
    private static let activationName = "activation.json"

    public init(directory: URL,
                checkpoint: @escaping @Sendable (SetupWriteCheckpoint) throws -> Void = { _ in }) {
        self.directory = directory.standardizedFileURL
        self.checkpoint = checkpoint
    }

    public func readInput() throws -> SetupInput? {
        try mapStorage {
            guard let bytes = try readRoot(Self.inputName, maximum: SetupManifest.maximumBytes) else { return nil }
            return try SetupInput(data: bytes)
        }
    }

    public func readReadbackRequest() throws -> SetupReadbackRequest? {
        try mapStorage {
            guard let bytes = try readRoot(Self.requestName, maximum: 64 * 1_024) else { return nil }
            return try SetupCodec.decodeRequest(bytes)
        }
    }

    public func writeReadbackReceipt(_ receipt: SetupReadbackReceipt) throws {
        let bytes = try receipt.encoded()
        do { try atomicWriteRoot(bytes, target: Self.responseName) }
        catch let failure as SetupFailure { throw failure }
        catch let failure as _SetupIOFailure { throw failure.setupFailure }
        catch { throw SetupFailure.storageUnavailable }
    }

    public func readReadbackReceipt() throws -> SetupReadbackReceipt? {
        try mapStorage {
            guard let bytes = try readRoot(Self.responseName, maximum: 64 * 1_024) else { return nil }
            return try SetupCodec.decodeReceipt(bytes)
        }
    }

    /// Seals transport-created incoming files before the App bootstrap reads
    /// them. The ingress boundary is intentionally bounded to the fixed
    /// request/input names and their derived support generation.
    public func prepareIncomingFiles() throws {
        do {
            guard let root = try preparationRootDescriptor() else { return }
            defer { Darwin.close(root) }
            try sealTransportDirectory(root)
            // Activation is App-owned state. Read it through the strict
            // private reader before touching any derived incoming generation.
            // A committed replay is already durable and must not require its
            // inactive generation to remain present or readable.
            let existingActivation = try activation()

            let requestBytes = try prepareTransportFile(root, name: Self.requestName, maximum: 64 * 1_024)
            if let requestBytes { _ = try SetupCodec.decodeRequest(requestBytes) }
            let inputBytes = try prepareTransportFile(root, name: Self.inputName, maximum: SetupManifest.maximumBytes)
            guard let inputBytes else { return }
            let input = try SetupInput(data: inputBytes)
            if let existing = existingActivation?.receipts.first(where: { $0.setupID == input.manifest.setupID }) {
                guard existing.rawManifestSHA256 == input.rawManifestSHA256 else { throw SetupFailure.invalidInput }
                return
            }
            try sealIncomingGeneration(root, manifest: input.manifest)
        } catch let failure as SetupFailure {
            throw failure
        } catch let failure as _SetupIOFailure {
            throw failure.setupFailure
        } catch {
            throw SetupFailure.storageUnavailable
        }
    }

    public func activation() throws -> SetupActivationRecord? {
        try mapStorage {
            guard let bytes = try readRoot(Self.activationName, maximum: 256 * 1_024) else { return nil }
            return try SetupCodec.decodeActivation(bytes)
        }
    }

    /// Streams and verifies every immutable support artifact. The returned URL
    /// points only at the derived generation directory owned by this store.
    public func validateSupport(for input: SetupInput) throws -> URL {
        try mapStorage { try validateSupportInternal(manifest: input.manifest) }
    }

    @discardableResult
    public func commit(_ input: SetupInput) throws -> SetupReceipt {
        do {
            let existing = try activation()
            if let existing, let prior = existing.receipts.first(where: { $0.setupID == input.manifest.setupID }) {
                guard prior.rawManifestSHA256 == input.rawManifestSHA256 else { throw SetupFailure.invalidInput }
                return prior
            }
            if let existing, existing.receipts.count >= SetupActivationRecord.maximumReceipts { throw SetupFailure.receiptCapacity }
            // Replays return above before touching the incoming generation.
            // New receipts validate all support bytes before pairing state can
            // be consumed by the coordinator.
            _ = try validateSupport(for: input)
            let receipt = try SetupReceipt(manifest: input.manifest, rawManifestSHA256: input.rawManifestSHA256)
            var receipts = existing?.receipts ?? []
            receipts.append(receipt)
            let record = try SetupActivationRecord(activeSetupID: input.manifest.setupID, receipts: receipts)
            let bytes = try SetupCodec.encodeActivation(record)
            try atomicWriteRoot(bytes, target: Self.activationName)
            return receipt
        } catch let failure as SetupFailure { throw failure }
        catch let failure as _SetupIOFailure { throw failure.setupFailure }
        catch { throw SetupFailure.storageUnavailable }
    }

    /// Returns nil when no formal active pointer exists. A malformed pointer or
    /// a pointer whose generation cannot be validated throws and never falls
    /// through to legacy support files.
    public func activeSupportDirectory(method: SetupSupportMethod) throws -> URL? {
        return try mapStorage {
            guard let record = try activation() else { return nil }
            guard let active = record.activeSetupID,
                  let receipt = record.receipts.first(where: { $0.setupID == active }),
                  receipt.method == method else { throw SetupFailure.artifactMismatch }
            let manifest = try SetupManifest(version: 1, setupID: receipt.setupID, nonce: receipt.nonce,
                expectedDeviceUDID: receipt.expectedDeviceUDID, pairingTransactionID: receipt.pairingTransactionID,
                pairingSHA256: receipt.pairingSHA256, app: receipt.app, teamID: receipt.teamID,
                signingExpiry: receipt.signingExpiry, deviceOS: receipt.deviceOS, method: receipt.method,
                artifacts: receipt.artifacts)
            return try validateSupportInternal(manifest: manifest)
        }
    }

    // MARK: Descriptor-backed filesystem

    private func mapStorage<T>(_ operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch let failure as SetupFailure { throw failure }
        catch let failure as _SetupIOFailure { throw failure.setupFailure }
        catch { throw SetupFailure.storageUnavailable }
    }

    private func rootDescriptor(create: Bool) throws -> Int32? {
        if create {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                         attributes: [.posixPermissions: 0o700])
            } catch { throw _SetupIOFailure.storage }
        }
        let fd = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT && !create { return nil }
            throw _SetupIOFailure.storage
        }
        try validateDirectory(fd)
        return fd
    }

    private func readRoot(_ name: String, maximum: Int) throws -> Data? {
        guard let root = try rootDescriptor(create: false) else { return nil }
        defer { Darwin.close(root) }
        return try readFile(root, name: name, maximum: maximum)
    }

    private func readFile(_ parent: Int32, name: String, maximum: Int) throws -> Data? {
        try requireComponent(name)
        let fd = openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { if errno == ENOENT { return nil }; throw _SetupIOFailure.unsafe }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw _SetupIOFailure.storage }
        try validateRegular(info)
        guard info.st_size >= 0 else { throw _SetupIOFailure.unsafe }
        guard info.st_size <= maximum else { throw _SetupIOFailure.limit }
        var result = Data(); var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw _SetupIOFailure.storage }
            if count == 0 {
                guard Int64(result.count) == info.st_size else { throw _SetupIOFailure.storage }
                return result
            }
            guard result.count + count <= maximum else { throw _SetupIOFailure.limit }
            result.append(contentsOf: buffer.prefix(count))
        }
    }

    private func atomicWriteRoot(_ data: Data, target: String) throws {
        guard data.count <= 256 * 1_024 else { throw _SetupIOFailure.limit }
        guard let root = try rootDescriptor(create: true) else { throw _SetupIOFailure.storage }
        defer { Darwin.close(root) }
        try requireComponent(target)
        let staging = ".setup-\(UUID().uuidString.lowercased()).staging"
        let fd = openat(root, staging, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw _SetupIOFailure.storage }
        var renamed = false
        defer { Darwin.close(fd); if !renamed { unlinkat(root, staging, 0) } }
        guard fchmod(fd, 0o600) == 0 else { throw _SetupIOFailure.storage }
        try checkpoint(.stagingSecured)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw _SetupIOFailure.storage }
                offset += count
            }
        }
        try checkpoint(.contentsWritten)
        guard fsync(fd) == 0 else { throw _SetupIOFailure.storage }
        try checkpoint(.stagingFlushed)
        try checkpoint(.beforeRename)
        var existing = stat()
        if fstatat(root, target, &existing, AT_SYMLINK_NOFOLLOW) == 0 {
            try validateRegular(existing)
        } else if errno != ENOENT {
            throw _SetupIOFailure.unsafe
        }
        guard renameat(root, staging, root, target) == 0 else { throw _SetupIOFailure.storage }
        renamed = true
        // Once the target name has been replaced, a checkpoint or directory
        // fsync failure leaves durable state uncertain. Collapse every error
        // in this tail, including generic injected I/O errors, to the public
        // commit-unknown result.
        do {
            try checkpoint(.afterRename)
            guard fsync(root) == 0 else { throw _SetupIOFailure.storage }
            try checkpoint(.parentDirectoryFlushed)
        } catch {
            throw SetupFailure.commitUnknown
        }
    }

    private func validateSupportInternal(manifest: SetupManifest) throws -> URL {
        guard let root = try rootDescriptor(create: false) else { throw SetupFailure.artifactMismatch }
        defer { Darwin.close(root) }
        let generations = try openDirectory(root, name: "generations", create: false)
        defer { Darwin.close(generations) }
        let generation = try openDirectory(generations, name: manifest.setupID.uuidString.lowercased(), create: false)
        defer { Darwin.close(generation) }
        guard Set(try names(generation, maximum: 2)) == ["DDI"] else { throw SetupFailure.artifactMismatch }
        let ddi = try openDirectory(generation, name: "DDI", create: false)
        defer { Darwin.close(ddi) }
        let expected = Set(manifest.artifacts.map(\.filename))
        guard Set(try names(ddi, maximum: expected.count + 1)) == expected else { throw SetupFailure.artifactMismatch }
        for artifact in manifest.artifacts {
            guard let info = try fileInfo(ddi, name: artifact.filename), info == artifact.byteCount else { throw SetupFailure.artifactMismatch }
            guard try streamHash(ddi, name: artifact.filename, expected: artifact.sha256, size: artifact.byteCount) else { throw SetupFailure.artifactMismatch }
            if artifact.filename == "MountMethod" {
                guard let bytes = try readFile(ddi, name: artifact.filename, maximum: 128), String(data: bytes, encoding: .utf8) == manifest.method.rawValue else { throw SetupFailure.artifactMismatch }
            }
        }
        return directory.appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(manifest.setupID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("DDI", isDirectory: true)
    }

    private func openDirectory(_ parent: Int32, name: String, create: Bool) throws -> Int32 {
        try requireComponent(name)
        var fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 && errno == ENOENT && create {
            guard mkdirat(parent, name, 0o700) == 0 || errno == EEXIST else { throw _SetupIOFailure.storage }
            fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else {
            if errno == ENOENT { throw _SetupIOFailure.notFound }
            throw errno == ELOOP || errno == ENOTDIR ? _SetupIOFailure.unsafe : _SetupIOFailure.storage
        }
        try validateDirectory(fd)
        return fd
    }

    private func fileInfo(_ parent: Int32, name: String) throws -> Int64? {
        try requireComponent(name)
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { if errno == ENOENT { return nil }; throw _SetupIOFailure.unsafe }
        try validateRegular(info)
        return Int64(info.st_size)
    }

    private func streamHash(_ parent: Int32, name: String, expected: String, size: Int64) throws -> Bool {
        try requireComponent(name)
        let fd = openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw _SetupIOFailure.unsafe }
        defer { Darwin.close(fd) }
        var info = stat(); guard fstat(fd, &info) == 0 else { throw _SetupIOFailure.storage }
        try validateRegular(info)
        guard info.st_size == size else { return false }
        var digest = SHA256(); var total: Int64 = 0; var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw _SetupIOFailure.storage }
            if count == 0 { break }
            digest.update(data: Data(buffer.prefix(count))); total += Int64(count)
            guard total <= SetupManifest.maximumGenerationBytes else { throw _SetupIOFailure.limit }
        }
        return total == size && digest.finalize().map { String(format: "%02x", $0) }.joined() == expected
    }

    private func names(_ fd: Int32, maximum: Int? = nil) throws -> [String] {
        let copy = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copy >= 0, let stream = fdopendir(copy) else { throw _SetupIOFailure.storage }
        defer { closedir(stream) }
        var output: [String] = []; errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { ptr in ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) } }
            if name != "." && name != ".." {
                if let maximum, output.count >= maximum { throw _SetupIOFailure.inventoryOverflow }
                output.append(name)
            }
            errno = 0
        }
        guard errno == 0 else { throw _SetupIOFailure.storage }
        return output
    }

    private func requireComponent(_ value: String) throws {
        guard !value.isEmpty, value != ".", value != "..", !value.contains("/"), !value.contains("\\"), !value.contains("\0") else { throw _SetupIOFailure.unsafe }
    }

    // MARK: Transport ingress sealing

    private func preparationRootDescriptor() throws -> Int32? {
        let fd = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            if errno == ELOOP || errno == ENOTDIR { throw _SetupIOFailure.unsafe }
            throw _SetupIOFailure.storage
        }
        do {
            try validateTransportDirectory(fd)
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    private func sealTransportDirectory(_ fd: Int32) throws {
        try validateTransportDirectory(fd)
        guard fchmod(fd, 0o700) == 0, fsync(fd) == 0 else { throw _SetupIOFailure.storage }
    }

    private func prepareTransportFile(_ parent: Int32, name: String, maximum: Int) throws -> Data? {
        try requireComponent(name)
        let fd = openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP || errno == ENOTDIR { throw _SetupIOFailure.unsafe }
            throw _SetupIOFailure.storage
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw _SetupIOFailure.storage }
        try validateTransportRegular(info)
        guard info.st_size > 0, info.st_size <= Int64(maximum) else {
            throw info.st_size > Int64(maximum) ? _SetupIOFailure.limit : _SetupIOFailure.unsafe
        }
        guard fchmod(fd, 0o600) == 0, fsync(fd) == 0 else { throw _SetupIOFailure.storage }
        return try readDescriptor(fd, maximum: maximum, expectedSize: info.st_size)
    }

    private func readDescriptor(_ fd: Int32, maximum: Int, expectedSize: Int64) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw _SetupIOFailure.storage }
            if count == 0 {
                guard Int64(result.count) == expectedSize else { throw _SetupIOFailure.storage }
                return result
            }
            guard result.count + count <= maximum else { throw _SetupIOFailure.limit }
            result.append(contentsOf: buffer.prefix(count))
        }
    }

    private func sealIncomingGeneration(_ root: Int32, manifest: SetupManifest) throws {
        let generations = try openTransportDirectory(root, name: "generations")
        defer { Darwin.close(generations) }
        let generation = try openTransportDirectory(generations, name: manifest.setupID.uuidString.lowercased())
        defer { Darwin.close(generation) }
        guard Set(try names(generation, maximum: 2)) == ["DDI"] else { throw SetupFailure.artifactMismatch }
        let ddi = try openTransportDirectory(generation, name: "DDI")
        defer { Darwin.close(ddi) }
        let expected = Set(manifest.artifacts.map(\.filename))
        guard Set(try names(ddi, maximum: expected.count + 1)) == expected else { throw SetupFailure.artifactMismatch }
        for artifact in manifest.artifacts {
            guard let actualSize = try prepareTransportArtifact(ddi, name: artifact.filename,
                                                                 maximum: SetupManifest.maximumGenerationBytes),
                  actualSize == artifact.byteCount else { throw SetupFailure.artifactMismatch }
            guard try streamHash(ddi, name: artifact.filename, expected: artifact.sha256, size: artifact.byteCount) else {
                throw SetupFailure.artifactMismatch
            }
            if artifact.filename == "MountMethod" {
                guard let bytes = try readFile(ddi, name: artifact.filename, maximum: 128),
                      String(data: bytes, encoding: .utf8) == manifest.method.rawValue else {
                    throw SetupFailure.artifactMismatch
                }
            }
        }
    }

    private func openTransportDirectory(_ parent: Int32, name: String) throws -> Int32 {
        try requireComponent(name)
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { throw _SetupIOFailure.notFound }
            if errno == ELOOP || errno == ENOTDIR { throw _SetupIOFailure.unsafe }
            throw _SetupIOFailure.storage
        }
        do {
            try sealTransportDirectory(fd)
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    private func prepareTransportArtifact(_ parent: Int32, name: String, maximum: Int64) throws -> Int64? {
        try requireComponent(name)
        let fd = openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP || errno == ENOTDIR { throw _SetupIOFailure.unsafe }
            throw _SetupIOFailure.storage
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw _SetupIOFailure.storage }
        try validateTransportRegular(info)
        guard info.st_size > 0, info.st_size <= maximum else {
            throw info.st_size > maximum ? _SetupIOFailure.limit : _SetupIOFailure.unsafe
        }
        guard fchmod(fd, 0o600) == 0, fsync(fd) == 0 else { throw _SetupIOFailure.storage }
        return Int64(info.st_size)
    }

    private func validateTransportDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw _SetupIOFailure.storage }
        let mode = info.st_mode & mode_t(0o7777)
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == geteuid(), info.st_nlink >= 2,
              mode == mode_t(0o700) || mode == mode_t(0o755) else {
            throw _SetupIOFailure.unsafe
        }
    }

    private func validateTransportRegular(_ info: stat) throws {
        let mode = info.st_mode & mode_t(0o7777)
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == geteuid(), info.st_nlink == 1,
              mode == mode_t(0o600) || mode == mode_t(0o644), info.st_size >= 0 else {
            throw _SetupIOFailure.unsafe
        }
    }

    private func validateDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0 else { Darwin.close(fd); throw _SetupIOFailure.storage }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == geteuid(),
              info.st_mode & mode_t(0o7777) == mode_t(0o700),
              info.st_nlink >= 2 else {
            Darwin.close(fd)
            throw _SetupIOFailure.unsafe
        }
    }

    private func validateRegular(_ info: stat) throws {
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == geteuid(),
              info.st_mode & mode_t(0o7777) == mode_t(0o600),
              info.st_nlink == 1,
              info.st_size >= 0 else { throw _SetupIOFailure.unsafe }
    }
}

private enum _SetupIOFailure: Error {
    case unsafe, limit, storage, notFound, inventoryOverflow
    var setupFailure: SetupFailure {
        switch self {
        case .unsafe: return .unsafeFile
        case .limit: return .limitExceeded
        case .storage: return .storageUnavailable
        case .notFound: return .artifactMismatch
        case .inventoryOverflow: return .artifactMismatch
        }
    }
}
