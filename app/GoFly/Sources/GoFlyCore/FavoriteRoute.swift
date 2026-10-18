import CryptoKit
import Foundation

public enum FavoriteRoutesLimits {
    public static let records = 100
    public static let payloadBytes = 64 * 1_024 * 1_024
    public static let manifestBytes = 1_024 * 1_024
    public static let fileBytes = 2 * 1_024 * 1_024
    public static let manualPlaces = 27
    public static let labelCharacters = FavoritePlacesLimits.labelCharacters
    public static let titleCharacters = FavoritePlacesLimits.titleCharacters
    public static let addressCharacters = FavoritePlacesLimits.addressCharacters
    public static let identityBytes = FavoritePlacesLimits.identityBytes
}

public enum FavoriteRouteSourceKind: String, Codable, Equatable, Sendable { case manual, gpx }
public enum FavoriteRouteSource: Equatable, Sendable {
    case manual([MapPlace])
    case gpx(GPXRouteSource)
}

public struct FavoriteRouteSaveCandidate: Equatable, Sendable {
    public let source: FavoriteRouteSource
    public let omittedUnavailableCurrent: Bool
    init(source: FavoriteRouteSource, omittedUnavailableCurrent: Bool) {
        self.source = source; self.omittedUnavailableCurrent = omittedUnavailableCurrent
    }
}

public enum FavoriteRouteSaveBuilder {
    /// Both arguments are values captured by the actual Save action. This pure
    /// boundary has no service, GPS cache, planner, persistence or live mutation.
    public static func build(draft: RouteDraft, currentRouteOrigin: GeoCoordinate?) throws -> FavoriteRouteSaveCandidate {
        if let source = draft.gpxSource {
            return FavoriteRouteSaveCandidate(source: .gpx(source), omittedUnavailableCurrent: false)
        }
        var places: [MapPlace] = []
        var omitted = false
        for node in draft.nodes {
            switch node.value {
            case .place(let place): try FavoriteRoutePayload.validate(place); places.append(place)
            case .current:
                if let coordinate = currentRouteOrigin {
                    places.append(MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate))
                } else { omitted = true }
            }
        }
        guard places.count >= 2 else { throw FavoriteRoutesFailure.tooFewValidPlaces }
        guard places.count <= FavoriteRoutesLimits.manualPlaces else { throw FavoriteRoutesFailure.limitExceeded }
        return FavoriteRouteSaveCandidate(source: .manual(places), omittedUnavailableCurrent: omitted)
    }
}

public struct FavoriteRouteRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String?
    public let sourceKind: FavoriteRouteSourceKind
    public let count: Int
    public let start: GeoCoordinate
    public let end: GeoCoordinate
    public let startTitle: String?
    public let endTitle: String?
    public let displayFilename: String?
    public let byteCount: Int
    public let sha256: String
    public init(id: UUID, label: String?, sourceKind: FavoriteRouteSourceKind, count: Int,
                start: GeoCoordinate, end: GeoCoordinate, startTitle: String? = nil, endTitle: String? = nil,
                displayFilename: String?, byteCount: Int, sha256: String) throws {
        self.label = try FavoriteRoutePayload.label(label)
        guard (2...(sourceKind == .manual ? FavoriteRoutesLimits.manualPlaces : GPXLimits.points)).contains(count),
              (1...FavoriteRoutesLimits.fileBytes).contains(byteCount), sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw FavoriteRoutesFailure.corruptArchive
        }
        switch sourceKind {
        case .manual:
            guard displayFilename == nil, let startTitle, let endTitle,
                  [startTitle, endTitle].allSatisfy({ FavoritePlacesArchive.validText($0, maximum: FavoriteRoutesLimits.titleCharacters) &&
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw FavoriteRoutesFailure.corruptArchive }
        case .gpx:
            guard startTitle == nil, endTitle == nil, let displayFilename,
                  GPXRouteSource.validDisplayFilename(displayFilename) else { throw FavoriteRoutesFailure.corruptArchive }
        }
        self.id = id; self.sourceKind = sourceKind; self.count = count
        self.start = start; self.end = end; self.displayFilename = displayFilename
        self.startTitle = startTitle; self.endTitle = endTitle
        self.byteCount = byteCount; self.sha256 = sha256
    }
    func replacingLabel(_ label: String?) throws -> FavoriteRouteRecord {
        try FavoriteRouteRecord(id: id, label: label, sourceKind: sourceKind, count: count,
            start: start, end: end, startTitle: startTitle, endTitle: endTitle,
            displayFilename: displayFilename, byteCount: byteCount, sha256: sha256)
    }
}

