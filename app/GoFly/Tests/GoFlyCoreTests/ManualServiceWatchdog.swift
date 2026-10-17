import Foundation

/// Tests choose the timeout boundary after observing native admission/dispatch;
/// CPU-heavy persistence work cannot accidentally advance this watchdog.
@MainActor
final class ManualServiceWatchdog {
    private(set) var requests: [Duration] = []
    private var waiters: [Int: CheckedContinuation<Void, any Error>] = [:]
    var sleep: @MainActor @Sendable (Duration) async throws -> Void {
        { try await self.wait($0) }
    }

    func fireLatest() {
        guard !requests.isEmpty else { return }
        waiters.removeValue(forKey: requests.count - 1)?.resume()
    }

    private func wait(_ duration: Duration) async throws {
        try Task.checkCancellation()
        let id = requests.count
        requests.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiters[id] = $0 }
        } onCancel: {
            Task { @MainActor in
                self.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }
}
