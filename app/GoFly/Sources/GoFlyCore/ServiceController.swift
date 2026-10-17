import Combine
import Foundation

@MainActor
public final class ServiceController: ObservableObject, RouteCommanding {
    @Published public private(set) var phase: ServicePhase = .stopped
    @Published public private(set) var nativeBusy = false
    @Published public private(set) var error: DeviceServiceFailure?
    @Published public private(set) var clearState: ClearState = .unknown
    @Published public private(set) var clearConfirmedAt: Date?
    @Published public private(set) var realLocation: RealLocationObservation?
    @Published public private(set) var pointState: PointMoveState = .idle
    @Published public private(set) var confirmedSimulatedLocation: GeoCoordinate?
    @Published public private(set) var preparedOperation: PreparedOperationSnapshot?

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
    public var canStart: Bool { !nativeBusy && phase == .stopped }
    public var canStop: Bool {
        !clearScheduled && (phase == .ready || phase == .preparing || phase == .repairRequired)
    }
    public var canRestoreGPS: Bool { !nativeBusy && phase == .stopped }
    public var canResetTunnel: Bool { canRestoreGPS }
    public var canTeleport: Bool {
        !nativeBusy && !pointUnconfirmed && !routeUnconfirmed && (phase == .stopped || phase == .ready)
    }
    private var pointUnconfirmed: Bool {
        if case .unconfirmed = pointState { return true }
        return false
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
        phase = context.wasReady ? .ready : .stopped
        error = nil
        return true
    }

    @discardableResult public func retryPreparedOperation(id: UUID) -> Bool {
        guard !nativeBusy, !pointUnconfirmed, let snapshot = preparedOperation,
              snapshot.id == id, case .failed = snapshot.state else { return false }
        if case .route(let intent) = snapshot.source {
            guard let owner = routeOwners[intent.id], !owner.ended, !owner.unknown, owner.begin != nil,
                  !routeUnconfirmed, (phase == .ready || phase == .stopped) else { return false }
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
                case .start: break
                case .point(let intent): self?.pointDidDispatch(intent.id)
                case .route(let intent): self?.routeDidDispatch(intent)
                }
            }
        }
        if case .start = source { return PointDispatchGate(onDispatch: callback) }
        return PointDispatchGate(authority: movementAuthority, lease: lease,
            replacing: movementAuthority.snapshot, onDispatch: callback)
    }

    private func enqueuePreparationAttempt(_ context: PreparationContext, attempt: PreparationAttempt,
                                            token: UInt64, point: PointContext?) {
        let owner: RouteOwner?
        if case .route(let intent) = context.source { owner = routeOwners[intent.id] } else { owner = nil }
        owner?.pendingCalls += 1
        enqueueAdapter({ [weak self] service in
            guard let self, self.revision == token, self.preparationIsCurrent(context) else { return .failure(.operationCancelled) }
            self.publishAttempt(attempt, context: context)
            switch context.source {
            case .start:
                do { try await service.prepare(); return .success }
                catch { return .failure(error as? DeviceServiceFailure ?? .serviceUnavailable) }
            case .point(let intent):
                return .point(await service.movePoint(to: intent.candidate.place.coordinate, dispatch: context.dispatch))
            case .route(let intent):
                return .point(await service.movePoint(to: intent.route.start, dispatch: context.dispatch))
            }
        }) { [weak self] result in
            guard let self else { return }
            owner?.pendingCalls -= 1
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
        movementAuthority.revokeAll()
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
                if operation == .stopping || operation == .restoring {
                    clearState = .confirmed
                    clearConfirmedAt = now()
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
            if phase == .repairRequired && !pointUnconfirmed && !routeUnconfirmed { phase = .stopped }
        }
        routeSubject.send(.availabilityChanged)
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
              movementAuthority.snapshot.health == .confirmedHealthy, !routeUnconfirmed else { return nil }
        return owner
    }
    public func sendRoutePoint(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedControlRevision: UInt64,
                               coordinate: GeoCoordinate) async -> RouteCommandOutcome {
        guard let owner = routeOwners[executionID], owner.intent.lease == lease, owner.begun,
              !owner.ended, !owner.unknown, owner.tick == nil, sequence == owner.lastSequence + 1,
              movementAuthority.permitsDispatch(for: lease), !routeUnconfirmed else { return .cancelled }
        guard owner.controlRevision == expectedControlRevision else { return .controlCancelled }
        let gate = PointDispatchGate(authority: movementAuthority, lease: lease) { [weak self] in
            Task { @MainActor in self?.routeTickDidDispatch(executionID: executionID, sequence: sequence) }
        }
        let tick = RouteTick(gate: gate, coordinate: coordinate, sequence: sequence)
        owner.tick = tick; owner.pendingCalls += 1
        return await withCheckedContinuation { continuation in
            enqueueAdapter({ [weak self] service in
                guard let self, self.routeTickIsCurrent(owner, tick), self.movementAuthority.permitsDispatch(for: lease) else {
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
              movementAuthority.snapshot.health == .confirmedHealthy, movementAuthority.snapshot.runState == .paused else { return false }
        return movementAuthority.updateRunState(.running, for: lease)
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

    private var hasPendingRouteRepair: Bool { routeOwners.values.contains { ($0.unknown || $0.interrupted || $0.ended) && $0.pendingCalls > 0 } }
    private func admitExplicitOperation() {
        routeAdmissionRevision &+= 1
        // A failed route preparation may still be awaiting user Retry/Cancel.
        for owner in Array(routeOwners.values) where owner.begin != nil {
            endRoute(executionID: owner.intent.id, lease: owner.intent.lease)
        }
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
