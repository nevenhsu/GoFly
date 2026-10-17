import Foundation

/// The map mode that was visible when a recovery checkpoint was captured.
public enum SessionMapMode: String, CaseIterable, Codable, Sendable {
    case teleport
    case route
    case joystick
}

/// A displayed position is a UI cache. Its source records how it was obtained,
/// but it does not prove a live device position or a movement task.
public struct SessionDisplayPosition: Equatable, Sendable {
    public let coordinate: GeoCoordinate
    public let source: PositionSource

    public init(coordinate: GeoCoordinate, source: PositionSource) {
        self.coordinate = coordinate
        self.source = source
    }
}

/// Historical state only. Loading this value never recreates a native owner.
public enum SessionSavedTaskState: String, Codable, Sendable {
    case running
    case paused
    case uncertain
}

public struct SessionRouteRecovery: Equatable, Sendable {
    public let draft: RouteDraft
    public let route: PlannedRoute
    public let progress: RouteProgress
    public let roundTripEnabled: Bool
    public let usesPositionAxis: Bool
    public let heading: RouteHeading
    public let state: SessionSavedTaskState

    public init(draft: RouteDraft, route: PlannedRoute, progress: RouteProgress,
                roundTripEnabled: Bool, usesPositionAxis: Bool,
                heading: RouteHeading, state: SessionSavedTaskState) {
        self.draft = draft
        self.route = route
        self.progress = progress
        self.roundTripEnabled = roundTripEnabled
        self.usesPositionAxis = usesPositionAxis
        self.heading = heading
        self.state = state
    }
}

public struct SessionWanderRecovery: Equatable, Sendable {
    public let target: WanderTarget
    public let speed: RouteSpeed
    public let history: [GeoCoordinate]
    public let lastAcknowledgedCoordinate: GeoCoordinate
    public let lastAcknowledgedBearingDegrees: Double?
    public let state: SessionSavedTaskState

    public init(target: WanderTarget, speed: RouteSpeed, history: [GeoCoordinate],
                lastAcknowledgedCoordinate: GeoCoordinate,
                lastAcknowledgedBearingDegrees: Double?,
                state: SessionSavedTaskState) {
        self.target = target
        self.speed = speed
        self.history = history
        self.lastAcknowledgedCoordinate = lastAcknowledgedCoordinate
        self.lastAcknowledgedBearingDegrees = lastAcknowledgedBearingDegrees
        self.state = state
    }
}

/// Manual movement intentionally has no associated input, direction, lease, or handle.
public enum SessionActiveRecovery: Equatable, Sendable {
    case route(SessionRouteRecovery)
    case wander(SessionWanderRecovery)
    case manual
}

public enum SessionUncertaintySource: String, Codable, Sendable {
    case point
    case route
    case joystick
    case wander
    case gpsRecovery
    case unverifiedPreviousMovement
}

public struct SessionMovementUncertainty: Equatable, Sendable {
    public let source: SessionUncertaintySource
    /// This is the requested destination, never a claimed current position.
    public let requestedPlace: MapPlace?

    public init(source: SessionUncertaintySource, requestedPlace: MapPlace? = nil) {
        self.source = source
        self.requestedPlace = requestedPlace
    }
}

public struct SessionRecoverySnapshot: Equatable, Sendable {
    public let mode: SessionMapMode
    public let draft: RouteDraft
    public let roundTripEnabled: Bool
    public let joystickSpeed: RouteSpeed
    public let position: SessionDisplayPosition?
    public let activeMovement: SessionActiveRecovery?
    public let uncertainty: SessionMovementUncertainty?

    public init(mode: SessionMapMode = .teleport,
                draft: RouteDraft = RouteDraft(),
                roundTripEnabled: Bool = false,
                joystickSpeed: RouteSpeed = .standard,
                position: SessionDisplayPosition? = nil,
                activeMovement: SessionActiveRecovery? = nil,
                uncertainty: SessionMovementUncertainty? = nil) {
        self.mode = mode
        self.draft = draft
        self.roundTripEnabled = roundTripEnabled
        self.joystickSpeed = joystickSpeed
        self.position = position
        self.activeMovement = activeMovement
        self.uncertainty = uncertainty
    }
}

public enum SessionRecoveryFailure: String, Error, Equatable, Sendable {
    case unavailable = "recovery.error.unavailable"
    case unsafeFile = "recovery.error.unsafeFile"
    case writeFailed = "recovery.error.writeFailed"
    case corruptArchive = "recovery.error.corruptArchive"
    case unsupportedSchema = "recovery.error.unsupportedSchema"
    case limitExceeded = "recovery.error.limitExceeded"
    case invalidSnapshot = "recovery.error.invalidSnapshot"
    case revisionExhausted = "recovery.error.revisionExhausted"

    public var localizationKey: String { rawValue }
}

public enum SessionRecoveryLoadState: Equatable, Sendable {
    case ready
    case blocked(SessionRecoveryFailure)
}
