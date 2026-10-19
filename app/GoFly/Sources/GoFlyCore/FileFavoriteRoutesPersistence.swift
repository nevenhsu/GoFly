import Foundation

public enum FavoriteRoutesWriteCheckpoint: CaseIterable, Sendable {
    case payloadSecured, payloadWritten, payloadFlushed
    case manifestSecured, manifestWritten, manifestFlushed, beforeManifestCommit
    case cleanup
}

/// One actor owns the manifest and payload writes. The manifest is authoritative;
/// a missing payload is reported as unavailable and is never removed implicitly.
public actor FileFavoriteRoutesPersistence: FavoriteRoutesPersistence {
    public nonisolated let directory: URL
    public nonisolated var manifestURL: URL { directory.appendingPathComponent(Self.manifestName) }
    private static let manifestName = "manifest.json"
    private let manifestFile: AtomicFile

    public init(directory: URL) {
        self.directory = directory.absoluteURL
        manifestFile = AtomicFile(directory: directory.absoluteURL, filename: Self.manifestName,
                                  maximumBytes: FavoriteRoutesLimits.manifestBytes)
    }

    public func read() throws -> FavoriteRoutesReceipt {
        let records = try loadRecords()
        var unavailable: [UUID: FavoriteRoutesFailure] = [:]
        for record in records where !payloadFile(record.id).exists() {
            unavailable[record.id] = .unavailable
        }
        return FavoriteRoutesReceipt(records: records, unavailable: unavailable)
    }

    public func save(_ candidate: FavoriteRouteSaveCandidate, label: String?) async throws -> FavoriteRouteSaveReceipt {
        try Task.checkCancellation()
        let artifact = try await Task.detached {
            _ = try FavoriteRoutePayload.label(label)
            return try FavoriteRouteArtifact(candidate: candidate)
        }.value
        try Task.checkCancellation()
        return try commitSave(artifact, label: label, omittedUnavailableCurrent: candidate.omittedUnavailableCurrent)
    }

    private func commitSave(_ artifact: FavoriteRouteArtifact, label: String?,
                            omittedUnavailableCurrent: Bool) throws -> FavoriteRouteSaveReceipt {
        var records = try loadRecords()
        guard records.count < FavoriteRoutesLimits.records else { throw FavoriteRoutesFailure.limitExceeded }
        let record = try artifact.record(label: label)
        try payloadFile(record.id).saveData(artifact.payload)
        records.append(record)
        try save(records)
        return FavoriteRouteSaveReceipt(archive: FavoriteRoutesReceipt(records: records, unavailable: [:]),
            result: FavoriteRouteSaveResult(record: record, omittedUnavailableCurrent: omittedUnavailableCurrent))
    }

    public func validate(_ id: UUID) async throws -> FavoriteRouteSnapshot {
        let record = try record(id)
        let data = try payload(id)
        return try await Task.detached {
            guard data.count == record.byteCount else { throw FavoriteRoutesFailure.metadataMismatch }
            guard FavoriteRoutePayload.hash(data) == record.sha256 else { throw FavoriteRoutesFailure.hashMismatch }
            return try FavoriteRouteSnapshot(record: record, source: FavoriteRoutePayload.decode(data, record: record))
        }.value
    }

    public func payload(_ id: UUID) throws -> Data {
        guard let data = try payloadFile(id).loadData() else { throw FavoriteRoutesFailure.unavailable }
        guard data.count <= FavoriteRoutesLimits.fileBytes else { throw FavoriteRoutesFailure.limitExceeded }
        return data
    }

    public func updateLabel(_ id: UUID, label: String?) throws -> FavoriteRoutesReceipt {
        _ = try FavoriteRoutePayload.label(label)
        var records = try loadRecords()
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw FavoriteRoutesFailure.notFound }
        records[index] = try records[index].replacingLabel(label)
        try save(records)
        var unavailable: [UUID: FavoriteRoutesFailure] = [:]
        for record in records where !payloadFile(record.id).exists() { unavailable[record.id] = .unavailable }
        return FavoriteRoutesReceipt(records: records, unavailable: unavailable)
    }

    public func delete(_ id: UUID) throws -> FavoriteRoutesReceipt {
        var records = try loadRecords()
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw FavoriteRoutesFailure.notFound }
        records.remove(at: index)
        try save(records)
        try? FileManager.default.removeItem(at: payloadFile(id).url)
        var unavailable: [UUID: FavoriteRoutesFailure] = [:]
        for record in records where !payloadFile(record.id).exists() { unavailable[record.id] = .unavailable }
        return FavoriteRoutesReceipt(records: records, unavailable: unavailable)
    }

    public func restore(_ record: FavoriteRouteRecord, payload: Data, at index: Int) throws -> FavoriteRoutesReceipt {
        guard payload.count == record.byteCount, FavoriteRoutePayload.hash(payload) == record.sha256 else {
            throw FavoriteRoutesFailure.metadataMismatch
        }
        var records = try loadRecords()
        guard !records.contains(where: { $0.id == record.id }) else { throw FavoriteRoutesFailure.corruptArchive }
        guard records.count < FavoriteRoutesLimits.records else { throw FavoriteRoutesFailure.limitExceeded }
        try payloadFile(record.id).saveData(payload)
        records.insert(record, at: min(index, records.count))
        try save(records)
        return FavoriteRoutesReceipt(records: records, unavailable: [:])
    }

    private func record(_ id: UUID) throws -> FavoriteRouteRecord {
        guard let record = try loadRecords().first(where: { $0.id == id }) else { throw FavoriteRoutesFailure.notFound }
        return record
    }
    private func loadRecords() throws -> [FavoriteRouteRecord] {
        guard let data = try manifestFile.loadData() else { return [] }
        return try _FavoriteRouteManifestCodec.decode(data)
    }
    private func save(_ records: [FavoriteRouteRecord]) throws {
        try manifestFile.saveData(try _FavoriteRouteManifestCodec.encode(records))
    }
    private func payloadFile(_ id: UUID) -> AtomicFile {
        AtomicFile(directory: directory, filename: id.uuidString + ".route", maximumBytes: FavoriteRoutesLimits.fileBytes)
    }
}

