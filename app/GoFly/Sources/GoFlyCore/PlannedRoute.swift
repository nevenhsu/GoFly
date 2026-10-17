import Foundation

public protocol RoutePlanning: Sendable {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate]
}

public struct PlannedRoute: Equatable, Sendable {
    public let points: [GeoCoordinate]
    public let cumulativeDistancesMeters: [Double]
    public var totalDistanceMeters: Double { cumulativeDistancesMeters.last! }
    public var start: GeoCoordinate { points[0] }
    public var end: GeoCoordinate { points.last! }
    private static let radius = 6_371_000.0

    public init(legs: [PlannedRoute]) throws {
        guard let first = legs.first, let last = legs.last else { throw RouteExecutionFailure.invalidPath }
        var joined = first.points
        for leg in legs.dropFirst() {
            guard joined.last == leg.start else { throw RouteExecutionFailure.invalidPath }
            joined.append(contentsOf: leg.points.dropFirst())
            guard joined.count <= 10_000 else { throw RouteExecutionFailure.invalidPath }
        }
        try self.init(points: joined, from: first.start, to: last.end)
    }

    public init(points: [GeoCoordinate], from: GeoCoordinate, to: GeoCoordinate) throws {
        guard (2...10_000).contains(points.count) else { throw RouteExecutionFailure.invalidPath }
        var normalized = Self.deduplicated(points)
        // Anchoring a degenerate planner result must not manufacture a straight-line fallback.
        guard normalized.count >= 2, Self.distances(normalized).last! > 0 else { throw RouteExecutionFailure.invalidPath }
        let startSnap = Self.distance(from: normalized[0], to: from)
        let endSnap = Self.distance(from: normalized[normalized.count - 1], to: to)
        guard startSnap.isFinite, endSnap.isFinite, startSnap <= 50, endSnap <= 50 else {
            throw RouteExecutionFailure.invalidPath
        }
        // Preserve every road vertex; only short road-snap links may join the exact requested endpoints.
        if normalized[0] != from { normalized.insert(from, at: 0) }
        if normalized.last != to { normalized.append(to) }
        normalized = Self.deduplicated(normalized)
        guard (2...10_000).contains(normalized.count) else { throw RouteExecutionFailure.invalidPath }
        let distances = Self.distances(normalized)
        guard let total = distances.last, total.isFinite, total > 0 else { throw RouteExecutionFailure.invalidPath }
        self.points = normalized
        cumulativeDistancesMeters = distances
    }
    public func coordinate(at distanceMeters: Double) -> GeoCoordinate? {
        guard distanceMeters.isFinite else { return nil }
        if distanceMeters <= 0 { return start }
        if distanceMeters >= totalDistanceMeters { return end }
        var low = 1, high = points.count - 1
        while low < high {
            let middle = (low + high) / 2
            if cumulativeDistancesMeters[middle] < distanceMeters { low = middle + 1 } else { high = middle }
        }
        let segment = cumulativeDistancesMeters[low] - cumulativeDistancesMeters[low - 1]
        let fraction = (distanceMeters - cumulativeDistancesMeters[low - 1]) / segment
        let a = points[low - 1], b = points[low]
        let angle = segment / Self.radius
        let latA = a.latitude * .pi / 180, lonA = a.longitude * .pi / 180
        let latB = b.latitude * .pi / 180, lonB = b.longitude * .pi / 180
        if abs(sin(angle)) < 1e-12 {
            let delta = (b.longitude - a.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
            let longitude = (a.longitude + delta * fraction + 540).truncatingRemainder(dividingBy: 360) - 180
            return GeoCoordinate(latitude: a.latitude + (b.latitude - a.latitude) * fraction, longitude: longitude)
        }
        let weightA = sin((1 - fraction) * angle) / sin(angle), weightB = sin(fraction * angle) / sin(angle)
        let x = weightA * cos(latA) * cos(lonA) + weightB * cos(latB) * cos(lonB)
        let y = weightA * cos(latA) * sin(lonA) + weightB * cos(latB) * sin(lonB)
        let z = weightA * sin(latA) + weightB * sin(latB)
        return GeoCoordinate(latitude: atan2(z, hypot(x, y)) * 180 / .pi, longitude: atan2(y, x) * 180 / .pi)
    }
    private static func deduplicated(_ points: [GeoCoordinate]) -> [GeoCoordinate] {
        points.reduce(into: []) { result, point in if result.last != point { result.append(point) } }
    }
    private static func distances(_ points: [GeoCoordinate]) -> [Double] {
        var result = [0.0]
        for index in 1..<points.count {
            result.append(result.last! + distance(from: points[index - 1], to: points[index]))
        }
        return result
    }
    private static func distance(from a: GeoCoordinate, to b: GeoCoordinate) -> Double {
        if a.latitude == b.latitude && abs(a.latitude) == 90 { return 0 }
        let latitude = (b.latitude - a.latitude) * .pi / 180
        var longitudeDelta = b.longitude - a.longitude
        if longitudeDelta > 180 { longitudeDelta -= 360 }
        if longitudeDelta < -180 { longitudeDelta += 360 }
        let longitude = longitudeDelta * .pi / 180
        let haversine = pow(sin(latitude / 2), 2) + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * pow(sin(longitude / 2), 2)
        return radius * 2 * asin(sqrt(min(1, max(0, haversine))))
    }
}
