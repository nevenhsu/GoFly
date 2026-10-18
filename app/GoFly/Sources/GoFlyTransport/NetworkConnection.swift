import Dispatch
import Network

/// Called only on its operation's queue; no connection is cached or shared.
final class NetworkConnection: TunnelConnection, @unchecked Sendable {
    private let connection: NWConnection

    init(host: String, port: UInt16) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }

    func start(on queue: DispatchQueue, stateUpdate: @escaping @Sendable (TunnelConnectionState) -> Void) {
        connection.stateUpdateHandler = { state in
            if let result = Self.probeState(for: state) { stateUpdate(result) }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    static func probeState(for state: NWConnection.State) -> TunnelConnectionState? {
        switch state {
        case .ready: .ready
        case .failed, .cancelled: .unavailable
        // LocalDevVPN may still be bringing up its route after app switching.
        // Keep this connection alive so Network.framework can recover. The
        // owning ProbeOperation still enforces its original two-second bound.
        case .waiting: nil
        default: nil
        }
    }
}
