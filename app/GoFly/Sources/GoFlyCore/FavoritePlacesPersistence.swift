import Foundation

public protocol FavoritePlacesPersistence: Sendable {
    func read() throws -> Data?
    /// Captures the current owner archive without invoking the normal reader's
    /// cleanup or normalization behavior. Unsupported conformers remain
    /// unavailable for transfer.
    func transferSnapshot() throws -> Data?
    /// Throwing guarantees that the previously authoritative bytes remain unchanged.
    func replaceAtomically(with data: Data) throws
}

public extension FavoritePlacesPersistence {
    func transferSnapshot() throws -> Data? { throw FavoritePlacesFailure.unavailable }
}

/// The on-disk DTO is deliberately separate from validated runtime coordinates.
enum FavoritePlacesArchive {
    private struct Version: Decodable { let schemaVersion: Int }
    private struct Archive: Codable {
        let schemaVersion: Int
        let favorites: [Record]
    }
    private struct Identity: Codable {
        let kind: String
        let value: String?
    }
    private struct Coordinate: Codable {
        let latitude: Double
        let longitude: Double
    }
    private struct Record: Codable {
        let identity: Identity
        let coordinate: Coordinate
        let title: String
        let address: String?
        let label: String?
    }

    static func decode(_ data: Data) throws -> [FavoritePlace] {
        guard data.count <= FavoritePlacesLimits.fileBytes else { throw FavoritePlacesFailure.limitExceeded }
        let version: Version
        do { version = try JSONDecoder().decode(Version.self, from: data) }
        catch { throw FavoritePlacesFailure.corruptArchive }
        guard version.schemaVersion == 1 else { throw FavoritePlacesFailure.unsupportedSchema }
        let archive: Archive
        do { archive = try JSONDecoder().decode(Archive.self, from: data) }
        catch { throw FavoritePlacesFailure.corruptArchive }
        guard archive.favorites.count <= FavoritePlacesLimits.records else { throw FavoritePlacesFailure.limitExceeded }
        var keys = Set<FavoritePlaceKey>()
        return try archive.favorites.map { record in
            guard let coordinate = GeoCoordinate(latitude: record.coordinate.latitude, longitude: record.coordinate.longitude) else {
                throw FavoritePlacesFailure.corruptArchive
            }
            let identity: PlaceIdentity
            switch record.identity.kind {
            case "mapKit":
                guard let value = record.identity.value else { throw FavoritePlacesFailure.corruptArchive }
                identity = .mapKit(value)
            case "coordinate":
                guard record.identity.value == nil else { throw FavoritePlacesFailure.corruptArchive }
                identity = .coordinate(coordinate)
            default: throw FavoritePlacesFailure.corruptArchive
            }
            // Validate original bytes before MapPlace's display fallbacks or normalization.
            guard validText(record.title, maximum: FavoritePlacesLimits.titleCharacters),
                  !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.address.map({ validText($0, maximum: FavoritePlacesLimits.addressCharacters) }) ?? true,
                  record.label.map({ validText($0, maximum: FavoritePlacesLimits.labelCharacters) }) ?? true else {
                throw FavoritePlacesFailure.corruptArchive
            }
            let place = MapPlace(id: identity, title: record.title, coordinate: coordinate, address: record.address)
            guard let key = FavoritePlaceKey(place: place), keys.insert(key).inserted else {
                throw FavoritePlacesFailure.corruptArchive
            }
            return FavoritePlace(key: key, place: place, label: normalizedLabel(record.label))
        }
    }

    static func encode(_ favorites: [FavoritePlace]) throws -> Data {
        guard favorites.count <= FavoritePlacesLimits.records else { throw FavoritePlacesFailure.limitExceeded }
        let records = try favorites.map { favorite -> Record in
            try validate(favorite.place)
            guard FavoritePlaceKey(place: favorite.place) == favorite.key else { throw FavoritePlacesFailure.invalidPlace }
            if let label = favorite.label, !validText(label, maximum: FavoritePlacesLimits.labelCharacters) {
                throw FavoritePlacesFailure.invalidLabel
            }
            let identity: Identity
            switch favorite.key.identity {
            case .mapKit(let value): identity = Identity(kind: "mapKit", value: value)
            case .coordinate: identity = Identity(kind: "coordinate", value: nil)
            }
            return Record(identity: identity,
                coordinate: Coordinate(latitude: favorite.place.coordinate.latitude, longitude: favorite.place.coordinate.longitude),
                title: favorite.place.title, address: favorite.place.address, label: favorite.label)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Archive(schemaVersion: 1, favorites: records))
        guard data.count <= FavoritePlacesLimits.fileBytes else { throw FavoritePlacesFailure.limitExceeded }
        return data
    }

    static func validate(_ place: MapPlace) throws {
        guard FavoritePlaceKey(place: place) != nil,
              validText(place.title, maximum: FavoritePlacesLimits.titleCharacters),
              place.address.map({ validText($0, maximum: FavoritePlacesLimits.addressCharacters) }) ?? true else {
            throw FavoritePlacesFailure.invalidPlace
        }
    }
    static func validText(_ text: String, maximum: Int) -> Bool { text.count <= maximum && !text.contains("\0") }
    static func normalizedLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
