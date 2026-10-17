import Foundation

public enum JoystickGeodesy {
    private static let radius = 6_371_000.0

    /// At a pole the origin's longitude defines the local north/east tangent basis.
    public static func destination(from origin: GeoCoordinate, displacement: JoystickDisplacement) -> GeoCoordinate {
        let latitude = origin.latitude * .pi / 180, longitude = origin.longitude * .pi / 180
        let bearing = displacement.bearingDegrees * .pi / 180
        let angle = displacement.distanceMeters / radius
        let sinLat = sin(latitude), cosLat = cos(latitude), sinLon = sin(longitude), cosLon = cos(longitude)
        let radial = (x: cosLat * cosLon, y: cosLat * sinLon, z: sinLat)
        let north = (x: -sinLat * cosLon, y: -sinLat * sinLon, z: cosLat)
        let east = (x: -sinLon, y: cosLon, z: 0.0)
        let x = cos(angle) * radial.x + sin(angle) * (cos(bearing) * north.x + sin(bearing) * east.x)
        let y = cos(angle) * radial.y + sin(angle) * (cos(bearing) * north.y + sin(bearing) * east.y)
        let z = cos(angle) * radial.z + sin(angle) * (cos(bearing) * north.z + sin(bearing) * east.z)
        let resultLatitude = atan2(z, hypot(x, y)) * 180 / .pi
        let resultLongitude = atan2(y, x) * 180 / .pi
        return GeoCoordinate(latitude: resultLatitude, longitude: resultLongitude >= 180 ? resultLongitude - 360 : resultLongitude)!
    }
}
