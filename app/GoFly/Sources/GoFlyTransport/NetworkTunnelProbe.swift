import Foundation
import GoFlyCore

/// Every check owns a fresh TCP connection. A reachable tunnel never starts a
/// device service or performs authentication, pairing, mounting or location work.
public struct NetworkTunnelProbe: TunnelProbing {
    private let timeout: TimeInterval
    private let makeConnection: @Sendable () -> any TunnelConnection

    public init() {
        self.init(host: LocalTunnelEndpoint.host, port: LocalTunnelEndpoint.port,
                  timeout: LocalTunnelEndpoint.timeoutSeconds)
    }

    init(host: String, port: UInt16, timeout: TimeInterval) {
        self.init(timeout: timeout, makeConnection: { NetworkConnection(host: host, port: port) })
    }

    init(timeout: TimeInterval, makeConnection: @escaping @Sendable () -> any TunnelConnection) {
        precondition(timeout.isFinite && timeout >= 0)
        self.timeout = timeout
        self.makeConnection = makeConnection
    }

    public func check() async throws {
        let operation = ProbeOperation(connection: makeConnection(), timeout: timeout)
        try await withTaskCancellationHandler {
            try await operation.run()
        } onCancel: {
            operation.cancel()
        }
    }

    #if DEBUG
    /// A real refused connection for deterministic simulator UI verification.
    /// This does not expose a caller-selected endpoint or manufacture success.
    public static var unavailableUITestProbe: NetworkTunnelProbe {
        NetworkTunnelProbe(host: "127.0.0.1", port: 0, timeout: LocalTunnelEndpoint.timeoutSeconds)
    }
    #endif
}

/// All mutable state, including cancellation before continuation installation,
/// lives on this one queue. The first terminal result closes and resumes once.
private final class ProbeOperation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.neven.gofly.tunnel-probe")
    private let connection: any TunnelConnection
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?
    private var timer: DispatchWorkItem?

    init(connection: any TunnelConnection, timeout: TimeInterval) {
        self.connection = connection
        self.timeout = timeout
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { self.install(continuation) }
        }
    }

    func cancel() {
        queue.async { self.finish(.failure(CancellationError())) }
    }

    private func install(_ continuation: CheckedContinuation<Void, Error>) {
        if let result {
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        guard timeout > 0 else {
            finish(.failure(TunnelProbeFailure.timedOut))
            return
        }
        let timer = DispatchWorkItem { [weak self] in
            self?.finish(.failure(TunnelProbeFailure.timedOut))
        }
        self.timer = timer
        queue.asyncAfter(deadline: .now() + timeout, execute: timer)
        connection.start(on: queue) { [weak self] state in
            switch state {
            case .ready: self?.finish(.success(()))
            case .unavailable: self?.finish(.failure(TunnelProbeFailure.unavailable))
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard self.result == nil else { return }
        self.result = result
        timer?.cancel()
        timer = nil
        connection.cancel()
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
