import Combine
import Foundation

@MainActor
public final class ServiceController: ObservableObject, RouteCommanding, JoystickCommanding {
    @Published public private(set) var phase: ServicePhase = .stopped
    @Published public private(set) var nativeBusy = false
    @Published public private(set) var error: DeviceServiceFailure?
    @Published public private(set) var clearState: ClearState = .unknown
    @Published public private(set) var clearConfirmedAt: Date?
    @Published public private(set) var realLocation: RealLocationObservation?
    @Published public private(set) var pointState: PointMoveState = .idle
    @Published public private(set) var confirmedSimulatedLocation: GeoCoordinate?
    @Published public private(set) var preparedOperation: PreparedOperationSnapshot?
    /// TCP reachability is an admission signal only. It never claims native
    /// service health or changes the current task lease.
    @Published public private(set) var movementConnectionAvailable = true
    @Published public private(set) var coldRecoveryHeld = false

    private struct DisplayedPosition {
        let coordinate: GeoCoordinate
        let source: PositionSource
    }
    private struct PointContext: Sendable {
        let intent: PointMoveIntent
        let dispatch: PointDispatchGate
        let wasReady: Bool
        let lease: MovementTaskLease
    }
    private struct PreparationContext: Sendable {
        let id: UUID
        let source: PreparedOperationSource
        let dispatch: PointDispatchGate
        let wasReady: Bool
    }
    private enum CommandResult: Sendable {
        case success
        case failure(DeviceServiceFailure)
        case point(PointDeliveryOutcome)
    }

    public let movementAuthority: MovementTaskAuthority
    private struct AdapterCommand {
        let work: @MainActor @Sendable (any DeviceService) async -> CommandResult
        let completion: @MainActor (CommandResult) -> Void
    }
    private final class RouteOwner {
        let intent: RouteExecutionIntent
        let stopGeneration: UInt64
        var begun = false
        var ended = false
        var unknown = false
        var unknownFailure: DeviceServiceFailure?
        var interrupted = false
        var pendingCalls = 0
        var lastSequence: UInt64 = 0
        var controlRevision: UInt64 = 0
        var begin: CheckedContinuation<RouteCommandOutcome, Never>?
        var idle: [CheckedContinuation<RouteIdleSettlement, Never>] = []
        var tick: RouteTick?
        init(_ intent: RouteExecutionIntent, stopGeneration: UInt64, begin: CheckedContinuation<RouteCommandOutcome, Never>) {
            self.intent = intent; self.stopGeneration = stopGeneration; self.begin = begin
        }
    }
    private final class RouteTick {
        let gate: PointDispatchGate
        let coordinate: GeoCoordinate
        let sequence: UInt64
        var timedOut = false
        var controlCancelled = false
        var skipped = false
        var didInvalidateProof = false
        var watchdog: Task<Void, Never>?
        init(gate: PointDispatchGate, coordinate: GeoCoordinate, sequence: UInt64) {
            self.gate = gate; self.coordinate = coordinate; self.sequence = sequence
        }
    }
    private final class JoystickOwner {
        let intent: JoystickMovementIntent
        let stopGeneration: UInt64
        var prepared = false
        var installed = false
        var neutral = false
        var paused = false
        var ended = false
        var unknownFailure: DeviceServiceFailure?
        var pendingCalls = 0
        var lastSequence: UInt64 = 0
        var tick: JoystickTick?
        var disposition: JoystickReleaseDisposition?
        var idle: [CheckedContinuation<JoystickIdleSettlement, Never>] = []
        var inputRevision = JoystickInputRevision()
        var begin: CheckedContinuation<JoystickPreparationOutcome, Never>?
        init(_ intent: JoystickMovementIntent, stopGeneration: UInt64,
             begin: CheckedContinuation<JoystickPreparationOutcome, Never>) {
            self.intent = intent; self.stopGeneration = stopGeneration; self.begin = begin
        }
    }
    private final class JoystickTick {
        let sequence: UInt64
        let input: JoystickInputRevision
        var origin: GeoCoordinate?
        var gate: PointDispatchGate?
        var receipt: JoystickStepReceipt?
        var failure: JoystickFailure?
        var inputCancelled = false
        var timedOut = false
        var didInvalidateProof = false
        var watchdog: Task<Void, Never>?
        init(sequence: UInt64, input: JoystickInputRevision) {
            self.sequence = sequence; self.input = input
        }
    }
    private var joystickUnconfirmed = false
    private var joystickOwners: [UUID: JoystickOwner] = [:]
    private let joystickSubject = PassthroughSubject<JoystickCommandEvent, Never>()
    private let movementAcknowledgementSubject = PassthroughSubject<MovementAcknowledgement, Never>()
    public private(set) var routeAdmissionRevision: UInt64 = 0
    private let routeSubject = PassthroughSubject<RouteCommandEvent, Never>()
    private var routeOwners: [UUID: RouteOwner] = [:]
    private var routeUnconfirmed = false
    private var routeStopGeneration: UInt64 = 0
    private let service: any DeviceService
    private let operationTimeout: Duration
    private let watchdogSleep: @MainActor @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date
    private var revision: UInt64 = 0
    private var outstandingWork = 0
    private var clearScheduled = false
    private var clearAttempted = false
    private var lastDisplayedPosition: DisplayedPosition?
    private var didRestoreColdRecovery = false
    private var didPerformActualOperation = false
    private var currentPoint: PointContext?
    private var currentPreparation: PreparationContext?
    private var adapterQueue: [AdapterCommand] = []
    private var pumping = false
    private var watchdog: Task<Void, Never>?

    public init(
        service: any DeviceService, operationTimeout: Duration = .seconds(30),
        now: @escaping @Sendable () -> Date = { Date() },
        movementAuthority: MovementTaskAuthority = MovementTaskAuthority(),
        watchdogSleep: @escaping @MainActor @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.service = service
        self.movementAuthority = movementAuthority
        self.operationTimeout = operationTimeout
        self.watchdogSleep = watchdogSleep
        self.now = now
    }
    public var statusKey: String {
        if phase == .stopped, clearAttempted, clearState == .unknown {
            return "service.stoppedGPSPending"
        }
        return "service.\(phase.rawValue)"
    }
    public var gpsStatusKey: String {
        switch clearState {
        case .unknown: return "gps.unknown"
        case .pending: return "gps.clearing"
        case .confirmed:
            guard let realLocation, let clearConfirmedAt,
                  realLocation.observedAt >= clearConfirmedAt else { return "gps.clearedWaiting" }
            return "gps.observed"
        }
    }
    public var canStart: Bool { !nativeBusy && movementAdmissionAllowed && phase == .stopped }
    public var canStop: Bool {
        !clearScheduled && (phase == .ready || phase == .preparing || phase == .repairRequired)
    }
    public var canRestoreGPS: Bool { !nativeBusy && phase == .stopped }
    public var canResetTunnel: Bool { canRestoreGPS }
    public var canTeleport: Bool {
        !nativeBusy && movementAdmissionAllowed && !pointUnconfirmed && !routeUnconfirmed && !joystickUnconfirmed && (phase == .stopped || phase == .ready)
    }
    private var movementAdmissionAllowed: Bool { !movementAuthority.isAdmissionBlocked }
    private var pointUnconfirmed: Bool {
        if case .unconfirmed = pointState { return true }
        return false
    }

    /// Called by the coordinator after a real tunnel probe. The fence is
    /// linearized before available gates are invalidated so a queued native
    /// head cannot claim between the two operations.
    public func setMovementConnectionAvailable(_ available: Bool) {
        guard movementConnectionAvailable != available else { return }
        movementAuthority.setAdmissionFence(connectionBlocked: !available, coldRecoveryHeld: coldRecoveryHeld)
        routeAdmissionRevision &+= 1
        if !available { invalidateAvailableMovementGates() }
        // Published observers see the already-closed authority fence. This
        // avoids an admission race from an objectWillChange callback.
        movementConnectionAvailable = available
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
    }

    /// Updates the scene fence used by native claim admission. Scene changes
    /// do not revoke a live grant or pause an owner; the facade performs that
    /// lifecycle action after closing this fence.
    public func setMovementSceneActive(_ active: Bool) {
        movementAuthority.setSceneActive(active)
        routeAdmissionRevision &+= 1
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
    }

    /// Binds a concrete framework grant to the currently healthy native owner.
    /// The owner check is intentionally based on ServiceController state, so a
    /// caller cannot manufacture health by presenting a grant alone.
    @discardableResult
    public func bindMovementContinuation(_ grant: ContinuedProcessingGrant) -> Bool {
        guard grant.isValid, !clearScheduled, !routeUnconfirmed, !joystickUnconfirmed,
              let owner = movementOwner(movementID: grant.movementID, lease: grant.lease),
              owner.isHealthyRunning else { return false }
        return movementAuthority.bind(grant)
    }

