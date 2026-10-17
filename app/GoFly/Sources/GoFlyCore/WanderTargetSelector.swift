import Foundation

public enum WanderTargetSelector {
    public static func select(origin: GeoCoordinate, speed: RouteSpeed, currentTarget: WanderTarget?,
                              history: [GeoCoordinate], bearingSamples: [Double]) -> WanderTarget? {
        for bearing in bearingSamples.prefix(32) where bearing.isFinite {
            let coordinate = JoystickGeodesy.destination(from: origin, bearingDegrees: JoystickInput.normalizedBearing(bearing),
                distanceMeters: speed.metersPerSecond * 600)
            guard JoystickGeodesy.distanceMeters(from: origin, to: coordinate) > 1,
                  currentTarget.map({ JoystickGeodesy.distanceMeters(from: $0.coordinate, to: coordinate) > 1 }) ?? true,
                  !history.suffix(100).contains(where: { JoystickGeodesy.distanceMeters(from: $0, to: coordinate) <= 1 }) else { continue }
            return WanderTarget(place: MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate))
        }
        return nil
    }
}
