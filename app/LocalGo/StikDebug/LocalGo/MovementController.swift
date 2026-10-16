import Combine
import Foundation

public enum MovementState: Equatable, Sendable {
    case idle, running, paused, joystick, completed, failed
}

/// One foreground motion producer, sharing the coordinator's serialized engine.
@MainActor
public final class MovementController: ObservableObject {
    @Published public private(set) var state: MovementState = .idle
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var distanceMeters: Double = 0
    @Published public private(set) var position: GeoPoint?
    @Published public private(set) var headingDegrees: Double = 0
    public var speed: Double = 2
    public var repeats = false

    private let commands: LocationCommandCoordinator
    private let ready: @MainActor () -> Bool
    private let automaticScheduling: Bool
    private var task: Task<Void, Never>?
    private var phaseChanges: AnyCancellable?
    private var path: RoutePath?
    private var reversing = false
    private var endpointPending = false
    private var throttle: Double = 1
    private(set) var generation: UInt64 = 0

    public init(commands: LocationCommandCoordinator,
                automaticScheduling: Bool = true,
                ready: @escaping @MainActor () -> Bool) {
        self.commands = commands
        self.automaticScheduling = automaticScheduling
        self.ready = ready
        phaseChanges = commands.$phase.sink { [weak self] phase in
            self?.didReceive(phase)
        }
    }

    public var isActive: Bool { state == .running || state == .joystick }

    @discardableResult
    public func start(_ route: RoutePath) -> Bool {
        guard canSend else { return false }
        invalidateScheduler()
        path = route
        reversing = false
        endpointPending = false
        distanceMeters = 0
        progress = 0
        position = route.points[0]
        if route.points.count > 1 {
            updateHeading(from: route.points[0], to: route.points[1])
        }
        state = .running
        let token = generation
        submit(route.points[0], token: token)
        schedule(token: token)
        return true
    }

    public func pause() {
        guard state == .running else { return }
        invalidateScheduler()
        state = .paused
        // At most one already-issued coordinate may still acknowledge.
    }

    @discardableResult
    public func resume() -> Bool {
        guard state == .paused, path != nil, canSend else { return false }
        invalidateScheduler()
        state = .running
        if endpointPending { finishEndpoint() }
        if state == .running { schedule(token: generation) }
        return true
    }

    @discardableResult
    public func updateJoystick(origin: GeoPoint, x: Double, y: Double) -> Bool {
        guard x.isFinite, y.isFinite else { return false }
        let amount = min(1, hypot(x, y))
        guard amount > 0.08 else {
            if state == .joystick {
                throttle = 0
            }
            return true
        }
        if state != .joystick {
            guard canSend else { return false }
            invalidateScheduler()
            path = nil
            endpointPending = false
            position = origin
            distanceMeters = 0
            progress = 0
            state = .joystick
            submit(origin, token: generation)
            schedule(token: generation)
        }
        headingDegrees = Self.normalizedHeading(atan2(x, y) * 180 / .pi)
        throttle = amount
        return true
    }

    public func endJoystick() {
        guard state == .joystick else { return }
        invalidateScheduler()
        state = .idle
    }

    public func cancelMotion() {
        invalidateScheduler()
        path = nil
        endpointPending = false
        state = .idle
    }

    public func stop(forceClear: Bool = false) {
        cancelMotion()
        commands.stop(forceClear: forceClear)
    }

    public func backgrounded() {
        if state == .running { pause() }
        else if state == .joystick { endJoystick() }
        else { invalidateScheduler() }
        // Hold the last issued pose so another app can inspect it. The OS may
        // still invalidate the device service; this is not background motion.
    }

    private var canSend: Bool {
        ready() && (commands.phase == .idle || commands.phase == .accepted)
    }

    private func invalidateScheduler() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    private func schedule(token: UInt64) {
        guard automaticScheduling else { return }
        task = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
                guard !Task.isCancelled, let self, token == self.generation else { return }
                let now = clock.now
                let elapsed = previous.duration(to: now).components
                previous = now
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                self.tick(elapsed: seconds, token: token)
            }
        }
    }

    /// The timer supplies elapsed time; tests can drive the same admission path.
    func tick(elapsed: Double, token: UInt64) {
        guard token == generation, isActive, elapsed.isFinite, elapsed > 0 else { return }
        guard ready() else {
            invalidateScheduler()
            state = .failed
            return
        }
        guard canSend, !endpointPending else { return }
        let meters = min(28, max(0.5, speed.isFinite ? speed : 2)) * min(1, elapsed)
        if state == .joystick, let position {
            guard throttle > 0 else { return }
            let next = position.moved(distanceMeters: meters * throttle, headingDegrees: headingDegrees)
            distanceMeters += meters * throttle
            self.position = next
            submit(next, token: token)
        } else if state == .running, let path {
            distanceMeters = min(path.lengthMeters, distanceMeters + meters)
            progress = distanceMeters / path.lengthMeters
            let alongPath = reversing ? path.lengthMeters - distanceMeters : distanceMeters
            let next = path.point(atDistanceMeters: alongPath)
            if let previous = position {
                updateHeading(from: previous, to: next)
            }
            position = next
            endpointPending = distanceMeters >= path.lengthMeters
            submit(next, token: token)
        }
    }

    private func submit(_ point: GeoPoint, token: UInt64) {
        // No suspension between generation/readiness admission and enqueue.
        guard token == generation, isActive, canSend else { return }
        commands.apply(latitude: point.latitude, longitude: point.longitude)
    }

    private func didReceive(_ phase: LocationCommandPhase) {
        if phase == .clearing {
            cancelMotion()
            return
        }
        if phase == .unknownFailure {
            invalidateScheduler()
            state = .failed
            return
        }
        if phase == .accepted, endpointPending, state == .running {
            finishEndpoint()
        }
    }

    private func finishEndpoint() {
        if repeats {
            reversing.toggle()
            distanceMeters = 0
            progress = 0
            endpointPending = false
        } else {
            invalidateScheduler()
            state = .completed
        }
    }

    private func updateHeading(from start: GeoPoint, to end: GeoPoint) {
        guard start.distance(to: end) > 0.001 else { return }

        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        guard hypot(x, y) > 1e-12 else { return }
        headingDegrees = Self.normalizedHeading(atan2(y, x) * 180 / .pi)
    }

    private static func normalizedHeading(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}