    public func hasMovementContinuation(movementID: UUID, lease: MovementTaskLease,
                                        requestID: UUID) -> Bool {
        guard let owner = movementOwner(movementID: movementID, lease: lease), owner.isHealthyRunning else { return false }
        return movementAuthority.hasValidBinding(movementID: movementID, lease: lease, requestID: requestID)
    }

    /// Reports the exact runtime binding without treating a closed grant as
    /// dispatch-valid. Facades use this distinction to tell a trusted atomic
    /// resume apart from a binding that has already been retired.
    func movementContinuationIsBound(requestID: UUID, lease: MovementTaskLease) -> Bool {
        movementAuthority.bindingMatches(requestID: requestID, lease: lease)
    }

    private func pauseExpiredContinuation(movementID: UUID, lease: MovementTaskLease,
                                          result: CommandResult) -> Bool {
        // Only an explicitly unsent runtime denial is safe to pause. Claimed,
        // malformed, timed-out and uncertain native results keep their existing
        // interruption/recovery paths.
        switch result {
        case .point(.notSent(.operationCancelled)), .point(.notSent(.serviceUnavailable)),
             .failure(.operationCancelled), .failure(.serviceUnavailable): break
        default: return false
        }
        guard !clearScheduled, !routeUnconfirmed, !joystickUnconfirmed,
              movementOwner(movementID: movementID, lease: lease)?.isHealthyRunning == true,
              movementAuthority.pauseForClosedBinding(movementID: movementID, lease: lease) else { return false }
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
        return true
    }

    @discardableResult
    public func retireMovementContinuation(requestID: UUID, lease: MovementTaskLease,
                                           reason: MovementContinuationRetirement) -> Bool {
        guard movementAuthority.bindingMatches(requestID: requestID, lease: lease) else { return false }
        switch reason {
        case .ownerPausedOrEnded:
            if let owner = movementOwner(lease: lease) {
                guard !owner.isHealthyRunning else { return false }
            } else {
                let snapshot = movementAuthority.snapshot
                guard snapshot.lease != lease || snapshot.runState != .running ||
                      snapshot.health != .confirmedHealthy else { return false }
            }
        case .foregroundGoalChange:
            guard movementAuthority.isSceneActive,
                  let owner = movementOwner(lease: lease), owner.isHealthyRunning,
                  movementAuthority.hasValidBinding(movementID: owner.movementID,
                      lease: lease, requestID: requestID) else { return false }
        case .foregroundManualAfterAutoOff:
            guard movementAuthority.isSceneActive,
                  let owner = joystickOwners.values.first(where: {
                      $0.intent.lease == lease && $0.installed && !$0.ended && !$0.neutral &&
                      !$0.paused && $0.unknownFailure == nil
                  }),
                  let view = movementOwner(movementID: owner.intent.id, lease: lease),
                  view.isHealthyRunning else { return false }
        }
        return movementAuthority.retireBinding(requestID: requestID, lease: lease, reason: reason)
    }

    private struct MovementOwnerView {
        let movementID: UUID
        let isHealthyRunning: Bool
    }

    private func movementOwner(movementID: UUID, lease: MovementTaskLease) -> MovementOwnerView? {
        let snapshot = movementAuthority.snapshot
        if let owner = routeOwners[movementID], owner.intent.lease == lease {
            return MovementOwnerView(movementID: owner.intent.id,
                isHealthyRunning: owner.begun && !owner.ended && !owner.unknown &&
                    snapshot.lease == lease && snapshot.health == .confirmedHealthy &&
                    snapshot.runState == .running)
        }
        if let owner = joystickOwners[movementID], owner.intent.lease == lease {
            return MovementOwnerView(movementID: owner.intent.id,
                isHealthyRunning: owner.prepared && owner.installed && !owner.ended &&
                    !owner.paused && !owner.neutral && owner.unknownFailure == nil &&
                    snapshot.lease == lease && snapshot.health == .confirmedHealthy &&
                    snapshot.runState == .running)
        }
        return nil
    }

    private func movementOwner(lease: MovementTaskLease) -> MovementOwnerView? {
        if let owner = routeOwners.values.first(where: { $0.intent.lease == lease }) {
            return movementOwner(movementID: owner.intent.id, lease: lease)
        }
        if let owner = joystickOwners.values.first(where: { $0.intent.lease == lease }) {
            return movementOwner(movementID: owner.intent.id, lease: lease)
        }
        return nil
    }

    /// Applies a persisted snapshot as waiting display data only. It never
    /// creates a native owner, origin proof, lease, or automatic command.
    @discardableResult public func restoreColdRecovery(
        position: SessionDisplayPosition?, requiresConfirmation: Bool
    ) -> Bool {
        guard !didRestoreColdRecovery, phase == .stopped, !nativeBusy,
              outstandingWork == 0, currentPoint == nil, currentPreparation == nil,
              realLocation == nil, confirmedSimulatedLocation == nil,
              clearState != .confirmed, clearConfirmedAt == nil,
              !didPerformActualOperation,
              movementAuthority.snapshot.lease == nil,
              !routeOwners.values.contains(where: { !$0.ended || $0.pendingCalls > 0 }),
              !joystickOwners.values.contains(where: { !$0.ended || $0.pendingCalls > 0 }) else { return false }
        didRestoreColdRecovery = true
        if let position {
            lastDisplayedPosition = DisplayedPosition(coordinate: position.coordinate, source: position.source)
        }
        if requiresConfirmation { setColdRecoveryHeld(true) }
        return true
    }

    private func setColdRecoveryHeld(_ held: Bool) {
        guard coldRecoveryHeld != held else { return }
        movementAuthority.setAdmissionFence(connectionBlocked: !movementConnectionAvailable, coldRecoveryHeld: held)
        routeAdmissionRevision &+= 1
        if held { invalidateAvailableMovementGates() }
        // As with reachability, publish only after admission is fenced and
        // every currently available gate has been withdrawn.
        coldRecoveryHeld = held
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
    }

    private func invalidateAvailableMovementGates() {
        currentPreparation?.dispatch.invalidate()
        currentPoint?.dispatch.invalidate()
        for owner in routeOwners.values {
            owner.controlRevision &+= 1
            owner.tick?.gate.invalidate()
        }
        for owner in joystickOwners.values {
            owner.inputRevision = JoystickInputRevision()
            owner.tick?.gate?.invalidate()
        }
    }

    public var positionMarker: PositionMarker? {
        guard let position = lastDisplayedPosition else { return nil }
        let fresh: Bool
        switch position.source {
        case .gps:
            fresh = confirmedSimulatedLocation == nil && realLocation?.coordinate == position.coordinate
        case .simulation:
            fresh = confirmedSimulatedLocation == position.coordinate
        }
        return PositionMarker(coordinate: position.coordinate, source: position.source,
                              freshness: fresh ? .fresh : .waiting)
    }

    /// Read-only evidence for cold recovery. This projection observes only
    /// actual gate/pending/clear state and never performs native work.
    public var recoveryUncertainty: SessionMovementUncertainty? {
        // An accepted clear is itself the recovery boundary. Until its GPS
        // acknowledgement arrives, do not let a still-draining owner hide
        // the required recovery hold behind a lower-priority movement proof.
        if clearAttempted && clearState != .confirmed {
            return SessionMovementUncertainty(source: .gpsRecovery)
        }
        if let point = currentPoint,
           point.dispatch.hasDispatched || pointStateIsSendingOrUnconfirmed {
            return SessionMovementUncertainty(source: .point, requestedPlace: point.intent.candidate.place)
        }
        if let preparation = currentPreparation,
           case .route(let intent) = preparation.source,
           preparation.dispatch.hasDispatched {
            // Route preparation owns the first native write before a route
            // tick exists. A claimed gate is uncertainty evidence; a merely
            // queued prepare remains display-only and is intentionally absent.
            return SessionMovementUncertainty(source: .route, requestedPlace: requestedPlace(for: intent.draft))
        }
        if let owner = routeOwners.values.first(where: { routeOwnerHasUncertainty($0) }) {
            return SessionMovementUncertainty(source: .route, requestedPlace: requestedPlace(for: owner))
        }
        if joystickOwners.values.contains(where: { joystickOwnerHasUncertainty($0) }) {
            return SessionMovementUncertainty(source: .joystick, requestedPlace: nil)
        }
        return nil
    }

    private var pointStateIsSendingOrUnconfirmed: Bool {
        switch pointState {
        case .sending, .unconfirmed: return true
        default: return false
        }
    }