enum _FavoriteRouteManifestCodec {
    private struct Manifest: Codable { let schemaVersion: Int; let records: [Record] }
    private struct Version: Decodable { let schemaVersion: Int }
    private struct Coordinate: Codable { let latitude: Double; let longitude: Double }
    private struct Record: Codable {
        let id: UUID; let label: String?; let sourceKind: FavoriteRouteSourceKind; let count: Int
        let start: Coordinate; let end: Coordinate; let startTitle: String?; let endTitle: String?
        let displayFilename: String?; let byteCount: Int; let sha256: String
        init(_ value: FavoriteRouteRecord) {
            id = value.id; label = value.label; sourceKind = value.sourceKind; count = value.count
            start = Coordinate(latitude: value.start.latitude, longitude: value.start.longitude)
            end = Coordinate(latitude: value.end.latitude, longitude: value.end.longitude)
            startTitle = value.startTitle; endTitle = value.endTitle; displayFilename = value.displayFilename
            byteCount = value.byteCount; sha256 = value.sha256
        }
        func value() throws -> FavoriteRouteRecord {
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

    static func decode(_ data: Data) throws -> [FavoriteRouteRecord] {
        guard data.count <= FavoriteRoutesLimits.manifestBytes else { throw FavoriteRoutesFailure.limitExceeded }
        do {
            let version = try JSONDecoder().decode(Version.self, from: data)
            guard version.schemaVersion == 1 else { throw FavoriteRoutesFailure.unsupportedSchema }
            let archive = try JSONDecoder().decode(Manifest.self, from: data)
            guard archive.schemaVersion == version.schemaVersion,
                  archive.records.count <= FavoriteRoutesLimits.records else {
                throw FavoriteRoutesFailure.corruptArchive
            }
            var ids = Set<UUID>()
            return try archive.records.map { dto in
                let record = try dto.value()
                guard ids.insert(record.id).inserted else { throw FavoriteRoutesFailure.corruptArchive }
                return record
            }
        } catch let failure as FavoriteRoutesFailure { throw failure }
        catch { throw FavoriteRoutesFailure.corruptArchive }
    }

    static func encode(_ records: [FavoriteRouteRecord]) throws -> Data {
        guard records.count <= FavoriteRoutesLimits.records else { throw FavoriteRoutesFailure.limitExceeded }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Manifest(schemaVersion: 1, records: records.map(Record.init)))
        guard data.count <= FavoriteRoutesLimits.manifestBytes else { throw FavoriteRoutesFailure.limitExceeded }
        return data
    }
}
