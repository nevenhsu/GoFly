import Foundation

/// Heartbeat for a held position that has no writer of its own: a paused route
/// or wander, or a released manual joystick. A running hold sends its own
/// heartbeat and a moving task's writes already prove liveness.
@MainActor
public final class PositionKeepAlive {
    private let service: ServiceController
    private let clock: any RouteClock
    private let interval: Duration
    private var task: Task<Void, Never>?

    public init(service: ServiceController, clock: any RouteClock = ContinuousRouteClock(),
                interval: Duration = PositionHoldController.heartbeat) {
        self.service = service
        self.clock = clock
        self.interval = interval
    }

    public func sceneDidBecomeActive() {
        guard task == nil else { return }
        let clock = clock
        let interval = interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: interval) } catch { return }
                guard let self else { return }
                await self.service.sendKeepAlive()
            }
        }
    }

    /// A paused task has no background grant, so its heartbeat stops with the
    /// scene; the next foreground write or Retry decides the connection.
    public func releaseForInactiveScene() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
