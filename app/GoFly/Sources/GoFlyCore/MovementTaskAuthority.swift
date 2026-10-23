import Foundation

public struct MovementTaskLease: Equatable, Sendable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

public enum MovementTaskRunState: Equatable, Sendable { case running, paused }
public enum MovementTaskHealth: Equatable, Sendable {
    case confirmedHealthy
    case interrupted(DeviceServiceFailure)
    case unknown
}

/// An immutable authority version. Health/run-state changes invalidate a captured handoff.
public struct MovementAuthoritySnapshot: Equatable, Sendable {
    public let lease: MovementTaskLease?
    public let runState: MovementTaskRunState?
    public let health: MovementTaskHealth?
    fileprivate let revision: UInt64
}

/// Synchronous ownership checks shared by the native dispatch gate and future schedulers.
/// This type never calls a gate or an arbitrary callback while holding its lock.
public final class MovementTaskAuthority: @unchecked Sendable {
    private struct GrantBinding {
        let grant: ContinuedProcessingGrant
    }

    private let lock = NSLock()
    private var stored = MovementAuthoritySnapshot(lease: nil, runState: nil, health: nil, revision: 0)
    private var connectionBlocked = false
    private var coldRecoveryHeld = false
    private var foreground = true
    private var grantBinding: GrantBinding?
    // Unknown health is only admissible for the first point gate installed
    // for a lease. Later unknown states must be revalidated by the owner.
    private var initialPointGateInstalled = false
    public init() {}
    public var snapshot: MovementAuthoritySnapshot { lock.withLock { stored } }

    /// Scene admission is independent from connection and cold-recovery
    /// fences. A valid bound grant is what permits a running healthy owner
    /// to dispatch while this flag is false.
    func setSceneActive(_ active: Bool) {
        lock.withLock {
            guard foreground != active else { return }
            foreground = active
            stored = MovementAuthoritySnapshot(lease: stored.lease, runState: stored.runState,
                health: stored.health, revision: stored.revision &+ 1)
        }
    }

    var isSceneActive: Bool { lock.withLock { foreground } }

    /// Service-owned admission fence shared by install CAS and dispatch permits.
    /// The setter intentionally changes only admission; it does not revoke the
    /// current lease or rewrite its health/run state.
    func setAdmissionFence(connectionBlocked: Bool, coldRecoveryHeld: Bool) {
        lock.withLock {
            guard self.connectionBlocked != connectionBlocked || self.coldRecoveryHeld != coldRecoveryHeld else { return }
            self.connectionBlocked = connectionBlocked
            self.coldRecoveryHeld = coldRecoveryHeld
            stored = MovementAuthoritySnapshot(lease: stored.lease, runState: stored.runState,
                health: stored.health, revision: stored.revision &+ 1)
        }
    }

    var isAdmissionBlocked: Bool {
        lock.withLock { connectionBlocked || coldRecoveryHeld }
    }

    /// Reserve the replacement lease with unknown health until its first validated ACK.
    @discardableResult public func install(_ lease: MovementTaskLease, replacing captured: MovementAuthoritySnapshot) -> Bool {
        lock.withLock {
            guard foreground, !connectionBlocked, !coldRecoveryHeld,
                  stored == captured,
                  stored.lease == nil || stored.health == .confirmedHealthy else { return false }
            if stored.lease == lease, let binding = grantBinding, !binding.grant.isValid { return false }
            if stored.lease != lease { grantBinding = nil }
            initialPointGateInstalled = true
            stored = MovementAuthoritySnapshot(lease: lease, runState: .running, health: .unknown, revision: stored.revision &+ 1)
            return true
        }
    }
    public func permitsDispatch(for lease: MovementTaskLease) -> Bool {
        lock.withLock {
            guard !connectionBlocked, !coldRecoveryHeld,
                  stored.lease == lease, stored.runState == .running,
                  stored.health == .confirmedHealthy else { return false }
            guard foreground else {
                return grantBinding?.grant.lease == lease && grantBinding?.grant.isValid == true
            }
            if let binding = grantBinding, binding.grant.lease == lease {
                return binding.grant.isValid
            }
            return true
        }
    }

    /// Recovery admission is checked under the same authority lock as the
    /// original dispatch. It accepts the initial gate's unknown health while
    /// its first point is still settling; subsequent unknown states require a
    /// fresh owner proof and are rejected.
    public func permitsRecovery(for lease: MovementTaskLease) -> Bool {
        lock.withLock {
            guard !connectionBlocked, !coldRecoveryHeld,
                  stored.lease == lease, stored.runState == .running else { return false }
            switch stored.health {
            case .confirmedHealthy:
                break
            case .unknown:
                guard initialPointGateInstalled else { return false }
            case .interrupted:
                return false
            case .none:
                return false
            }
            if let binding = grantBinding {
                return binding.grant.lease == lease && binding.grant.isValid
            }
            return foreground
        }
    }

