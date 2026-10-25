import Foundation

public struct JoystickTargetStep: Equatable, Sendable {
    public let targetID: UUID
    public let coordinate: GeoCoordinate
    public let maximumDistanceMeters: Double

    public init?(targetID: UUID, coordinate: GeoCoordinate, maximumDistanceMeters: Double) {
        guard maximumDistanceMeters.isFinite, maximumDistanceMeters > 0 else { return nil }
        self.targetID = targetID
        self.coordinate = coordinate
        self.maximumDistanceMeters = maximumDistanceMeters
    }
}

public enum JoystickStepRecipe: Equatable, Sendable {
    case manual(JoystickDisplacement)
    case target(JoystickTargetStep)
    /// May only refresh the exact coordinate of an explicitly admitted hold.
    case fixedPosition(GeoCoordinate)
}

public struct JoystickStepReceipt: Equatable, Sendable {
    public let actualCoordinate: GeoCoordinate
    public let actualBearingDegrees: Double?
    public let targetID: UUID?
    public let arrived: Bool

    public init(actualCoordinate: GeoCoordinate, actualBearingDegrees: Double?, targetID: UUID?, arrived: Bool) {
        self.actualCoordinate = actualCoordinate
        self.actualBearingDegrees = actualBearingDegrees
        self.targetID = targetID
        self.arrived = arrived
    }
}

public enum JoystickRecipeStepOutcome: Equatable, Sendable {
    case acknowledged(JoystickStepReceipt)
    case notSent(JoystickFailure)
    case unconfirmed(DeviceServiceFailure)
    case inputCancelled
    case cancelled
}