    private func requestedPlace(for owner: RouteOwner) -> MapPlace? {
        requestedPlace(for: owner.intent.draft)
    }

    private func requestedPlace(for draft: RouteDraft) -> MapPlace? {
        for node in draft.nodes.reversed() {
            if case .place(let place) = node.value { return place }
        }
        return nil
    }

    private func routeOwnerHasUncertainty(_ owner: RouteOwner) -> Bool {
        owner.unknown || owner.tick?.gate.hasDispatched == true
    }

    private func joystickOwnerHasUncertainty(_ owner: JoystickOwner) -> Bool {
        owner.unknownFailure != nil || owner.tick?.gate?.hasDispatched == true
    }

    @discardableResult public func teleport(to candidate: TeleportCandidate) -> Bool {
        guard canTeleport else { return false }
        admitExplicitOperation()
        beginPreparation(.point(PointMoveIntent(candidate: candidate)))
        return true
    }

    @discardableResult public func start() -> Bool {
        guard canStart else { return false }
        admitExplicitOperation()
        beginPreparation(.start)
        return true
    }

    @discardableResult public func cancelPreparation(id: UUID) -> Bool {
        if !nativeBusy, let snapshot = preparedOperation, snapshot.id == id, case .failed = snapshot.state {
            if case .route(let intent) = snapshot.source { endRoute(executionID: intent.id, lease: intent.lease) }
            if case .joystick(let intent) = snapshot.source, let owner = joystickOwners[intent.id] { cancelJoystickOwner(owner) }
            preparedOperation = nil
            return true
        }
        guard let context = currentPreparation, context.id == id,
              let snapshot = preparedOperation, snapshot.state == .preparing,
              context.dispatch.invalidateIfAvailable() else { return false }
        revision &+= 1
        watchdog?.cancel()
        preparedOperation = PreparedOperationSnapshot(id: id, source: context.source,
            attempt: snapshot.attempt, state: .cancelled)
        currentPoint = nil
        if case .point(let intent) = context.source { pointState = .notSent(intent, .operationCancelled) }
        if case .route(let intent) = context.source, let owner = routeOwners[intent.id] {
            owner.ended = true
            movementAuthority.revoke(intent.lease)
            routeSubject.send(.ended(intent.id))
            settle(owner)
        }
        if case .joystick(let intent) = context.source, let owner = joystickOwners[intent.id] { cancelJoystickOwner(owner) }
        phase = context.wasReady ? .ready : .stopped
        error = nil
        return true
    }

    @discardableResult public func retryPreparedOperation(id: UUID) -> Bool {
        guard !nativeBusy, movementAdmissionAllowed, !pointUnconfirmed, let snapshot = preparedOperation,
              snapshot.id == id, case .failed = snapshot.state else { return false }
        if case .route(let intent) = snapshot.source {
            guard let owner = routeOwners[intent.id], !owner.ended, !owner.unknown, owner.begin != nil,
                  !routeUnconfirmed, (phase == .ready || phase == .stopped) else { return false }
        }
        if case .joystick(let intent) = snapshot.source {
            guard let owner = joystickOwners[intent.id], !owner.ended, owner.begin != nil else { return false }
        }
        beginPreparation(snapshot.source)
        return true
    }

    private func beginPreparation(_ source: PreparedOperationSource) {
        let lease: MovementTaskLease
        if case .route(let intent) = source { lease = intent.lease } else { lease = MovementTaskLease() }
        let dispatch = makePreparationGate(source, lease: lease)
        let context = PreparationContext(id: UUID(), source: source, dispatch: dispatch, wasReady: phase == .ready)
        currentPreparation = context
        preparedOperation = PreparedOperationSnapshot(id: context.id, source: source, attempt: .first, state: .preparing)
        let point: PointContext?
        if case .point(let intent) = source {
            point = PointContext(intent: intent, dispatch: dispatch, wasReady: context.wasReady, lease: lease)
            currentPoint = point; pointState = .preparing(intent)
        } else { point = nil }
        let token = beginLifecycle(.preparing, point: point, preparation: context)
        enqueuePreparationAttempt(context, attempt: .first, token: token, point: point)
    }