    @discardableResult public func updateHealth(_ health: MovementTaskHealth, for lease: MovementTaskLease) -> Bool {
        lock.withLock {
            guard stored.lease == lease else { return false }
            // Any explicit health publication closes the initial unknown
            // window, including an idempotent `.unknown` publication from a
            // stop or expiry path.
            initialPointGateInstalled = false
            guard stored.health != health else { return true }
            stored = MovementAuthoritySnapshot(lease: lease, runState: stored.runState, health: health, revision: stored.revision &+ 1)
            return true
        }
    }
    @discardableResult public func updateRunState(_ state: MovementTaskRunState, for lease: MovementTaskLease) -> Bool {
        lock.withLock {
            guard stored.lease == lease else { return false }
            guard stored.runState != state else { return true }
            stored = MovementAuthoritySnapshot(lease: lease, runState: state, health: stored.health, revision: stored.revision &+ 1)
            return true
        }
    }
    @discardableResult public func revoke(_ lease: MovementTaskLease) -> Bool {
        lock.withLock {
            guard stored.lease == lease else { return false }
            grantBinding = nil
            initialPointGateInstalled = false
            stored = MovementAuthoritySnapshot(lease: nil, runState: nil, health: nil, revision: stored.revision &+ 1)
            return true
        }
    }
    public func revokeAll() {
        lock.withLock {
            grantBinding = nil
            initialPointGateInstalled = false
            stored = MovementAuthoritySnapshot(lease: nil, runState: nil, health: nil, revision: stored.revision &+ 1)
        }
    }

    /// Binds an already validated concrete owner to a live framework grant.
    /// ServiceController performs the owner/health checks before calling this
    /// method; this lock only protects the identity binding and its fence.
    @discardableResult
    func bind(_ grant: ContinuedProcessingGrant) -> Bool {
        lock.withLock {
            guard !connectionBlocked, !coldRecoveryHeld,
                  stored.lease == grant.lease, stored.runState == .running,
                  stored.health == .confirmedHealthy, grant.isValid else { return false }
            if let existing = grantBinding {
                return existing.grant === grant && existing.grant.isValid
            }
            grantBinding = GrantBinding(grant: grant)
            stored = MovementAuthoritySnapshot(lease: stored.lease, runState: stored.runState,
                health: stored.health, revision: stored.revision &+ 1)
            return true
        }
    }

    func hasValidBinding(movementID: UUID, lease: MovementTaskLease, requestID: UUID) -> Bool {
        lock.withLock {
            guard let binding = grantBinding,
                  stored.lease == lease, stored.runState == .running,
                  stored.health == .confirmedHealthy,
                  binding.grant.movementID == movementID,
                  binding.grant.requestID == requestID,
                  binding.grant.lease == lease,
                  binding.grant.isValid,
                  !connectionBlocked, !coldRecoveryHeld else { return false }
            return true
        }
    }

    func bindingMatches(requestID: UUID, lease: MovementTaskLease) -> Bool {
        lock.withLock {
            guard let binding = grantBinding else { return false }
            return binding.grant.requestID == requestID && binding.grant.lease == lease
        }
    }

    /// A rejected native claim can observe expiry before its MainActor event.
    /// Preserve the proven owner while closing its run state atomically.
    func pauseForClosedBinding(movementID: UUID, lease: MovementTaskLease) -> Bool {
        lock.withLock {
            guard !connectionBlocked, !coldRecoveryHeld,
                  stored.lease == lease, stored.health == .confirmedHealthy,
                  let binding = grantBinding,
                  binding.grant.movementID == movementID,
                  binding.grant.lease == lease, !binding.grant.isValid else { return false }
            stored = MovementAuthoritySnapshot(lease: lease, runState: .paused,
                health: stored.health, revision: stored.revision &+ 1)
            return true
        }
    }

    /// Drops only the exact bound request. Validity and foreground requirements
    /// are checked again while this lock is held so a grant that closes on a
    /// different queue cannot race a foreground-goal retirement.
    @discardableResult
    func retireBinding(requestID: UUID, lease: MovementTaskLease,
                       reason: MovementContinuationRetirement) -> Bool {
        lock.withLock {
            guard let binding = grantBinding,
                  binding.grant.requestID == requestID,
                  binding.grant.lease == lease else { return false }
            let healthyRunning = stored.lease == lease && stored.runState == .running &&
                stored.health == .confirmedHealthy
            switch reason {
            case .foregroundGoalChange:
                guard foreground, healthyRunning, binding.grant.isValid else { return false }
            case .foregroundManualAfterAutoOff:
                guard foreground, healthyRunning else { return false }
            case .ownerPausedOrEnded:
                guard !healthyRunning else { return false }
            }
            grantBinding = nil
            stored = MovementAuthoritySnapshot(lease: stored.lease, runState: stored.runState,
                health: stored.health, revision: stored.revision &+ 1)
            return true
        }
    }

    /// Explicit foreground resume is the only operation that reopens a
    /// paused owner. It atomically drops a matching runtime binding and
    /// changes the run state under this authority lock.
    @discardableResult
    func resumeForeground(_ lease: MovementTaskLease) -> Bool {
        lock.withLock {
            guard foreground, !connectionBlocked, !coldRecoveryHeld,
                  stored.lease == lease, stored.runState == .paused,
                  stored.health == .confirmedHealthy else { return false }
            grantBinding = nil
            stored = MovementAuthoritySnapshot(lease: lease, runState: .running,
                health: stored.health, revision: stored.revision &+ 1)
            return true
        }
    }
}
