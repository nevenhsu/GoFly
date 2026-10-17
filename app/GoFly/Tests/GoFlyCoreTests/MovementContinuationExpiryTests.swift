import Combine
import Foundation
import Testing
import GoFlyCore

@Suite @MainActor
struct MovementContinuationExpiryTests {
    @Test func expiryBeforeQueuedWanderClaimPreservesHealthyPausedOwnerUntilExplicitResume() async throws {
        let device = ExpiryWanderDevice()
        let service = ServiceController(service: device)
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: Date()))
        let clock = ContinuationTestClock()
        let route = RouteExecutionController(planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock,
            wanderBearingSamples: { [90] })
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: clock)
        let driver = ExpiringDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: "Wandering", subtitle: "(progress.acknowledgedWrites)")
            }
        var acknowledgements: [MovementAcknowledgement] = []
        let acknowledgementToken = service.movementAcknowledgements.sink { acknowledgements.append($0) }
        defer { acknowledgementToken.cancel() }

        controller.sceneDidBecomeActive()
        let gestureID = UUID()
        let input = try #require(JoystickInput(bearingDegrees: 90, strength: 1))
        #expect(joystick.beginGesture(id: gestureID, input: input))
        await waitForContinuation { joystick.phase == .moving }
        #expect(joystick.setWanderEnabled(true))

        await waitUntilAsync { clock.hasSleeper(for: .milliseconds(500)) }
        clock.advance(by: .milliseconds(500))
        await waitForContinuation { driver.submitCalls == 1 }
        let firstDeviceState = await device.snapshot()
        #expect(firstDeviceState.callCount == 1)
        let oldRequest = try #require(driver.requests.first)
        let movementID = try #require(joystick.intent?.id)
        let lease = try #require(joystick.intent?.lease)
        let target = try #require(joystick.wanderTarget)
        #expect(joystick.phase == .moving)
        #expect(acknowledgements.count == 1)

        await waitUntilAsync { clock.hasSleeper(for: .milliseconds(500)) }
        clock.advance(by: .milliseconds(500))
        await waitForContinuation { driver.submitCalls == 1 }
        await waitUntilAsync { await device.snapshot().waiting }
        #expect(driver.closeGrantWithoutEvent(requestID: oldRequest.requestID))
        #expect(!(await device.claim()))
        await device.finish(.notSent(.operationCancelled))
        await waitForContinuation { joystick.phase == .paused }

        #expect(joystick.phase == .paused)
        #expect(joystick.intent?.id == movementID)
        #expect(joystick.intent?.lease == lease)
        #expect(joystick.wanderTarget == target)
        #expect(service.movementAuthority.snapshot.lease == lease)
        #expect(service.movementAuthority.snapshot.runState == .paused)
        #expect(service.movementAuthority.snapshot.health == .confirmedHealthy)
        #expect((await device.snapshot()).callCount == 2)
        #expect(acknowledgements.count == 1)
        #expect(driver.submitCalls == 1)

        driver.deliverExpired(requestID: oldRequest.requestID)
        for _ in 0..<20 { await Task.yield() }
        #expect(joystick.phase == .paused)
        #expect(joystick.intent?.lease == lease)
        #expect(driver.submitCalls == 1)

        controller.releaseForInactiveScene()
        controller.sceneDidBecomeActive()
        await waitForContinuation { joystick.canResume }
        #expect(joystick.resume())
        await waitForContinuation { driver.submitCalls == 2 }
        let replacement = try #require(driver.requests.last)
        #expect(replacement.lease == lease)
        #expect(replacement.requestID != oldRequest.requestID)
        #expect(joystick.intent?.id == movementID)
    }

    @Test func expiryBeforeQueuedFiniteRouteClaimPreservesPausedProgressUntilExplicitResume() async throws {
        let device = ExpiryWanderDevice()
        let service = ServiceController(service: device)
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: clock)
        let driver = ExpiringDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: "Route", subtitle: "\(progress.acknowledgedWrites)")
            }
        var acknowledgements: [MovementAcknowledgement] = []
        let acknowledgementToken = route.movementAcknowledgements.sink { acknowledgements.append($0) }
        defer { acknowledgementToken.cancel() }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && driver.submitCalls == 1 && acknowledgements.count == 1 }
        let movementID = try #require(route.intent?.id)
        let lease = try #require(route.intent?.lease)
        let progress = try #require(route.progress)
        let oldRequest = try #require(driver.requests.first)
        #expect(progress.committedDistanceMeters == 0)

        await waitForContinuation { clock.sleepingCount > 0 }
        clock.advance(by: .milliseconds(500))
        await waitUntilAsync { await device.snapshot().waiting }
        #expect(driver.closeGrantWithoutEvent(requestID: oldRequest.requestID))
        #expect(!(await device.claim()))
        await device.finish(.notSent(.operationCancelled))
        await waitForContinuation { route.phase == .paused }

        #expect(route.phase == .paused)
        #expect(route.intent?.id == movementID)
        #expect(route.intent?.lease == lease)
        let pausedProgress = try #require(route.progress)
        #expect(pausedProgress.committedDistanceMeters == progress.committedDistanceMeters)
        #expect(pausedProgress.totalDistanceMeters == progress.totalDistanceMeters)
        #expect(pausedProgress.activeElapsed == .milliseconds(500))
        #expect(service.movementAuthority.snapshot.lease == lease)
        #expect(service.movementAuthority.snapshot.runState == .paused)
        #expect(service.movementAuthority.snapshot.health == .confirmedHealthy)
        #expect(acknowledgements.count == 1)
        #expect(driver.submitCalls == 1)

        driver.deliverExpired(requestID: oldRequest.requestID)
        for _ in 0..<20 { await Task.yield() }
        #expect(route.phase == .paused)
        #expect(route.intent?.lease == lease)
        #expect(route.progress == pausedProgress)
        #expect(driver.submitCalls == 1)

        await waitForContinuation { route.canResume }
        #expect(route.resume())
        await waitForContinuation { route.phase == .running && driver.submitCalls == 2 }
        let replacement = try #require(driver.requests.last)
        #expect(replacement.movementID == movementID)
        #expect(replacement.lease == lease)
        #expect(replacement.requestID != oldRequest.requestID)
        #expect(route.progress == pausedProgress)
        #expect(service.movementAuthority.snapshot.runState == .running)
        #expect(service.movementAuthority.snapshot.health == .confirmedHealthy)
    }

    @Test func claimedUncertainFiniteRouteDenialRemainsUnknownForRecovery() async throws {
        let device = ExpiryWanderDevice()
        let service = ServiceController(service: device)
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: clock)
        let driver = ExpiringDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: "Route", subtitle: "\(progress.acknowledgedWrites)")
            }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && driver.submitCalls == 1 }
        let oldRequest = try #require(driver.requests.first)
        await waitForContinuation { clock.sleepingCount > 0 }
        clock.advance(by: .milliseconds(500))
        await waitUntilAsync { await device.snapshot().waiting }
        #expect(await device.claim())
        await device.finish(.unconfirmed(.operationTimedOut))
        await waitForContinuation { route.phase == .unknown }

        #expect(route.phase == .unknown)
        #expect(route.error == .device(.operationTimedOut))
        #expect(service.phase == .repairRequired)
        #expect(service.movementAuthority.snapshot.health == .unknown)
        #expect(driver.submitCalls == 1)

        driver.deliverExpired(requestID: oldRequest.requestID)
        for _ in 0..<20 { await Task.yield() }
        #expect(route.phase == .unknown)
        #expect(service.movementAuthority.snapshot.health == .unknown)
    }
}