    private func makePreparationGate(_ source: PreparedOperationSource, lease: MovementTaskLease) -> PointDispatchGate {
        let callback: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                switch source {
                case .start, .joystick: break
                case .point(let intent): self?.pointDidDispatch(intent.id)
                case .route(let intent): self?.routeDidDispatch(intent)
                }
            }
        }
        switch source {
        case .start, .joystick: return PointDispatchGate(onDispatch: callback)
        default: break
        }
        return PointDispatchGate(authority: movementAuthority, lease: lease,
            replacing: movementAuthority.snapshot, onDispatch: callback)
    }

    private func enqueuePreparationAttempt(_ context: PreparationContext, attempt: PreparationAttempt,
                                            token: UInt64, point: PointContext?) {
        let owner: RouteOwner?
        if case .route(let intent) = context.source { owner = routeOwners[intent.id] } else { owner = nil }
        let joystick: JoystickOwner?
        if case .joystick(let intent) = context.source { joystick = joystickOwners[intent.id] } else { joystick = nil }
        owner?.pendingCalls += 1
        joystick?.pendingCalls += 1
        enqueueAdapter({ [weak self] service in
            guard let self, self.revision == token, self.preparationIsCurrent(context) else { return .failure(.operationCancelled) }
            self.publishAttempt(attempt, context: context)
            switch context.source {
            case .start:
                guard self.movementAdmissionAllowed else { return .failure(.operationCancelled) }
                do { try await service.prepare(); return .success }
                catch { return .failure(error as? DeviceServiceFailure ?? .serviceUnavailable) }
            case .joystick:
                guard self.movementAdmissionAllowed else { return .failure(.operationCancelled) }
                do { try await service.prepare(); return .success }
                catch { return .failure(error as? DeviceServiceFailure ?? .serviceUnavailable) }
            case .point(let intent):
                guard self.movementAdmissionAllowed else { return .point(.notSent(.operationCancelled)) }
                return .point(await service.movePoint(to: intent.candidate.place.coordinate, dispatch: context.dispatch))
            case .route(let intent):
                guard self.movementAdmissionAllowed else { return .point(.notSent(.operationCancelled)) }
                return .point(await service.movePoint(to: intent.route.start, dispatch: context.dispatch))
            }
        }) { [weak self] result in
            guard let self else { return }
            owner?.pendingCalls -= 1
            joystick?.pendingCalls -= 1
            if let owner { self.quarantineCancelledRouteWrite(owner, gate: context.dispatch, result: result) }
            let retryable: Bool
            switch result {
            case .failure: retryable = true
            case .point(.notSent): retryable = true
            default: retryable = false
            }
            if retryable, self.revision == token, self.preparationIsCurrent(context),
               let next = attempt.next {
                // Requeue behind already waiting healthy old ticks, never hold the pump for a whole round.
                self.enqueuePreparationAttempt(context, attempt: next, token: token, point: point)
            } else {
                self.complete(.preparing, token: token, result: result, point: point, preparation: context)
            }
            if let owner { self.settle(owner) }
            if let joystick { self.settleJoystick(joystick) }
        }
    }

    private func preparationIsCurrent(_ context: PreparationContext) -> Bool {
        currentPreparation?.id == context.id && preparedOperation?.state == .preparing && context.dispatch.state == .available
    }

    private func publishAttempt(_ attempt: PreparationAttempt, context: PreparationContext) {
        guard preparationIsCurrent(context) else { return }
        preparedOperation = PreparedOperationSnapshot(id: context.id, source: context.source, attempt: attempt, state: .preparing)
    }

    /// Safety cleanup is unconditional FIFO work. Invalidation can skip a point
    /// before dispatch but cannot cancel an FFI call that already owns handles.
    @discardableResult public func stop() -> Bool {
        guard canStop else { return false }
        routeStopGeneration &+= 1
        routeAdmissionRevision &+= 1
        nativeBusy = true
        beginClear()
        phase = .stopping
        for owner in Array(routeOwners.values) { endRoute(executionID: owner.intent.id, lease: owner.intent.lease) }
        routeUnconfirmed = false
        joystickUnconfirmed = false
        for owner in Array(joystickOwners.values) { cancelJoystickOwner(owner) }
        movementAuthority.revokeAll()
        joystickSubject.send(.movementBoundary(nil))
        currentPreparation?.dispatch.invalidate()
        currentPreparation = nil
        preparedOperation = nil
        currentPoint?.dispatch.invalidate()
        currentPoint = nil
        pointState = .idle
        enqueue(.stopping) { try await $0.clearLocation() }
        return true
    }

    @discardableResult public func restoreGPS() -> Bool {
        guard canRestoreGPS else { return false }
        admitExplicitOperation()
        beginClear()
        enqueue(.restoring) { try await $0.clearLocation() }
        return true
    }

    private func beginClear() {
        clearScheduled = true
        clearAttempted = true
        clearState = .pending
        clearConfirmedAt = nil
        realLocation = nil
        confirmedSimulatedLocation = nil
    }

    @discardableResult public func resetTunnel() -> Bool {
        guard canResetTunnel else { return false }
        admitExplicitOperation()
        enqueue(.resetting) { try await $0.resetClientConnection() }
        return true
    }

    /// GPS remains independent evidence; active simulation takes display priority.
    public func observeRealLocation(_ observation: RealLocationObservation?) {
        if let point = currentPoint, point.dispatch.hasDispatched {
            pointDidDispatch(point.intent.id)
        }
        guard let observation,
              observation.observedAt <= now(),
              now().timeIntervalSince(observation.observedAt) <= 15 else {
            realLocation = nil
            return
        }
        realLocation = observation
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
        if confirmedSimulatedLocation == nil {
            lastDisplayedPosition = DisplayedPosition(coordinate: observation.coordinate, source: .gps)
        }
    }

    private func pointDidDispatch(_ id: UUID) {
        guard currentPoint?.intent.id == id,
              case .preparing(let intent) = pointState, intent.id == id else { return }
        pointState = .sending(intent)
        preparedOperation = nil
        if phase == .preparing { phase = .ready }
        realLocation = nil
        confirmedSimulatedLocation = nil
        // A new point write supersedes prior evidence that simulation was cleared.
        clearState = .unknown
        clearConfirmedAt = nil
        clearAttempted = false
        endSupersededRoutes()
    }

    private func enqueue(
        _ operation: ServicePhase,
        work: @escaping @Sendable (any DeviceService) async throws -> Void
    ) {
        enqueueCommand(operation) { service in
            do { try await work(service); return .success }
            catch { return .failure(error as? DeviceServiceFailure ?? .serviceUnavailable) }
        }
    }

    private func enqueueCommand(
        _ operation: ServicePhase, point: PointContext? = nil, preparation: PreparationContext? = nil,
        work: @escaping @MainActor @Sendable (any DeviceService) async -> CommandResult
    ) {
        let token = beginLifecycle(operation, point: point, preparation: preparation)
        enqueueAdapter(work) { [weak self] result in
            self?.complete(operation, token: token, result: result, point: point, preparation: preparation)
        }
    }

    private func beginLifecycle(_ operation: ServicePhase, point: PointContext?, preparation: PreparationContext?) -> UInt64 {
        revision &+= 1
        let token = revision
        phase = operation
        error = nil
        nativeBusy = true
        outstandingWork += 1
        watchdog?.cancel()
        let timeout = operationTimeout
        let watchdogSleep = self.watchdogSleep
        watchdog = Task { [weak self] in
            do { try await watchdogSleep(timeout) } catch { return }
            guard let self, self.revision == token, self.nativeBusy else { return }
            self.revision &+= 1
            self.phase = .repairRequired
            self.error = .operationTimedOut
            if let preparation, self.currentPreparation?.id == preparation.id {
                preparation.dispatch.invalidate()
                if !preparation.dispatch.hasDispatched {
                    if preparation.wasReady { self.phase = .ready }
                    self.preparedOperation = PreparedOperationSnapshot(id: preparation.id, source: preparation.source,
                        attempt: self.preparedOperation?.attempt ?? .first, state: .failed(.operationTimedOut))
                }
            }
            if let point {
                point.dispatch.invalidate()
                if point.dispatch.hasDispatched {
                    self.pointDidDispatch(point.intent.id)
                    self.pointState = .unconfirmed(point.intent, .operationTimedOut)
                    self.movementAuthority.updateHealth(.unknown, for: point.lease)
                } else {
                    self.pointState = .notSent(point.intent, .operationTimedOut)
                }
            }
            if let preparation, case .route(let intent) = preparation.source,
               preparation.dispatch.hasDispatched, let owner = self.routeOwners[intent.id], !owner.ended {
                self.markRouteUnknown(owner, failure: .operationTimedOut)
                self.resolveBegin(owner, outcome: .unconfirmed(.operationTimedOut))
            }
            if operation == .stopping || operation == .restoring {
                self.clearState = .unknown
            }
            // Only actual completion releases nativeBusy and permits FIFO clear.
        }
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
        return token
    }

    private func enqueueAdapter(_ work: @escaping @MainActor @Sendable (any DeviceService) async -> CommandResult,
                                completion: @escaping @MainActor (CommandResult) -> Void) {
        adapterQueue.append(AdapterCommand(work: work, completion: completion))
        guard !pumping else { return }
        pumping = true
        Task { [weak self] in
            guard let self else { return }
            while !self.adapterQueue.isEmpty {
                let command = self.adapterQueue.removeFirst()
                let result = await command.work(self.service)
                // Completion and any retry requeue finish before the next adapter call.
                command.completion(result)
            }
            self.pumping = false
        }
    }

    private func complete(
        _ operation: ServicePhase, token: UInt64,
        result: CommandResult, point: PointContext?, preparation: PreparationContext?
    ) {
        outstandingWork -= 1
        if operation == .stopping || operation == .restoring { clearScheduled = false }
        if token == revision {
            watchdog?.cancel()
            switch result {
            case .success:
                if preparation != nil { preparedOperation = nil }
                phase = operation == .preparing ? .ready : .stopped
                error = nil
                if let preparation, case .joystick(let intent) = preparation.source,
                   let owner = joystickOwners[intent.id], !owner.ended, owner.unknownFailure == nil {
                    owner.prepared = true
                    resolveJoystickBeginning(owner, outcome: .prepared)
                }
                if operation == .stopping || operation == .restoring {
                    clearState = .confirmed
                    clearConfirmedAt = now()
                    setColdRecoveryHeld(false)
                }
            case .failure(let failure):
                if let preparation { failPreparation(preparation, failure: failure) }
                phase = preparation?.wasReady == true ? .ready : .stopped
                error = failure
                if operation == .stopping || operation == .restoring {
                    clearState = .unknown
                    clearConfirmedAt = nil
                }
            case .point(let outcome):
                if let point { completePoint(point, outcome: outcome) }
                if let preparation, case .route(let intent) = preparation.source,
                   let owner = routeOwners[intent.id], !owner.ended {
                    completeRouteBeginning(owner, context: preparation, outcome: outcome)
                }
                if let preparation, !preparation.dispatch.hasDispatched, case .notSent(let failure) = outcome {
                    failPreparation(preparation, failure: failure)
                }
            }
        }
        if let preparation, currentPreparation?.id == preparation.id {
            currentPreparation = nil
            if preparedOperation?.state == .cancelled { preparedOperation = nil }
        }
        if let point, currentPoint?.intent.id == point.intent.id { currentPoint = nil }
        if outstandingWork == 0 {
            nativeBusy = hasPendingRouteRepair
            if phase == .repairRequired && !pointUnconfirmed && !routeUnconfirmed && !joystickUnconfirmed { phase = .stopped }
        }
        routeSubject.send(.availabilityChanged)
        joystickSubject.send(.availabilityChanged)
    }

    private func failPreparation(_ context: PreparationContext, failure: DeviceServiceFailure) {
        preparedOperation = PreparedOperationSnapshot(id: context.id, source: context.source,
            attempt: preparedOperation?.attempt ?? .first, state: .failed(failure))
    }

    private func completePoint(_ point: PointContext, outcome: PointDeliveryOutcome) {
        if point.dispatch.hasDispatched { pointDidDispatch(point.intent.id) }
        switch outcome {
        case .notSent(let failure):
            if point.dispatch.hasDispatched {
                pointState = .unconfirmed(point.intent, failure)
                movementAuthority.updateHealth(.unknown, for: point.lease)
                phase = .repairRequired
            } else {
                pointState = .notSent(point.intent, failure)
                phase = point.wasReady ? .ready : .stopped
            }
            error = failure
        case .acknowledged:
            preparedOperation = nil
            point.dispatch.invalidate()
            guard point.dispatch.hasDispatched else {
                pointState = .unconfirmed(point.intent, .serviceUnavailable)
                movementAuthority.revokeAll()
                phase = .repairRequired
                error = .serviceUnavailable
                return
            }
            movementAuthority.updateHealth(.confirmedHealthy, for: point.lease)
            confirmedSimulatedLocation = point.intent.candidate.place.coordinate
            lastDisplayedPosition = DisplayedPosition(coordinate: point.intent.candidate.place.coordinate, source: .simulation)
            pointState = .acknowledged(point.intent)
            phase = .ready
            error = nil
        case .unconfirmed(let failure):
            preparedOperation = nil
            point.dispatch.invalidate()
            if point.dispatch.hasDispatched { movementAuthority.updateHealth(.unknown, for: point.lease) }
            else { movementAuthority.revokeAll() }
            pointState = .unconfirmed(point.intent, failure)
            phase = .repairRequired
            error = failure
        }
    }
}

