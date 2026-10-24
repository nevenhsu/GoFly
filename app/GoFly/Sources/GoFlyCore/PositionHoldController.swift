import Combine
import Foundation

public enum PositionHoldPhase: String, Equatable, Sendable {
    case idle
    case preparing
    case running
    case paused
    case unknown
    case completed
}

/// Keeps the device at the coordinate that was most recently confirmed by a
/// point operation. The controller owns one joystick lease for the lifetime of
/// one finite hold and ends it at the configured duration.
@MainActor
public final class PositionHoldController: ObservableObject {
    @Published public private(set) var phase: PositionHoldPhase = .idle
    @Published public private(set) var isRecoveringConnection = false
    @Published public private(set) var intent: JoystickMovementIntent?
    @Published public private(set) var elapsedSeconds: Double = 0
    @Published public private(set) var completedCycles: Int64 = 0

    public var continuationControlEvents: AnyPublisher<MovementContinuationControlEvent, Never> {
        continuationSubject.eraseToAnyPublisher()
    }
    public var movementAcknowledgements: AnyPublisher<MovementAcknowledgement, Never> {
        acknowledgementSubject.eraseToAnyPublisher()
    }

    /// A retry is deliberately a new point operation. It is the only way to
    /// resume a paused hold and therefore creates a new point and joystick
    /// lease through ServiceController.
    public var canRetry: Bool {
        foreground && (phase == .paused || phase == .completed) && lastPlace != nil && service.canTeleport && !service.nativeBusy
    }

    private let service: ServiceController
    private let clock: any RouteClock
    private let interval: Duration
    private let cadence: Duration
    private let maximumAcknowledgementGap: Duration
    private let continuationSubject = PassthroughSubject<MovementContinuationControlEvent, Never>()
    private let acknowledgementSubject = PassthroughSubject<MovementAcknowledgement, Never>()
    private var subscriptions: [AnyCancellable] = []
    private var work: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var foreground = true
    private var continuationIdentity: MovementContinuationIdentity?
    private var lastPlace: MapPlace?
    private var lastAcknowledgementAt: Duration?
    private var acknowledgedDuration: Duration = .zero
    private var acknowledgedWholeSeconds: Int64 = 0
    private var nextSequence: UInt64 = 1

    public init(service: ServiceController,
                clock: any RouteClock = ContinuousRouteClock(),
                interval: Duration = .seconds(43_200),
                cadence: Duration = .seconds(5),
                maximumAcknowledgementGap: Duration = .seconds(15)) {
        self.service = service
        self.clock = clock
        self.interval = min(interval > .zero ? interval : .seconds(43_200), .seconds(43_200))
        self.cadence = cadence > .zero ? cadence : .seconds(5)
        self.maximumAcknowledgementGap = maximumAcknowledgementGap > .zero
            ? maximumAcknowledgementGap : .seconds(15)
        subscriptions = [
            service.teleportAcknowledgements.sink { [weak self] acknowledgement in
                self?.receive(acknowledgement)
            },
            service.joystickEvents.sink { [weak self] event in
                self?.receive(event)
            }
        ]
    }

    /// The facade calls this when the app enters the foreground. A paused
    /// target remains paused; only retry starts a new point operation.
    public func sceneDidBecomeActive() {
        foreground = true
    }

    /// A valid continuation lease allows the current owner to keep dispatching
    /// while the scene is inactive. The lease must also be bound in the
    /// service authority, so a caller cannot manufacture background admission.
    public func releaseForInactiveScene(continuingLease: MovementTaskLease? = nil) {
        foreground = false
        guard phase == .running, let operation = intent,
              continuingLease == operation.lease,
              (service.movementAuthority.permitsDispatch(for: operation.lease)
                || (isRecoveringConnection && service.movementAuthority.permitsConnectionRepair(for: operation.lease))) else {
            if phase == .running || phase == .preparing { pause(reason: .userPaused) }
            return
        }
    }

    /// Runtime loss closes the eligibility window. Any open ACK interval is
    /// discarded by pause(), and no command is submitted until retry creates a
    /// new point and lease.
    public func continuationDidBecomeUnavailable() {
        if phase == .running || phase == .preparing { pause(reason: .userPaused) }
    }

