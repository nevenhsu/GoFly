import Foundation

public enum GeoPointError: Error, Equatable, Sendable {
    case nonFinite
    case latitudeOutOfRange
    case longitudeOutOfRange
}

/// A validated geographic coordinate in decimal degrees.
public struct GeoPoint: Codable, Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite else {
            throw GeoPointError.nonFinite
        }
        guard (-90.0...90.0).contains(latitude) else {
            throw GeoPointError.latitudeOutOfRange
        }
        guard (-180.0...180.0).contains(longitude) else {
            throw GeoPointError.longitudeOutOfRange
        }

        self.latitude = latitude
        self.longitude = longitude
    }

    public func distance(to other: GeoPoint) -> Double {
        let latitude1 = latitude * .pi / 180.0
        let latitude2 = other.latitude * .pi / 180.0
        let latitudeDelta = latitude2 - latitude1
        let longitudeDelta = Self.shortestLongitudeDelta(
            (other.longitude - longitude) * .pi / 180.0
        )

        let latitudeHaversine = sin(latitudeDelta / 2.0)
        let longitudeHaversine = sin(longitudeDelta / 2.0)
        let haversine = min(
            1.0,
            max(
                0.0,
                latitudeHaversine * latitudeHaversine
                    + cos(latitude1) * cos(latitude2)
                    * longitudeHaversine * longitudeHaversine
            )
        )
        return 2.0 * Self.earthRadiusMeters * asin(sqrt(haversine))
    }

    public func moved(distanceMeters: Double, headingDegrees: Double) -> GeoPoint {
        guard distanceMeters.isFinite, headingDegrees.isFinite else {
            return self
        }

        let latitude1 = latitude * .pi / 180.0
        let longitude1 = longitude * .pi / 180.0
        let heading = headingDegrees * .pi / 180.0
        let angularDistance = distanceMeters / Self.earthRadiusMeters

        let latitude2 = asin(Self.clamp(
            sin(latitude1) * cos(angularDistance)
                + cos(latitude1) * sin(angularDistance) * cos(heading)
        ))
        let longitudeDelta = atan2(
            sin(heading) * sin(angularDistance) * cos(latitude1),
            cos(angularDistance) - sin(latitude1) * sin(latitude2)
        )
        let longitude2 = Self.normalizedLongitude(longitude1 + longitudeDelta)

        // The spherical destination formula produces a valid coordinate for
        // finite inputs. Rounding at a pole can otherwise exceed asin's range
        // by a few ulps, which is clamped above.
        return try! GeoPoint(
            latitude: latitude2 * 180.0 / .pi,
            longitude: longitude2 * 180.0 / .pi
        )
    }

    fileprivate static let earthRadiusMeters = 6_371_000.0

    fileprivate static func shortestLongitudeDelta(_ radians: Double) -> Double {
        var result = radians.truncatingRemainder(dividingBy: 2.0 * .pi)
        if result > .pi {
            result -= 2.0 * .pi
        } else if result < -.pi {
            result += 2.0 * .pi
        }
        return result
    }

    fileprivate static func normalizedLongitude(_ radians: Double) -> Double {
        var result = radians.truncatingRemainder(dividingBy: 2.0 * .pi)
        if result > .pi {
            result -= 2.0 * .pi
        } else if result < -.pi {
            result += 2.0 * .pi
        }
        return result
    }

    fileprivate static func clamp(_ value: Double, lower: Double = -1.0, upper: Double = 1.0) -> Double {
        min(upper, max(lower, value))
    }

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)

        do {
            try self.init(latitude: latitude, longitude: longitude)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .latitude,
                in: container,
                debugDescription: "GeoPoint contains an invalid latitude or longitude."
            )
        }
    }
}

public enum RoutePathError: Error, Equatable, Sendable {
    case tooFewPoints
    case tooManyPoints
    case zeroLength
}

/// A route made up of validated geographic points and great-circle segments.
public struct RoutePath: Sendable {
    public let points: [GeoPoint]
    public let lengthMeters: Double

    private let cumulativeDistances: [Double]

