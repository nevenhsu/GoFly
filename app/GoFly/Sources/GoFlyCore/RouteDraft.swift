import Foundation

public struct RouteNodeID: Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}
public enum RouteNodeValue: Equatable, Sendable { case current, place(MapPlace) }
public enum RouteNodeRole: Equatable, Sendable { case start, waypoint(Int), destination }
public struct RouteNode: Identifiable, Equatable, Sendable {
    public let id: RouteNodeID
    public let value: RouteNodeValue
    public init(id: RouteNodeID = RouteNodeID(), value: RouteNodeValue) { self.id = id; self.value = value }
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
    public static let maximumNodeCount = 27
    public let nodes: [RouteNode]
    public let speed: RouteSpeed
    public var start: RouteNode? { nodes.first }
    public var destination: RouteNode? { nodes.count >= 2 ? nodes.last : nil }
    public init(speed: RouteSpeed = .standard) {
        nodes = [RouteNode(value: .current)]; self.speed = speed
    }
    public init?(start: RouteNodeValue? = .current, destination: RouteNodeValue?, speed: RouteSpeed = .standard) {
        self.init(values: [start, destination].compactMap { $0 }, speed: speed)
    }
    public init?(values: [RouteNodeValue], speed: RouteSpeed = .standard) {
        guard values.count <= Self.maximumNodeCount, values.filter({ $0 == .current }).count <= 1 else { return nil }
        nodes = values.map { RouteNode(value: $0) }; self.speed = speed
    }
    private init(nodes: [RouteNode], speed: RouteSpeed) { self.nodes = nodes; self.speed = speed }
    public func role(of id: RouteNodeID) -> RouteNodeRole? {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return nil }
        if index == 0 { return .start }
        return index == nodes.count - 1 ? .destination : .waypoint(index)
    }
    func replacing(nodeID: RouteNodeID, value: RouteNodeValue) -> RouteDraft? {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }),
              value != .current || !nodes.contains(where: { $0.id != nodeID && $0.value == .current }) else { return nil }
        var nodes = nodes
        nodes[index] = RouteNode(id: nodeID, value: value)
        return RouteDraft(nodes: nodes, speed: speed)
    }
    func inserting(nodeID: RouteNodeID, value: RouteNodeValue) -> RouteDraft? {
        guard nodes.count < Self.maximumNodeCount, !nodes.contains(where: { $0.id == nodeID }),
              value != .current || !nodes.contains(where: { $0.value == .current }) else { return nil }
        var nodes = nodes
        nodes.insert(RouteNode(id: nodeID, value: value), at: nodes.count < 2 ? nodes.count : nodes.count - 1)
        return RouteDraft(nodes: nodes, speed: speed)
    }
    func removing(nodeID: RouteNodeID) -> RouteDraft? {
        guard nodes.contains(where: { $0.id == nodeID }) else { return nil }
        return RouteDraft(nodes: nodes.filter { $0.id != nodeID }, speed: speed)
    }
    func moving(nodeID: RouteNodeID, toIndex: Int) -> RouteDraft? {
        guard nodes.indices.contains(toIndex), let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return nil }
        var nodes = nodes
        let node = nodes.remove(at: index)
        nodes.insert(node, at: toIndex)
        return RouteDraft(nodes: nodes, speed: speed)
    }
    func resolvingCurrent(to coordinate: GeoCoordinate?) -> RouteDraft? {
        var resolved: [RouteNode] = []
        for node in nodes {
            if node.value == .current {
                guard let coordinate else { return nil }
                resolved.append(RouteNode(id: node.id, value: .place(MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate))))
            } else { resolved.append(node) }
        }
        return RouteDraft(nodes: resolved, speed: speed)
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