    @discardableResult
    public func retry() -> Bool {
        guard canRetry, let place = lastPlace else { return false }
        let savedIntent = intent
        let savedPhase = phase

        // The service emits the old owner's ended event synchronously while it
        // admits the new point. Fence this generation before entering it so a
        // stale event or preparation result cannot touch the new hold.
        invalidateWork()
        phase = .idle
        intent = nil
        continuationIdentity = nil

        guard service.teleport(to: TeleportCandidate(place: place)) else {
            intent = savedIntent
            phase = savedPhase
            return false
        }
        return true
    }

    func suspendForConnectionRecovery() -> Bool {
        if isRecoveringConnection { return true }
        guard phase == .running else { return false }
        isRecoveringConnection = true
        invalidateWork()
        lastAcknowledgementAt = nil
        return true
    }

    func finishConnectionRecovery(succeeded: Bool) {
        guard isRecoveringConnection, let operation = intent else { return }
        isRecoveringConnection = false
        guard succeeded else { pause(reason: .userPaused); return }
        // The repair is a fresh timing baseline, not acknowledged execution
        // time during the connection outage.
        lastAcknowledgementAt = clock.now
        let token = generation
        work = Task { [weak self] in await self?.run(operation: operation, token: token) }
    }

    private func receive(_ acknowledgement: TeleportAcknowledgement) {
        // The service publishes the acknowledgement from the same main-actor
        // completion stack that clears nativeBusy. Start asynchronously and
        // let beginPositionHold perform the atomic post-ACK admission check.
        guard foreground, phase == .idle || phase == .completed else { return }
        start(after: acknowledgement)
    }

    private func start(after acknowledgement: TeleportAcknowledgement) {
        invalidateWork()
        generation &+= 1
        let token = generation
        let operation = JoystickMovementIntent(lease: acknowledgement.lease,
                                               fixedPosition: acknowledgement.coordinate)
        intent = operation
        lastPlace = acknowledgement.intent.candidate.place
        phase = .preparing
        lastAcknowledgementAt = nil
        acknowledgedDuration = .zero
        acknowledgedWholeSeconds = 0
        completedCycles = 0
        elapsedSeconds = 0
        nextSequence = 1

        let identity = MovementContinuationIdentity(movementID: operation.id, lease: operation.lease)
        continuationIdentity = identity
        continuationSubject.send(.requested(MovementContinuationDemand(
            movementID: operation.id,
            lease: operation.lease,
            kind: .fixedPosition,
            goal: .finiteDuration(seconds: goalIntervalSeconds))))

        work = Task { [weak self] in
            guard let self else { return }
            let preparation = await self.service.beginPositionHold(after: acknowledgement, intent: operation)
            guard self.isCurrent(token, operation), self.phase == .preparing else { return }
            guard preparation == .prepared else {
                self.finishWithoutOwner(token: token, operation: operation)
                return
            }
            guard self.isEligible(operation, allowUnknownHealth: true),
                  let input = self.service.joystickInputRevision(executionID: operation.id,
                                                                  lease: operation.lease) else {
                self.pause(reason: .userPaused)
                return
            }
            guard await self.send(operation: operation, token: token, input: input) else { return }
            await self.run(operation: operation, token: token)
        }
    }

    private func run(operation: JoystickMovementIntent, token: UInt64) async {
        while isCurrent(token, operation), phase == .running, !Task.isCancelled {
            do {
                try await clock.sleep(for: cadence)
            } catch {
                return
            }
            guard isCurrent(token, operation), phase == .running, !Task.isCancelled else { return }
            guard isEligible(operation),
                  nextSequence < UInt64.max,
                  let input = service.joystickInputRevision(executionID: operation.id,
                                                            lease: operation.lease) else {
                pause(reason: .userPaused)
                return
            }
            guard await send(operation: operation, token: token, input: input) else { return }
        }
    }

