import Combine
import Foundation
import Testing
import GoFlyCore

@Suite @MainActor
struct MovementRecoveryControllerTests {
    @Test func coldSummaryIsDisplayOnlyAndProbeStartsOnlyForAnActiveScene() async throws {
        let device = RecoveryControllerDevice()
        let service = ServiceController(service: device)
        let retained = SessionRecoverySnapshot(
            position: SessionDisplayPosition(
                coordinate: GeoCoordinate(latitude: 25, longitude: 121)!, source: .simulation
            ),
            activeMovement: .manual,
            uncertainty: SessionMovementUncertainty(source: .unverifiedPreviousMovement)
        )
        let probe = RecoveryControllerProbe()
        let route = RouteExecutionController(planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch())
        let joystick = JoystickMovementController(commands: service)
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick,
                                                   probe: probe, retainedColdSnapshot: retained)

        #expect(await probe.count == 0)
        #expect(recovery.requiresColdConfirmation)
        #expect(recovery.unverifiedMovement == .manual)
        #expect(recovery.noticeKey == "recovery.confirmationNeeded")
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(service.positionMarker?.freshness == .waiting)

        recovery.sceneDidBecomeActive()
        #expect(await probe.count == 0)
        #expect(recovery.canCheck)
        recovery.checkConnection()
        await wait { await probe.count == 1 }
        #expect(recovery.connectionState == .reachable)
        #expect(await probe.count == 1)
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(!service.canTeleport)

        recovery.discardUnverifiedMovement()
        #expect(recovery.unverifiedMovement == nil)
        #expect(recovery.unverifiedUncertainty?.source == .unverifiedPreviousMovement)
        #expect(recovery.requiresColdConfirmation)
        #expect(recovery.snapshot(mode: .teleport).uncertainty?.source == .unverifiedPreviousMovement)

