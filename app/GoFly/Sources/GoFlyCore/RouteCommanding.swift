import Combine
import Foundation

public enum RouteCommandOutcome: Equatable, Sendable {
    case acknowledged
    case notSent(DeviceServiceFailure)
    case unconfirmed(DeviceServiceFailure)
    case cancelled
}

public enum RouteIdleSettlement: Equatable, Sendable {
    case settled
    case requiresStop(DeviceServiceFailure)
}

public enum RouteCommandEvent: Sendable {
    case ended(UUID)
    case unknown(UUID, DeviceServiceFailure)
    case interrupted(UUID, DeviceServiceFailure)
    case availabilityChanged
}

@MainActor
public protocol RouteCommanding: AnyObject {
    var canBeginRoute: Bool { get }
    var routeEvents: AnyPublisher<RouteCommandEvent, Never> { get }
    var currentRouteOrigin: GeoCoordinate? { get }
    var routeAdmissionRevision: UInt64 { get }
    func beginRoute(_ intent: RouteExecutionIntent, expectedAdmissionRevision: UInt64) async -> RouteCommandOutcome
    func sendRoutePoint(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, coordinate: GeoCoordinate) async -> RouteCommandOutcome
    func pauseRoute(executionID: UUID, lease: MovementTaskLease) -> Bool
    func resumeRoute(executionID: UUID, lease: MovementTaskLease) -> Bool
    func endRoute(executionID: UUID, lease: MovementTaskLease)
    func waitForRouteIdle(executionID: UUID, lease: MovementTaskLease) async -> RouteIdleSettlement
}
