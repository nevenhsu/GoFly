import Foundation

/// Asks the platform for one low-power real location fix.
@MainActor
public protocol RealLocationFixRequesting: AnyObject {
    func requestFix()
}

/// Keeps the real location fresh enough for joystick and route origins, which
/// accept a fix up to 15 s old, with occasional one-shot fixes instead of a
/// continuous GPS stream. It refreshes only while the scene is active and the
/// device reports its real location: a software-simulated fix means real GPS
/// cannot be observed, so refreshing waits for an explicit `refreshNow()`.
@MainActor
public final class RealLocationRefresher {
    public static let interval: Duration = .seconds(8)

    private weak var source: (any RealLocationFixRequesting)?
    private let clock: any RouteClock
    private let interval: Duration
    private var sceneActive = false
    private var task: Task<Void, Never>?

    /// The last fix was software-simulated.
    public private(set) var deviceSimulating = false
    public var isRefreshing: Bool { task != nil }

    public init(source: any RealLocationFixRequesting, clock: any RouteClock = ContinuousRouteClock(),
                interval: Duration = RealLocationRefresher.interval) {
        self.source = source; self.clock = clock; self.interval = interval
    }

    /// Something needs a current fix now: Recenter, a joystick origin, or a
    /// confirmed GPS clear. It retries real GPS even after a simulated fix.
    public func refreshNow() {
        deviceSimulating = false
        stop()
        if sceneActive { startLoop() } else { source?.requestFix() }
    }

    public func sceneDidBecomeActive() {
        sceneActive = true
        refreshNow()
    }

    public func sceneDidBecomeInactive() {
        sceneActive = false
        stop()
    }

    public func fixReceived(simulated: Bool) {
        deviceSimulating = simulated
        if simulated { stop() }
        else if sceneActive, task == nil { startLoop() }
    }

    private func startLoop() {
        let clock = clock, interval = interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                self?.source?.requestFix()
                do { try await clock.sleep(for: interval) } catch { return }
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
