import Foundation

/// The native adapter claims this gate on its shared serial queue immediately before the one point write.
/// Invalidating it cannot cancel a native call that already crossed the gate.
public final class PointDispatchGate: @unchecked Sendable {
    private let onDispatch: @Sendable () -> Void
    private let lock = NSLock()
    private let authority: MovementTaskAuthority?
    private let lease: MovementTaskLease?
    private let replacing: MovementAuthoritySnapshot?
    private let connectionRepair: Bool
    private let repairPausedTask: Bool
    private let keepAlive: Bool
    public enum State: Sendable { case available, dispatched, invalidated }
    private var storedState: State = .available
    private var recoveryRevoked = false
    private var recoveryAttemptClaimed = false
    public var state: State { lock.withLock { storedState } }

    public init(onDispatch: @escaping @Sendable () -> Void = {}) {
        self.onDispatch = onDispatch
        authority = nil
        lease = nil
        replacing = nil
        connectionRepair = false
        repairPausedTask = false
        keepAlive = false
    }

    public init(authority: MovementTaskAuthority, lease: MovementTaskLease,
                replacing: MovementAuthoritySnapshot? = nil,
                onDispatch: @escaping @Sendable () -> Void = {}) {
        self.authority = authority
        self.lease = lease
        self.replacing = replacing
        self.connectionRepair = false
        repairPausedTask = false
        keepAlive = false
        self.onDispatch = onDispatch
    }

    init(repairingConnection authority: MovementTaskAuthority, lease: MovementTaskLease, allowingPaused: Bool) {
        self.authority = authority
        self.lease = lease
        replacing = nil
        connectionRepair = true
        repairPausedTask = allowingPaused
        keepAlive = false
        onDispatch = {}
    }

    init(keepingAlive authority: MovementTaskAuthority, lease: MovementTaskLease) {
        self.authority = authority
        self.lease = lease
        replacing = nil
        connectionRepair = false
        repairPausedTask = false
        keepAlive = true
        onDispatch = {}
    }

    public var hasDispatched: Bool { lock.withLock { storedState == .dispatched } }
    /// A cheap admission hint for the native adapter. `claimRecovery()` still
    /// repeats every check while this gate lock is held.
    public var canAttemptRecovery: Bool {
        lock.withLock {
            guard storedState == .dispatched, !recoveryRevoked,
                  !recoveryAttemptClaimed, let authority, let lease else { return false }
            return authority.permitsRecovery(for: lease)
        }
    }
    public var recoveryAvailable: Bool { canAttemptRecovery }

    public func claim() -> Bool {
        let claimed = lock.withLock {
            guard storedState == .available else { return false }
            if let authority, let lease {
                let permitted = keepAlive ? authority.permitsKeepAlive(for: lease)
                    : connectionRepair ? authority.permitsConnectionRepair(for: lease, allowingPaused: repairPausedTask)
                    : (replacing.map { authority.install(lease, replacing: $0) } ?? authority.permitsDispatch(for: lease))
                guard permitted else {
                    storedState = .invalidated
                    recoveryRevoked = true
                    return false
                }
            }
            storedState = .dispatched
            return true
        }
        if claimed { onDispatch() }
        return claimed
    }

    /// Claims the single write-repair opportunity for the exact point that
    /// already crossed this gate. The original dispatched state and its
    /// `hasDispatched` truth are intentionally unchanged.
    public func claimRecovery() -> Bool {
        lock.withLock {
            guard storedState == .dispatched, !recoveryRevoked,
                  !recoveryAttemptClaimed, let authority, let lease,
                  authority.permitsRecovery(for: lease) else { return false }
            recoveryAttemptClaimed = true
            return true
        }
    }

    @discardableResult public func invalidateIfAvailable() -> Bool {
        lock.withLock {
            guard storedState == .available else { return false }
            storedState = .invalidated
            recoveryRevoked = true
            return true
        }
    }
    public func invalidate() {
        lock.withLock {
            if storedState == .available { storedState = .invalidated }
            recoveryRevoked = true
        }
    }
}
