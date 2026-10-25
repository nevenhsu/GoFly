import Foundation

/// One manual step. Its length is speed × the time since the previous step;
/// there is no separate cap (2026-10-25), the speed setting bounds it.
public struct JoystickDisplacement: Equatable, Sendable {
    public let bearingDegrees: Double
    public let distanceMeters: Double

    public init?(bearingDegrees: Double, distanceMeters: Double) {
        guard bearingDegrees.isFinite, distanceMeters.isFinite, distanceMeters > 0 else { return nil }
        self.bearingDegrees = JoystickInput.normalizedBearing(bearingDegrees)
        self.distanceMeters = distanceMeters
    }
}
