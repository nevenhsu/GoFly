import Combine
import Foundation

public enum JoystickMovementPhase: String, Equatable, Sendable {
    case neutral, preparing, moving, settling, pausing, paused, interrupted, unknown
}

@MainActor
public final class JoystickMovementController: ObservableObject {
    @Published public private(set) var phase: JoystickMovementPhase = .neutral
    @Published public private(set) var speed: RouteSpeed
    @Published public private(set) var input: JoystickInput?
    @Published public private(set) var activeGestureID: UUID?
    @Published public private(set) var intent: JoystickMovementIntent?
    @Published public private(set) var lastAcknowledgedCoordinate: GeoCoordinate?
    @Published public private(set) var lastAcknowledgedBearingDegrees: Double?
    @Published public private(set) var error: JoystickFailure?
    public var displayBearingDegrees: Double? { input?.bearingDegrees ?? lastAcknowledgedBearingDegrees }
    public var canBeginGesture: Bool { phase == .neutral && commands.canBeginJoystick && !requiresOrigin }
    public var requiresOrigin: Bool { commands.currentJoystickOrigin == nil }
    public var requiresStop: Bool { phase == .unknown }
    public var canPause: Bool { phase == .moving && hasAcknowledgedLease }
    public var canResume: Bool { phase == .paused }
    public var canSetSpeed: Bool { [.neutral, .preparing, .moving, .paused, .interrupted].contains(phase) }
    private let commands: any JoystickCommanding
    private let clock: any RouteClock
    private var task: Task<Void, Never>?
    private var transition: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var generation: UInt64 = 0
    private var settlementRevision: UInt64 = 0
    private var hasAcknowledgedLease = false
    private var resumedNeutralIntent: JoystickMovementIntent?
    private static let cadence: Duration = .milliseconds(500)

    public init(commands: any JoystickCommanding, clock: any RouteClock = ContinuousRouteClock(), speed: RouteSpeed = .standard) {
        self.commands = commands; self.clock = clock; self.speed = speed
        subscription = commands.joystickEvents.sink { [weak self] event in self?.receive(event) }
    }

    @discardableResult public func beginGesture(id: UUID, input: JoystickInput) -> Bool {
        guard canBeginGesture, input.strength > 0 else { return false }
        generation &+= 1
        let token = generation, operation = JoystickMovementIntent(), admission = commands.movementAdmissionRevision
        intent = operation; activeGestureID = id; self.input = input; error = nil
        hasAcknowledgedLease = false; phase = .preparing
        task = Task { [weak self] in
            guard let self, self.generation == token, self.phase == .preparing, !Task.isCancelled else { return }
            let outcome = await self.commands.beginJoystick(operation, expectedMovementAdmissionRevision: admission)
            guard self.generation == token, self.phase == .preparing, !Task.isCancelled else { return }
            switch outcome {
            case .prepared:
                self.phase = .moving
                await self.run(operation, token: token)
            case .cancelled: self.returnToNeutral()
            }
        }
        return true
    }

    @discardableResult public func updateGesture(id: UUID, input: JoystickInput) -> Bool {
        guard activeGestureID == id, let intent, phase == .preparing || phase == .moving else { return false }
        guard input.strength > 0 else { return endGesture(id: id) }
        guard self.input != input else { return true }
        _ = commands.reviseJoystickInput(executionID: intent.id, lease: intent.lease)
        self.input = input
        return true
    }
    @discardableResult public func setSpeed(_ speed: RouteSpeed) -> Bool {
        guard canSetSpeed else { return false }
        guard self.speed != speed else { return true }
        if input != nil, let intent { _ = commands.reviseJoystickInput(executionID: intent.id, lease: intent.lease) }
        self.speed = speed
        return true
    }

    @discardableResult public func endGesture(id: UUID) -> Bool {
        guard activeGestureID == id, let intent, phase == .preparing || phase == .moving else { return false }
        settle(intent, disposition: .endGesture)
        return true
    }

