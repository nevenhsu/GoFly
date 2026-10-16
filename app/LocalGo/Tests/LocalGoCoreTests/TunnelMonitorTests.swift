import Foundation
import XCTest
@testable import LocalGoCore

@MainActor
final class TunnelMonitorTests: XCTestCase {
    func testInjectedProbePublishesReachableAndUnreachable() async throws {
        let reachable = LocalGoTunnelMonitor(
            host: "10.7.0.1",
            probe: { true },
            automaticPolling: false
        )
        reachable.start()
        try await wait { reachable.state == .reachable }
        XCTAssertEqual(reachable.state, .reachable)
        reachable.stop()

        let unreachable = LocalGoTunnelMonitor(
            host: "10.7.0.1",
            probe: { false },
            automaticPolling: false
        )
        unreachable.start()
        try await wait { unreachable.state == .unreachable }
        XCTAssertEqual(unreachable.state, .unreachable)
        unreachable.stop()
    }

    func testProbeTimeoutPublishesUnreachableAndCancelsProbe() async throws {
        let cancellations = CancellationCounter()
        let monitor = LocalGoTunnelMonitor(
            host: "10.7.0.1",
            probe: {
                await withTaskCancellationHandler(operation: {
                    do {
                        try await Task.sleep(for: .seconds(3))
                    } catch {
                        // The monitor's two-second bound cancels this probe.
                    }
                    return true
                }, onCancel: {
                    cancellations.increment()
                })
            },
            automaticPolling: false
        )

        monitor.start()
        try await wait { monitor.state == .unreachable }
        try await wait { cancellations.value > 0 }
        monitor.stop()
    }

    func testStopCancelsProbeAndIgnoresItsLateResult() async throws {
        let probe = DeferredProbe()
        let monitor = LocalGoTunnelMonitor(
            host: "10.7.0.1",
            probe: { await probe.call() },
            automaticPolling: false
        )

        monitor.start()
        try await wait { probe.calls == 1 }
        monitor.stop()
        try await wait { probe.cancellations > 0 }

        probe.resolve(true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(monitor.state, .checking)
    }

    func testRefreshDoesNotOverlapAndRestartStartsForegroundProbe() async throws {
        let probe = DeferredProbe()
        let monitor = LocalGoTunnelMonitor(
            host: "10.7.0.1",
            probe: { await probe.call() },
            automaticPolling: false
        )

        monitor.start()
        try await wait { probe.calls == 1 }
        monitor.refresh()
        monitor.refresh()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(probe.calls, 1)

        monitor.stop()
        try await wait { probe.cancellations > 0 }
        probe.resolve(true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(monitor.state, .checking)

        monitor.start()
        try await wait { probe.calls == 2 }
        probe.resolve(false)
        try await wait { monitor.state == .unreachable }
        monitor.stop()
    }

    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<650 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Tunnel monitor did not reach the expected test state")
        throw TestTimeout.timeout
    }

    private enum TestTimeout: Error { case timeout }
}

private final class CancellationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private final class DeferredProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Bool, Never>] = []
    private var callCount = 0
    private var cancellationCount = 0

    var calls: Int { lock.withLock { callCount } }
    var cancellations: Int { lock.withLock { cancellationCount } }

    func call() async -> Bool {
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    callCount += 1
                    continuations.append(continuation)
                }
            }
        }, onCancel: {
            lock.withLock { cancellationCount += 1 }
        })
    }

    func resolve(_ result: Bool) {
        let continuation: CheckedContinuation<Bool, Never>? = lock.withLock {
            guard !continuations.isEmpty else { return nil }
            return continuations.removeFirst()
        }
        continuation?.resume(returning: result)
    }
}
