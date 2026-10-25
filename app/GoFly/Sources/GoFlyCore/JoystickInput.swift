import Foundation

public struct JoystickInput: Equatable, Sendable {
    public let bearingDegrees: Double
    public let strength: Double

    public init?(bearingDegrees: Double, strength: Double) {
        guard bearingDegrees.isFinite, strength.isFinite else { return nil }
        self.bearingDegrees = Self.normalizedBearing(bearingDegrees)
        self.strength = min(1, max(0, strength))
    }

    /// - Parameter seconds: the cadence this step covers.
    public func displacement(speed: RouteSpeed, seconds: Double = MovementCadence.manualSeconds) -> JoystickDisplacement? {
        guard strength > 0 else { return nil }
        return JoystickDisplacement(bearingDegrees: bearingDegrees,
            distanceMeters: speed.metersPerSecond * strength * seconds)
    }

    /// Screen coordinates use +x right and +y down. Camera heading rotates screen-up into world north.
    public static func fromScreenVector(x: Double, y: Double, radius: Double, cameraHeadingDegrees: Double) -> JoystickInput? {
        guard x.isFinite, y.isFinite, radius.isFinite, radius > 0, cameraHeadingDegrees.isFinite else { return nil }
        let strength = max(abs(x), abs(y)) >= radius ? 1 : min(1, hypot(x / radius, y / radius))
        let screenBearing = x == 0 && y == 0 ? 0 : atan2(x, -y) * 180 / .pi
        return JoystickInput(bearingDegrees: screenBearing + normalizedBearing(cameraHeadingDegrees), strength: strength)
    }

    static func normalizedBearing(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        let normalized = remainder < 0 ? remainder + 360 : remainder
        return normalized == 0 || normalized == 360 ? 0 : normalized
    }
}
