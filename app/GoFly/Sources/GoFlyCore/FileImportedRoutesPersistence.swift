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
        self.directory = directory.absoluteURL
        self.checkpoint = checkpoint
    }

    public func read() throws -> ImportedRoutesReceipt {
        guard let descriptor = try openDirectory(create: false) else { return receipt([]) }

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
        let (record, data) = try validationInput(id)
        // Payload parse/encoding/hash work does not hold the persistence actor.
        return try await Task.detached {
            guard data.count == record.byteCount else { throw ImportedRoutesFailure.metadataMismatch }
            guard ImportedRouteArtifact.hash(data) == record.sha256 else { throw ImportedRoutesFailure.hashMismatch }
            return try ImportedRouteSnapshot(record: record, document: GPXCodec.decode(data))
        }.value
    }

    public func transferSnapshot() async throws -> TransferArchiveSnapshot {
        let snapshot: TransferArchiveSnapshot
        do {
            snapshot = try TransferFileIO.captureArchive(
                directory: directory,
                manifestLimit: ImportedRoutesLimits.manifestBytes,
                payloadLimit: GPXLimits.fileBytes,
                aggregateLimit: ImportedRoutesLimits.payloadBytes,
                emptyManifest: { try TransferArchiveCodec.encodeImportedManifest([]) },
                payloadNames: { data in
                    try _ImportedRouteManifestCodec.decode(data).map { $0.id.uuidString + ".gpx" }
                })
        } catch let failure as TransferFailure {
            switch failure {
            case .unsafeFile: throw ImportedRoutesFailure.unsafeFile
            case .limitExceeded: throw ImportedRoutesFailure.limitExceeded
            case .artifactMismatch: throw ImportedRoutesFailure.metadataMismatch
            default: throw ImportedRoutesFailure.unavailable
            }
        }
        do {
            _ = try await Task.detached {
                try TransferArchiveCodec.importedRoutes(snapshot)
            }.value
            return snapshot
        } catch let failure as TransferFailure {
            switch failure {
            case .unsafeFile: throw ImportedRoutesFailure.unsafeFile
            case .limitExceeded: throw ImportedRoutesFailure.limitExceeded
            case .artifactMismatch: throw ImportedRoutesFailure.metadataMismatch
            default: throw ImportedRoutesFailure.corruptArchive
            }
        }
    }

    private func validationInput(_ id: UUID) throws -> (ImportedRouteRecord, Data) {
        guard let archive = try openDirectory(create: false) else { throw ImportedRoutesFailure.notFound }
        let records = try currentRecords(archive)
        guard let record = records.first(where: { $0.id == id }) else { throw ImportedRoutesFailure.notFound }
        guard let data = try readFile(payloadName(id), directoryFD: archive, maximum: GPXLimits.fileBytes) else {
            throw ImportedRoutesFailure.notFound
        }
        return (record, data)
    }

    public func delete(_ id: UUID) throws -> ImportedRoutesReceipt {
        try Task.checkCancellation()
        guard let descriptor = try openDirectory(create: false) else { throw ImportedRoutesFailure.notFound }

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

    private func currentRecords(_ descriptor: SecureArchiveDirectory) throws -> [ImportedRouteRecord] {
        guard let data = try readFile(Self.manifestName, directoryFD: descriptor, maximum: ImportedRoutesLimits.manifestBytes) else {
            // A missing archive is a new namespace. Existing recognized payloads
            // are counted/cleaned only after this healthy empty manifest decision.
            return []
        }
        let records = try _ImportedRouteManifestCodec.decode(data)
        return try records.map { record in
            try verifyMetadata(record, directoryFD: descriptor)
            return record
        }
    }

    private func verifyMetadata(_ record: ImportedRouteRecord, directoryFD: SecureArchiveDirectory) throws {
        guard let attributes = try regularAttributes(payloadName(record.id), directoryFD: directoryFD) else {
            throw ImportedRoutesFailure.metadataMismatch
        }
        guard attributes.st_size == record.byteCount else { throw ImportedRoutesFailure.metadataMismatch }
    }

    private func commit(_ records: [ImportedRouteRecord], directoryFD: SecureArchiveDirectory) throws {
        let data = try _ImportedRouteManifestCodec.encode(records)
        do {
            try directoryFD.replaceAtomically(data, target: Self.manifestName, staging: ".manifest-\(UUID().uuidString).staging", checkpoint: { point in
                switch point {
                case .secured: try reach(.manifestSecured)
                case .written: try reach(.manifestWritten)
                case .flushed: try reach(.manifestFlushed)
                }
            }, beforeCommit: { try reach(.beforeManifestCommit) })
        } catch { throw mapped(error) }
    }

    private func writePayload(_ data: Data, record: ImportedRouteRecord, directoryFD: SecureArchiveDirectory) throws {
        do {
            try directoryFD.writeExclusive(data, name: payloadName(record.id)) { point in
                switch point {
                case .secured: try reach(.payloadSecured)
                case .written: try reach(.payloadWritten)
                case .flushed: try reach(.payloadFlushed)
                }
            }
        } catch { throw mapped(error) }
    }

    private func reach(_ point: ImportedRoutesWriteCheckpoint) throws {
        do { try checkpoint(point) }
        catch let failure as ImportedRoutesFailure { throw failure }
        catch { throw ImportedRoutesFailure.writeFailed }
    }
    private func readFile(_ name: String, directoryFD: SecureArchiveDirectory, maximum: Int) throws -> Data? {
        do { return try directoryFD.read(name, maximum: maximum) } catch { throw mapped(error) }
    }
    private func regularAttributes(_ name: String, directoryFD: SecureArchiveDirectory) throws -> stat? {
        do { return try directoryFD.attributes(name) } catch { throw mapped(error) }
    }
    private func directoryNames(_ directoryFD: SecureArchiveDirectory) throws -> [String] {
        do { return try directoryFD.names() } catch { throw mapped(error) }
    }
    private func ownedPayloadID(_ name: String) -> UUID? {
        guard name.hasSuffix(".gpx") else { return nil }
        let stem = String(name.dropLast(4))
        guard let id = UUID(uuidString: stem), id.uuidString == stem else { return nil }
        return id
    }
    private func requireQuota(_ directoryFD: SecureArchiveDirectory, adding: Int = 0) throws {
        var total = adding
        guard total <= ImportedRoutesLimits.payloadBytes else { throw ImportedRoutesFailure.limitExceeded }
        for name in try directoryNames(directoryFD) where ownedPayloadID(name) != nil {
            guard let attributes = try regularAttributes(name, directoryFD: directoryFD) else { continue }
            guard attributes.st_size <= ImportedRoutesLimits.payloadBytes - total else { throw ImportedRoutesFailure.limitExceeded }
            total += Int(attributes.st_size)
        }
    }
    private func cleanup(_ directoryFD: SecureArchiveDirectory, records: [ImportedRouteRecord]) {
        // Only reached after a healthy manifest read or a successful commit.
        // A cleanup fault never changes the result of an already committed write.
        do {
            try reach(.cleanup)
            var referenced = Set(records.map(\.id))
            if let undo { referenced.insert(undo.record.id) }
            for name in try directoryNames(directoryFD) {
                if let id = ownedPayloadID(name), !referenced.contains(id) {
                    guard (try? regularAttributes(name, directoryFD: directoryFD)) != nil else { continue }
                    try? directoryFD.removeRegularFile(name)
                } else if name.hasPrefix(".manifest-"), name.hasSuffix(".staging"),
                          UUID(uuidString: String(name.dropFirst(10).dropLast(8))) != nil {
                    guard (try? regularAttributes(name, directoryFD: directoryFD)) != nil else { continue }
                    try? directoryFD.removeRegularFile(name)
                }
            }
        } catch { return }
    }

    private func openDirectory(create: Bool) throws -> SecureArchiveDirectory? {
        do { return try SecureArchiveDirectory.open(directory, create: create, secureDirectory: true) }
        catch { throw mapped(error) }
    }
    private func mapped(_ error: any Error) -> any Error {
        guard let failure = error as? SecureArchiveFailure else { return error }
        switch failure {
        case .unsafeFile: return ImportedRoutesFailure.unsafeFile
        case .unavailable: return ImportedRoutesFailure.unavailable
        case .writeFailed: return ImportedRoutesFailure.writeFailed
        case .limitExceeded: return ImportedRoutesFailure.limitExceeded
        }
    }
}