extension ServiceController {
    public var canBeginRoute: Bool { canTeleport }
    public var routeEvents: AnyPublisher<RouteCommandEvent, Never> { routeSubject.eraseToAnyPublisher() }
    public var currentRouteOrigin: GeoCoordinate? {
        if let confirmedSimulatedLocation { return confirmedSimulatedLocation }
        guard let realLocation, realLocation.observedAt <= now(), now().timeIntervalSince(realLocation.observedAt) <= 15 else { return nil }
        return realLocation.coordinate
    }
    public func beginRoute(_ intent: RouteExecutionIntent, expectedAdmissionRevision: UInt64) async -> RouteCommandOutcome {
        guard expectedAdmissionRevision == routeAdmissionRevision, canBeginRoute, routeOwners[intent.id] == nil else { return .cancelled }
        admitExplicitOperation()
        return await withCheckedContinuation { continuation in
            let owner = RouteOwner(intent, stopGeneration: routeStopGeneration, begin: continuation)
            routeOwners[intent.id] = owner
            beginPreparation(.route(intent))
        }
    }
    public func routeControlRevision(executionID: UUID, lease: MovementTaskLease) -> UInt64? {
        eligibleRouteControlOwner(executionID: executionID, lease: lease)?.controlRevision
    }
    public func reviseRouteControl(executionID: UUID, lease: MovementTaskLease) -> UInt64? {
        guard let owner = eligibleRouteControlOwner(executionID: executionID, lease: lease) else { return nil }
        owner.controlRevision &+= 1
        if let tick = owner.tick, tick.gate.invalidateIfAvailable() {
            tick.controlCancelled = true
            tick.watchdog?.cancel()
        }
        return owner.controlRevision
    }
    private func eligibleRouteControlOwner(executionID: UUID, lease: MovementTaskLease) -> RouteOwner? {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease, owner.begun,
              !owner.ended, !owner.unknown, movementAuthority.snapshot.lease == lease,
              movementAuthority.snapshot.health == .confirmedHealthy, !routeUnconfirmed, !joystickUnconfirmed else { return nil }
        return owner
    }
    public func sendRoutePoint(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedControlRevision: UInt64,
                               coordinate: GeoCoordinate) async -> RouteCommandOutcome {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease, owner.begun,
              !owner.ended, !owner.unknown, owner.tick == nil,
              owner.lastSequence < UInt64.max, sequence == owner.lastSequence + 1,
              movementAdmissionAllowed, !routeUnconfirmed, !joystickUnconfirmed else { return .cancelled }
        guard movementAuthority.permitsDispatch(for: lease) else {
            _ = pauseExpiredContinuation(movementID: executionID, lease: lease,
                result: .point(.notSent(.operationCancelled)))
            return .cancelled
        }
        guard owner.controlRevision == expectedControlRevision else { return .controlCancelled }
        let gate = PointDispatchGate(authority: movementAuthority, lease: lease) { [weak self] in
            Task { @MainActor in self?.routeTickDidDispatch(executionID: executionID, sequence: sequence) }
        }
        let tick = RouteTick(gate: gate, coordinate: coordinate, sequence: sequence)
        owner.tick = tick; owner.pendingCalls += 1
        return await withCheckedContinuation { continuation in
            enqueueAdapter({ [weak self] service in
                guard let self, self.routeTickIsCurrent(owner, tick), self.movementAdmissionAllowed,
                      self.movementAuthority.permitsDispatch(for: lease), !self.joystickUnconfirmed else {
                    tick.skipped = true
                    return .point(.notSent(.operationCancelled))
                }
                if tick.controlCancelled { return .point(.notSent(.operationCancelled)) }
                tick.watchdog = Task { [weak self] in
                    guard let self, !tick.controlCancelled else { return }
                    do { try await self.watchdogSleep(self.operationTimeout) } catch { return }
                    guard self.routeTickIsCurrent(owner, tick), !owner.ended, !tick.controlCancelled,
                          self.movementAuthority.snapshot.lease == lease else { return }
                    if !tick.gate.hasDispatched, self.movementAuthority.snapshot.runState != .running { return }
                    tick.timedOut = true; tick.gate.invalidate()
                    if tick.gate.hasDispatched {
                        self.routeTickDidDispatch(executionID: executionID, sequence: sequence)
                        self.markRouteUnknown(owner, failure: .operationTimedOut)
                    } else { self.markRouteInterrupted(owner, failure: .operationTimedOut) }
                }
                return .point(await service.movePoint(to: coordinate, dispatch: gate))
            }) { [weak self] result in
                guard let self else { continuation.resume(returning: .cancelled); return }
                tick.watchdog?.cancel()
                let outcome = self.completeRouteTick(owner, tick: tick, result: result)
                owner.tick = nil; owner.pendingCalls -= 1
                self.nativeBusy = self.outstandingWork > 0 || self.hasPendingRouteRepair
                continuation.resume(returning: outcome)
                self.settle(owner)
                self.routeSubject.send(.availabilityChanged)
            }
        }
    }
    public func pauseRoute(executionID: UUID, lease: MovementTaskLease) -> Bool {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease, owner.begun, !owner.ended, !owner.unknown,
              movementAuthority.snapshot.lease == lease, movementAuthority.snapshot.health == .confirmedHealthy else { return false }
        guard movementAuthority.updateRunState(.paused, for: lease) else { return false }
        owner.tick?.gate.invalidate()
        return true
    }
    public func resumeRoute(executionID: UUID, lease: MovementTaskLease) -> Bool {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease, owner.begun, !owner.ended, !owner.unknown,
              owner.tick == nil, movementAuthority.snapshot.lease == lease,
              !clearScheduled, !routeUnconfirmed, !joystickUnconfirmed,
              movementAuthority.snapshot.health == .confirmedHealthy,
              movementAuthority.snapshot.runState == .paused else { return false }
        return movementAuthority.resumeForeground(lease)
    }
    public func endRoute(executionID: UUID, lease: MovementTaskLease) {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease else { return }
        if !owner.ended {
            if let tick = owner.tick, tick.gate.hasDispatched { routeTickDidDispatch(executionID: executionID, sequence: tick.sequence) }
            if let context = currentPreparation, case .route(let intent) = context.source, intent.id == executionID {
                if context.dispatch.hasDispatched { routeDidDispatch(intent) }
                context.dispatch.invalidate(); revision &+= 1; watchdog?.cancel()
                currentPreparation = nil; preparedOperation = nil
                if !clearScheduled { phase = context.wasReady || context.dispatch.hasDispatched ? .ready : .stopped }
            }
            if let snapshot = preparedOperation, case .route(let intent) = snapshot.source, intent.id == executionID { preparedOperation = nil }
            owner.ended = true; owner.tick?.gate.invalidate()
            movementAuthority.revoke(lease)
            nativeBusy = outstandingWork > 0 || hasPendingRouteRepair
            routeSubject.send(.ended(executionID))
        } else if clearScheduled {
            routeSubject.send(.ended(executionID))
        }
        settle(owner)
    }
    public func waitForRouteIdle(executionID: UUID, lease: MovementTaskLease) async -> RouteIdleSettlement {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease else { return .settled }
        guard owner.pendingCalls > 0 else { return idleSettlement(owner) }
        return await withCheckedContinuation { owner.idle.append($0) }
    }