private actor ExpiryWanderDevice: DeviceService {
    private var pending: CheckedContinuation<PointDeliveryOutcome, Never>?
    private var gate: PointDispatchGate?
    private(set) var callCount = 0
    private(set) var claimCount = 0
    var waiting: Bool { pending != nil }

    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}

    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        callCount += 1
        if callCount == 1 {
            guard dispatch.claim() else { return .notSent(.operationCancelled) }
            return .acknowledged
        }
        gate = dispatch
        return await withCheckedContinuation { pending = $0 }
    }

    func claim() -> Bool {
        claimCount += 1
        return gate?.claim() ?? false
    }

    func finish(_ outcome: PointDeliveryOutcome) {
        pending?.resume(returning: outcome)
        pending = nil
        gate = nil
    }

    func snapshot() -> (callCount: Int, claimCount: Int, waiting: Bool) {
        (callCount, claimCount, pending != nil)
    }
}


@MainActor
private final class ExpiringDriver: ContinuedProcessingDriving {
    private var handlers: [UUID: @MainActor @Sendable (ContinuedProcessingEvent) -> Void] = [:]
    private var grants: [UUID: ContinuedProcessingGrant] = [:]
    var submitCalls = 0
    var requests: [ContinuedProcessingRequest] = []

    func register() -> Bool { true }

    func submit(
        _ request: ContinuedProcessingRequest,
        onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void
    ) async throws {
        submitCalls += 1
        requests.append(request)
        handlers[request.requestID] = onEvent
        let grant = ContinuedProcessingGrant(requestID: request.requestID,
            movementID: request.movementID, lease: request.lease)
        grants[request.requestID] = grant
        onEvent(.launched(grant))
    }

    func closeGrantWithoutEvent(requestID: UUID) -> Bool {
        guard let grant = grants[requestID] else { return false }
        grant.revoke()
        return true
    }

    func deliverExpired(requestID: UUID) {
        handlers[requestID]?(.expired(requestID: requestID))
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {}
    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? { nil }
    func cancel(requestID: UUID) {}
}


@MainActor
private func waitUntilAsync(_ condition: @escaping @MainActor () async -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await condition()), ContinuousClock.now < deadline {
        await Task.yield()
    }
    #expect(await condition())
}
