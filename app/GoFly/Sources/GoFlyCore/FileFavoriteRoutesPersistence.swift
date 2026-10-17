import Darwin
import Foundation

public enum FavoriteRoutesWriteCheckpoint: CaseIterable, Sendable {
    case payloadSecured, payloadWritten, payloadFlushed
    case manifestSecured, manifestWritten, manifestFlushed, beforeManifestCommit
    case cleanup
}

/// One actor owns every directory transaction, including cleanup and undo. File
/// transactions are synchronous: no suspension can expose an in-flight payload
/// to another admission or to orphan cleanup.
public actor FileFavoriteRoutesPersistence: FavoriteRoutesPersistence {
    public nonisolated let directory: URL
    public nonisolated var manifestURL: URL { directory.appendingPathComponent(Self.manifestName) }
    private static let manifestName = "manifest.json"
    private let checkpoint: @Sendable (FavoriteRoutesWriteCheckpoint) throws -> Void
    private var undo: (record: FavoriteRouteRecord, index: Int)?

    public init(directory: URL, checkpoint: @escaping @Sendable (FavoriteRoutesWriteCheckpoint) throws -> Void = { _ in }) {
        self.directory = directory.standardizedFileURL
        self.checkpoint = checkpoint
    }

    public func read() throws -> FavoriteRoutesReceipt {
        guard let descriptor = try openDirectory(create: false) else { return receipt([]) }

        let records = try currentRecords(descriptor)
        cleanup(descriptor, records: records)
        try requireQuota(descriptor)
        return receipt(records)
    }

    public nonisolated func save(_ candidate: FavoriteRouteSaveCandidate, label: String?) async throws -> FavoriteRouteSaveReceipt {
        try Task.checkCancellation()
        let artifact = try await Task.detached {
            _ = try FavoriteRoutePayload.label(label)
            return try FavoriteRouteArtifact(candidate: candidate)
        }.value
        try Task.checkCancellation()
        return try await commitSave(artifact, label: label, omittedUnavailableCurrent: candidate.omittedUnavailableCurrent)
    }

    private func commitSave(_ artifact: FavoriteRouteArtifact, label: String?, omittedUnavailableCurrent: Bool) throws -> FavoriteRouteSaveReceipt {
        try Task.checkCancellation()
        guard let archive = try openDirectory(create: true) else { throw FavoriteRoutesFailure.unavailable }
        var records = try currentRecords(archive)
        cleanup(archive, records: records)
        guard records.count < FavoriteRoutesLimits.records else { throw FavoriteRoutesFailure.limitExceeded }
        try requireQuota(archive, adding: artifact.payload.count)
        let record = try artifact.record(label: label)
        try writePayload(artifact.payload, record: record, directoryFD: archive)
        records.append(record)
        try commit(records, directoryFD: archive)
        cleanup(archive, records: records)
        return FavoriteRouteSaveReceipt(archive: receipt(records), result: FavoriteRouteSaveResult(record: record,
            omittedUnavailableCurrent: omittedUnavailableCurrent))
    }

    public func validate(_ id: UUID) async throws -> FavoriteRouteSnapshot {
        let (record, data) = try validationInput(id)
        // Payload parse/encoding/hash work does not hold the persistence actor.
        return try await Task.detached {
            guard data.count == record.byteCount else { throw FavoriteRoutesFailure.metadataMismatch }
            guard FavoriteRoutePayload.hash(data) == record.sha256 else { throw FavoriteRoutesFailure.hashMismatch }
            return try FavoriteRouteSnapshot(record: record, source: FavoriteRoutePayload.decode(data, record: record))
        }.value
    }

    private func validationInput(_ id: UUID) throws -> (FavoriteRouteRecord, Data) {
        guard let archive = try openDirectory(create: false) else { throw FavoriteRoutesFailure.notFound }
        let records = try currentRecords(archive)
        guard let record = records.first(where: { $0.id == id }) else { throw FavoriteRoutesFailure.notFound }
        guard let data = try readFile(payloadName(id), directoryFD: archive, maximum: FavoriteRoutesLimits.fileBytes) else {
            throw FavoriteRoutesFailure.notFound
        }
        return (record, data)
    }

    public func updateLabel(_ id: UUID, label: String?) throws -> FavoriteRoutesReceipt {
        try Task.checkCancellation()
        _ = try FavoriteRoutePayload.label(label)
        guard let archive = try openDirectory(create: false) else { throw FavoriteRoutesFailure.notFound }
        var records = try currentRecords(archive)
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw FavoriteRoutesFailure.notFound }
        records[index] = try records[index].replacingLabel(label)
        try requireQuota(archive)
        try commit(records, directoryFD: archive)
        cleanup(archive, records: records)
        return receipt(records)
    }

    public func delete(_ id: UUID) throws -> FavoriteRoutesReceipt {
        try Task.checkCancellation()
        guard let descriptor = try openDirectory(create: false) else { throw FavoriteRoutesFailure.notFound }

        var records = try currentRecords(descriptor)
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw FavoriteRoutesFailure.notFound }
        let record = records.remove(at: index)
        try requireQuota(descriptor)
        try commit(records, directoryFD: descriptor)
        undo = (record, index)
        cleanup(descriptor, records: records)
        return receipt(records)
    }

    public func undoDelete() throws -> FavoriteRoutesReceipt {
        try Task.checkCancellation()
        guard let undo else { throw FavoriteRoutesFailure.nothingToUndo }
        guard let descriptor = try openDirectory(create: false) else { throw FavoriteRoutesFailure.notFound }

        var records = try currentRecords(descriptor)
        guard records.count < FavoriteRoutesLimits.records else { throw FavoriteRoutesFailure.limitExceeded }
        guard !records.contains(where: { $0.id == undo.record.id }) else { throw FavoriteRoutesFailure.corruptArchive }
        try verifyMetadata(undo.record, directoryFD: descriptor)
        try requireQuota(descriptor)
        records.insert(undo.record, at: min(undo.index, records.count))
        try commit(records, directoryFD: descriptor)
        self.undo = nil
        cleanup(descriptor, records: records)
        return receipt(records)
    }

    private func receipt(_ records: [FavoriteRouteRecord]) -> FavoriteRoutesReceipt {
        FavoriteRoutesReceipt(records: records, canUndo: undo != nil)
    }
    private func payloadName(_ id: UUID) -> String { id.uuidString + ".route" }

    private struct Manifest: Codable { let schemaVersion: Int; let records: [Record] }
    private struct Version: Decodable { let schemaVersion: Int }
    private struct Coordinate: Codable { let latitude: Double; let longitude: Double }
    private struct Record: Codable {
        let id: UUID; let label: String?; let sourceKind: FavoriteRouteSourceKind; let count: Int
        let start: Coordinate; let end: Coordinate; let startTitle: String?; let endTitle: String?
        let displayFilename: String?; let byteCount: Int; let sha256: String
        init(_ record: FavoriteRouteRecord) {
            id = record.id; label = record.label; sourceKind = record.sourceKind; count = record.count
            byteCount = record.byteCount; sha256 = record.sha256; displayFilename = record.displayFilename
            start = Coordinate(latitude: record.start.latitude, longitude: record.start.longitude)
            end = Coordinate(latitude: record.end.latitude, longitude: record.end.longitude)
            startTitle = record.startTitle; endTitle = record.endTitle
        }
        func validated() throws -> FavoriteRouteRecord {
            guard let start = GeoCoordinate(latitude: start.latitude, longitude: start.longitude),
                  let end = GeoCoordinate(latitude: end.latitude, longitude: end.longitude) else {
                throw FavoriteRoutesFailure.corruptArchive
            }
            do {
                return try FavoriteRouteRecord(id: id, label: label, sourceKind: sourceKind, count: count,
                    start: start, end: end, startTitle: startTitle, endTitle: endTitle,
                    displayFilename: displayFilename, byteCount: byteCount, sha256: sha256)
            } catch { throw FavoriteRoutesFailure.corruptArchive }
        }
    }

    private func currentRecords(_ descriptor: SecureArchiveDirectory) throws -> [FavoriteRouteRecord] {
        guard let data = try readFile(Self.manifestName, directoryFD: descriptor, maximum: FavoriteRoutesLimits.manifestBytes) else {
            // A missing archive is a new namespace. Existing recognized payloads
            // are counted/cleaned only after this healthy empty manifest decision.
            return []
        }
        let decoder = JSONDecoder()
        let version: Version
        do { version = try decoder.decode(Version.self, from: data) }
        catch { throw FavoriteRoutesFailure.corruptArchive }
        guard version.schemaVersion == 1 else { throw FavoriteRoutesFailure.unsupportedSchema }
        let manifest: Manifest
        do { manifest = try decoder.decode(Manifest.self, from: data) }
        catch { throw FavoriteRoutesFailure.corruptArchive }
        guard manifest.records.count <= FavoriteRoutesLimits.records else { throw FavoriteRoutesFailure.limitExceeded }
        var identities = Set<UUID>()
        return try manifest.records.map { dto in
            let record = try dto.validated()
            guard identities.insert(record.id).inserted else { throw FavoriteRoutesFailure.corruptArchive }
            try verifyMetadata(record, directoryFD: descriptor)
            return record
        }
    }

    private func verifyMetadata(_ record: FavoriteRouteRecord, directoryFD: SecureArchiveDirectory) throws {
        guard let attributes = try regularAttributes(payloadName(record.id), directoryFD: directoryFD) else {
            throw FavoriteRoutesFailure.metadataMismatch
        }
        guard attributes.st_size == record.byteCount else { throw FavoriteRoutesFailure.metadataMismatch }
    }

    private func commit(_ records: [FavoriteRouteRecord], directoryFD: SecureArchiveDirectory) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Manifest(schemaVersion: 1, records: records.map(Record.init)))
        guard data.count <= FavoriteRoutesLimits.manifestBytes else { throw FavoriteRoutesFailure.limitExceeded }
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

    private func writePayload(_ data: Data, record: FavoriteRouteRecord, directoryFD: SecureArchiveDirectory) throws {
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

    private func reach(_ point: FavoriteRoutesWriteCheckpoint) throws {
        do { try checkpoint(point) }
        catch let failure as FavoriteRoutesFailure { throw failure }
        catch { throw FavoriteRoutesFailure.writeFailed }
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
        guard name.hasSuffix(".route") else { return nil }
        let stem = String(name.dropLast(6))
        guard let id = UUID(uuidString: stem), id.uuidString == stem else { return nil }
        return id
    }
    private func requireQuota(_ directoryFD: SecureArchiveDirectory, adding: Int = 0) throws {
        var total = adding
        guard total <= FavoriteRoutesLimits.payloadBytes else { throw FavoriteRoutesFailure.limitExceeded }
        for name in try directoryNames(directoryFD) where ownedPayloadID(name) != nil {
            guard let attributes = try regularAttributes(name, directoryFD: directoryFD) else { continue }
            guard attributes.st_size <= FavoriteRoutesLimits.payloadBytes - total else { throw FavoriteRoutesFailure.limitExceeded }
            total += Int(attributes.st_size)
        }
    }
    private func cleanup(_ directoryFD: SecureArchiveDirectory, records: [FavoriteRouteRecord]) {
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
        case .unsafeFile: return FavoriteRoutesFailure.unsafeFile
        case .unavailable: return FavoriteRoutesFailure.unavailable
        case .writeFailed: return FavoriteRoutesFailure.writeFailed
        case .limitExceeded: return FavoriteRoutesFailure.limitExceeded
        }
    }
}