    private var hasPendingRouteRepair: Bool {
        routeOwners.values.contains { ($0.unknown || $0.interrupted || $0.ended) && $0.pendingCalls > 0 }
            || joystickOwners.values.contains { ($0.ended || $0.disposition != nil || $0.unknownFailure != nil || $0.tick?.timedOut == true) && $0.pendingCalls > 0 }
    }
    private func admitExplicitOperation() {
        didPerformActualOperation = true
        routeAdmissionRevision &+= 1
        // A failed route preparation may still be awaiting user Retry/Cancel.
        for owner in Array(routeOwners.values) where owner.begin != nil {
            endRoute(executionID: owner.intent.id, lease: owner.intent.lease)
        }
        for owner in Array(joystickOwners.values) where owner.begin != nil { cancelJoystickOwner(owner) }
    }
    private func routeDidDispatch(_ intent: RouteExecutionIntent) {
        guard !clearScheduled, let context = currentPreparation, case .route(let stored) = context.source,
              stored.id == intent.id, context.dispatch.hasDispatched, preparedOperation?.state == .preparing,
              let owner = routeOwners[intent.id], !owner.ended else { return }
        preparedOperation = nil
        if phase == .preparing { phase = .ready }
        invalidatePositionProof()
        endSupersededRoutes()
    }
    private func invalidatePositionProof() {
        realLocation = nil; confirmedSimulatedLocation = nil
        clearState = .unknown; clearConfirmedAt = nil; clearAttempted = false
    }
    private func endSupersededRoutes() {
        let lease = movementAuthority.snapshot.lease
        for owner in Array(routeOwners.values) where owner.begun && owner.intent.lease != lease {
            endRoute(executionID: owner.intent.id, lease: owner.intent.lease)
        }
        for owner in Array(joystickOwners.values) where owner.installed && owner.intent.lease != lease {
            cancelJoystickOwner(owner)
        }
        if let lease { joystickSubject.send(.movementBoundary(lease)) }
    }
    private func completeRouteBeginning(_ owner: RouteOwner, context: PreparationContext, outcome: PointDeliveryOutcome) {
        if context.dispatch.hasDispatched { routeDidDispatch(owner.intent) }
        switch outcome {
        case .notSent(let failure) where !context.dispatch.hasDispatched:
            phase = context.wasReady ? .ready : .stopped
            error = failure
        case .acknowledged where context.dispatch.hasDispatched:
            movementAuthority.updateHealth(.confirmedHealthy, for: owner.intent.lease)
            owner.begun = true
            publishSimulation(owner.intent.route.start)
            phase = .ready; error = nil; preparedOperation = nil
            resolveBegin(owner, outcome: .acknowledged)
        case .notSent(let failure), .unconfirmed(let failure):
            context.dispatch.invalidate(); preparedOperation = nil
            markRouteUnknown(owner, failure: failure)
            resolveBegin(owner, outcome: .unconfirmed(failure))
        case .acknowledged:
            context.dispatch.invalidate(); preparedOperation = nil
            markRouteUnknown(owner, failure: .serviceUnavailable)
            resolveBegin(owner, outcome: .unconfirmed(.serviceUnavailable))
        }
    }
    private func publishSimulation(_ coordinate: GeoCoordinate) {
        confirmedSimulatedLocation = coordinate
        lastDisplayedPosition = DisplayedPosition(coordinate: coordinate, source: .simulation)
    }
    private func routeTickIsCurrent(_ owner: RouteOwner, _ tick: RouteTick) -> Bool {
        routeOwners[owner.intent.id] === owner && owner.tick === tick && !owner.ended && !owner.unknown
    }
    private func routeTickDidDispatch(executionID: UUID, sequence: UInt64) {
        guard !clearScheduled, let owner = routeOwners[executionID], !owner.ended,
              let tick = owner.tick, tick.sequence == sequence, tick.gate.hasDispatched,
              !tick.didInvalidateProof, movementAuthority.snapshot.lease == owner.intent.lease else { return }
        tick.didInvalidateProof = true
        invalidatePositionProof()
    }
    private func completeRouteTick(_ owner: RouteOwner, tick: RouteTick, result: CommandResult) -> RouteCommandOutcome {
        quarantineCancelledRouteWrite(owner, gate: tick.gate, result: result)
        guard routeOwners[owner.intent.id] === owner, !owner.ended,
              movementAuthority.snapshot.lease == owner.intent.lease else { return .cancelled }
        if tick.timedOut { return tick.gate.hasDispatched ? .unconfirmed(.operationTimedOut) : .notSent(.operationTimedOut) }
        guard !owner.unknown else { return .unconfirmed(error ?? .serviceUnavailable) }
        if !tick.gate.hasDispatched,
           pauseExpiredContinuation(movementID: owner.intent.id, lease: owner.intent.lease, result: result) {
            return .cancelled
        }
        if tick.skipped { return .cancelled }
        if tick.gate.hasDispatched { routeTickDidDispatch(executionID: owner.intent.id, sequence: tick.sequence) }
        let outcome: PointDeliveryOutcome
        switch result {
        case .point(let value): outcome = value
        case .failure(let failure): outcome = .notSent(failure)
        case .success: outcome = .unconfirmed(.serviceUnavailable)
        }
        switch outcome {
        case .acknowledged where tick.gate.hasDispatched:
            owner.lastSequence = tick.sequence
            publishSimulation(tick.coordinate)
            return .acknowledged
        case .notSent(let failure) where !tick.gate.hasDispatched:
            if movementAuthority.snapshot.runState != .running { return .cancelled }
            if tick.controlCancelled { return .controlCancelled }
            if tick.gate.state == .invalidated { return .cancelled }
            markRouteInterrupted(owner, failure: failure)
            return .notSent(failure)
        case .notSent(let failure), .unconfirmed(let failure):
            markRouteUnknown(owner, failure: failure)
            return .unconfirmed(failure)
        case .acknowledged:
            markRouteUnknown(owner, failure: .serviceUnavailable)
            return .unconfirmed(.serviceUnavailable)
        }
    }
    private func markRouteInterrupted(_ owner: RouteOwner, failure: DeviceServiceFailure) {
        guard !owner.ended, movementAuthority.snapshot.lease == owner.intent.lease,
              movementAuthority.snapshot.runState == .running else { return }
        owner.interrupted = true
        movementAuthority.updateHealth(.interrupted(failure), for: owner.intent.lease)
        nativeBusy = outstandingWork > 0 || owner.pendingCalls > 0
        error = failure
        routeSubject.send(.interrupted(owner.intent.id, failure))
    }
    private func markRouteUnknown(_ owner: RouteOwner, failure: DeviceServiceFailure) {
        guard !owner.ended else { return }
        owner.unknown = true; owner.unknownFailure = failure; routeUnconfirmed = true
        if movementAuthority.snapshot.lease == owner.intent.lease { movementAuthority.updateHealth(.unknown, for: owner.intent.lease) }
        else { movementAuthority.revokeAll() }
        phase = .repairRequired; error = failure
        nativeBusy = outstandingWork > 0 || owner.pendingCalls > 0
        routeSubject.send(.unknown(owner.intent.id, failure))
        quarantineJoystickOwners(failure)
    }
    private func quarantineCancelledRouteWrite(_ owner: RouteOwner, gate: PointDispatchGate, result: CommandResult) {
        guard owner.ended, owner.stopGeneration == routeStopGeneration else { return }
        let failure: DeviceServiceFailure
        switch result {
        case .point(.notSent(let value)) where gate.hasDispatched: failure = value
        case .point(.unconfirmed(let value)): failure = value
        case .point(.acknowledged) where !gate.hasDispatched: failure = .serviceUnavailable
        default: return
        }
        // Cancellation suppresses publication, but cannot turn an uncertain native write into a confirmed stop.
        owner.unknown = true; owner.unknownFailure = failure; routeUnconfirmed = true
        movementAuthority.revokeAll()
        phase = .repairRequired; error = failure
        routeSubject.send(.unknown(owner.intent.id, failure))
        quarantineJoystickOwners(failure)
    }
    private func resolveBegin(_ owner: RouteOwner, outcome: RouteCommandOutcome) {
        let continuation = owner.begin; owner.begin = nil
        continuation?.resume(returning: outcome)
    }
    private func idleSettlement(_ owner: RouteOwner) -> RouteIdleSettlement {
        if owner.stopGeneration == routeStopGeneration, owner.unknown {
            return .requiresStop(owner.unknownFailure ?? .serviceUnavailable)
        }
        return .settled
    }
    private func settle(_ owner: RouteOwner) {
        guard owner.pendingCalls == 0 else { return }
        if owner.ended { resolveBegin(owner, outcome: .cancelled) }
        let waiting = owner.idle; owner.idle = []
        for continuation in waiting { continuation.resume(returning: idleSettlement(owner)) }
        if owner.ended && (!owner.unknown || clearScheduled) { routeOwners.removeValue(forKey: owner.intent.id) }
    }
}