        #expect(service.restoreGPS())
        await wait { service.clearState == .confirmed && !service.nativeBusy }
        #expect(!recovery.requiresColdConfirmation)
        #expect(recovery.unverifiedMovement == nil)
        #expect(service.canTeleport)
    }

    @Test func failedProbeClosesAdmissionWithoutRewritingNativeFailure() async throws {
        let device = RecoveryControllerDevice()
        let service = ServiceController(service: device)
        service.setMovementConnectionAvailable(false)
        let probe = RecoveryControllerProbe(failure: .timedOut)
        let route = RouteExecutionController(planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch())
        let joystick = JoystickMovementController(commands: service)
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick, probe: probe)

        recovery.sceneDidBecomeActive()
        await wait { await probe.count == 1 }
        #expect(recovery.connectionState == .timedOut)
        #expect(recovery.noticeKey == "recovery.connectionLost")
        #expect(!service.movementConnectionAvailable)
        #expect(service.error == nil)
        #expect(!route.canStart)
        #expect(!joystick.canBeginGesture)
    }

    @Test func foregroundFreshProbeIsImmediateAndRepeatedActiveIsIdempotent() async throws {
        let device = RecoveryControllerDevice()
        let service = ServiceController(service: device)
        #expect(service.start())
        await wait { service.phase == .ready && !service.nativeBusy }
        let probe = RecoveryControllerProbe(hold: true)
        let route = RouteExecutionController(planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch())
        let joystick = JoystickMovementController(commands: service)
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick, probe: probe)

        recovery.sceneDidBecomeActive()
        await wait { await probe.count == 1 && recovery.isChecking }
        recovery.sceneDidBecomeActive()
        #expect(await probe.count == 1)
        #expect(recovery.noticeKey == "recovery.connectionChecking")
        await probe.release()
        await wait { recovery.connectionState == .reachable && !recovery.isChecking }
        recovery.releaseForInactiveScene()
    }

    @Test func acceptedClearKeepsTerminalSnapshotUncertainUntilAcknowledgement() async throws {
        let device = RecoveryControllerDevice(holdClear: true)
        let service = ServiceController(service: device)
        let retained = SessionRecoverySnapshot(activeMovement: .manual,
            uncertainty: SessionMovementUncertainty(source: .unverifiedPreviousMovement))
        let route = RouteExecutionController(planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch())
        let joystick = JoystickMovementController(commands: service)
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick,
                                                   probe: RecoveryControllerProbe(), retainedColdSnapshot: retained)

        #expect(service.restoreGPS())
        await wait { await device.clearStarted }
        #expect(recovery.snapshot(mode: .teleport).activeMovement == nil)
        #expect(recovery.snapshot(mode: .teleport).uncertainty?.source == .gpsRecovery)
        #expect(recovery.unverifiedMovement == .manual)
        await device.releaseClear()
        await wait { service.clearState == .confirmed && !service.nativeBusy }
        #expect(recovery.unverifiedMovement == nil)
    }

    @Test func stoppedColdHoldNeedsExplicitProbeInsteadOfAutomaticForegroundProbe() async throws {
        let device = RecoveryControllerDevice()
        let service = ServiceController(service: device)
        let position = SessionDisplayPosition(coordinate: GeoCoordinate(latitude: 25, longitude: 121)!, source: .gps)
        #expect(service.restoreColdRecovery(position: position, requiresConfirmation: true))
        let probe = RecoveryControllerProbe()
        let route = RouteExecutionController(planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch())
        let joystick = JoystickMovementController(commands: service)
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick, probe: probe)
        recovery.sceneDidBecomeActive()
        await Task.yield()
        #expect(await probe.count == 0)
        #expect(recovery.canCheck)
        recovery.checkConnection()
        await wait { await probe.count == 1 }
    }

    @Test func acceptedStopInvalidatesLateProbeWithoutReopeningConnectionFence() async throws {
        let device = RecoveryControllerDevice(holdClear: true)
        let service = ServiceController(service: device)
        #expect(service.start())
        await wait { service.phase == .ready && !service.nativeBusy }
        service.setMovementConnectionAvailable(false)
        let probe = RecoveryControllerProbe(hold: true)
        let route = RouteExecutionController(planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch())
        let joystick = JoystickMovementController(commands: service)
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick, probe: probe)
        recovery.sceneDidBecomeActive()
        await wait { await probe.count == 1 && recovery.isChecking }

        #expect(service.stop())
        await wait { await device.clearStarted }
        await probe.release()
        await Task.yield()
        #expect(!service.movementConnectionAvailable)
        #expect(recovery.connectionState == .unknown)
        recovery.releaseForInactiveScene()
        await device.releaseClear()
        await wait { service.clearState == .confirmed && !service.nativeBusy }
    }

    @Test func queuedPreparationIsNotReportedAsMovementUncertainty() async throws {
        let device = RecoveryControllerDevice(holdPrepare: true)
        let service = ServiceController(service: device)
        let intent = JoystickMovementIntent()
        let beginning = Task {
            await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision)
        }
        await wait { await device.prepareStarted }
        #expect(service.recoveryUncertainty == nil)
        await device.releasePrepare()
        #expect(await beginning.value == .prepared)
        #expect(service.recoveryUncertainty == nil)
    }

    @Test func unavailableFenceWithdrawsQueuedJoystickAndRouteBeforeNativeWrite() async throws {
        let joystickDevice = RecoveryControllerDevice(holdPrepare: true)
        let joystickService = ServiceController(service: joystickDevice)
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        joystickService.observeRealLocation(RealLocationObservation(latitude: origin.latitude, longitude: origin.longitude,
            horizontalAccuracy: 1, observedAt: Date()))
        let joystick = JoystickMovementController(commands: joystickService)
        #expect(joystick.beginGesture(id: UUID(), input: JoystickInput(bearingDegrees: 0, strength: 1)!))
        await wait { await joystickDevice.prepareStarted }
        joystickService.setMovementConnectionAvailable(false)
        joystick.connectionDidBecomeUnavailable()
        await joystickDevice.releasePrepare()
        await wait { joystick.phase == .neutral && !joystickService.nativeBusy }
        #expect(joystickService.movementAuthority.snapshot.lease == nil)
        #expect(await joystickDevice.moveCount == 0)

        let routeDevice = RecoveryControllerDevice(holdMoveBeforeClaim: true)
        let routeService = ServiceController(service: routeDevice)
        let start = GeoCoordinate(latitude: 25, longitude: 121)!
        let end = GeoCoordinate(latitude: 25.01, longitude: 121.01)!
        let place: (GeoCoordinate) -> MapPlace = {
            MapPlace(id: .coordinate($0), title: $0.displayText, coordinate: $0)
        }
        let draft = try #require(RouteDraft(start: .place(place(start)), destination: .place(place(end))))
        let route = RouteExecutionController(draft: draft, planner: RecoveryControllerPlanner(), commands: routeService,
                                               search: RecoveryControllerSearch())
        #expect(route.start())
        await wait { await routeDevice.moveEntered }
        routeService.setMovementConnectionAvailable(false)
        route.connectionDidBecomeUnavailable()
        await routeDevice.releaseMove()
        await wait { route.phase == .editing && !routeService.nativeBusy }
        #expect(routeService.movementAuthority.snapshot.lease == nil)
        #expect(await routeDevice.moveCount == 0)
    }

    @Test func claimedJoystickLossRequiresAckOrUnknownAndNeverAutoResumes() async throws {
        let device = RecoveryControllerDevice(holdMoveAfterClaim: true)
        let service = ServiceController(service: device)
        #expect(service.start())
        await wait { service.phase == .ready && !service.nativeBusy }
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(RealLocationObservation(latitude: origin.latitude, longitude: origin.longitude,
            horizontalAccuracy: 1, observedAt: Date()))
        let joystick = JoystickMovementController(commands: service)
        #expect(joystick.beginGesture(id: UUID(), input: JoystickInput(bearingDegrees: 0, strength: 1)!))
        await wait { await device.moveEntered }
        service.setMovementConnectionAvailable(false)
        joystick.connectionDidBecomeUnavailable()
        #expect(service.recoveryUncertainty?.source == .joystick)
        #expect(!joystick.canResume)
        await device.releaseMove()
        await wait { joystick.phase == .neutral || joystick.phase == .unknown }
        #expect(!service.movementConnectionAvailable)
        #expect(await device.moveCount == 1)
        #expect(!joystick.canResume)
    }

    @Test func firstRouteClaimIsPersistedAsUncertaintyUntilAckThenBecomesActiveTruth() async throws {
        let device = RecoveryControllerDevice(holdFirstMoveAfterClaim: true)
        let service = ServiceController(service: device)
        let start = GeoCoordinate(latitude: 25, longitude: 121)!
        let end = GeoCoordinate(latitude: 25.01, longitude: 121.01)!
        let place: (GeoCoordinate) -> MapPlace = {
            MapPlace(id: .coordinate($0), title: $0.displayText, coordinate: $0)
        }
        let draft = try #require(RouteDraft(start: .place(place(start)), destination: .place(place(end))))
        let route = RouteExecutionController(draft: draft, planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch())
        let recovery = MovementRecoveryController(service: service, route: route,
            joystick: JoystickMovementController(commands: service), probe: RecoveryControllerProbe())

        #expect(route.start())
        await wait { await device.moveStarted }
        let beforeAck = recovery.snapshot(mode: .route)
        #expect(beforeAck.activeMovement == nil)
        #expect(beforeAck.uncertainty?.source == .route)

        let encoded = try SessionRecoveryCodec.encode(beforeAck)
        #expect(try SessionRecoveryCodec.decode(encoded) == beforeAck)
        let persistence = RecoveryMemoryPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        #expect(store.capture(beforeAck))
        #expect(await store.flush())
        let relaunchedStore = SessionRecoveryStore(persistence: persistence)
        #expect(relaunchedStore.loadState == .ready)
        #expect(relaunchedStore.initialSnapshot.uncertainty?.source == .route)

        let relaunchedService = ServiceController(service: RecoveryControllerDevice())
        let relaunchedRoute = RouteExecutionController(planner: RecoveryControllerPlanner(), commands: relaunchedService,
                                                         search: RecoveryControllerSearch())
        let relaunchedRecovery = MovementRecoveryController(service: relaunchedService, route: relaunchedRoute,
            joystick: JoystickMovementController(commands: relaunchedService), probe: RecoveryControllerProbe(),
            retainedColdSnapshot: relaunchedStore.initialSnapshot)
        #expect(relaunchedService.coldRecoveryHeld)
        #expect(relaunchedRecovery.snapshot(mode: .route).activeMovement == nil)
        #expect(relaunchedRecovery.snapshot(mode: .route).uncertainty?.source == .route)

        await device.releaseMove()
        await wait { route.phase == .running }
        #expect(recovery.snapshot(mode: .route).activeMovement != nil)
        #expect(recovery.snapshot(mode: .route).uncertainty == nil)
        #expect(route.cancel())
        await wait { route.phase == .editing }
    }

    @Test func inactiveActiveDrainKeepsPausedResumeClosedUntilFreshProbeFinishes() async throws {
        let device = RecoveryControllerDevice()
        let service = ServiceController(service: device)
        #expect(service.start())
        await wait { service.phase == .ready && !service.nativeBusy }
        let start = GeoCoordinate(latitude: 25, longitude: 121)!
        let end = GeoCoordinate(latitude: 25.01, longitude: 121.01)!
        let place: (GeoCoordinate) -> MapPlace = {
            MapPlace(id: .coordinate($0), title: $0.displayText, coordinate: $0)
        }
        let draft = try #require(RouteDraft(start: .place(place(start)), destination: .place(place(end))))
        let route = RouteExecutionController(draft: draft, planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch())
        #expect(route.start())
        await wait { route.phase == .running }
        #expect(route.pause())
        await wait { route.phase == .paused }
        #expect(route.canResume)

        let probe = RecoveryControllerProbe(hold: true)
        let joystick = JoystickMovementController(commands: service)
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick, probe: probe)
        recovery.sceneDidBecomeActive()
        await wait { await probe.count == 1 && recovery.isChecking }
        #expect(!route.canResume)

        recovery.releaseForInactiveScene()
        recovery.sceneDidBecomeActive()
        #expect(!route.canResume)
        #expect(await probe.count == 1)

        await probe.release()
        await wait { await probe.count == 2 }
        #expect(!route.canResume)
        await probe.release()
        await wait { route.canResume }
        recovery.releaseForInactiveScene()
    }

    @Test func freshProbeBlocksWanderRetryAndGestureUntilActualResult() async throws {
        let device = RecoveryControllerDevice()
        let service = ServiceController(service: device)
        #expect(service.start())
        await wait { service.phase == .ready && !service.nativeBusy }
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(RealLocationObservation(latitude: origin.latitude, longitude: origin.longitude,
            horizontalAccuracy: 1, observedAt: Date()))
        let sequence = RecoveryBearingSequence([[0], []])
        let joystick = JoystickMovementController(commands: service,
            wanderBearingSamples: { sequence.next() })
        #expect(joystick.setWanderEnabled(true))
        let nearby = MapPlace(id: .coordinate(origin), title: "nearby", coordinate: origin)
        #expect(joystick.applyWanderTarget(nearby))
        await wait { joystick.phase == .suspended && joystick.wanderNeedsTarget }

        let route = RouteExecutionController(planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch())
        let probe = RecoveryControllerProbe(hold: true)
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick, probe: probe)
        recovery.sceneDidBecomeActive()
        await wait { await probe.count == 1 && recovery.isChecking }
        #expect(!joystick.canRetryWander)
        #expect(!joystick.beginGesture(id: UUID(), input: JoystickInput(bearingDegrees: 90, strength: 1)!))

        await probe.release()
        await wait { recovery.connectionState == .reachable && !recovery.isChecking }
        #expect(joystick.canRetryWander)
        recovery.releaseForInactiveScene()
        #expect(service.stop())
        await wait { service.clearState == .confirmed && !service.nativeBusy }
    }

    @Test func acceptedClearTakesPriorityOverClaimedOwnerUncertaintyAndSuppressesRetainedActive() async throws {
        let device = RecoveryControllerDevice(holdMoveAfterClaim: true)
        let service = ServiceController(service: device)
        #expect(service.start())
        await wait { service.phase == .ready && !service.nativeBusy }
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(RealLocationObservation(latitude: origin.latitude, longitude: origin.longitude,
            horizontalAccuracy: 1, observedAt: Date()))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let step = Task {
            await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
                expectedInputRevision: input, displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!)
        }
        await wait { await device.moveStarted }
        #expect(service.recoveryUncertainty?.source == .joystick)
        let route = RouteExecutionController(planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch())
        let recovery = MovementRecoveryController(service: service, route: route,
            joystick: JoystickMovementController(commands: service), probe: RecoveryControllerProbe(),
            retainedColdSnapshot: SessionRecoverySnapshot(activeMovement: .manual,
                uncertainty: SessionMovementUncertainty(source: .unverifiedPreviousMovement)))
        #expect(service.stop())
        #expect(service.recoveryUncertainty?.source == .gpsRecovery)
        #expect(recovery.snapshot(mode: .teleport).activeMovement == nil)
        await device.releaseMove()
        await wait { await device.clearStarted }
        await device.releaseClear()
        let outcome = await step.value
        #expect(outcome == .cancelled || outcome == .unconfirmed(.operationCancelled))
        await wait { service.clearState == .confirmed && !service.nativeBusy }
    }

    @Test func acknowledgedManualOwnerRemainsRecoverableThroughSettlement() async throws {
        let device = RecoveryControllerDevice(holdMoveAfterFirstClaim: true)
        let service = ServiceController(service: device)
        #expect(service.start())
        await wait { service.phase == .ready && !service.nativeBusy }
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(RealLocationObservation(latitude: origin.latitude, longitude: origin.longitude,
            horizontalAccuracy: 1, observedAt: Date()))
        let joystick = JoystickMovementController(commands: service)
        let finger = UUID()
        #expect(joystick.beginGesture(id: finger, input: JoystickInput(bearingDegrees: 0, strength: 1)!))
        await wait { joystick.canPause }
        let route = RouteExecutionController(planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch())
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick,
                                                   probe: RecoveryControllerProbe())
        await wait { await device.moveCount >= 2 }
        let moveStarted = await device.moveStarted
        #expect(moveStarted)
        #expect(joystick.endGesture(id: finger))
        #expect(joystick.phase == .settling)
        #expect(recovery.snapshot(mode: .joystick).activeMovement == .manual)
        await device.releaseMove()
        await wait { joystick.phase == .neutral }
    }

    @Test func nativeBusyMonitorWakeClearsCompletedTimerAndReschedulesAfterCleanup() async throws {
        let device = RecoveryControllerDevice(holdClear: true)
        let service = ServiceController(service: device)
        service.setMovementConnectionAvailable(false)
        let clock = RouteTestClock()
        let probe = RecoverySequenceProbe(failures: [.timedOut, nil])
        let route = RouteExecutionController(planner: RecoveryControllerPlanner(), commands: service,
                                               search: RecoveryControllerSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick,
                                                   probe: probe, clock: clock)

        recovery.sceneDidBecomeActive()
        await wait { await probe.count == 1 && recovery.connectionState == .timedOut && !recovery.isChecking }
        #expect(service.restoreGPS())
        await wait { await device.clearStarted && service.nativeBusy }
        clock.advance(by: .seconds(2))
        await Task.yield()
        #expect(await probe.count == 1)

        await device.releaseClear()
        await wait { service.clearState == .confirmed && !service.nativeBusy }
        await wait { await probe.count == 2 && recovery.connectionState == .reachable }
    }

    private func wait(_ predicate: @escaping @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await predicate()) && ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(await predicate())
    }
}

