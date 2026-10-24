import Combine
import Foundation

public struct JoystickMovementIntent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let lease: MovementTaskLease
    public let fixedPosition: GeoCoordinate?
    public init(id: UUID = UUID(), lease: MovementTaskLease = MovementTaskLease(),
                fixedPosition: GeoCoordinate? = nil) {
        self.id = id; self.lease = lease; self.fixedPosition = fixedPosition
    }
}

/// Separate from the immutable movement identity; resume creates a new generation.
public struct JoystickInputRevision: Equatable, Sendable {
    public let generation: UUID
    public let revision: UInt64
    public init(generation: UUID = UUID(), revision: UInt64 = 0) {
        self.generation = generation; self.revision = revision
    }
}
public enum JoystickFailure: Equatable, Sendable {
    case originUnavailable
    case device(DeviceServiceFailure)
    public var localizationKey: String {
        switch self {
        case .originUnavailable: "joystick.error.originUnavailable"
        case .device(let failure): failure.rawValue
        }
    }
}
public enum JoystickPreparationOutcome: Equatable, Sendable { case prepared, cancelled }
public enum JoystickStepOutcome: Equatable, Sendable {
    case acknowledged(GeoCoordinate)
    case notSent(JoystickFailure)
    case unconfirmed(DeviceServiceFailure)
    case inputCancelled
    case cancelled
}
public enum JoystickReleaseDisposition: Equatable, Sendable { case endGesture, pause }
public enum JoystickIdleSettlement: Equatable, Sendable {
    case settled
    case requiresStop(DeviceServiceFailure)
}
public enum JoystickCommandEvent: Sendable {
    case movementBoundary(MovementTaskLease?)
    case ended(UUID)
    case interrupted(UUID, JoystickFailure)
    case unknown(UUID, DeviceServiceFailure)
    case availabilityChanged
}

@MainActor
public protocol JoystickCommanding: AnyObject {
    func cancelConnectionRecovery()
    var canBeginJoystick: Bool { get }
    var currentJoystickOrigin: GeoCoordinate? { get }
    var movementAdmissionRevision: UInt64 { get }
    var joystickEvents: AnyPublisher<JoystickCommandEvent, Never> { get }
    func beginJoystick(_ intent: JoystickMovementIntent, expectedMovementAdmissionRevision: UInt64) async -> JoystickPreparationOutcome
    func joystickInputRevision(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision?
    func reviseJoystickInput(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision?
    func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64,
                          expectedInputRevision: JoystickInputRevision, displacement: JoystickDisplacement) async -> JoystickStepOutcome
    func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64,
                          expectedInputRevision: JoystickInputRevision, recipe: JoystickStepRecipe) async -> JoystickRecipeStepOutcome
    @discardableResult func releaseJoystick(executionID: UUID, lease: MovementTaskLease, disposition: JoystickReleaseDisposition) -> Bool
    func resumeJoystick(executionID: UUID, lease: MovementTaskLease) -> Bool
    func resumeJoystickStream(executionID: UUID, lease: MovementTaskLease) -> Bool
    func waitForJoystickIdle(executionID: UUID, lease: MovementTaskLease) async -> JoystickIdleSettlement
}

public extension JoystickCommanding {
    func cancelConnectionRecovery() {}
}
