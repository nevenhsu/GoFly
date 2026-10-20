import Dispatch
import Network

/// Called only on its operation's queue; no connection is cached or shared.
final class NetworkConnection: TunnelConnection, @unchecked Sendable {
    private let connection: NWConnection

    init(host: String, port: UInt16) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }

    func start(on queue: DispatchQueue, stateUpdate: @escaping @Sendable (TunnelConnectionState) -> Void) {
        connection.stateUpdateHandler = { [weak connection] state in
            if let result = Self.probeState(for: state, path: connection?.currentPath) { stateUpdate(result) }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    static func probeState(for state: NWConnection.State, path: NWPath? = nil) -> TunnelConnectionState? {
        switch state {
        case .ready: .ready
        case .failed, .cancelled: .unavailable(detail: detail(for: state, path: path))
        // A refusal means the route reached iPhone but nothing listens there,
        // e.g. on cellular only. Waiting cannot fix that, so report it now.
        case .waiting(.posix(.ECONNREFUSED)): .unavailable(detail: detail(for: state, path: path))
        // LocalDevVPN may still be bringing up its route after app switching.
        // Keep this connection alive so Network.framework can recover. The
        // owning ProbeOperation still enforces its original two-second bound.
        case .waiting, .preparing: .pending(detail: detail(for: state, path: path))
        default: nil
        }
    }

    /// Display-only text for diagnosing a failed check on device. It never
    /// changes the probe result or retry behavior.
    static func detail(for state: NWConnection.State, path: NWPath?) -> String {
        var parts: [String]
        switch state {
        case .waiting(let error): parts = ["waiting: \(error.debugDescription)"]
        case .failed(let error): parts = ["failed: \(error.debugDescription)"]
        case .preparing: parts = ["preparing"]
        case .cancelled: parts = ["cancelled"]
        default: parts = ["\(state)"]
        }
        if let path {
            var pathText = "path: \(path.status)"
            if path.status != .satisfied { pathText += " (\(path.unsatisfiedReason))" }
            let interfaces = path.availableInterfaces.map(\.name).joined(separator: ",")
            pathText += interfaces.isEmpty ? ", no interface" : ", via \(interfaces)"
            parts.append(pathText)
        }
        return parts.joined(separator: "; ")
    }
}
