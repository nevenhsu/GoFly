import Foundation
import GoFlyCore

struct ContinuationPlanner: RoutePlanning, Sendable {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}

struct ContinuationSearch: PlaceSearching, Sendable {
    func search(query: String) async throws -> [MapPlace] { [] }
}

struct ContinuationProbe: TunnelProbing, Sendable {
    func check() async throws {}
}

final class ContinuationTestClock: RouteClock, @unchecked Sendable {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }
    private let lock = NSLock()
    private var instant: Duration = .zero
    private var sleepers: [UUID: Sleeper] = [:]
    private var cancelled: Set<UUID> = []

    var now: Duration { lock.withLock { instant } }
    var sleepingCount: Int { lock.withLock { sleepers.count } }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let isCancelled = lock.withLock {
                    if cancelled.remove(id) != nil { return true }
                    sleepers[id] = Sleeper(deadline: instant + duration, continuation: continuation)
                    return false
                }
                if isCancelled { continuation.resume(throwing: CancellationError()) }
            }
        }, onCancel: {
            let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
                if let sleeper = sleepers.removeValue(forKey: id) { return sleeper.continuation }
                cancelled.insert(id)
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        })
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

@MainActor
func waitForContinuation(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<400 {
        if condition() { return }
        await Task.yield()
    }
}
