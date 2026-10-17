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
    private let lock = NSLock()
    private var stored = MovementAuthoritySnapshot(lease: nil, runState: nil, health: nil, revision: 0)
    public init() {}
    public var snapshot: MovementAuthoritySnapshot { lock.withLock { stored } }

    /// Reserve the replacement lease with unknown health until its first validated ACK.
    @discardableResult public func install(_ lease: MovementTaskLease, replacing captured: MovementAuthoritySnapshot) -> Bool {
        lock.withLock {
            guard stored == captured,
                  stored.lease == nil || stored.health == .confirmedHealthy else { return false }
            stored = MovementAuthoritySnapshot(lease: lease, runState: .running, health: .unknown, revision: stored.revision &+ 1)
            return true
        }
    }
    public func permitsDispatch(for lease: MovementTaskLease) -> Bool {
        lock.withLock { stored.lease == lease && stored.runState == .running && stored.health == .confirmedHealthy }
    }
    @discardableResult public func updateHealth(_ health: MovementTaskHealth, for lease: MovementTaskLease) -> Bool {
        lock.withLock {
            guard stored.lease == lease else { return false }
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
    public func revokeAll() {
        lock.withLock {
            stored = MovementAuthoritySnapshot(lease: nil, runState: nil, health: nil, revision: stored.revision &+ 1)
        }
    }
}