    private func send(operation: JoystickMovementIntent, token: UInt64,
                      input: JoystickInputRevision) async -> Bool {
        guard isCurrent(token, operation), phase == .running || phase == .preparing,
              let coordinate = operation.fixedPosition else { return false }
        let sequence = nextSequence
        let outcome = await service.sendJoystickStep(
            executionID: operation.id,
            lease: operation.lease,
            sequence: sequence,
            expectedInputRevision: input,
            recipe: .fixedPosition(coordinate))
        guard isCurrent(token, operation), phase == .running || phase == .preparing else { return false }

        switch outcome {
        case .acknowledged(let receipt):
            guard receipt.actualCoordinate == coordinate else {
                markUnknown(operation: operation, failure: .serviceUnavailable)
                return false
            }
            phase = .running
            guard acceptAcknowledgement(operation: operation, token: token) else { return false }
            nextSequence &+= 1
            return true
        case .unconfirmed(let failure):
            markUnknown(operation: operation, failure: failure)
            return false
        case .notSent(let failure):
            // ServiceController emits interrupted/ended for an unsent native
            // command. If it did not, pausing still prevents any further write.
            if phase == .running { pause(reason: .userPaused) }
            diagnose("positionHold.stepNotSent", level: .notice, [
                "failure": .text(failure.localizationKey)
            ])
            return false
        case .inputCancelled, .cancelled:
            if phase == .running { pause(reason: .userPaused) }
            return false
        }
    }

    private func acceptAcknowledgement(operation: JoystickMovementIntent, token: UInt64) -> Bool {
        guard isEligible(operation, allowUnknownHealth: lastAcknowledgementAt == nil),
              isCurrent(token, operation) else { return false }
        let now = clock.now
        var completes = false
        if let previous = lastAcknowledgementAt {
            guard now >= previous else {
                pause(reason: .userPaused)
                return false
            }
            let gap = now - previous
            guard gap <= maximumAcknowledgementGap else {
                pause(reason: .userPaused)
                return false
            }
            if gap > .zero {
                let remaining = interval - acknowledgedDuration
                let credited = min(gap, remaining)
                acknowledgedDuration = addClamped(acknowledgedDuration, credited)
                acknowledgedWholeSeconds = addClamped(acknowledgedWholeSeconds, credited.components.seconds)
                completes = acknowledgedDuration >= interval
                if completes {
                    acknowledgedDuration = interval
                    acknowledgedWholeSeconds = interval.components.seconds
                    completedCycles = 1
                }
            }
        }
        lastAcknowledgementAt = now
        elapsedSeconds = secondsBridge(acknowledgedDuration)
        acknowledgementSubject.send(MovementAcknowledgement(
            movementID: operation.id,
            lease: operation.lease,
            sequence: nextSequence,
            source: .fixedPosition,
            acknowledgedDistanceMeters: 0,
            routePositionMeters: nil,
            finiteArrival: completes,
            cumulativeAcknowledgedDurationSeconds: elapsedSeconds))
        if completes, isCurrent(token, operation), phase == .running {
            phase = .completed
            finishCompleted(operation: operation)
        }
        return true
    }

    private func receive(_ event: JoystickCommandEvent) {
        guard let operation = intent else { return }
        switch event {
        case .movementBoundary(let lease):
            // Boundaries for our own claimed write are normal. A foreign or
            // nil boundary is the service's supersession/stop fence.
            guard let lease, lease == operation.lease else {
                finishEnded(operation: operation)
                return
            }
        case .ended(let id):
            guard id == operation.id else { return }
            guard phase != .completed else { return }
            finishEnded(operation: operation)
        case .unknown(let id, let failure):
            guard id == operation.id else { return }
            markUnknown(operation: operation, failure: failure)
        case .interrupted(let id, let failure):
            guard id == operation.id else { return }
            diagnose("positionHold.interrupted", level: .notice,
                ["failure": .text(failure.localizationKey)])
            pause(reason: .userPaused)
        case .availabilityChanged:
            guard !isRecoveringConnection else { return }
            guard phase == .running || phase == .preparing else { return }
            if !service.movementConnectionAvailable { pause(reason: .userPaused) }
        }
    }