/// Prepared away from MainActor and outside the persistence transaction. Label
/// is intentionally absent, so editing it never changes immutable payload bytes.
public struct FavoriteRouteArtifact: Equatable, Sendable {
    public let source: FavoriteRouteSource
    public let payload: Data
    private let sha256: String
    public init(candidate: FavoriteRouteSaveCandidate) throws {
        source = candidate.source
        payload = try FavoriteRoutePayload.encode(source)
        guard payload.count <= FavoriteRoutesLimits.fileBytes else { throw FavoriteRoutesFailure.limitExceeded }
        sha256 = FavoriteRoutePayload.hash(payload)
    }
    public func record(id: UUID = UUID(), label: String?) throws -> FavoriteRouteRecord {
        let kind: FavoriteRouteSourceKind
        let count: Int
        let start: GeoCoordinate
        let end: GeoCoordinate
        let filename: String?
        let startTitle: String?
        let endTitle: String?
        switch source {
        case .manual(let places):
            kind = .manual; count = places.count; start = places.first!.coordinate; end = places.last!.coordinate; filename = nil
            startTitle = places.first!.title; endTitle = places.last!.title
        case .gpx(let gpx):
            kind = .gpx; count = gpx.document.pointCount; start = gpx.document.segments.first!.first!
            end = gpx.document.segments.last!.last!; filename = gpx.displayFilename
            startTitle = nil; endTitle = nil
        }
        return try FavoriteRouteRecord(id: id, label: label, sourceKind: kind, count: count, start: start,
            end: end, startTitle: startTitle, endTitle: endTitle, displayFilename: filename, byteCount: payload.count, sha256: sha256)
    }
}

public struct FavoriteRouteSnapshot: Equatable, Sendable {
    public let record: FavoriteRouteRecord
    public let source: FavoriteRouteSource
    public init(record: FavoriteRouteRecord, source: FavoriteRouteSource) throws {
        let artifact = try FavoriteRouteArtifact(candidate: FavoriteRouteSaveCandidate(source: source, omittedUnavailableCurrent: false))
        guard try artifact.record(id: record.id, label: record.label) == record else { throw FavoriteRoutesFailure.metadataMismatch }
        self.record = record; self.source = source
    }
    public init(source: FavoriteRouteSource, label: String? = nil, id: UUID = UUID()) throws {
        let artifact = try FavoriteRouteArtifact(candidate: FavoriteRouteSaveCandidate(source: source, omittedUnavailableCurrent: false))
        try self.init(record: artifact.record(id: id, label: label), source: source)
    }
}

