import Foundation

public enum ContinuedProcessingRegistrationReservation: Equatable, Sendable {
    case reserved
    case alreadyAttempted
    case capacityReached
}

/// Per-process registration resource boundary. It records attempts only; it
/// does not call the SDK or imply that registration succeeded.
@MainActor
public final class ContinuedProcessingRegistrationBook {
    public static let maximumRegistrations = 256

    private var attemptedRequestIDs: Set<UUID> = []

    public init() {}

    public func reserve(_ requestID: UUID) -> ContinuedProcessingRegistrationReservation {
        if attemptedRequestIDs.contains(requestID) { return .alreadyAttempted }
        guard attemptedRequestIDs.count < Self.maximumRegistrations else { return .capacityReached }
        attemptedRequestIDs.insert(requestID)
        return .reserved
    }
}
