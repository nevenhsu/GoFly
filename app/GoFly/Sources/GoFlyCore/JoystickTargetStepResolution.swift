import Foundation

/// Computed geometry for a target step; it is not a device acknowledgement.
public struct JoystickTargetStepResolution: Equatable, Sendable {
    public let coordinate: GeoCoordinate
    public let bearingDegrees: Double?
    public let arrived: Bool
}
