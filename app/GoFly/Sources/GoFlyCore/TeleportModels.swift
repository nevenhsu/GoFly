import Foundation

public enum PlaceIdentity: Hashable, Sendable {
    case mapKit(String)
    case coordinate(GeoCoordinate)
}

public struct MapPlace: Identifiable, Equatable, Sendable {
    public let id: PlaceIdentity
    public let title: String
    public let coordinate: GeoCoordinate
    public let address: String?

    public init(id: PlaceIdentity, title: String, coordinate: GeoCoordinate, address: String? = nil) {
        self.id = id
        let address = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.address = address?.isEmpty == false ? address : nil
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (self.address ?? coordinate.displayText) : title
        self.coordinate = coordinate
    }
}

public struct TeleportCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let place: MapPlace

    public init(id: UUID = UUID(), place: MapPlace) {
        self.id = id
        self.place = place
    }
}

public struct PointMoveIntent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let candidate: TeleportCandidate

    public init(id: UUID = UUID(), candidate: TeleportCandidate) {
        self.id = id
        self.candidate = candidate
    }
}

/// Acknowledged means a validated protocol reply, not observation by recipient apps.
public enum PointDeliveryOutcome: Equatable, Sendable {
    case notSent(DeviceServiceFailure)
    case acknowledged
    case unconfirmed(DeviceServiceFailure)
}

public enum PointMoveState: Equatable, Sendable {
    case idle
    case preparing(PointMoveIntent)
    case sending(PointMoveIntent)
    case acknowledged(PointMoveIntent)
    case notSent(PointMoveIntent, DeviceServiceFailure)
    case unconfirmed(PointMoveIntent, DeviceServiceFailure)
}

public enum PositionSource: Equatable, Sendable { case gps, simulation }
public enum PositionFreshness: Equatable, Sendable { case fresh, waiting }

/// A display-only projection. Waiting coordinates are never a route origin or GPS/clear proof.
public struct PositionMarker: Equatable, Sendable {
    public let coordinate: GeoCoordinate
    public let source: PositionSource
    public let freshness: PositionFreshness
}
