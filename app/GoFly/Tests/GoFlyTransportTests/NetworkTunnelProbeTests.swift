import Darwin
import Foundation
import GoFlyCore
import Network
import Testing
@testable import GoFlyTransport

struct NetworkTunnelProbeTests {
    @Test func temporaryNetworkWaitIsNotATerminalFailure() {
        // Replay the actual NWConnection state used while a VPN route settles.
        switch NetworkConnection.probeState(for: .waiting(.posix(.ENETDOWN))) {
        case .pending(let detail): #expect(detail.contains("waiting"))
        default: Issue.record("A temporary VPN path wait must remain pending until ready, failure, cancellation or deadline")
        }
    }

    @Test func refusedConnectionFailsWithoutWaitingForDeadline() {
        switch NetworkConnection.probeState(for: .waiting(.posix(.ECONNREFUSED))) {
        case .unavailable(let detail): #expect(detail?.contains("refused") == true)
        default: Issue.record("A refused connection has no listener to wait for")
        }
    }

    @Test(.timeLimit(.minutes(1))) func timeoutReportsLastPendingDetail() async throws {
        let connection = ControlledConnection()
        let probe = NetworkTunnelProbe(timeout: 0.03, makeConnection: { connection })
        let task = Task { try await probe.check() }
        defer { task.cancel() }
        try await connection.waitForStart()
        connection.emitNetworkState(.waiting(.posix(.ENETDOWN)))
        await #expect(throws: TunnelProbeFailure.timedOut) { try await task.value }
        let detail = try #require(probe.lastFailureDetail)
        #expect(detail.contains("timed out"))
        #expect(detail.contains("waiting"))
    }

    @Test(.timeLimit(.minutes(1))) func failureDetailIsClearedBySuccess() async throws {
        let failing = ControlledConnection()
        let passing = ControlledConnection()
        let connections = ConnectionQueue([failing, passing])
        let probe = NetworkTunnelProbe(timeout: 1, makeConnection: { connections.next() })
        let first = Task { try await probe.check() }
        try await failing.waitForStart()
        failing.emitNetworkState(.failed(.posix(.ECONNREFUSED)))
        await #expect(throws: TunnelProbeFailure.unavailable) { try await first.value }
        #expect(probe.lastFailureDetail?.contains("failed") == true)
        let second = Task { try await probe.check() }
        try await passing.waitForStart()
        passing.emit(.ready)
        try await second.value
        #expect(probe.lastFailureDetail == nil)
    }

    @Test(.timeLimit(.minutes(1))) func waitingThenReadyCanCompleteTheSameProbe() async throws {
        let connection = ControlledConnection()
        let probe = NetworkTunnelProbe(timeout: 0.5, makeConnection: { connection })
        let task = Task { try await probe.check() }
        defer { task.cancel() }
        try await connection.waitForStart()
        connection.emitNetworkState(.waiting(.posix(.ENETDOWN)))
        connection.emitNetworkState(.ready)
        try await task.value
        #expect(connection.counts.cancelled == 1)
    }

    @Test(.timeLimit(.minutes(1))) func persistentWaitingStillTimesOutAndCloses() async throws {
        let connection = ControlledConnection()
        let probe = NetworkTunnelProbe(timeout: 0.03, makeConnection: { connection })
        let task = Task { try await probe.check() }
        defer { task.cancel() }
        try await connection.waitForStart()
        connection.emitNetworkState(.waiting(.posix(.ENETDOWN)))
        await #expect(throws: TunnelProbeFailure.timedOut) { try await task.value }
        #expect(connection.counts.cancelled == 1)
    }
    @Test(.timeLimit(.minutes(1))) func eachCheckMakesFreshLoopbackConnection() async throws {
        let listener = try LoopbackEndpoint(listening: true)
        defer { withExtendedLifetime(listener) {} }
        let probe: any TunnelProbing = NetworkTunnelProbe(host: "127.0.0.1", port: listener.port, timeout: 0.5)
        try await probe.check()
        try await probe.check()
        try await probe.check()
        #expect(try listener.acceptedConnectionCount() == 3)
    }

