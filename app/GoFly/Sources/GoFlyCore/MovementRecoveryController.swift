import Combine
import Foundation

/// Coordinates foreground reachability checks and the data-only recovery
/// projection. It never creates a movement owner or resumes a controller.
@MainActor
public final class MovementRecoveryController: ObservableObject {
    @Published public private(set) var connectionState: VPNCheckState = .unknown
    @Published public private(set) var isChecking = false
    @Published public private(set) var checkpointRevision: UInt64 = 0

    private let service: ServiceController
    private let route: RouteExecutionController
    private let joystick: JoystickMovementController
    private let probe: any TunnelProbing
    private let clock: any RouteClock
    private var retainedSnapshot: SessionRecoverySnapshot?
    private var coldSummaryDiscarded = false
    private var discardedColdUncertainty: SessionMovementUncertainty?
    private var sceneActive = false
    private var generation: UInt64 = 0
    private var checkTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var lastProbeFinishedAt: Duration?
    private var lastObservedPhase: ServicePhase
    private var recoveredNotice = false
    private var probeStartedFromFailure = false
    private var checkNoticeVisible = false
    private var revisionQueued = false
    private var subscriptions: [AnyCancellable] = []

    public init(
        service: ServiceController,
        route: RouteExecutionController,
        joystick: JoystickMovementController,
        probe: any TunnelProbing,
        clock: any RouteClock = ContinuousRouteClock(),
        retainedColdSnapshot: SessionRecoverySnapshot? = nil
    ) {
        self.service = service
        self.route = route
        self.joystick = joystick
        self.probe = probe
        self.clock = clock
        self.retainedSnapshot = retainedColdSnapshot
        self.lastObservedPhase = service.phase

        subscriptions = [
            service.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            route.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            joystick.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            service.joystickEvents.sink { [weak self] event in
                guard case .movementBoundary(nil) = event else { return }
                self?.invalidateProbeForSafety()
            }
        ]

        if let retainedColdSnapshot {
            let needsConfirmation = retainedColdSnapshot.activeMovement != nil || retainedColdSnapshot.uncertainty != nil
            _ = service.restoreColdRecovery(position: retainedColdSnapshot.position,
                                            requiresConfirmation: needsConfirmation)
        }
    }

    deinit {
        checkTask?.cancel()
        monitorTask?.cancel()
    }

    public var requiresColdConfirmation: Bool {
        service.coldRecoveryHeld || (retainedSummaryAvailable &&
            (retainedSnapshot?.activeMovement != nil || retainedSnapshot?.uncertainty != nil))
    }

    public var unverifiedMovement: SessionActiveRecovery? {
        guard retainedSummaryAvailable else { return nil }
        return retainedSnapshot?.activeMovement
    }

    public var unverifiedUncertainty: SessionMovementUncertainty? {
        if service.clearState == .confirmed { return nil }
        if retainedSummaryAvailable, let uncertainty = retainedSnapshot?.uncertainty { return uncertainty }
        if let discardedColdUncertainty { return discardedColdUncertainty }
        guard let uncertainty = service.recoveryUncertainty else { return nil }
        return normalized(uncertainty)
    }

    public var noticeKey: String? {
        if requiresColdConfirmation { return "recovery.confirmationNeeded" }
        if isChecking && checkNoticeVisible { return "recovery.connectionChecking" }
        if recoveredNotice { return "recovery.connectionRecovered" }
        switch connectionState {
        case .unavailable, .timedOut: return "recovery.connectionLost"
        case .unknown, .checking, .reachable: return nil
        }
    }

    public var canCheck: Bool {
        sceneActive && !isChecking && isManualProbeEligible
    }

    public func sceneDidBecomeActive() {
        guard !sceneActive else { return }
        sceneActive = true
        route.sceneDidBecomeActive()
        joystick.sceneDidBecomeActive()
        // A foreground return is an explicit freshness boundary. It bypasses
        // the ordinary two-second healthy monitor interval, while still
        // requiring an actually ready service or a known connection fence.
        evaluateServiceState(immediate: true)
    }

    public func releaseForInactiveScene(continuingLease: MovementTaskLease? = nil) {
        sceneActive = false
        generation &+= 1
        checkTask?.cancel()
        monitorTask?.cancel()
        monitorTask = nil
        isChecking = false
        connectionState = .unknown
        recoveredNotice = false
        checkNoticeVisible = false
        if checkTask == nil {
            route.recoveryProbeDidFinish()
            joystick.recoveryProbeDidFinish()
        }
        route.releaseForInactiveScene(continuingLease: continuingLease)
        joystick.releaseForInactiveScene(continuingLease: continuingLease)
    }

