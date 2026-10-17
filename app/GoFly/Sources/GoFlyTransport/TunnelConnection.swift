import Dispatch

/// Internal seam for testing terminal races without relying on a routable
/// blackhole address. Public callers can only use the fixed production probe.
enum TunnelConnectionState: Sendable { case ready, unavailable }

protocol TunnelConnection: AnyObject, Sendable {
    func start(on queue: DispatchQueue, stateUpdate: @escaping @Sendable (TunnelConnectionState) -> Void)
    func cancel()
}