public enum FavoriteRoutesFailure: Error, Equatable, Sendable {
    case corruptArchive, unsupportedSchema, unsafeFile, unavailable, writeFailed, limitExceeded
    case invalidLabel, invalidPlace, tooFewValidPlaces, notFound, metadataMismatch, hashMismatch, noSelection, busy, nothingToUndo
    case gpx(GPXFailure)
    public var localizationKey: String {
        switch self {
        case .gpx(let failure): failure.localizationKey
        case .corruptArchive: "favoriteRoutes.error.corruptArchive"
        case .unsupportedSchema: "favoriteRoutes.error.unsupportedSchema"
        case .unsafeFile: "favoriteRoutes.error.unsafeFile"
        case .unavailable: "favoriteRoutes.error.unavailable"
        case .writeFailed: "favoriteRoutes.error.writeFailed"
        case .limitExceeded: "favoriteRoutes.error.limitExceeded"
        case .invalidLabel: "favoriteRoutes.error.invalidLabel"
        case .invalidPlace: "favoriteRoutes.error.invalidPlace"
        case .tooFewValidPlaces: "favoriteRoutes.error.tooFewValidPlaces"
        case .notFound: "favoriteRoutes.error.notFound"
        case .metadataMismatch: "favoriteRoutes.error.metadataMismatch"
        case .hashMismatch: "favoriteRoutes.error.hashMismatch"
        case .noSelection: "favoriteRoutes.error.noSelection"
        case .busy: "favoriteRoutes.error.busy"
        case .nothingToUndo: "favoriteRoutes.error.nothingToUndo"
        }
    }
    static func mapped(_ error: any Error) -> Self {
        if let failure = error as? Self { return failure }
        if let failure = error as? GPXFailure { return .gpx(failure) }
        if error is GPXRouteSourceFailure { return .corruptArchive }
        return .unavailable
    }
}
public enum FavoriteRoutesLoadState: Equatable, Sendable { case loading, ready, blocked(FavoriteRoutesFailure) }
public struct FavoriteRoutesReceipt: Equatable, Sendable {
    public let records: [FavoriteRouteRecord]
    public let canUndo: Bool
    public init(records: [FavoriteRouteRecord], canUndo: Bool) { self.records = records; self.canUndo = canUndo }
}
public struct FavoriteRouteSaveResult: Equatable, Sendable {
    public let record: FavoriteRouteRecord
    public let omittedUnavailableCurrent: Bool
    public init(record: FavoriteRouteRecord, omittedUnavailableCurrent: Bool) {
        self.record = record; self.omittedUnavailableCurrent = omittedUnavailableCurrent
    }
}
public struct FavoriteRouteSaveReceipt: Equatable, Sendable {
    public let archive: FavoriteRoutesReceipt
    public let result: FavoriteRouteSaveResult
    public init(archive: FavoriteRoutesReceipt, result: FavoriteRouteSaveResult) { self.archive = archive; self.result = result }
}
public protocol FavoriteRoutesPersistence: Sendable {
    func read() async throws -> FavoriteRoutesReceipt
    func save(_ candidate: FavoriteRouteSaveCandidate, label: String?) async throws -> FavoriteRouteSaveReceipt
    func validate(_ id: UUID) async throws -> FavoriteRouteSnapshot
    func transferSnapshot() async throws -> TransferArchiveSnapshot
    func updateLabel(_ id: UUID, label: String?) async throws -> FavoriteRoutesReceipt
    func delete(_ id: UUID) async throws -> FavoriteRoutesReceipt
    func undoDelete() async throws -> FavoriteRoutesReceipt
}

public extension FavoriteRoutesPersistence {
    func transferSnapshot() async throws -> TransferArchiveSnapshot {
        throw FavoriteRoutesFailure.unavailable
    }
}
public struct UnavailableFavoriteRoutesPersistence: FavoriteRoutesPersistence {
    public init() {}
    public func read() async throws -> FavoriteRoutesReceipt { throw FavoriteRoutesFailure.unavailable }
    public func save(_ candidate: FavoriteRouteSaveCandidate, label: String?) async throws -> FavoriteRouteSaveReceipt { throw FavoriteRoutesFailure.unavailable }
    public func validate(_ id: UUID) async throws -> FavoriteRouteSnapshot { throw FavoriteRoutesFailure.unavailable }
    public func updateLabel(_ id: UUID, label: String?) async throws -> FavoriteRoutesReceipt { throw FavoriteRoutesFailure.unavailable }
    public func delete(_ id: UUID) async throws -> FavoriteRoutesReceipt { throw FavoriteRoutesFailure.unavailable }
    public func undoDelete() async throws -> FavoriteRoutesReceipt { throw FavoriteRoutesFailure.unavailable }
}