    @discardableResult public func pause() -> Bool {
        guard canPause, let intent,
              commands.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .pause) else { return false }
        settle(intent, disposition: .pause, alreadyReleased: true)
        return true
    }
    @discardableResult public func resume() -> Bool {
        guard canResume, let intent, commands.resumeJoystick(executionID: intent.id, lease: intent.lease) else { return false }
        generation &+= 1
        resumedNeutralIntent = intent
        phase = .neutral; input = nil; activeGestureID = nil
        return true
    }
    public func releaseForInactiveScene() {
        // A new preclaim gesture has not replaced the resumed healthy owner yet.
        if let neutral = resumedNeutralIntent, neutral.id != intent?.id {
            if commands.releaseJoystick(executionID: neutral.id, lease: neutral.lease, disposition: .endGesture) {
                resumedNeutralIntent = nil
            }
        }
        guard let intent, phase != .unknown, phase != .settling else { return }
        settle(intent, disposition: .endGesture)
    }
    public func clearError() { if !requiresStop { error = nil } }

    private func settle(_ operation: JoystickMovementIntent, disposition: JoystickReleaseDisposition, alreadyReleased: Bool = false) {
        input = nil; activeGestureID = nil
        phase = disposition == .pause ? .pausing : .settling
        settlementRevision &+= 1
        let settlementToken = settlementRevision
        let token = generation, running = task
        running?.cancel()
        if !alreadyReleased { commands.releaseJoystick(executionID: operation.id, lease: operation.lease, disposition: disposition) }
        transition = Task { [weak self] in
            guard let self else { return }
            let settlement = await self.commands.waitForJoystickIdle(executionID: operation.id, lease: operation.lease)
            await running?.value
            guard self.generation == token, self.settlementRevision == settlementToken, self.intent?.id == operation.id else { return }
            switch settlement {
            case .requiresStop(let failure): self.markUnknown(failure)
            case .settled:
                guard self.phase != .unknown else { return }
                if disposition == .pause { self.phase = .paused }
                else { self.returnToNeutral() }
            }
        }
    }

    private func run(_ operation: JoystickMovementIntent, token: UInt64) async {
        var sequence: UInt64 = 1
        while generation == token, phase == .moving, !Task.isCancelled {
            do { try await clock.sleep(for: Self.cadence) } catch { return }
            guard generation == token, phase == .moving, !Task.isCancelled,
                  let input, let displacement = input.displacement(speed: speed),
                  let revision = commands.joystickInputRevision(executionID: operation.id, lease: operation.lease) else { return }
            let outcome = await commands.sendJoystickStep(executionID: operation.id, lease: operation.lease,
                sequence: sequence, expectedInputRevision: revision, displacement: displacement)
            guard generation == token, intent?.id == operation.id, phase != .unknown else { return }
            switch outcome {
            case .acknowledged(let coordinate):
                sequence &+= 1
                lastAcknowledgedCoordinate = coordinate
                lastAcknowledgedBearingDegrees = displacement.bearingDegrees
                hasAcknowledgedLease = true
            case .inputCancelled: break
            case .cancelled:
                if phase == .moving { returnToNeutral() }
                return
            case .notSent(let failure):
                error = failure
                commands.releaseJoystick(executionID: operation.id, lease: operation.lease, disposition: .endGesture)
                returnToNeutral()
                return
            case .unconfirmed(let failure): markUnknown(failure); return
            }
        }
    }

    private func markUnknown(_ failure: DeviceServiceFailure) {
        phase = .unknown; error = .device(failure); input = nil; activeGestureID = nil
        task?.cancel()
    }
    private func returnToNeutral() {
        if resumedNeutralIntent?.id == intent?.id { resumedNeutralIntent = nil }
        phase = .neutral; input = nil; activeGestureID = nil; intent = nil; hasAcknowledgedLease = false
    }
    private func receive(_ event: JoystickCommandEvent) {
        switch event {
        case .availabilityChanged: objectWillChange.send()
        case .ended(let id):
            if resumedNeutralIntent?.id == id { resumedNeutralIntent = nil }
            guard intent?.id == id else { return }
            // Release waits for its actual call to return before accepting another gesture.
            guard phase != .settling && phase != .pausing else { return }
            generation &+= 1; task?.cancel(); returnToNeutral()
        case .unknown(let id, let failure):
            guard intent?.id == id else { return }
            markUnknown(failure)
        case .interrupted(let id, let failure):
            guard intent?.id == id, phase != .unknown else { return }
            phase = .interrupted; error = failure; input = nil; activeGestureID = nil; task?.cancel()
        }
    }

    deinit { task?.cancel(); transition?.cancel() }
}