private actor RecoveryControllerProbe: TunnelProbing {
    private(set) var count = 0
    let failure: TunnelProbeFailure?
    let hold: Bool
    private var waiter: CheckedContinuation<Void, Never>?

    init(failure: TunnelProbeFailure? = nil, hold: Bool = false) {
        self.failure = failure; self.hold = hold
    }

    func check() async throws {
        count += 1
        if hold { await withCheckedContinuation { waiter = $0 } }
        if let failure { throw failure }
    }

    func release() { waiter?.resume(); waiter = nil }
}

private actor RecoverySequenceProbe: TunnelProbing {
    private(set) var count = 0
    private var failures: [TunnelProbeFailure?]

    init(failures: [TunnelProbeFailure?]) { self.failures = failures }

    func check() async throws {
        count += 1
        if !failures.isEmpty, let failure = failures.removeFirst() { throw failure }
    }
}

private actor RecoveryControllerDevice: DeviceService {
    let holdPrepare: Bool
    let holdClear: Bool
    let holdMoveBeforeClaim: Bool
    let holdFirstMoveAfterClaim: Bool
    let holdMoveAfterClaim: Bool
    let holdMoveAfterFirstClaim: Bool
    private(set) var prepareStarted = false
    private var prepareWaiter: CheckedContinuation<Void, Never>?
    private(set) var clearStarted = false
    private var clearWaiter: CheckedContinuation<Void, Never>?
    private(set) var moveStarted = false
    private(set) var moveEntered = false
    private(set) var moveCount = 0
    private var moveWaiter: CheckedContinuation<Void, Never>?

    init(holdPrepare: Bool = false, holdClear: Bool = false, holdMoveBeforeClaim: Bool = false,
         holdFirstMoveAfterClaim: Bool = false,
         holdMoveAfterClaim: Bool = false, holdMoveAfterFirstClaim: Bool = false) {
        self.holdPrepare = holdPrepare; self.holdClear = holdClear
        self.holdMoveBeforeClaim = holdMoveBeforeClaim
        self.holdFirstMoveAfterClaim = holdFirstMoveAfterClaim
        self.holdMoveAfterClaim = holdMoveAfterClaim
        self.holdMoveAfterFirstClaim = holdMoveAfterFirstClaim
    }
    func prepare() async throws {
        prepareStarted = true
        if holdPrepare { await withCheckedContinuation { prepareWaiter = $0 } }
    }
    func releasePrepare() { prepareWaiter?.resume(); prepareWaiter = nil }
    func clearLocation() async throws {
        clearStarted = true
        if holdClear { await withCheckedContinuation { clearWaiter = $0 } }
    }
    func releaseClear() { clearWaiter?.resume(); clearWaiter = nil }
    func releaseMove() { moveWaiter?.resume(); moveWaiter = nil }
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        moveEntered = true
        if holdMoveBeforeClaim { await withCheckedContinuation { moveWaiter = $0 } }
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        moveCount += 1; moveStarted = true
        if holdMoveAfterClaim || (holdFirstMoveAfterClaim && moveCount == 1) ||
            (holdMoveAfterFirstClaim && moveCount > 1) {
            await withCheckedContinuation { moveWaiter = $0 }
        }
        return .acknowledged
    }
}

private final class RecoveryMemoryPersistence: SessionRecoveryPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?

    func read() throws -> Data? { lock.withLock { stored } }
    func replaceAtomically(with data: Data) throws { lock.withLock { stored = data } }
}

private final class RecoveryBearingSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[Double]]
    init(_ values: [[Double]]) { self.values = values }
    func next() -> [Double] { lock.withLock { values.isEmpty ? [] : values.removeFirst() } }
}

private struct RecoveryControllerPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}

private struct RecoveryControllerSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