    @Test(.timeLimit(.minutes(1))) func closedEndpointCannotReportSuccessAndFinishesWithinDeadline() async throws {
        // Bound but not listening: this port cannot be stolen by another test.
        let endpoint = try LoopbackEndpoint(listening: false)
        defer { withExtendedLifetime(endpoint) {} }
        let probe: any TunnelProbing = NetworkTunnelProbe(host: "127.0.0.1", port: endpoint.port, timeout: 0.5)
        let start = ContinuousClock.now
        do { try await probe.check(); Issue.record("A non-listening endpoint must not report success") }
        catch let failure as TunnelProbeFailure { #expect(failure == .unavailable || failure == .timedOut) }
        catch { Issue.record("Unexpected probe error: \(error)") }
        #expect(start.duration(to: .now) < .seconds(1))
    }

    #if DEBUG
    @Test(.timeLimit(.minutes(1))) func simulatorUIFailureFixtureReallyFails() async {
        let start = ContinuousClock.now
        do {
            try await NetworkTunnelProbe.unavailableUITestProbe.check()
            Issue.record("The unavailable simulator fixture must never report success")
        } catch let failure as TunnelProbeFailure {
            // Network.framework may wait on port zero instead of failing.
            // That pending state must honor the production deadline too.
            #expect(failure == .unavailable || failure == .timedOut)
        } catch { Issue.record("Unexpected probe error: \(error)") }
        #expect(start.duration(to: .now) < .seconds(3))
    }
    #endif

    @Test(.timeLimit(.minutes(1))) func failedConnectionClosesAndIgnoresLateReady() async throws {
        let connection = ControlledConnection()
        let probe: any TunnelProbing = NetworkTunnelProbe(timeout: 1, makeConnection: { connection })
        let task = Task { try await probe.check() }
        defer { task.cancel() }
        try await connection.waitForStart()
        connection.emit(.unavailable(detail: nil))
        connection.emit(.ready)
        await #expect(throws: TunnelProbeFailure.unavailable) { try await task.value }
        await connection.drain()
        #expect(connection.counts.cancelled == 1)
    }

    @Test(.timeLimit(.minutes(1))) func timeoutClosesAnUnresponsiveConnection() async {
        let connection = ControlledConnection()
        let probe: any TunnelProbing = NetworkTunnelProbe(timeout: 0.02, makeConnection: { connection })
        await #expect(throws: TunnelProbeFailure.timedOut) { try await probe.check() }
        #expect(connection.counts.started == 1)
        #expect(connection.counts.cancelled == 1)
    }

    @Test(.timeLimit(.minutes(1))) func cancellationBeforeContinuationInstallClosesWithoutStarting() async {
        let connection = ControlledConnection()
        let probe: any TunnelProbing = NetworkTunnelProbe(timeout: 1, makeConnection: { connection })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await probe.check()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(connection.counts.started == 0)
        #expect(connection.counts.cancelled == 1)
    }

    @Test(.timeLimit(.minutes(1))) func cancellationDuringCheckIgnoresLateCallbacks() async throws {
        let connection = ControlledConnection()
        let probe: any TunnelProbing = NetworkTunnelProbe(timeout: 1, makeConnection: { connection })
        let task = Task { try await probe.check() }
        defer { task.cancel() }
        try await connection.waitForStart()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        connection.emit(.ready)
        connection.emit(.unavailable(detail: nil))
        await connection.drain()
        #expect(connection.counts.cancelled == 1)
    }

    @Test(.timeLimit(.minutes(1))) func duplicateTerminalCallbacksCompleteOnlyOnce() async throws {
        let connection = ControlledConnection()
        let probe: any TunnelProbing = NetworkTunnelProbe(timeout: 1, makeConnection: { connection })
        let task = Task { try await probe.check() }
        defer { task.cancel() }
        try await connection.waitForStart()
        connection.emit(.ready)
        for _ in 0..<100 { connection.emit(.unavailable(detail: nil)); connection.emit(.ready) }
        try await task.value
        await connection.drain()
        #expect(connection.counts.started == 1)
        #expect(connection.counts.cancelled == 1)
    }

    @Test(.timeLimit(.minutes(1))) func timeoutCancellationRacesRemainSingleCompletion() async throws {
        for _ in 0..<20 {
            let connection = ControlledConnection()
            let probe: any TunnelProbing = NetworkTunnelProbe(timeout: 0.005, makeConnection: { connection })
            let task = Task { try await probe.check() }
            defer { task.cancel() }
            try await connection.waitForStart()
            task.cancel()
            do { try await task.value; Issue.record("Cancelled or expired probe must fail") }
            catch is CancellationError { }
            catch TunnelProbeFailure.timedOut { }
            catch { Issue.record("Unexpected probe error: \(error)") }
            await connection.drain()
            #expect(connection.counts.cancelled == 1)
        }
    }

}

private final class LoopbackEndpoint {
    let descriptor: Int32
    let port: UInt16

    init(listening: Bool) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw FixtureFailure.socket }
        var keep = false
        defer { if !keep { Darwin.close(descriptor) } }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, !listening || listen(descriptor, 16) == 0 else { throw FixtureFailure.socket }
        if listening, fcntl(descriptor, F_SETFL, O_NONBLOCK) == -1 { throw FixtureFailure.socket }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0 else { throw FixtureFailure.socket }
        self.descriptor = descriptor
        self.port = UInt16(bigEndian: address.sin_port)
        keep = true
    }

    func acceptedConnectionCount() throws -> Int {
        var count = 0
        while true {
            let client = accept(descriptor, nil, nil)
            if client < 0 {
                guard errno == EAGAIN || errno == EWOULDBLOCK else { throw FixtureFailure.socket }
                return count
            }
            Darwin.close(client)
            count += 1
        }
    }

    deinit { Darwin.close(descriptor) }
}

private enum FixtureFailure: Error { case socket, notStarted }

private final class ConnectionQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [ControlledConnection]

    init(_ connections: [ControlledConnection]) { remaining = connections }

    func next() -> ControlledConnection { lock.withLock { remaining.removeFirst() } }
}

private final class ControlledConnection: TunnelConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var started = 0
    private var cancelled = 0
    private var queue: DispatchQueue?
    private var update: (@Sendable (TunnelConnectionState) -> Void)?

    var counts: (started: Int, cancelled: Int) { lock.withLock { (started, cancelled) } }

    func start(on queue: DispatchQueue, stateUpdate: @escaping @Sendable (TunnelConnectionState) -> Void) {
        lock.withLock { started += 1; self.queue = queue; update = stateUpdate }
    }

    func cancel() { lock.withLock { cancelled += 1 } }

    func emit(_ state: TunnelConnectionState) {
        let callback = lock.withLock { (queue, update) }
        if let queue = callback.0, let update = callback.1 { queue.async { update(state) } }
    }

    func emitNetworkState(_ state: NWConnection.State) {
        if let result = NetworkConnection.probeState(for: state) { emit(result) }
    }

    func waitForStart() async throws {
        let limit = ContinuousClock.now + .seconds(1)
        while counts.started == 0 {
            if ContinuousClock.now >= limit { throw FixtureFailure.notStarted }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func drain() async {
        guard let queue = lock.withLock({ queue }) else { return }
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
}
