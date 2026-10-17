import Foundation

public struct WanderTarget: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let place: MapPlace
    public var coordinate: GeoCoordinate { place.coordinate }
    public init(id: UUID = UUID(), place: MapPlace) { self.id = id; self.place = place }
}

public enum WanderSelectionFailure: String, Error, Sendable {
    case noCandidate = "joystick.error.noCandidate"
    public var localizationKey: String { rawValue }
}
public enum WanderSuspensionReason: String, Sendable { case targetUnavailable, sceneInactive, connectionUnavailable }