extension ServiceController {
    public var canBeginJoystick: Bool {
        let snapshot = movementAuthority.snapshot
        return canTeleport && (snapshot.lease == nil || snapshot.health == .confirmedHealthy)
            && joystickOwners.values.allSatisfy { $0.ended || $0.neutral || $0.paused }
    }
    public var currentJoystickOrigin: GeoCoordinate? { currentRouteOrigin }
    public var movementAdmissionRevision: UInt64 { routeAdmissionRevision }
    public var joystickEvents: AnyPublisher<JoystickCommandEvent, Never> { joystickSubject.eraseToAnyPublisher() }
    public var movementAcknowledgements: AnyPublisher<MovementAcknowledgement, Never> {
        movementAcknowledgementSubject.eraseToAnyPublisher()
    }
    public func beginJoystick(_ intent: JoystickMovementIntent, expectedMovementAdmissionRevision: UInt64) async -> JoystickPreparationOutcome {
        guard canBeginJoystick, expectedMovementAdmissionRevision == movementAdmissionRevision,
              joystickOwners[intent.id] == nil else { return .cancelled }
        admitExplicitOperation()
        return await withCheckedContinuation { continuation in
            let owner = JoystickOwner(intent, stopGeneration: routeStopGeneration, begin: continuation)
            joystickOwners[intent.id] = owner
            beginPreparation(.joystick(intent))
        }
    }
    public func joystickInputRevision(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, !owner.ended,
              !owner.neutral, !owner.paused, owner.disposition == nil, owner.unknownFailure == nil,
              !joystickUnconfirmed, !routeUnconfirmed, !pointUnconfirmed else { return nil }
        return owner.inputRevision
    }
    private func resolveJoystickBeginning(_ owner: JoystickOwner, outcome: JoystickPreparationOutcome) {
        let continuation = owner.begin; owner.begin = nil
        continuation?.resume(returning: outcome)
    }

    private func cancelJoystickOwner(_ owner: JoystickOwner) {
        if !owner.ended {
            owner.ended = true
            owner.tick?.gate?.invalidate()
            movementAuthority.revoke(owner.intent.lease)
            joystickSubject.send(.ended(owner.intent.id))
        }
        settleJoystick(owner)
    }
    private func joystickSettlement(_ owner: JoystickOwner) -> JoystickIdleSettlement {
        if owner.stopGeneration == routeStopGeneration, let failure = owner.unknownFailure { return .requiresStop(failure) }
        return .settled
    }
    private func settleJoystick(_ owner: JoystickOwner) {
        guard owner.pendingCalls == 0 else { return }
        if owner.unknownFailure == nil, let disposition = owner.disposition {
            owner.disposition = nil
            switch disposition {
            case .endGesture:
                owner.ended = true
                movementAuthority.revoke(owner.intent.lease)
                joystickSubject.send(.ended(owner.intent.id))
            case .pause: owner.paused = true
            }
        }
        if owner.ended || owner.unknownFailure != nil { resolveJoystickBeginning(owner, outcome: .cancelled) }
        let waiting = owner.idle; owner.idle = []
        for continuation in waiting { continuation.resume(returning: joystickSettlement(owner)) }
        if owner.ended && (owner.unknownFailure == nil || clearScheduled) { joystickOwners.removeValue(forKey: owner.intent.id) }
        nativeBusy = outstandingWork > 0 || hasPendingRouteRepair
    }

