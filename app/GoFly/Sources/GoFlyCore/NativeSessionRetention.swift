import Foundation

/// What the device adapter should do with the native session it already owns
/// after one point-delivery attempt or one preparation failure.
///
/// The adapter owns every handle; this policy only states the rule so the
/// decision can be tested without FFI. Stage A deliberately keeps the current
/// behaviour (`reuse`) and only makes the decision explicit; the movement-stop
/// investigation (H2) expects a failed point write to force a rebuild.
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
        case .acknowledged, .unconfirmed:
            return .reuse
        case .notSent:
            // A point that never crossed the dispatch gate proves nothing about
            // the handles, but an unowned session is closed as before.
            return sessionWasOwned ? .reuse : .rebuild
        }
    }

    /// A failed `prepare()` inside a tick means the session could not complete
    /// identity/support verification; today it is kept and retried as-is.
    public func retention(afterPreparationFailure failure: DeviceServiceFailure,
                          sessionWasOwned: Bool) -> NativeSessionRetention {
        sessionWasOwned ? .reuse : .rebuild
    }
}
