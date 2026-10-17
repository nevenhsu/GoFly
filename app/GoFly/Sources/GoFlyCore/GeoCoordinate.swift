import Foundation

public struct GeoCoordinate: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    public var displayText: String {
        String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }
}