enum FavoriteRoutePayload {
    private struct Version: Decodable { let schemaVersion: Int }
    private struct ManualArchive: Codable { let schemaVersion: Int; let places: [Place] }
    private struct Identity: Codable { let kind: String; let value: String? }
    private struct Coordinate: Codable { let latitude: Double; let longitude: Double }
    private struct Place: Codable {
        let identity: Identity; let coordinate: Coordinate; let title: String; let address: String?
    }
    static func label(_ value: String?) throws -> String? {
        if let value, !FavoritePlacesArchive.validText(value, maximum: FavoriteRoutesLimits.labelCharacters) { throw FavoriteRoutesFailure.invalidLabel }
        return FavoritePlacesArchive.normalizedLabel(value)
    }
    static func validate(_ place: MapPlace) throws {
        guard FavoritePlaceKey(place: place) != nil,
              FavoritePlacesArchive.validText(place.title, maximum: FavoriteRoutesLimits.titleCharacters),
              !place.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              place.address.map({ FavoritePlacesArchive.validText($0, maximum: FavoriteRoutesLimits.addressCharacters) }) ?? true else {
            throw FavoriteRoutesFailure.invalidPlace
        }
    }
    static func encode(_ source: FavoriteRouteSource) throws -> Data {
        switch source {
        case .gpx(let source): return try GPXCodec.encode(source.document, name: source.displayFilename)
        case .manual(let places):
            guard places.count >= 2 else { throw FavoriteRoutesFailure.tooFewValidPlaces }
            guard places.count <= FavoriteRoutesLimits.manualPlaces else { throw FavoriteRoutesFailure.limitExceeded }
            let records = try places.map { place -> Place in
                try validate(place)
                let identity: Identity
                switch place.id {
                case .mapKit(let id): identity = Identity(kind: "mapKit", value: id)
                case .coordinate: identity = Identity(kind: "coordinate", value: nil)
                }
                return Place(identity: identity, coordinate: Coordinate(latitude: place.coordinate.latitude,
                    longitude: place.coordinate.longitude), title: place.title, address: place.address)
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(ManualArchive(schemaVersion: 1, places: records))
        }
    }
    static func decode(_ data: Data, record: FavoriteRouteRecord) throws -> FavoriteRouteSource {
        guard data.count <= FavoriteRoutesLimits.fileBytes else { throw FavoriteRoutesFailure.limitExceeded }
        if record.sourceKind == .gpx {
            guard let filename = record.displayFilename else { throw FavoriteRoutesFailure.corruptArchive }
            do { return .gpx(try GPXRouteSource(document: GPXCodec.decode(data), displayFilename: filename)) }
            catch { throw FavoriteRoutesFailure.mapped(error) }
        }
        let decoder = JSONDecoder()
        let version: Version
        do { version = try decoder.decode(Version.self, from: data) }
        catch { throw FavoriteRoutesFailure.corruptArchive }
        guard version.schemaVersion == 1 else { throw FavoriteRoutesFailure.unsupportedSchema }
        let archive: ManualArchive
        do { archive = try decoder.decode(ManualArchive.self, from: data) }
        catch { throw FavoriteRoutesFailure.corruptArchive }
        guard (2...FavoriteRoutesLimits.manualPlaces).contains(archive.places.count) else { throw FavoriteRoutesFailure.corruptArchive }
        let places = try archive.places.map { dto -> MapPlace in
            guard let coordinate = GeoCoordinate(latitude: dto.coordinate.latitude, longitude: dto.coordinate.longitude),
                  FavoritePlacesArchive.validText(dto.title, maximum: FavoriteRoutesLimits.titleCharacters),
                  !dto.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  dto.address.map({ FavoritePlacesArchive.validText($0, maximum: FavoriteRoutesLimits.addressCharacters) }) ?? true else {
                throw FavoriteRoutesFailure.corruptArchive
            }
            let identity: PlaceIdentity
            switch dto.identity.kind {
            case "mapKit": guard let id = dto.identity.value else { throw FavoriteRoutesFailure.corruptArchive }; identity = .mapKit(id)
            case "coordinate": guard dto.identity.value == nil else { throw FavoriteRoutesFailure.corruptArchive }; identity = .coordinate(coordinate)
            default: throw FavoriteRoutesFailure.corruptArchive
            }
            let place = MapPlace(id: identity, title: dto.title, coordinate: coordinate, address: dto.address)
            do { try validate(place) } catch { throw FavoriteRoutesFailure.corruptArchive }
            return place
        }
        return .manual(places)
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
