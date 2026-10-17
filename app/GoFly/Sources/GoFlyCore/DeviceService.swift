import Foundation

/// The device boundary never receives a coordinate during service startup.
public protocol DeviceService: Sendable {
    func prepare() async throws
    func clearLocation() async throws
    func resetClientConnection() async throws
}

public enum DeviceServiceFailure: String, Error, Sendable, Equatable {
    case pairingRequired = "error.pairingRequired"
    case identityMismatch = "error.identityMismatch"
    case devicePreparationRequired = "error.devicePreparationRequired"
    case serviceUnavailable = "error.serviceUnavailable"
    case tunnelUnavailable = "error.tunnelUnavailable"
    case operationTimedOut = "error.operationTimedOut"
    case deviceRequired = "error.deviceRequired"
    case storageUnavailable = "error.storageUnavailable"
}

public enum ServicePhase: String, Sendable {
    case stopped, preparing, ready, stopping, restoring, resetting, repairRequired
}

public enum ClearState: Sendable {
    case unknown, pending, confirmed
}

public struct RealLocationObservation: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double
    public let observedAt: Date

    public init?(
        latitude: Double, longitude: Double, horizontalAccuracy: Double,
        observedAt: Date, isSoftwareSimulated: Bool = false
    ) {
        guard !isSoftwareSimulated, latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              horizontalAccuracy.isFinite, horizontalAccuracy >= 0 else { return nil }
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.observedAt = observedAt
    }
}
