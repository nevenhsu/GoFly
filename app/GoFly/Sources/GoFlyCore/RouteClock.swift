import Foundation

public protocol RouteClock: Sendable {
    var now: Duration { get }
    func sleep(for duration: Duration) async throws
}
public struct ContinuousRouteClock: RouteClock {
    private let origin = ContinuousClock.now
    public init() {}
    public var now: Duration { origin.duration(to: .now) }
    public func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}
