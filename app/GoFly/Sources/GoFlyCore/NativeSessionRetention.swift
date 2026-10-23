import Foundation

/// What the device adapter should do with the native session it already owns
/// after one point-delivery attempt or one preparation failure.
///
/// The adapter owns every handle; this policy only states the rule so the
/// decision can be tested without FFI. A known transport or service failure
/// invalidates an owned session so a safe retry can establish a fresh RSD
/// connection.
public enum NativeSessionRetention: Equatable, Sendable {
    /// Keep the owned session and use it for the next point.
    case reuse
    /// Close the owned session now; the next point must create a fresh one.
    case rebuild
}

public struct NativeSessionRetentionPolicy: Sendable {
    public init() {}

    /// - Parameters:
    ///   - outcome: the result the adapter just reported to its caller.
    ///   - sessionWasOwned: whether this attempt reused an already-owned session.
    public func retention(after outcome: PointDeliveryOutcome,
                          sessionWasOwned: Bool) -> NativeSessionRetention {
        switch outcome {
        case .acknowledged:
            return .reuse
        case .unconfirmed(let failure):
            return shouldRecreateSession(after: failure) ? .rebuild : .reuse
        case .notSent(let failure):
            return shouldRebuild(after: failure, sessionWasOwned: sessionWasOwned)
        }
    }

    /// A failed preparation has not dispatched a location write, so replacing
    /// a session known to have lost its transport is safe before retrying.
    public func retention(afterPreparationFailure failure: DeviceServiceFailure,
                          sessionWasOwned: Bool) -> NativeSessionRetention {
        shouldRebuild(after: failure, sessionWasOwned: sessionWasOwned)
    }

    /// Only these failures are safe to retry before a dispatch gate is claimed.
    public func shouldRetryBeforeDispatch(after failure: DeviceServiceFailure) -> Bool {
        shouldRecreateSession(after: failure)
    }

    /// Only a transient adapter result after a real dispatch may enter the
    /// one-shot same-coordinate recovery path.
    public func shouldRetryAfterDispatch(after failure: DeviceServiceFailure) -> Bool {
        shouldRecreateSession(after: failure)
    }

    public func sessionHasExpired(lastActivityNanoseconds: UInt64?, nowNanoseconds: UInt64,
                                  maximumIdleNanoseconds: UInt64) -> Bool {
        guard maximumIdleNanoseconds > 0,
              let lastActivityNanoseconds,
              nowNanoseconds >= lastActivityNanoseconds else { return false }
        return nowNanoseconds - lastActivityNanoseconds >= maximumIdleNanoseconds
    }

    private func shouldRecreateSession(after failure: DeviceServiceFailure) -> Bool {
        switch failure {
        case .serviceUnavailable, .tunnelUnavailable, .operationTimedOut:
            return true
        case .pairingRequired, .identityMismatch, .developerModeRequired,
             .devicePreparationRequired, .deviceRequired, .storageUnavailable,
             .operationCancelled:
            return false
        }
    }

    private func shouldRebuild(after failure: DeviceServiceFailure,
                               sessionWasOwned: Bool) -> NativeSessionRetention {
        guard sessionWasOwned else { return .rebuild }
        return shouldRecreateSession(after: failure) ? .rebuild : .reuse
    }
}
