import CryptoKit
import Foundation

/// Shared pure manifest codecs.  File persistence and transfer validation use
/// the same DTOs so the legacy archive acceptance rules do not drift.
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
            guard archive.schemaVersion == version.schemaVersion else { throw ImportedRoutesFailure.corruptArchive }
            guard archive.records.count <= ImportedRoutesLimits.records else { throw ImportedRoutesFailure.limitExceeded }
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
            guard archive.schemaVersion == version.schemaVersion else { throw FavoriteRoutesFailure.corruptArchive }
            guard archive.records.count <= FavoriteRoutesLimits.records else { throw FavoriteRoutesFailure.limitExceeded }
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

public enum TransferArchiveCodec {
    public static func favoritePlaces(_ data: Data) throws -> [FavoritePlace] {
        do { return try FavoritePlacesArchive.decode(data) }
        catch let failure as FavoritePlacesFailure {
            switch failure {
            case .limitExceeded: throw TransferFailure.limitExceeded
            default: throw TransferFailure.invalidInput
            }
        } catch { throw TransferFailure.invalidInput }
    }

    public static func emptyFavoritePlaces() throws -> Data {
        do { return try FavoritePlacesArchive.encode([]) }
        catch { throw TransferFailure.invalidInput }
    }

    public static func importedRoutes(_ snapshot: TransferArchiveSnapshot) throws -> [ImportedRouteRecord] {
        let records: [ImportedRouteRecord]
        records = try decodeImportedManifest(snapshot.manifest)
        guard records.count <= ImportedRoutesLimits.records else { throw TransferFailure.limitExceeded }
        let expected = Set(records.map { $0.id.uuidString + ".gpx" })
        guard Set(snapshot.payloads.keys) == expected else { throw TransferFailure.artifactMismatch }
        var aggregate: Int64 = 0
        for record in records {
            let name = record.id.uuidString + ".gpx"
            guard let data = snapshot.payloads[name], data.count == record.byteCount,
                  data.count <= GPXLimits.fileBytes,
                  aggregate <= Int64(ImportedRoutesLimits.payloadBytes - data.count) else {
                throw TransferFailure.limitExceeded
            }
            aggregate += Int64(data.count)
            try validateImportedPayload(data, record: record)
        }
        return records
    }

    public static func favoriteRoutes(_ snapshot: TransferArchiveSnapshot) throws -> [FavoriteRouteRecord] {
        let records: [FavoriteRouteRecord]
        records = try decodeFavoriteRouteManifest(snapshot.manifest)
        guard records.count <= FavoriteRoutesLimits.records else { throw TransferFailure.limitExceeded }
        let expected = Set(records.map { $0.id.uuidString + ".route" })
        guard Set(snapshot.payloads.keys) == expected else { throw TransferFailure.artifactMismatch }
        var aggregate: Int64 = 0
        for record in records {
            let name = record.id.uuidString + ".route"
            guard let data = snapshot.payloads[name], data.count == record.byteCount,
                  data.count <= FavoriteRoutesLimits.fileBytes,
                  aggregate <= Int64(FavoriteRoutesLimits.payloadBytes) - Int64(data.count) else {
                throw TransferFailure.limitExceeded
            }
            aggregate += Int64(data.count)
            try validateFavoriteRoutePayload(data, record: record)
        }
        return records
    }

    static func encodeImportedManifest(_ records: [ImportedRouteRecord]) throws -> Data {
        do { return try _ImportedRouteManifestCodec.encode(records) }
        catch { throw transferFailure(error) }
    }

    static func encodeFavoriteRouteManifest(_ records: [FavoriteRouteRecord]) throws -> Data {
        do { return try _FavoriteRouteManifestCodec.encode(records) }
        catch { throw transferFailure(error) }
    }

    static func decodeImportedManifest(_ data: Data) throws -> [ImportedRouteRecord] {
        do { return try _ImportedRouteManifestCodec.decode(data) }
        catch { throw transferFailure(error) }
    }

    static func decodeFavoriteRouteManifest(_ data: Data) throws -> [FavoriteRouteRecord] {
        do { return try _FavoriteRouteManifestCodec.decode(data) }
        catch { throw transferFailure(error) }
    }

    static func validateImportedPayload(_ data: Data, record: ImportedRouteRecord) throws {
        guard data.count == record.byteCount, data.count <= GPXLimits.fileBytes else { throw TransferFailure.limitExceeded }
        guard ImportedRouteArtifact.hash(data) == record.sha256 else { throw TransferFailure.artifactMismatch }
        do {
            let document = try GPXCodec.decode(data)
            _ = try ImportedRouteSnapshot(record: record, document: document)
        } catch { throw transferFailure(error) }
    }

    static func validateFavoriteRoutePayload(_ data: Data, record: FavoriteRouteRecord) throws {
        guard data.count == record.byteCount, data.count <= FavoriteRoutesLimits.fileBytes else { throw TransferFailure.limitExceeded }
        guard FavoriteRoutePayload.hash(data) == record.sha256 else { throw TransferFailure.artifactMismatch }
        do {
            let source = try FavoriteRoutePayload.decode(data, record: record)
            _ = try FavoriteRouteSnapshot(record: record, source: source)
        } catch { throw transferFailure(error) }
    }

    private static func transferFailure(_ error: any Error) -> TransferFailure {
        if let failure = error as? TransferFailure { return failure }
        switch error {
        case let failure as ImportedRoutesFailure:
            switch failure { case .limitExceeded: return .limitExceeded; case .unsafeFile: return .unsafeFile; default: return .invalidInput }
        case let failure as FavoriteRoutesFailure:
            switch failure { case .limitExceeded: return .limitExceeded; case .unsafeFile: return .unsafeFile; default: return .invalidInput }
        case let failure as GPXFailure:
            switch failure { case .sizeLimitExceeded, .pointLimitExceeded, .resourceLimitExceeded: return .limitExceeded; default: return .invalidInput }
        default: return .invalidInput
        }
    }
}
