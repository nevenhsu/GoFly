import Foundation

public final class ContinuedProcessingGrant: @unchecked Sendable {
    private let lock = NSLock()
    public let requestID: UUID
    public let movementID: UUID
    public let lease: MovementTaskLease
    private var open = true

    public init(requestID: UUID, movementID: UUID, lease: MovementTaskLease) {
        self.requestID = requestID
        self.movementID = movementID
        self.lease = lease
    }

    public var isValid: Bool {
        lock.withLock { open }
    }

    public func revoke() {
        lock.withLock { open = false }
    }

    /// Claims the grant for a successful framework completion while atomically closing it.
    /// This is intentionally internal: callers use ContinuedProcessingTaskCompletion.claim.
    func closeIfValid() -> Bool {
        lock.withLock {
            guard open else { return false }
            open = false
            return true
        }
    }
}

public final class ContinuedProcessingTaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let grant: ContinuedProcessingGrant?
    private var sealedOutcome: ContinuedProcessingCompletionOutcome?

    public init(grant: ContinuedProcessingGrant?) {
        self.grant = grant
    }

    public func claim(_ proposed: ContinuedProcessingCompletionOutcome) -> ContinuedProcessingCompletionClaim {
        lock.lock()
        defer { lock.unlock() }
        if let sealedOutcome {
            return ContinuedProcessingCompletionClaim(outcome: sealedOutcome, isFirst: false)
        }

        let effective: ContinuedProcessingCompletionOutcome
        if proposed == .success {
            effective = (grant?.closeIfValid() == true) ? .success : .invalidated
        } else {
            grant?.revoke()
            effective = proposed
        }
        sealedOutcome = effective
        return ContinuedProcessingCompletionClaim(outcome: effective, isFirst: true)
    }
}