    /// A manual check joins an in-flight check; it never starts a second probe.
    public func checkConnection() {
        monitorTask?.cancel()
        monitorTask = nil
        guard sceneActive, isManualProbeEligible else { return }
        guard checkTask == nil else { return }
        beginProbe(manual: true, showCheckingNotice: true)
    }

    /// This forgets the visible old-task summary. The service cold hold remains
    /// until an actual clear acknowledgement releases it.
    public func discardUnverifiedMovement() {
        retainedSnapshot = nil
        coldSummaryDiscarded = true
        if service.coldRecoveryHeld {
            discardedColdUncertainty = SessionMovementUncertainty(source: .unverifiedPreviousMovement)
        }
        queueCheckpointRevision()
    }

    public func snapshot(mode: SessionMapMode) -> SessionRecoverySnapshot {
        reconcileColdClear()
        let position = service.positionMarker.map {
            SessionDisplayPosition(coordinate: $0.coordinate, source: $0.source)
        } ?? retainedSnapshot?.position
        let runtime = activeMovement()
        let clearPending = service.clearState != .confirmed &&
            (service.clearState == .pending || service.statusKey == "service.stoppedGPSPending")
        let active = clearPending ? nil : (runtime ?? (coldSummaryDiscarded ? nil : retainedSnapshot?.activeMovement))
        let uncertainty = normalized(service.recoveryUncertainty) ??
            (coldSummaryDiscarded ? discardedColdUncertainty : retainedSnapshot?.uncertainty)
        return SessionRecoverySnapshot(
            mode: mode,
            draft: route.draft,
            roundTripEnabled: route.roundTripEnabled,
            joystickSpeed: joystick.speed,
            position: position,
            activeMovement: active,
            uncertainty: uncertainty
        )
    }

    /// Manual checks are allowed while stopped so an initial or cold session
    /// can explicitly establish connectivity. They never create movement.
    private var isManualProbeEligible: Bool {
        guard !service.nativeBusy else { return false }
        if service.phase == .ready { return true }
        return service.phase == .stopped || service.phase == .repairRequired
    }

    /// Automatic checks require actual service readiness or an already-known
    /// unavailable connection fence. A cold hold alone is display state, not
    /// evidence that a probe should run.
    private var isAutomaticProbeEligible: Bool {
        guard !service.nativeBusy else { return false }
        if service.phase == .ready { return true }
        guard service.phase == .stopped || service.phase == .repairRequired else { return false }
        return !service.movementConnectionAvailable
    }

    private var retainedSummaryAvailable: Bool {
        !coldSummaryDiscarded && service.clearState != .confirmed
    }

    private func evaluateServiceState(immediate: Bool = false) {
        let phase = service.phase
        if lastObservedPhase == .ready, phase != .ready {
            generation &+= 1
            checkTask?.cancel()
            isChecking = false
            connectionState = .unknown
            checkNoticeVisible = false
        }
        lastObservedPhase = phase
        guard sceneActive else { return }
        guard isAutomaticProbeEligible else {
            monitorTask?.cancel()
            monitorTask = nil
            return
        }
        scheduleProbeIfDue(immediate: immediate)
    }

    private func scheduleProbeIfDue(immediate: Bool = false) {
        guard sceneActive, isAutomaticProbeEligible, checkTask == nil, monitorTask == nil else { return }
        let delay: Duration
        if immediate {
            delay = .zero
        } else if let lastProbeFinishedAt {
            delay = max(.zero, .seconds(2) - (clock.now - lastProbeFinishedAt))
        } else {
            delay = .zero
        }
        if delay == .zero {
            beginProbe(showCheckingNotice: immediate)
            return
        }
        let token = generation
        let clock = clock
        monitorTask = Task { [weak self] in
            do { try await clock.sleep(for: delay) } catch { return }
            guard let self, self.generation == token, self.sceneActive else { return }
            // Clear the completed timer before re-checking eligibility. A
            // native-busy wake may make the probe ineligible without causing
            // another objectWillChange evaluation, and the finished task must
            // not block a later automatic schedule.
            self.monitorTask = nil
            guard self.isAutomaticProbeEligible else { return }
            self.beginProbe()
        }
    }

