import Foundation

/// The native adapter claims this gate on its shared serial queue immediately before the one point write.
/// Invalidating it cannot cancel a native call that already crossed the gate.
public final class PointDispatchGate: @unchecked Sendable {
    private let onDispatch: @Sendable () -> Void
    private let lock = NSLock()
    private let authority: MovementTaskAuthority?
    private let lease: MovementTaskLease?
    private let replacing: MovementAuthoritySnapshot?
    public enum State: Sendable { case available, dispatched, invalidated }
    private var storedState: State = .available
    public var state: State { lock.withLock { storedState } }

    public init(onDispatch: @escaping @Sendable () -> Void = {}) {
        self.onDispatch = onDispatch
        authority = nil
        lease = nil
        replacing = nil
    }

    public init(authority: MovementTaskAuthority, lease: MovementTaskLease,
                replacing: MovementAuthoritySnapshot? = nil,
                onDispatch: @escaping @Sendable () -> Void = {}) {
        self.authority = authority
        self.lease = lease
        self.replacing = replacing
        self.onDispatch = onDispatch
    }

    public var hasDispatched: Bool { lock.withLock { storedState == .dispatched } }
    public func claim() -> Bool {
        let claimed = lock.withLock {
            guard storedState == .available else { return false }
            if let authority, let lease {
                let permitted = replacing.map { authority.install(lease, replacing: $0) } ?? authority.permitsDispatch(for: lease)
                guard permitted else {
                    storedState = .invalidated
                    return false
                }
            }
            storedState = .dispatched
            return true
        }
        if claimed { onDispatch() }
        return claimed
    }
    @discardableResult public func invalidateIfAvailable() -> Bool {
        lock.withLock {
            guard storedState == .available else { return false }
            storedState = .invalidated
            return true
        }
    }
    public func invalidate() {
        lock.withLock {
            if storedState == .available { storedState = .invalidated }
        }
    }
}
