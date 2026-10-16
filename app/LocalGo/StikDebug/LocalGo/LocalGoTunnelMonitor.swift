import Combine
import Foundation
import Network

/// Foreground-only reachability for the device endpoint exposed by LocalDevVPN.
///
/// This monitor only answers whether a TCP connection can be opened. It does
/// not perform pairing, send a protocol payload, or change the location
/// engine's lifecycle.
@MainActor
public final class LocalGoTunnelMonitor: ObservableObject {
    public enum State: Equatable, Sendable {
        case checking
        case reachable
        case unreachable
    }

    public typealias Probe = @Sendable () async -> Bool

    @Published public private(set) var state: State = .checking

    public let host: String
    public let port: UInt16

    private let probe: Probe
    private let automaticPolling: Bool
    private var probeTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var running = false

    public init(
        host: String,
        port: UInt16 = 49152,
        probe: Probe? = nil,
        automaticPolling: Bool = true
    ) {
        self.host = host
        self.port = port
        self.automaticPolling = automaticPolling
        self.probe = probe ?? { [host, port] in
            await Self.tcpProbe(host: host, port: port)
        }
    }

    /// Starts immediate foreground monitoring. Calling start while already
    /// running does not create a second probe or polling loop.
    public func start() {
        guard !running else { return }
        running = true
        generation &+= 1
        let token = generation

        refresh()

        guard automaticPolling else { return }
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                guard let self,
                      self.running,
                      self.generation == token else {
                    return
                }
                self.refresh()
            }
        }
    }

    /// Stops foreground monitoring and cancels the current probe and poll.
    /// The last result remains visible until a later start produces a new one.
    public func stop() {
        guard running || probeTask != nil || pollingTask != nil else { return }
        running = false
        generation &+= 1
        probeTask?.cancel()
        probeTask = nil
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Requests one immediate reachability check while the monitor is running.
    /// A refresh already in flight is allowed to finish instead of being
    /// replaced, keeping the monitor at most one probe deep.
    public func refresh() {
        guard running, probeTask == nil else { return }
        let token = generation
        probeTask = Task { @MainActor [weak self] in
            guard let self,
                  self.running,
                  self.generation == token else {
                return
            }
            let result = await ProbeRace.run(self.probe)
            self.complete(result, token: token)
        }
    }

    private func complete(_ reachable: Bool, token: UInt64) {
        guard running, token == generation else { return }
        probeTask = nil
        state = reachable ? .reachable : .unreachable
    }

    private static func tcpProbe(host: String, port: UInt16) async -> Bool {
        let session = TCPProbeSession(host: host, port: port)
        return await session.run()
    }
}

/// Races an injected or native probe against the two-second reachability
/// bound. The operation uses unstructured probe work so a non-cooperative
/// injected test probe cannot hold the monitor's timeout or lifecycle task.
private final class ProbeRace: @unchecked Sendable {
    private static let timeout: Duration = .seconds(2)

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var finished = false
    private var probeTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    static func run(_ probe: @escaping LocalGoTunnelMonitor.Probe) async -> Bool {
        let race = ProbeRace()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                race.start(continuation, probe: probe)
            }
        }, onCancel: {
            race.finish(false)
        })
    }

    private func start(
        _ continuation: CheckedContinuation<Bool, Never>,
        probe: @escaping LocalGoTunnelMonitor.Probe
    ) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            continuation.resume(returning: false)
            return
        }

        self.continuation = continuation
        probeTask = Task { [weak self] in
            let result = await probe()
            self?.finish(result)
        }
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.timeout)
            } catch {
                return
            }
            self?.finish(false)
        }
        lock.unlock()
    }

    fileprivate func finish(_ result: Bool) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let probeTask = self.probeTask
        self.probeTask = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        probeTask?.cancel()
        timeoutTask?.cancel()
        continuation?.resume(returning: result)
    }
}

/// A read-only TCP connect probe. It never sends bytes and always cancels the
/// connection after the first terminal result or task cancellation.
private final class TCPProbeSession: @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let lock = NSLock()
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var finished = false

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    func run() async -> Bool {
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                start(continuation)
            }
        }, onCancel: {
            finish(false)
        })
    }

    private func start(_ continuation: CheckedContinuation<Bool, Never>) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            continuation.resume(returning: false)
            return
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: .tcp
        )
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.finish(true)
            case .failed, .cancelled:
                self?.finish(false)
            default:
                break
            }
        }

        lock.lock()
        guard !finished else {
            lock.unlock()
            connection.cancel()
            continuation.resume(returning: false)
            return
        }
        self.connection = connection
        self.continuation = continuation
        lock.unlock()

        connection.start(queue: DispatchQueue.global(qos: .utility))
    }

    private func finish(_ result: Bool) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let connection = self.connection
        self.connection = nil
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        connection?.cancel()
        continuation?.resume(returning: result)
    }
}