    public init(points: [GeoPoint]) throws {
        guard points.count >= 2 else {
            throw RoutePathError.tooFewPoints
        }
        guard points.count <= 10_000 else {
            throw RoutePathError.tooManyPoints
        }

        var cumulativeDistances = [0.0]
        cumulativeDistances.reserveCapacity(points.count)
        var length = 0.0
        for pair in zip(points, points.dropFirst()) {
            length += pair.0.distance(to: pair.1)
            cumulativeDistances.append(length)
        }
        guard length > 0.0 else {
            throw RoutePathError.zeroLength
        }

        self.points = points
        self.lengthMeters = length
        self.cumulativeDistances = cumulativeDistances
    }

    /// Returns the point at a clamped distance along the route.
    ///
    /// Interpolation is along the shortest great-circle arc, so a segment
    /// crossing the antimeridian does not jump through longitude zero.
    public func point(atDistanceMeters distanceMeters: Double) -> GeoPoint {
        if distanceMeters.isNaN || distanceMeters <= 0.0 {
            return points[0]
        }
        if !distanceMeters.isFinite || distanceMeters >= lengthMeters {
            return points[points.count - 1]
        }

        guard let upperIndex = cumulativeDistances.firstIndex(where: { $0 >= distanceMeters }) else {
            return points[points.count - 1]
        }
        if upperIndex == 0 {
            return points[0]
        }

        let lowerIndex = upperIndex - 1
        let segmentLength = cumulativeDistances[upperIndex] - cumulativeDistances[lowerIndex]
        if segmentLength <= 0.0 {
            return points[upperIndex]
        }
        let fraction = (distanceMeters - cumulativeDistances[lowerIndex]) / segmentLength
        return Self.interpolate(points[lowerIndex], points[upperIndex], fraction: fraction)
    }

    private static func interpolate(_ start: GeoPoint, _ end: GeoPoint, fraction: Double) -> GeoPoint {
        let startVector = vector(for: start)
        let endVector = vector(for: end)
        let dot = GeoPoint.clamp(
            startVector.x * endVector.x
                + startVector.y * endVector.y
                + startVector.z * endVector.z
        )
        let angle = acos(dot)

        if angle < 1e-12 {
            return start
        }

        let sine = sin(angle)
        if abs(sine) < 1e-12 {
            // The exact antipodal case has infinitely many shortest arcs.
            // Choose the deterministic arc represented by the initial bearing.
            return start.moved(
                distanceMeters: GeoPoint.earthRadiusMeters * angle * fraction,
                headingDegrees: initialBearing(from: start, to: end)
            )
        }

        let firstWeight = sin((1.0 - fraction) * angle) / sine
        let secondWeight = sin(fraction * angle) / sine
        return point(from: (
            x: firstWeight * startVector.x + secondWeight * endVector.x,
            y: firstWeight * startVector.y + secondWeight * endVector.y,
            z: firstWeight * startVector.z + secondWeight * endVector.z
        ))
    }

    private static func vector(for point: GeoPoint) -> (x: Double, y: Double, z: Double) {
        let latitude = point.latitude * .pi / 180.0
        let longitude = point.longitude * .pi / 180.0
        let cosLatitude = cos(latitude)
        return (
            x: cosLatitude * cos(longitude),
            y: cosLatitude * sin(longitude),
            z: sin(latitude)
        )
    }

    private static func point(from vector: (x: Double, y: Double, z: Double)) -> GeoPoint {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        let latitude = asin(GeoPoint.clamp(vector.z / length)) * 180.0 / .pi
        let longitude = atan2(vector.y, vector.x) * 180.0 / .pi
        return try! GeoPoint(latitude: latitude, longitude: longitude)
    }

    private static func initialBearing(from start: GeoPoint, to end: GeoPoint) -> Double {
        let latitude1 = start.latitude * .pi / 180.0
        let latitude2 = end.latitude * .pi / 180.0
        let longitudeDelta = GeoPoint.shortestLongitudeDelta(
            (end.longitude - start.longitude) * .pi / 180.0
        )
        let bearing = atan2(
            sin(longitudeDelta) * cos(latitude2),
            cos(latitude1) * sin(latitude2)
                - sin(latitude1) * cos(latitude2) * cos(longitudeDelta)
        )
        return bearing * 180.0 / .pi
    }
}

public struct SavedPlace: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let point: GeoPoint
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        point: GeoPoint,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.point = point
        self.createdAt = createdAt
    }
}

public struct PlaceArchive: Codable, Sendable {
    public var favorites: [SavedPlace]
    public var history: [SavedPlace]

    public init(favorites: [SavedPlace] = [], history: [SavedPlace] = []) {
        self.favorites = favorites
        self.history = history
    }
}