    public func reviseJoystickInput(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, !owner.ended,
              !owner.neutral, !owner.paused, owner.disposition == nil, owner.unknownFailure == nil,
              !joystickUnconfirmed, !routeUnconfirmed, !pointUnconfirmed else { return nil }
        advanceJoystickInput(owner)
        return owner.inputRevision
    }
    private func advanceJoystickInput(_ owner: JoystickOwner) {
        owner.inputRevision = JoystickInputRevision(generation: owner.inputRevision.generation, revision: owner.inputRevision.revision &+ 1)
        if let tick = owner.tick, tick.gate == nil || tick.gate?.invalidateIfAvailable() == true {
            tick.inputCancelled = true
            tick.watchdog?.cancel()
        }
    }
    public func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64,
                                 expectedInputRevision: JoystickInputRevision, displacement: JoystickDisplacement) async -> JoystickStepOutcome {
        switch await executeJoystickStep(executionID: executionID, lease: lease, sequence: sequence,
                                         expectedInputRevision: expectedInputRevision, recipe: .manual(displacement)) {
        case .acknowledged(let receipt): return .acknowledged(receipt.actualCoordinate)
        case .notSent(let failure): return .notSent(failure)
        case .unconfirmed(let failure): return .unconfirmed(failure)
        case .inputCancelled: return .inputCancelled
        case .cancelled: return .cancelled
        }
    }
    public func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64,
                                 expectedInputRevision: JoystickInputRevision, recipe: JoystickStepRecipe) async -> JoystickRecipeStepOutcome {
        await executeJoystickStep(executionID: executionID, lease: lease, sequence: sequence,
                                  expectedInputRevision: expectedInputRevision, recipe: recipe)
    }
    private func executeJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64,
                                     expectedInputRevision: JoystickInputRevision, recipe: JoystickStepRecipe) async -> JoystickRecipeStepOutcome {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, owner.prepared,
              !owner.ended, !owner.neutral, !owner.paused, owner.disposition == nil,
              owner.unknownFailure == nil, owner.tick == nil, owner.stopGeneration == routeStopGeneration,
              movementAdmissionAllowed, owner.lastSequence < UInt64.max,
              sequence == owner.lastSequence + 1 else { return .cancelled }
        guard owner.inputRevision == expectedInputRevision else { return .inputCancelled }
        let tick = JoystickTick(sequence: sequence, input: expectedInputRevision)
        owner.tick = tick; owner.pendingCalls += 1
        nativeBusy = true
        return await withCheckedContinuation { continuation in
            enqueueAdapter({ [weak self] service in
                guard let self, self.joystickTickIsCurrent(owner, tick), self.movementAdmissionAllowed else { return .failure(.operationCancelled) }
                guard !tick.inputCancelled, owner.inputRevision == tick.input else { tick.inputCancelled = true; return .failure(.operationCancelled) }
                let snapshot = self.movementAuthority.snapshot
                guard !self.clearScheduled, !self.pointUnconfirmed, !self.routeUnconfirmed, !self.joystickUnconfirmed,
                      snapshot.lease == nil || snapshot.health == .confirmedHealthy,
                      !owner.installed || self.movementAuthority.permitsDispatch(for: lease) else {
                    tick.failure = .device(.serviceUnavailable); return .failure(.operationCancelled)
                }
                guard let origin = self.currentJoystickOrigin else {
                    tick.failure = .originUnavailable; return .failure(.operationCancelled)
                }
                tick.origin = origin
                // No suspension between current truth, geometry, fresh CAS snapshot and gate construction.
                let receipt: JoystickStepReceipt
                switch recipe {
                case .manual(let displacement):
                    receipt = JoystickStepReceipt(actualCoordinate: JoystickGeodesy.destination(from: origin, displacement: displacement),
                        actualBearingDegrees: displacement.bearingDegrees, targetID: nil, arrived: false)
                case .target(let step):
                    let resolved = JoystickGeodesy.resolveTarget(from: origin, step: step)
                    receipt = JoystickStepReceipt(actualCoordinate: resolved.coordinate, actualBearingDegrees: resolved.bearingDegrees,
                        targetID: step.targetID, arrived: resolved.arrived)
                }
                let fresh = self.movementAuthority.snapshot
                guard fresh.lease == nil || fresh.health == .confirmedHealthy else {
                    tick.failure = .device(.serviceUnavailable); return .failure(.operationCancelled)
                }
                tick.receipt = receipt
                let gate = PointDispatchGate(authority: self.movementAuthority, lease: lease,
                    replacing: owner.installed ? nil : fresh) { [weak self] in
                    Task { @MainActor in self?.joystickDidDispatch(executionID: executionID, sequence: sequence) }
                }
                tick.gate = gate
                tick.watchdog = Task { [weak self] in
                    guard let self else { return }
                    do { try await self.watchdogSleep(self.operationTimeout) } catch { return }
                    guard self.joystickTickIsCurrent(owner, tick), !tick.inputCancelled else { return }
                    tick.timedOut = true
                    // Atomic invalidation wins against the native claim, or a
                    // pre-existing invalidation already prevented dispatch.
                    if gate.invalidateIfAvailable() || !gate.hasDispatched {
                        tick.failure = .device(.operationTimedOut)
                        self.error = .operationTimedOut
                        self.nativeBusy = true
                    } else if gate.hasDispatched {
                        self.joystickDidDispatch(owner, tick)
                        _ = self.unknownJoystick(owner, failure: .operationTimedOut)
                    }
                }
                return .point(await service.movePoint(to: receipt.actualCoordinate, dispatch: gate))
            }) { [weak self] result in
                guard let self else { continuation.resume(returning: .cancelled); return }
                let outcome = self.completeJoystickTick(owner, tick, result: result)
                tick.watchdog?.cancel()
                owner.tick = nil; owner.pendingCalls -= 1
                self.settleJoystick(owner)
                continuation.resume(returning: outcome)
                self.joystickSubject.send(.availabilityChanged)
            }
        }
    }
    private func joystickTickIsCurrent(_ owner: JoystickOwner, _ tick: JoystickTick) -> Bool {
        joystickOwners[owner.intent.id] === owner && owner.tick === tick && !owner.ended
            && owner.stopGeneration == routeStopGeneration
    }
    private func joystickDidDispatch(executionID: UUID, sequence: UInt64) {
        guard let owner = joystickOwners[executionID], let tick = owner.tick, tick.sequence == sequence else { return }
        joystickDidDispatch(owner, tick)
    }
    private func joystickDidDispatch(_ owner: JoystickOwner, _ tick: JoystickTick) {
        guard joystickTickIsCurrent(owner, tick), !clearScheduled, tick.gate?.hasDispatched == true,
              !tick.didInvalidateProof, movementAuthority.snapshot.lease == owner.intent.lease else { return }
        tick.didInvalidateProof = true
        invalidatePositionProof()
        endSupersededRoutes()
    }
    private func completeJoystickTick(_ owner: JoystickOwner, _ tick: JoystickTick, result: CommandResult) -> JoystickRecipeStepOutcome {
        guard joystickTickIsCurrent(owner, tick) else { return .cancelled }
        if tick.timedOut {
            if tick.gate?.hasDispatched == true { return .unconfirmed(.operationTimedOut) }
            return failJoystickBeforeClaim(owner, failure: .device(.operationTimedOut))
        }
        if let failure = owner.unknownFailure {
            return tick.gate?.hasDispatched == true ? .unconfirmed(failure) : .notSent(.device(failure))
        }
        // Even a withdrawn, unclaimed request cannot erase a malformed native
        // acknowledgement or an explicitly uncertain native result.
        if case .point(.unconfirmed(let failure)) = result { return unknownJoystick(owner, failure: failure) }
        if case .point(.acknowledged) = result, tick.gate?.hasDispatched != true {
            return unknownJoystick(owner, failure: .serviceUnavailable)
        }
        if tick.inputCancelled { return .inputCancelled }
        if tick.gate?.hasDispatched != true,
           pauseExpiredContinuation(movementID: owner.intent.id, lease: owner.intent.lease, result: result) {
            return .cancelled
        }
        if let failure = tick.failure { return failJoystickBeforeClaim(owner, failure: failure) }
        let outcome: PointDeliveryOutcome
        switch result {
        case .point(let value): outcome = value
        case .failure(let failure): outcome = .notSent(failure)
        case .success: outcome = .unconfirmed(.serviceUnavailable)
        }
        if tick.gate?.hasDispatched == true { joystickDidDispatch(owner, tick) }
        switch outcome {
        case .acknowledged where tick.gate?.hasDispatched == true:
            guard let receipt = tick.receipt, movementAuthority.snapshot.lease == owner.intent.lease else {
                return unknownJoystick(owner, failure: .serviceUnavailable)
            }
            owner.installed = true; owner.lastSequence = tick.sequence
            movementAuthority.updateHealth(.confirmedHealthy, for: owner.intent.lease)
            publishSimulation(receipt.actualCoordinate)
            guard let origin = tick.origin else {
                return unknownJoystick(owner, failure: .serviceUnavailable)
            }
            let distance = JoystickGeodesy.distanceMeters(from: origin, to: receipt.actualCoordinate)
            guard distance.isFinite, distance >= 0 else {
                return unknownJoystick(owner, failure: .serviceUnavailable)
            }
            movementAcknowledgementSubject.send(MovementAcknowledgement(
                movementID: owner.intent.id, lease: owner.intent.lease, sequence: tick.sequence,
                source: .joystick, acknowledgedDistanceMeters: distance,
                routePositionMeters: nil, finiteArrival: false))
            return .acknowledged(receipt)
        case .notSent(let failure) where tick.gate?.hasDispatched != true:
            return failJoystickBeforeClaim(owner, failure: .device(failure))
        case .notSent(let failure), .unconfirmed(let failure): return unknownJoystick(owner, failure: failure)
        case .acknowledged: return unknownJoystick(owner, failure: .serviceUnavailable)
        }
    }
    private func failJoystickBeforeClaim(_ owner: JoystickOwner, failure: JoystickFailure) -> JoystickRecipeStepOutcome {
        owner.ended = true
        movementAuthority.revoke(owner.intent.lease)
        joystickSubject.send(.interrupted(owner.intent.id, failure))
        return .notSent(failure)
    }
    private func unknownJoystick(_ owner: JoystickOwner, failure: DeviceServiceFailure) -> JoystickRecipeStepOutcome {
        guard owner.stopGeneration == routeStopGeneration else { return .cancelled }
        owner.unknownFailure = failure; joystickUnconfirmed = true
        if movementAuthority.snapshot.lease == owner.intent.lease { movementAuthority.updateHealth(.unknown, for: owner.intent.lease) }
        else { movementAuthority.revokeAll() }
        phase = .repairRequired; error = failure; nativeBusy = owner.pendingCalls > 0 || outstandingWork > 0
        joystickSubject.send(.unknown(owner.intent.id, failure))
        for route in Array(routeOwners.values) where route.begun && !route.ended && !route.unknown {
            markRouteUnknown(route, failure: failure)
        }
        quarantineJoystickOwners(failure)
        return .unconfirmed(failure)
    }
    private func quarantineJoystickOwners(_ failure: DeviceServiceFailure) {
        for owner in Array(joystickOwners.values) where !owner.ended && owner.unknownFailure == nil {
            owner.unknownFailure = failure; joystickUnconfirmed = true
            owner.tick?.gate?.invalidate()
            if let context = currentPreparation, case .joystick(let intent) = context.source, intent.id == owner.intent.id {
                context.dispatch.invalidate(); revision &+= 1; watchdog?.cancel()
                currentPreparation = nil; preparedOperation = nil
            }
            joystickSubject.send(.unknown(owner.intent.id, failure))
        }
    }
    @discardableResult public func releaseJoystick(executionID: UUID, lease: MovementTaskLease, disposition: JoystickReleaseDisposition) -> Bool {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, !owner.ended, owner.unknownFailure == nil else { return false }
        if disposition == .pause {
            guard owner.installed, !owner.neutral, !owner.paused, owner.disposition == nil,
                  movementAuthority.snapshot.lease == lease,
                  movementAuthority.snapshot.health == .confirmedHealthy else { return false }
        }
        advanceJoystickInput(owner)
        owner.disposition = disposition
        if disposition == .pause { movementAuthority.updateRunState(.paused, for: lease) }
        if let snapshot = preparedOperation, case .joystick(let intent) = snapshot.source, intent.id == executionID {
            _ = cancelPreparation(id: snapshot.id)
        }
        nativeBusy = outstandingWork > 0 || hasPendingRouteRepair
        settleJoystick(owner)
        return true
    }
    public func resumeJoystick(executionID: UUID, lease: MovementTaskLease) -> Bool {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, !owner.ended,
              owner.paused, owner.pendingCalls == 0, owner.unknownFailure == nil,
              !clearScheduled, !pointUnconfirmed, !routeUnconfirmed, !joystickUnconfirmed,
              movementAuthority.snapshot.lease == lease, movementAuthority.snapshot.health == .confirmedHealthy else { return false }
        guard movementAuthority.resumeForeground(lease) else { return false }
        owner.inputRevision = JoystickInputRevision()
        owner.paused = false; owner.neutral = true
        joystickSubject.send(.availabilityChanged)
        return true
    }
    public func resumeJoystickStream(executionID: UUID, lease: MovementTaskLease) -> Bool {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease, !owner.ended,
              owner.installed, owner.paused, owner.pendingCalls == 0, owner.tick == nil,
              owner.disposition == nil, owner.unknownFailure == nil, owner.stopGeneration == routeStopGeneration,
              !clearScheduled, !pointUnconfirmed, !routeUnconfirmed, !joystickUnconfirmed,
              movementAuthority.snapshot.lease == lease, movementAuthority.snapshot.runState == .paused,
              movementAuthority.snapshot.health == .confirmedHealthy else { return false }
        guard movementAuthority.resumeForeground(lease) else { return false }
        owner.inputRevision = JoystickInputRevision()
        owner.paused = false; owner.neutral = false
        joystickSubject.send(.availabilityChanged)
        return true
    }
    public func waitForJoystickIdle(executionID: UUID, lease: MovementTaskLease) async -> JoystickIdleSettlement {
        guard let owner = joystickOwners[executionID], owner.intent.lease == lease else { return .settled }
        guard owner.pendingCalls > 0 else { return joystickSettlement(owner) }
        return await withCheckedContinuation { owner.idle.append($0) }
    }

}
