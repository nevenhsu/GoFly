import Dispatch

/// Internal seam for testing terminal races without relying on a routable
/// blackhole address. Public callers can only use the fixed production probe.
/// `pending` is non-terminal and only refreshes the diagnostic detail.
enum TunnelConnectionState: Sendable, Equatable {
    case ready
    case unavailable(detail: String?)
    case pending(detail: String)
}

protocol TunnelConnection: AnyObject, Sendable {
    func start(on queue: DispatchQueue, stateUpdate: @escaping @Sendable (TunnelConnectionState) -> Void)
    func cancel()
}
