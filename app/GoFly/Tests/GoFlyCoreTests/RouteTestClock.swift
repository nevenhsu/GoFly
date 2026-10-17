import Foundation
@testable import GoFlyCore

final class RouteTestClock: RouteClock, @unchecked Sendable {
    private struct Sleeper { let deadline: Duration; let continuation: CheckedContinuation<Void, Error> }
    private let lock = NSLock()
    private var instant: Duration = .zero
    private var sleepers: [UUID: Sleeper] = [:]
    private var cancelled: Set<UUID> = []
    var now: Duration { lock.withLock { instant } }
    var sleepingCount: Int { lock.withLock { sleepers.count } }
    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = lock.withLock {
                    if self.cancelled.remove(id) != nil { return true }
                    sleepers[id] = Sleeper(deadline: instant + duration, continuation: continuation)
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let continuation: CheckedContinuation<Void, Error>? = self.lock.withLock {
                if let sleeper = self.sleepers.removeValue(forKey: id) { return sleeper.continuation }
                self.cancelled.insert(id)
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        }
    }
    func advance(by duration: Duration) {
        let due = lock.withLock {
            instant += duration
            let due = sleepers.filter { $0.value.deadline <= instant }
            for id in due.keys { sleepers.removeValue(forKey: id) }
            return due.values.map(\.continuation)
        }
        for continuation in due { continuation.resume() }
    }
}
