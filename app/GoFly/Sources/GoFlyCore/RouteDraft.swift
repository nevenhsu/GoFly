import Foundation

public struct RouteNodeID: Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}
public enum RouteNodeValue: Equatable, Sendable { case current, place(MapPlace) }
public struct RouteNode: Identifiable, Equatable, Sendable {
    public let id: RouteNodeID
    public let value: RouteNodeValue?
}
public struct RouteSpeed: Equatable, Sendable {
    public let kilometersPerHour: Int
    public var metersPerSecond: Double { Double(kilometersPerHour) / 3.6 }
    public static let standard = RouteSpeed(kilometersPerHour: 20)!
    public init?(kilometersPerHour: Int) {
        guard (2...100).contains(kilometersPerHour) else { return nil }
        self.kilometersPerHour = kilometersPerHour
    }
}
public struct RouteDraft: Equatable, Sendable {
    public let nodes: [RouteNode]
    public let speed: RouteSpeed
    public var start: RouteNode { nodes[0] }
    public var destination: RouteNode { nodes[1] }
    public init(start: RouteNodeValue? = .current, destination: RouteNodeValue? = nil, speed: RouteSpeed = .standard) {
        nodes = [RouteNode(id: RouteNodeID(), value: start), RouteNode(id: RouteNodeID(), value: destination)]
        self.speed = speed
    }
    private init(nodes: [RouteNode], speed: RouteSpeed) { self.nodes = nodes; self.speed = speed }
    func replacing(nodeID: RouteNodeID, value: RouteNodeValue) -> RouteDraft? {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }), index == 0 || value != .current else { return nil }
        var nodes = nodes
        nodes[index] = RouteNode(id: nodeID, value: value)
        return RouteDraft(nodes: nodes, speed: speed)
    }
    func replacing(speed: RouteSpeed) -> RouteDraft { RouteDraft(nodes: nodes, speed: speed) }
}

public enum RouteExecutionPhase: String, Equatable, Sendable {
    case editing, planning, preparing, running, pausing, paused, cancelling, interrupted, unknown
}
public enum RouteExecutionFailure: Error, Equatable, Sendable {
    case missingStart, missingDestination, currentLocationUnavailable, planningFailed, invalidPath
    case device(DeviceServiceFailure)
    public var localizationKey: String {
        switch self {
        case .missingStart: "route.error.missingStart"
        case .missingDestination: "route.error.missingDestination"
        case .currentLocationUnavailable: "route.error.currentLocationUnavailable"
        case .planningFailed: "route.error.planningFailed"
        case .invalidPath: "route.error.invalidPath"
        case .device(let failure): failure.rawValue
        }
    }
}
public struct RouteExecutionIntent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let lease: MovementTaskLease
    public let draft: RouteDraft
    public let route: PlannedRoute
    public let speed: RouteSpeed
    public init(id: UUID = UUID(), lease: MovementTaskLease = MovementTaskLease(), draft: RouteDraft, route: PlannedRoute) {
        self.id = id; self.lease = lease; self.draft = draft; self.route = route; speed = draft.speed
    }
}
public struct RouteProgress: Equatable, Sendable {
    public let committedDistanceMeters: Double
    public let totalDistanceMeters: Double
    public let activeElapsed: Duration
    public let estimatedRemaining: Duration
    public var fraction: Double { committedDistanceMeters / totalDistanceMeters }
}
public struct RouteCompletion: Equatable, Sendable {
    public let executionID: UUID
    public let coordinate: GeoCoordinate
}
