import Foundation

public struct WanderTarget: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let place: MapPlace
    public var coordinate: GeoCoordinate { place.coordinate }
    public init(id: UUID = UUID(), place: MapPlace) { self.id = id; self.place = place }
}

public enum WanderSelectionFailure: String, Error, Sendable {
    case noCandidate = "joystick.error.noCandidate"
    case planningFailed = "wander.error.planningFailed"
    public var localizationKey: String { rawValue }
}
public enum WanderSuspensionReason: String, Sendable {
    case targetUnavailable, sceneInactive, connectionUnavailable, backgroundUnavailable
}

/// One-shot gate for a Start Wander tap received while its location setup is
/// already in flight. Only the matching location ACK consumes the request.
public struct WanderStartRequestGate: Equatable, Sendable {
    public private(set) var originIntentID: UUID?
    public init() {}
    public mutating func waitForOriginAcknowledgement(_ intentID: UUID) {
        originIntentID = intentID
    }
    public mutating func consumeAcknowledgement(for intentID: UUID) -> Bool {
        guard originIntentID == intentID else { return false }
        originIntentID = nil
        return true
    }
    public mutating func consumeFailure(for intentID: UUID) -> Bool {
        consumeAcknowledgement(for: intentID)
    }
    public mutating func cancel() { originIntentID = nil }
}
