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

    private struct DisplayedPosition {
        let coordinate: GeoCoordinate
        let source: PositionSource
    }
    private struct PointContext: Sendable {
        let intent: PointMoveIntent
        let dispatch: PointDispatchGate
        let wasReady: Bool
    }
    private enum CommandResult: Sendable {
        case success
        case failure(DeviceServiceFailure)
        case point(PointDeliveryOutcome)
    }

    private let service: any DeviceService
    private let operationTimeout: Duration
    private let now: @Sendable () -> Date
    private var revision: UInt64 = 0
    private var outstandingWork = 0
    private var clearScheduled = false
    private var clearAttempted = false
    private var lastDisplayedPosition: DisplayedPosition?
    private var currentPoint: PointContext?
    private var tail: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    public init(
        service: any DeviceService, operationTimeout: Duration = .seconds(30),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
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
        let intent = PointMoveIntent(candidate: candidate)
        let dispatch = PointDispatchGate { [weak self] in
            Task { @MainActor in self?.pointDidDispatch(intent.id) }
        }
        let point = PointContext(intent: intent, dispatch: dispatch, wasReady: phase == .ready)
        currentPoint = point
        pointState = .preparing(intent)
        enqueueCommand(.preparing, point: point) { service in
            .point(await service.movePoint(to: candidate.place.coordinate, dispatch: dispatch))
        }
        return true
    }

    @discardableResult public func start() -> Bool {
        guard canStart else { return false }
        enqueue(.preparing) { try await $0.prepare() }
        return true
    }

    /// Safety cleanup is unconditional FIFO work. Invalidation can skip a point
    /// before dispatch but cannot cancel an FFI call that already owns handles.
    @discardableResult public func stop() -> Bool {
        guard canStop else { return false }
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
        _ operation: ServicePhase, point: PointContext? = nil,
        work: @escaping @Sendable (any DeviceService) async -> CommandResult
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
            if let point {
                point.dispatch.invalidate()
                if point.dispatch.hasDispatched {
                    self.pointDidDispatch(point.intent.id)
                    self.pointState = .unconfirmed(point.intent, .operationTimedOut)
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
            self?.complete(operation, token: token, result: result, point: point)
        }
    }

    private func complete(
        _ operation: ServicePhase, token: UInt64,
        result: CommandResult, point: PointContext?
    ) {
        outstandingWork -= 1
        if operation == .stopping || operation == .restoring { clearScheduled = false }
        if token == revision {
            watchdog?.cancel()
            switch result {
            case .success:
                phase = operation == .preparing ? .ready : .stopped
                error = nil
                if operation == .stopping || operation == .restoring {
                    clearState = .confirmed
                    clearConfirmedAt = now()
                }
            case .failure(let failure):
                phase = .stopped
                error = failure
                if operation == .stopping || operation == .restoring {
                    clearState = .unknown
                    clearConfirmedAt = nil
                }
            case .point(let outcome):
                if let point { completePoint(point, outcome: outcome) }
            }
        }
        if let point, currentPoint?.intent.id == point.intent.id { currentPoint = nil }
        if outstandingWork == 0 {
            nativeBusy = false
            tail = nil
            if phase == .repairRequired && !pointUnconfirmed { phase = .stopped }
        }
    }

    private func completePoint(_ point: PointContext, outcome: PointDeliveryOutcome) {
        if point.dispatch.hasDispatched { pointDidDispatch(point.intent.id) }
        switch outcome {
        case .notSent(let failure):
            if point.dispatch.hasDispatched {
                pointState = .unconfirmed(point.intent, failure)
                phase = .repairRequired
            } else {
                pointState = .notSent(point.intent, failure)
                phase = point.wasReady ? .ready : .stopped
            }
            error = failure
        case .acknowledged:
            guard point.dispatch.hasDispatched else {
                pointState = .unconfirmed(point.intent, .serviceUnavailable)
                phase = .repairRequired
                error = .serviceUnavailable
                return
            }
            confirmedSimulatedLocation = point.intent.candidate.place.coordinate
            lastDisplayedPosition = DisplayedPosition(coordinate: point.intent.candidate.place.coordinate, source: .simulation)
            pointState = .acknowledged(point.intent)
            phase = .ready
            error = nil
        case .unconfirmed(let failure):
            pointState = .unconfirmed(point.intent, failure)
            phase = .repairRequired
            error = failure
        }
    }
}
