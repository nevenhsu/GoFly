import Foundation

public enum FavoritePlacesLimits {
    public static let records = 100
    public static let fileBytes = 1_048_576
    public static let titleCharacters = 512
    public static let addressCharacters = 2_048
    public static let labelCharacters = 120
    public static let identityBytes = 2_048
}

/// Display names and custom labels never participate in favorite identity.
public struct FavoritePlaceKey: Hashable, Sendable {
    public let identity: PlaceIdentity
    public let coordinate: GeoCoordinate
    public init?(place: MapPlace) {
        switch place.id {
        case .coordinate(let coordinate):
            guard coordinate == place.coordinate else { return nil }
        case .mapKit(let value):
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.utf8.count <= FavoritePlacesLimits.identityBytes, !value.contains("\0") else { return nil }
        }
        identity = place.id
        coordinate = place.coordinate
    }
}

public struct FavoritePlace: Identifiable, Equatable, Sendable {
    public let key: FavoritePlaceKey
    public let place: MapPlace
    public let label: String?
    public var id: FavoritePlaceKey { key }
    public var displayTitle: String { label ?? place.title }
}

public enum FavoritePlacesFailure: String, Error, Equatable, Sendable {
    case corruptArchive = "favorites.error.corruptArchive"
    case unsupportedSchema = "favorites.error.unsupportedSchema"
    case unsafeFile = "favorites.error.unsafeFile"
    case unavailable = "favorites.error.unavailable"
    case writeFailed = "favorites.error.writeFailed"
    case invalidPlace = "favorites.error.invalidPlace"
    case invalidLabel = "favorites.error.invalidLabel"
    case limitExceeded = "favorites.error.limitExceeded"
    case notFavorite = "favorites.error.notFavorite"
}

public enum FavoritePlacesLoadState: Equatable, Sendable {
    case ready
    case blocked(FavoritePlacesFailure)
}