    private func beginProbe(manual: Bool = false, showCheckingNotice: Bool = false) {
        let eligible = manual ? isManualProbeEligible : isAutomaticProbeEligible
        guard sceneActive, eligible, checkTask == nil else { return }
        monitorTask?.cancel()
        monitorTask = nil
        generation &+= 1
        let token = generation
        let probe = probe
        probeStartedFromFailure = connectionState == .unavailable || connectionState == .timedOut
        recoveredNotice = false
        checkNoticeVisible = showCheckingNotice
        isChecking = true
        connectionState = .checking
        route.recoveryProbeDidStart()
        joystick.recoveryProbeDidStart()
        checkTask = Task { [weak self] in
            let result: Result<Void, TunnelProbeFailure>
            do {
                try await probe.check()
                result = .success(())
            } catch let failure as TunnelProbeFailure {
                result = .failure(failure)
            } catch {
                result = .failure(.unavailable)
            }
            guard let self else { return }
            guard self.generation == token, self.sceneActive else {
                // Keep the in-flight reference until this task has actually
                // observed cancellation. This is the max-one probe boundary.
                self.checkTask = nil
                self.checkNoticeVisible = false
                self.route.recoveryProbeDidFinish()
                self.joystick.recoveryProbeDidFinish()
                if self.sceneActive { self.evaluateServiceState(immediate: true) }
                return
            }
            self.checkTask = nil
            self.isChecking = false
            self.checkNoticeVisible = false
            self.route.recoveryProbeDidFinish()
            self.joystick.recoveryProbeDidFinish()
            self.lastProbeFinishedAt = self.clock.now
            switch result {
            case .success:
                self.connectionState = .reachable
                self.recoveredNotice = self.probeStartedFromFailure
                self.service.setMovementConnectionAvailable(true)
                self.route.connectionDidBecomeAvailable()
                self.joystick.connectionDidBecomeAvailable()
            case .failure(let failure):
                self.connectionState = failure == .timedOut ? .timedOut : .unavailable
                self.service.setMovementConnectionAvailable(false)
                self.route.connectionDidBecomeUnavailable()
                self.joystick.connectionDidBecomeUnavailable()
            }
            self.scheduleProbeIfDue()
        }
    }

    /// Stop/reset emits this synchronously before any adapter clear work. It
    /// invalidates an in-flight probe generation before a late positive can
    /// reopen movement admission.
    private func invalidateProbeForSafety() {
        generation &+= 1
        checkTask?.cancel()
        monitorTask?.cancel()
        monitorTask = nil
        isChecking = false
        connectionState = .unknown
        checkNoticeVisible = false
        route.recoveryProbeDidFinish()
        joystick.recoveryProbeDidFinish()
    }

    private func observeDomainMutation() {
        queueCheckpointRevision()
        let token = generation
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.generation == token else { return }
            self.evaluateServiceState()
        }
    }

    private func queueCheckpointRevision() {
        guard !revisionQueued else { return }
        revisionQueued = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.revisionQueued = false
            if self.checkpointRevision < UInt64.max { self.checkpointRevision += 1 }
        }
    }

    private func reconcileColdClear() {
        guard service.clearState == .confirmed else { return }
        retainedSnapshot = nil
        coldSummaryDiscarded = true
        discardedColdUncertainty = nil
    }

    private func normalized(_ uncertainty: SessionMovementUncertainty?) -> SessionMovementUncertainty? {
        guard let uncertainty else { return nil }
        if uncertainty.source == .joystick, joystick.wanderEnabled {
            return SessionMovementUncertainty(source: .wander, requestedPlace: uncertainty.requestedPlace)
        }
        return uncertainty
    }

    private func activeMovement() -> SessionActiveRecovery? {
        // Manual input has no safe replay payload. Preserve only an installed
        // owner; a preparing gesture has no native claim to report.
        if joystick.recoveryHasAcknowledgedLease,
           joystick.intent != nil, !joystick.wanderEnabled,
           [.moving, .settling, .paused].contains(joystick.phase) {
            return .manual
        }

        let authority = service.movementAuthority.snapshot
        guard let lease = authority.lease,
              authority.health == .confirmedHealthy,
              authority.runState != nil else { return nil }

        if let intent = route.intent, intent.lease == lease,
           let progress = route.progress,
           [.running, .paused].contains(route.phase) {
            return .route(SessionRouteRecovery(
                draft: intent.draft,
                route: intent.route,
                progress: progress,
                roundTripEnabled: route.roundTripEnabled,
                usesPositionAxis: route.usesPositionAxis,
                heading: route.heading,
                state: route.phase == .running ? .running : .paused
            ))
        }

        if let intent = joystick.intent, intent.lease == lease,
           joystick.wanderEnabled,
           let coordinate = joystick.lastAcknowledgedCoordinate,
           [.moving, .paused, .suspended].contains(joystick.phase),
           let target = joystick.wanderTarget {
            return .wander(SessionWanderRecovery(
                target: target,
                speed: joystick.speed,
                history: joystick.recoveryWanderHistory,
                lastAcknowledgedCoordinate: coordinate,
                lastAcknowledgedBearingDegrees: joystick.lastAcknowledgedBearingDegrees,
                state: joystick.phase == .moving ? .running : .paused
            ))
        }

        return nil
    }
}
