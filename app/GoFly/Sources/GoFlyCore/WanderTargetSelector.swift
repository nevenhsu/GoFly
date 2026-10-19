import Foundation

public enum WanderTargetSelector {
    /// Picks one random direction on the ten-minute ring. The caller only needs
    /// a fresh reachable target; recent-target exclusion is deliberately gone.
    public static func select(origin: GeoCoordinate, speed: RouteSpeed,
                              bearingSamples: [Double]) -> WanderTarget? {
        guard let bearing = bearingSamples.first(where: { $0.isFinite }) else { return nil }
        let coordinate = JoystickGeodesy.destination(from: origin,
            bearingDegrees: JoystickInput.normalizedBearing(bearing),
            distanceMeters: speed.metersPerSecond * 600)
        guard JoystickGeodesy.distanceMeters(from: origin, to: coordinate) > 1 else { return nil }
        return WanderTarget(place: MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate))
    }
}
