import Combine
import Foundation

@MainActor
public final class ServiceController: ObservableObject {
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
    private let service: any DeviceService
    private let operationTimeout: Duration
    private let now: @Sendable () -> Date
    private var revision: UInt64 = 0
    private var outstandingWork = 0
    private var clearScheduled = false
    private var clearAttempted = false
    private var lastDisplayedPosition: DisplayedPosition?
    private var currentPoint: PointContext?
    private var currentPreparation: PreparationContext?
    private var tail: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    public init(
        service: any DeviceService, operationTimeout: Duration = .seconds(30),
        now: @escaping @Sendable () -> Date = { Date() },
        movementAuthority: MovementTaskAuthority = MovementTaskAuthority()
    ) {
        self.service = service
        self.movementAuthority = movementAuthority
        self.operationTimeout = operationTimeout
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
        !nativeBusy && !pointUnconfirmed && (phase == .stopped || phase == .ready)
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
        beginPreparation(.point(PointMoveIntent(candidate: candidate)))
        return true
    }

    @discardableResult public func start() -> Bool {
        guard canStart else { return false }
        beginPreparation(.start)
        return true
    }

    @discardableResult public func cancelPreparation(id: UUID) -> Bool {
        if !nativeBusy, let snapshot = preparedOperation, snapshot.id == id, case .failed = snapshot.state {
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
        phase = context.wasReady ? .ready : .stopped
        error = nil
        return true
    }

    @discardableResult public func retryPreparedOperation(id: UUID) -> Bool {
        guard !nativeBusy, !pointUnconfirmed, let snapshot = preparedOperation,
              snapshot.id == id, case .failed = snapshot.state else { return false }
        beginPreparation(snapshot.source)
        return true
    }

    private func beginPreparation(_ source: PreparedOperationSource) {
        let lease = MovementTaskLease()
        let onDispatch: @Sendable () -> Void = { [weak self] in
            guard case .point(let intent) = source else { return }
            Task { @MainActor in self?.pointDidDispatch(intent.id) }
        }
        let dispatch: PointDispatchGate
        switch source {
        case .start: dispatch = PointDispatchGate(onDispatch: onDispatch)
        case .point:
            dispatch = PointDispatchGate(authority: movementAuthority, lease: lease,
                replacing: movementAuthority.snapshot, onDispatch: onDispatch)
        }
        let context = PreparationContext(id: UUID(), source: source, dispatch: dispatch, wasReady: phase == .ready)
        currentPreparation = context
        preparedOperation = PreparedOperationSnapshot(id: context.id, source: source, attempt: .first, state: .preparing)
        let point: PointContext?
        if case .point(let intent) = source {
            point = PointContext(intent: intent, dispatch: dispatch, wasReady: context.wasReady, lease: lease)
            currentPoint = point
            pointState = .preparing(intent)
        } else { point = nil }
        enqueueCommand(.preparing, point: point, preparation: context) { [weak self] service in
            var attempt = PreparationAttempt.first
            while true {
                // Admission and publication share the lifecycle actor; no reentrant gap precedes the adapter call.
                guard self?.preparationIsCurrent(context) == true else { return .failure(.operationCancelled) }
                self?.publishAttempt(attempt, context: context)
                let result: CommandResult
                switch source {
                case .start:
                    do { try await service.prepare(); result = .success }
                    catch { result = .failure(error as? DeviceServiceFailure ?? .serviceUnavailable) }
                case .point(let intent):
                    result = .point(await service.movePoint(to: intent.candidate.place.coordinate, dispatch: dispatch))
                }
                let retryable: Bool
                switch result {
                case .failure: retryable = true
                case .point(.notSent): retryable = true
                default: retryable = false
                }
                guard retryable, dispatch.state == .available,
                      self?.preparationIsCurrent(context) == true,
                      let next = attempt.next else { return result }
                attempt = next
                await Task.yield()
            }
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
        movementAuthority.revokeAll()
        currentPreparation?.dispatch.invalidate()
        currentPreparation = nil
        preparedOperation = nil
        currentPoint?.dispatch.invalidate()
        currentPoint = nil
        pointState = .idle
        beginClear()
        enqueue(.stopping) { try await $0.clearLocation() }
        return true
    }

    @discardableResult public func restoreGPS() -> Bool {
        guard canRestoreGPS else { return false }
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
        revision &+= 1
        let token = revision
        let previous = tail
        phase = operation
        error = nil
        nativeBusy = true
        outstandingWork += 1
        watchdog?.cancel()
        let timeout = operationTimeout
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
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
            if operation == .stopping || operation == .restoring {
                self.clearState = .unknown
            }
            // Only actual completion releases nativeBusy and permits FIFO clear.
        }
        let service = service
        tail = Task { [weak self] in
            await previous?.value
            let result = await work(service)
            self?.complete(operation, token: token, result: result, point: point, preparation: preparation)
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
            nativeBusy = false
            tail = nil
            if phase == .repairRequired && !pointUnconfirmed { phase = .stopped }
        }
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
