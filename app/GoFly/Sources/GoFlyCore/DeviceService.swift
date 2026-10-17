import Foundation

/// The device boundary never receives a coordinate during service startup.
public protocol DeviceService: Sendable {
    func prepare() async throws
    func clearLocation() async throws
    func resetClientConnection() async throws
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome
}

public enum DeviceServiceFailure: String, Error, Sendable, Equatable {
    case pairingRequired = "error.pairingRequired"
    case identityMismatch = "error.identityMismatch"
    case developerModeRequired = "error.developerModeRequired"
    case devicePreparationRequired = "error.devicePreparationRequired"
    case serviceUnavailable = "error.serviceUnavailable"
    case tunnelUnavailable = "error.tunnelUnavailable"
    case operationTimedOut = "error.operationTimedOut"
    case deviceRequired = "error.deviceRequired"
    case storageUnavailable = "error.storageUnavailable"
    case operationCancelled = "error.operationCancelled"
}

public enum ServicePhase: String, Sendable {
    case stopped, preparing, ready, stopping, restoring, resetting, repairRequired
}

public enum ClearState: Sendable {
    case unknown, pending, confirmed
}

public struct RealLocationObservation: Equatable, Sendable {
    public let coordinate: GeoCoordinate
    public var latitude: Double { coordinate.latitude }
    public var longitude: Double { coordinate.longitude }
    public let horizontalAccuracy: Double
    public let observedAt: Date

    public init?(
        latitude: Double, longitude: Double, horizontalAccuracy: Double,
        observedAt: Date, isSoftwareSimulated: Bool = false
    ) {
        guard !isSoftwareSimulated, let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude),
              horizontalAccuracy.isFinite, horizontalAccuracy >= 0 else { return nil }
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.observedAt = observedAt
    }
}