    private func pause(reason: MovementContinuationWithdrawalReason) {
        guard phase == .running || phase == .preparing, let operation = intent else { return }
        if isRecoveringConnection { service.cancelConnectionRecovery(); isRecoveringConnection = false }
        invalidateWork()
        phase = .paused
        if service.movementAuthority.snapshot.lease == operation.lease {
            service.markSimulationPositionUnverified()
        }
        if service.joystickInputRevision(executionID: operation.id, lease: operation.lease) != nil {
            _ = service.releaseJoystick(executionID: operation.id, lease: operation.lease, disposition: .pause)
        }
        withdraw(reason)
    }

    private func markUnknown(operation: JoystickMovementIntent, failure: DeviceServiceFailure) {
        guard intent?.id == operation.id else { return }
        invalidateWork()
        phase = .unknown
        diagnose("positionHold.unknown", level: .error, ["failure": .text(failure.rawValue)])
        withdraw(.ended)
    }

    private func finishEnded(operation: JoystickMovementIntent) {
        isRecoveringConnection = false
        guard intent?.id == operation.id else { return }
        invalidateWork()
        phase = .idle
        intent = nil
        lastPlace = nil
        withdraw(.ended)
    }

    private func finishCompleted(operation: JoystickMovementIntent) {
        guard intent?.id == operation.id, phase == .completed else { return }
        invalidateWork()
        if service.movementAuthority.snapshot.lease == operation.lease {
            service.markSimulationPositionUnverified()
        }
        _ = service.releaseJoystick(executionID: operation.id, lease: operation.lease, disposition: .endGesture)
        withdraw(.ended)
    }

    private func finishWithoutOwner(token: UInt64, operation: JoystickMovementIntent) {
        guard isCurrent(token, operation) else { return }
        phase = .idle
        intent = nil
        lastPlace = nil
        withdraw(.ended)
        work = nil
    }

    private func withdraw(_ reason: MovementContinuationWithdrawalReason) {
        guard let identity = continuationIdentity else { return }
        continuationIdentity = nil
        continuationSubject.send(.withdrawn(identity, reason))
    }

    private func invalidateWork() {
        generation &+= 1
        work?.cancel()
        work = nil
    }

    private func isCurrent(_ token: UInt64, _ operation: JoystickMovementIntent) -> Bool {
        generation == token && intent?.id == operation.id && intent?.lease == operation.lease
    }

    private func isEligible(_ operation: JoystickMovementIntent, allowUnknownHealth: Bool = false) -> Bool {
        let snapshot = service.movementAuthority.snapshot
        guard service.movementConnectionAvailable,
              snapshot.lease == operation.lease,
              snapshot.runState == .running else { return false }
        if allowUnknownHealth {
            guard snapshot.health == .confirmedHealthy || snapshot.health == .unknown else { return false }
        } else {
            guard snapshot.health == .confirmedHealthy else { return false }
        }
        return foreground || service.movementAuthority.permitsDispatch(for: operation.lease)
    }

    private var goalIntervalSeconds: Double {
        secondsBridge(interval)
    }

    private func secondsBridge(_ duration: Duration) -> Double {
        let components = duration.components
        let value = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return value.isFinite ? max(0, value) : Double.greatestFiniteMagnitude
    }

    private func addClamped(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        guard rhs > 0 else { return lhs }
        if lhs > Int64.max - rhs { return Int64.max }
        return lhs + rhs
    }

    private func addClamped(_ lhs: Duration, _ rhs: Duration) -> Duration {
        guard rhs > .zero else { return lhs }
        let left = lhs.components
        let right = rhs.components
        if left.seconds > Int64.max - right.seconds {
            return Duration(secondsComponent: Int64.max, attosecondsComponent: 999_999_999_999_999_999)
        }
        var seconds = left.seconds + right.seconds
        var attoseconds = left.attoseconds + right.attoseconds
        if attoseconds >= 1_000_000_000_000_000_000 {
            if seconds == Int64.max {
                return Duration(secondsComponent: Int64.max, attosecondsComponent: 999_999_999_999_999_999)
            }
            seconds += 1
            attoseconds -= 1_000_000_000_000_000_000
        }
        return Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
    }

    private func diagnose(_ name: String, level: DiagnosticsLevel,
                          _ fields: [String: DiagnosticsField] = [:]) {
        Diagnostics.shared.record(name, category: .movement, level: level, fields)
    }

    deinit { work?.cancel() }
}
