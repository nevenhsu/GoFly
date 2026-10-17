import Darwin
import Foundation

public enum ImportedRoutesWriteCheckpoint: CaseIterable, Sendable {
    case payloadSecured, payloadWritten, payloadFlushed
    case manifestSecured, manifestWritten, manifestFlushed, beforeManifestCommit
    case cleanup
}

/// One actor owns every directory transaction, including cleanup and undo. File
/// transactions are synchronous: no suspension can expose an in-flight payload
/// to another admission or to orphan cleanup.
public actor FileImportedRoutesPersistence: ImportedRoutesPersistence {
    public nonisolated let directory: URL
    public nonisolated var manifestURL: URL { directory.appendingPathComponent(Self.manifestName) }
    private static let manifestName = "manifest.json"
    private let checkpoint: @Sendable (ImportedRoutesWriteCheckpoint) throws -> Void
    private var undo: (record: ImportedRouteRecord, index: Int)?

    public init(directory: URL, checkpoint: @escaping @Sendable (ImportedRoutesWriteCheckpoint) throws -> Void = { _ in }) {
        self.directory = directory.standardizedFileURL
        self.checkpoint = checkpoint
    }

    public func read() throws -> ImportedRoutesReceipt {
        guard let descriptor = try openDirectory(create: false) else { return receipt([]) }
        defer { Darwin.close(descriptor) }
        let records = try currentRecords(descriptor)
        cleanup(descriptor, records: records)
        try requireQuota(descriptor)
        return receipt(records)
    }

    public func importArtifact(_ artifact: ImportedRouteArtifact) throws -> ImportedRoutesReceipt {
        // Cancellation may revoke a queued admission. Once this synchronous
        // transaction starts, its real commit receipt remains authoritative.
        try Task.checkCancellation()
        guard let descriptor = try openDirectory(create: true) else { throw ImportedRoutesFailure.unavailable }
        defer { Darwin.close(descriptor) }
        var records = try currentRecords(descriptor)
        cleanup(descriptor, records: records)
        guard records.count < ImportedRoutesLimits.records else { throw ImportedRoutesFailure.limitExceeded }
        try requireQuota(descriptor, adding: artifact.payload.count)
        let record = try artifact.record()
        try writePayload(artifact.payload, record: record, directoryFD: descriptor)
        records.append(record)
        try commit(records, directoryFD: descriptor)
        cleanup(descriptor, records: records)
        return receipt(records)
    }

    public func validate(_ id: UUID) async throws -> ImportedRouteSnapshot {
        guard let descriptor = try openDirectory(create: false) else { throw ImportedRoutesFailure.notFound }
        let record: ImportedRouteRecord
        let data: Data
        do {
            let records = try currentRecords(descriptor)
            guard let found = records.first(where: { $0.id == id }) else { throw ImportedRoutesFailure.notFound }
            record = found
            guard let bytes = try readFile(payloadName(id), directoryFD: descriptor, maximum: GPXLimits.fileBytes) else {
                throw ImportedRoutesFailure.notFound
            }
            data = bytes
        } catch { Darwin.close(descriptor); throw error }
        Darwin.close(descriptor)
        // Payload parse/encoding/hash work does not hold the persistence actor.
        return try await Task.detached {
            guard data.count == record.byteCount else { throw ImportedRoutesFailure.metadataMismatch }
            guard ImportedRouteArtifact.hash(data) == record.sha256 else { throw ImportedRoutesFailure.hashMismatch }
            return try ImportedRouteSnapshot(record: record, document: GPXCodec.decode(data))
        }.value
    }

    public func delete(_ id: UUID) throws -> ImportedRoutesReceipt {
        try Task.checkCancellation()
        guard let descriptor = try openDirectory(create: false) else { throw ImportedRoutesFailure.notFound }
        defer { Darwin.close(descriptor) }
        var records = try currentRecords(descriptor)
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw ImportedRoutesFailure.notFound }
        let record = records.remove(at: index)
        try requireQuota(descriptor)
        try commit(records, directoryFD: descriptor)
        undo = (record, index)
        cleanup(descriptor, records: records)
        return receipt(records)
    }

    public func undoDelete() throws -> ImportedRoutesReceipt {
        try Task.checkCancellation()
        guard let undo else { throw ImportedRoutesFailure.nothingToUndo }
        guard let descriptor = try openDirectory(create: false) else { throw ImportedRoutesFailure.notFound }
        defer { Darwin.close(descriptor) }
        var records = try currentRecords(descriptor)
        guard records.count < ImportedRoutesLimits.records else { throw ImportedRoutesFailure.limitExceeded }
        guard !records.contains(where: { $0.id == undo.record.id }) else { throw ImportedRoutesFailure.corruptArchive }
        try verifyMetadata(undo.record, directoryFD: descriptor)
        try requireQuota(descriptor)
        records.insert(undo.record, at: min(undo.index, records.count))
        try commit(records, directoryFD: descriptor)
        self.undo = nil
        cleanup(descriptor, records: records)
        return receipt(records)
    }

    private func receipt(_ records: [ImportedRouteRecord]) -> ImportedRoutesReceipt {
        ImportedRoutesReceipt(records: records, canUndo: undo != nil)
    }
    private func payloadName(_ id: UUID) -> String { id.uuidString + ".gpx" }

    private struct Manifest: Codable { let schemaVersion: Int; let records: [Record] }
    private struct Version: Decodable { let schemaVersion: Int }
    private struct Coordinate: Codable { let latitude: Double; let longitude: Double }
    private struct Record: Codable {
        let id: UUID; let filename: String; let kind: GPXKind; let pointCount: Int; let byteCount: Int; let sha256: String
        let start: Coordinate; let end: Coordinate
        init(_ record: ImportedRouteRecord) {
            id = record.id; filename = record.filename; kind = record.kind; pointCount = record.pointCount
            byteCount = record.byteCount; sha256 = record.sha256
            start = Coordinate(latitude: record.start.latitude, longitude: record.start.longitude)
            end = Coordinate(latitude: record.end.latitude, longitude: record.end.longitude)
        }
        func validated() throws -> ImportedRouteRecord {
            guard let start = GeoCoordinate(latitude: start.latitude, longitude: start.longitude),
                  let end = GeoCoordinate(latitude: end.latitude, longitude: end.longitude) else {
                throw ImportedRoutesFailure.corruptArchive
            }
            return try ImportedRouteRecord(id: id, filename: filename, kind: kind, pointCount: pointCount,
                byteCount: byteCount, sha256: sha256, start: start, end: end)
        }
    }

    private func currentRecords(_ descriptor: Int32) throws -> [ImportedRouteRecord] {
        guard let data = try readFile(Self.manifestName, directoryFD: descriptor, maximum: ImportedRoutesLimits.manifestBytes) else {
            // A missing archive is a new namespace. Existing recognized payloads
            // are counted/cleaned only after this healthy empty manifest decision.
            return []
        }
        let decoder = JSONDecoder()
        let version: Version
        do { version = try decoder.decode(Version.self, from: data) }
        catch { throw ImportedRoutesFailure.corruptArchive }
        guard version.schemaVersion == 1 else { throw ImportedRoutesFailure.unsupportedSchema }
        let manifest: Manifest
        do { manifest = try decoder.decode(Manifest.self, from: data) }
        catch { throw ImportedRoutesFailure.corruptArchive }
        guard manifest.records.count <= ImportedRoutesLimits.records else { throw ImportedRoutesFailure.limitExceeded }
        var identities = Set<UUID>()
        return try manifest.records.map { dto in
            let record = try dto.validated()
            guard identities.insert(record.id).inserted else { throw ImportedRoutesFailure.corruptArchive }
            try verifyMetadata(record, directoryFD: descriptor)
            return record
        }
    }

    private func verifyMetadata(_ record: ImportedRouteRecord, directoryFD: Int32) throws {
        guard let attributes = try regularAttributes(payloadName(record.id), directoryFD: directoryFD) else {
            throw ImportedRoutesFailure.metadataMismatch
        }
        guard attributes.st_size == record.byteCount else { throw ImportedRoutesFailure.metadataMismatch }
    }

    private func commit(_ records: [ImportedRouteRecord], directoryFD: Int32) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Manifest(schemaVersion: 1, records: records.map(Record.init)))
        guard data.count <= ImportedRoutesLimits.manifestBytes else { throw ImportedRoutesFailure.limitExceeded }
        _ = try regularAttributes(Self.manifestName, directoryFD: directoryFD)
        let staging = ".manifest-\(UUID().uuidString).staging"
        let fd = openat(directoryFD, staging, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ImportedRoutesFailure.writeFailed }
        var committed = false
        defer { Darwin.close(fd); if !committed { unlinkat(directoryFD, staging, 0) } }
        try secure(fd, name: staging)
        try reach(.manifestSecured)
        try write(data, descriptor: fd)
        try reach(.manifestWritten)
        guard fsync(fd) == 0 else { throw ImportedRoutesFailure.writeFailed }
        try reach(.manifestFlushed)
        _ = try regularAttributes(Self.manifestName, directoryFD: directoryFD)
        try reach(.beforeManifestCommit)
        guard renameat(directoryFD, staging, directoryFD, Self.manifestName) == 0 else { throw ImportedRoutesFailure.writeFailed }
        committed = true
        // The authoritative rename is last. Cleanup afterwards is best effort.
    }

    private func writePayload(_ data: Data, record: ImportedRouteRecord, directoryFD: Int32) throws {
        let name = payloadName(record.id)
        let fd = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ImportedRoutesFailure.writeFailed }
        var durable = false
        defer { Darwin.close(fd); if !durable { unlinkat(directoryFD, name, 0) } }
        try secure(fd, name: name)
        try reach(.payloadSecured)
        try write(data, descriptor: fd)
        try reach(.payloadWritten)
        guard fsync(fd) == 0 else { throw ImportedRoutesFailure.writeFailed }
        durable = true
        try reach(.payloadFlushed)
    }

    private func reach(_ point: ImportedRoutesWriteCheckpoint) throws {
        do { try checkpoint(point) }
        catch let failure as ImportedRoutesFailure { throw failure }
        catch { throw ImportedRoutesFailure.writeFailed }
    }
    private func secure(_ descriptor: Int32, name: String) throws {
        guard fchmod(descriptor, 0o600) == 0 else { throw ImportedRoutesFailure.writeFailed }
        try protect(directory.appendingPathComponent(name))
    }
    private func write(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw ImportedRoutesFailure.writeFailed }
                offset += count
            }
        }
    }

    private func readFile(_ name: String, directoryFD: Int32, maximum: Int) throws -> Data? {
        let fd = openat(directoryFD, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw pathFailure(errno)
        }
        defer { Darwin.close(fd) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0 else { throw ImportedRoutesFailure.unavailable }
        guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw ImportedRoutesFailure.unsafeFile }
        guard attributes.st_size >= 0, attributes.st_size <= maximum else { throw ImportedRoutesFailure.limitExceeded }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, min($0.count, maximum + 1 - data.count)) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw ImportedRoutesFailure.unavailable }
            if count == 0 { return data }
            guard data.count + count <= maximum else { throw ImportedRoutesFailure.limitExceeded }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
    private func regularAttributes(_ name: String, directoryFD: Int32) throws -> stat? {
        var attributes = stat()
        guard fstatat(directoryFD, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return nil }
            throw pathFailure(errno)
        }
        guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), attributes.st_size >= 0 else {
            throw ImportedRoutesFailure.unsafeFile
        }
        return attributes
    }

    private func directoryNames(_ directoryFD: Int32) throws -> [String] {
        // A new open description keeps each scan's directory offset independent.
        let duplicate = openat(directoryFD, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard duplicate >= 0 else { throw ImportedRoutesFailure.unavailable }
        guard let handle = fdopendir(duplicate) else { Darwin.close(duplicate); throw ImportedRoutesFailure.unavailable }
        defer { closedir(handle) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(handle) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != ".", name != ".." { names.append(name) }
            errno = 0
        }
        guard errno == 0 else { throw ImportedRoutesFailure.unavailable }
        return names
    }
    private func ownedPayloadID(_ name: String) -> UUID? {
        guard name.hasSuffix(".gpx") else { return nil }
        let stem = String(name.dropLast(4))
        guard let id = UUID(uuidString: stem), id.uuidString == stem else { return nil }
        return id
    }
    private func requireQuota(_ directoryFD: Int32, adding: Int = 0) throws {
        var total = adding
        guard total <= ImportedRoutesLimits.payloadBytes else { throw ImportedRoutesFailure.limitExceeded }
        for name in try directoryNames(directoryFD) where ownedPayloadID(name) != nil {
            guard let attributes = try regularAttributes(name, directoryFD: directoryFD) else { continue }
            guard attributes.st_size <= ImportedRoutesLimits.payloadBytes - total else { throw ImportedRoutesFailure.limitExceeded }
            total += Int(attributes.st_size)
        }
    }
    private func cleanup(_ directoryFD: Int32, records: [ImportedRouteRecord]) {
        // Only reached after a healthy manifest read or a successful commit.
        // A cleanup fault never changes the result of an already committed write.
        do {
            try reach(.cleanup)
            var referenced = Set(records.map(\.id))
            if let undo { referenced.insert(undo.record.id) }
            for name in try directoryNames(directoryFD) {
                if let id = ownedPayloadID(name), !referenced.contains(id) {
                    guard (try? regularAttributes(name, directoryFD: directoryFD)) != nil else { continue }
                    unlinkat(directoryFD, name, 0)
                } else if name.hasPrefix(".manifest-"), name.hasSuffix(".staging"),
                          UUID(uuidString: String(name.dropFirst(10).dropLast(8))) != nil {
                    guard (try? regularAttributes(name, directoryFD: directoryFD)) != nil else { continue }
                    unlinkat(directoryFD, name, 0)
                }
            }
        } catch { return }
    }

    private func openDirectory(create: Bool) throws -> Int32? {
        var descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0, errno == ENOENT, create {
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            catch { throw ImportedRoutesFailure.unavailable }
            descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            if !create, errno == ENOENT { return nil }
            throw pathFailure(errno)
        }
        do {
            guard fchmod(descriptor, 0o700) == 0 else { throw ImportedRoutesFailure.writeFailed }
            try protect(directory)
        } catch { Darwin.close(descriptor); throw error }
        return descriptor
    }
    private func pathFailure(_ code: Int32) -> ImportedRoutesFailure {
        code == ELOOP || code == ENOTDIR ? .unsafeFile : .unavailable
    }
    private func protect(_ url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
}
