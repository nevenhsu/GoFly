import Foundation

public struct JoystickDisplacement: Equatable, Sendable {
    public static let maximumDistanceMeters = 50.0 / 3.0
    public let bearingDegrees: Double
    public let distanceMeters: Double

    public init?(bearingDegrees: Double, distanceMeters: Double) {
        guard bearingDegrees.isFinite, distanceMeters.isFinite, distanceMeters > 0,
              distanceMeters <= Self.maximumDistanceMeters else { return nil }
        self.bearingDegrees = JoystickInput.normalizedBearing(bearingDegrees)
        self.distanceMeters = distanceMeters
    }
}
