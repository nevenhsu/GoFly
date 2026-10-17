import Foundation

/// The native adapter claims this gate immediately before the one point write.
/// Invalidating it cannot cancel a native call that already crossed the gate.
public final class PointDispatchGate: @unchecked Sendable {
    private let onDispatch: @Sendable () -> Void
    private let lock = NSLock()
    private enum State { case available, dispatched, invalidated }
    private var state: State = .available

    public init(onDispatch: @escaping @Sendable () -> Void = {}) {
        self.onDispatch = onDispatch
    }

    public var hasDispatched: Bool { lock.withLock { state == .dispatched } }
    public func claim() -> Bool {
        let claimed = lock.withLock {
            guard state == .available else { return false }
            state = .dispatched
            return true
        }
        if claimed { onDispatch() }
        return claimed
    }
    public func invalidate() {
        lock.withLock {
            if state == .available { state = .invalidated }
        }
    }
}
