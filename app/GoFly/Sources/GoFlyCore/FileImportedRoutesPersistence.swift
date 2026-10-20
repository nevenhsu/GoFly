import Foundation

/// One actor owns the manifest and payload writes. Index is authoritative; a
/// missing payload is reported as unavailable and is never removed implicitly.
public actor FileImportedRoutesPersistence: ImportedRoutesPersistence {
    public nonisolated let directory: URL
    public nonisolated var manifestURL: URL { directory.appendingPathComponent(Self.manifestName) }
    private static let manifestName = "manifest.json"
    private let manifestFile: AtomicFile

    public init(directory: URL) {
        self.directory = directory.absoluteURL
        manifestFile = AtomicFile(directory: directory.absoluteURL, filename: Self.manifestName,
                                  maximumBytes: ImportedRoutesLimits.manifestBytes)
    }

    public func read() throws -> ImportedRoutesReceipt {
        let records = try loadRecords()
        var unavailable: [UUID: ImportedRoutesFailure] = [:]
        for record in records where !payloadFile(record.id).exists() {
            unavailable[record.id] = .unavailable
        }
        return ImportedRoutesReceipt(records: records, unavailable: unavailable)
    }

    public func importArtifact(_ artifact: ImportedRouteArtifact) throws -> ImportedRoutesReceipt {
        try Task.checkCancellation()
        var records = try loadRecords()
        guard records.count < ImportedRoutesLimits.records else { throw ImportedRoutesFailure.limitExceeded }
        let record = try artifact.record()
        try payloadFile(record.id).saveData(artifact.payload)
        records.append(record)
        try save(records)
        return ImportedRoutesReceipt(records: records, unavailable: [:])
    }

    public func validate(_ id: UUID) async throws -> ImportedRouteSnapshot {
        guard let record = try loadRecords().first(where: { $0.id == id }) else {
            throw ImportedRoutesFailure.notFound
        }
        let data = try payload(id)
        return try ImportedRouteSnapshot(record: record, payload: data)
    }

    public func payload(_ id: UUID) throws -> Data {
        guard let data = try payloadFile(id).loadData() else { throw ImportedRoutesFailure.unavailable }
        guard data.count <= GPXLimits.fileBytes else { throw ImportedRoutesFailure.limitExceeded }
        return data
    }

    public func delete(_ id: UUID) throws -> ImportedRoutesReceipt {
        var records = try loadRecords()
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw ImportedRoutesFailure.notFound }
        records.remove(at: index)
        try save(records)
        try? FileManager.default.removeItem(at: payloadFile(id).url)
        var unavailable: [UUID: ImportedRoutesFailure] = [:]
        for record in records where !payloadFile(record.id).exists() { unavailable[record.id] = .unavailable }
        return ImportedRoutesReceipt(records: records, unavailable: unavailable)
    }

    public func restore(_ record: ImportedRouteRecord, payload: Data, at index: Int) throws -> ImportedRoutesReceipt {
        guard payload.count == record.byteCount, ImportedRouteArtifact.hash(payload) == record.sha256 else {
            throw ImportedRoutesFailure.metadataMismatch
        }
        var records = try loadRecords()
        guard !records.contains(where: { $0.id == record.id }) else { throw ImportedRoutesFailure.corruptArchive }
        guard records.count < ImportedRoutesLimits.records else { throw ImportedRoutesFailure.limitExceeded }
        try payloadFile(record.id).saveData(payload)
        records.insert(record, at: min(index, records.count))
        try save(records)
        return ImportedRoutesReceipt(records: records, unavailable: [:])
    }

    private func loadRecords() throws -> [ImportedRouteRecord] {
        guard let data = try manifestFile.loadData() else { return [] }
        return try _ImportedRouteManifestCodec.decode(data)
    }

    private func save(_ records: [ImportedRouteRecord]) throws {
        try manifestFile.saveData(try _ImportedRouteManifestCodec.encode(records))
    }

    private func payloadFile(_ id: UUID) -> AtomicFile {
        AtomicFile(directory: directory, filename: id.uuidString + ".gpx", maximumBytes: GPXLimits.fileBytes)
    }
}

enum _ImportedRouteManifestCodec {
    private struct Manifest: Codable { let schemaVersion: Int; let records: [Record] }
    private struct Version: Decodable { let schemaVersion: Int }
    private struct Coordinate: Codable { let latitude: Double; let longitude: Double }
    private struct Record: Codable {
        let id: UUID; let filename: String; let kind: GPXKind; let pointCount: Int; let byteCount: Int; let sha256: String
        let start: Coordinate; let end: Coordinate
        init(_ value: ImportedRouteRecord) {
            id = value.id; filename = value.filename; kind = value.kind; pointCount = value.pointCount
            byteCount = value.byteCount; sha256 = value.sha256
            start = Coordinate(latitude: value.start.latitude, longitude: value.start.longitude)
            end = Coordinate(latitude: value.end.latitude, longitude: value.end.longitude)
        }
        func value() throws -> ImportedRouteRecord {
            guard let start = GeoCoordinate(latitude: start.latitude, longitude: start.longitude),
                  let end = GeoCoordinate(latitude: end.latitude, longitude: end.longitude) else {
                throw ImportedRoutesFailure.corruptArchive
            }
            return try ImportedRouteRecord(id: id, filename: filename, kind: kind,
                pointCount: pointCount, byteCount: byteCount, sha256: sha256, start: start, end: end)
        }
    }

    static func decode(_ data: Data) throws -> [ImportedRouteRecord] {
        guard data.count <= ImportedRoutesLimits.manifestBytes else { throw ImportedRoutesFailure.limitExceeded }
        do {
            let version = try JSONDecoder().decode(Version.self, from: data)
            guard version.schemaVersion == 1 else { throw ImportedRoutesFailure.unsupportedSchema }
            let archive = try JSONDecoder().decode(Manifest.self, from: data)
            guard archive.schemaVersion == version.schemaVersion,
                  archive.records.count <= ImportedRoutesLimits.records else {
                throw ImportedRoutesFailure.corruptArchive
            }
            var ids = Set<UUID>()
            return try archive.records.map { dto in
                let record = try dto.value()
                guard ids.insert(record.id).inserted else { throw ImportedRoutesFailure.corruptArchive }
                return record
            }
        } catch let failure as ImportedRoutesFailure { throw failure }
        catch { throw ImportedRoutesFailure.corruptArchive }
    }

    static func encode(_ records: [ImportedRouteRecord]) throws -> Data {
        guard records.count <= ImportedRoutesLimits.records else { throw ImportedRoutesFailure.limitExceeded }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Manifest(schemaVersion: 1, records: records.map(Record.init)))
        guard data.count <= ImportedRoutesLimits.manifestBytes else { throw ImportedRoutesFailure.limitExceeded }
        return data
    }
}
