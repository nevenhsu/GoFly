import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct ServiceRouteCommandsTests {
    @Test(arguments: [false, true], [false, true])
    func cancelledWritesSettleSafelyOnlyForAnUnclaimedFailureOrAValidatedAcknowledgement(firstPoint: Bool, claimedACK: Bool) async throws {
        let device = RouteControlledDevice()
        let service = ServiceController(service: device)
        let intent = try routeIntent()
        let begin = Task { await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }
        let tick: Task<RouteCommandOutcome, Never>?
        if firstPoint { tick = nil }
        else {
            await device.finish(.acknowledged)
            #expect(await begin.value == .acknowledged)
            tick = Task { await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1, coordinate: intent.route.end) }
            await wait { await device.waiting }
        }
        if claimedACK { #expect(await device.claim()) }
        service.endRoute(executionID: intent.id, lease: intent.lease)
        #expect(service.nativeBusy)
        #expect(!service.canTeleport)
        let idle = Task { await service.waitForRouteIdle(executionID: intent.id, lease: intent.lease) }
        await device.finish(claimedACK ? .acknowledged : .notSent(.operationCancelled))
        if let tick { #expect(await tick.value == .cancelled) }
        else { #expect(await begin.value == .cancelled) }
        #expect(await idle.value == .settled)
        #expect(!service.nativeBusy)
        #expect(service.canTeleport)
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(service.confirmedSimulatedLocation == (!firstPoint && !claimedACK ? intent.route.start : nil))
        #expect(await device.clears == 0)
    }

    @Test(arguments: [false, true], [false, true])
    func malformedAcknowledgementOrAnyUnconfirmedResultStillRequiresStopAfterCancel(firstPoint: Bool, malformedACK: Bool) async throws {
        let device = RouteControlledDevice()
        let service = ServiceController(service: device)
        let intent = try routeIntent()
        let begin = Task { await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }
        let tick: Task<RouteCommandOutcome, Never>?
        if firstPoint { tick = nil }
        else {
            await device.finish(.acknowledged)
            #expect(await begin.value == .acknowledged)
            tick = Task { await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1, coordinate: intent.route.end) }
            await wait { await device.waiting }
        }
        service.endRoute(executionID: intent.id, lease: intent.lease)
        await device.finish(malformedACK ? .acknowledged : .unconfirmed(.serviceUnavailable), validateAcknowledgement: false)
        if let tick { #expect(await tick.value == .cancelled) }
        else { #expect(await begin.value == .cancelled) }
        #expect(await service.waitForRouteIdle(executionID: intent.id, lease: intent.lease) == .requiresStop(.serviceUnavailable))
        #expect(service.phase == .repairRequired)
        #expect(!service.canTeleport)
        #expect(service.confirmedSimulatedLocation == (firstPoint ? nil : intent.route.start))
        #expect(service.stop())
        await wait { !service.nativeBusy }
        #expect(await device.clears == 1)
    }

    @Test(arguments: [false, true], [false, true])
    func cancellingAClaimedRouteWriteCannotEraseAnUnconfirmedResult(firstPoint: Bool, notSent: Bool) async throws {
        let device = RouteControlledDevice()
        let service = ServiceController(service: device)
        let intent = try routeIntent()
        let begin = Task { await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }
        let tick: Task<RouteCommandOutcome, Never>?
        if firstPoint { tick = nil }
        else {
            await device.finish(.acknowledged)
            #expect(await begin.value == .acknowledged)
            tick = Task { await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1, coordinate: intent.route.end) }
            await wait { await device.waiting }
        }
        #expect(await device.claim())
        service.endRoute(executionID: intent.id, lease: intent.lease)
        #expect(service.nativeBusy)
        #expect(!service.canTeleport)
        await device.finish(notSent ? .notSent(.serviceUnavailable) : .unconfirmed(.serviceUnavailable))
        if let tick { #expect(await tick.value == .cancelled) }
        else { #expect(await begin.value == .cancelled) }
        await wait { !service.nativeBusy }
        #expect(await service.waitForRouteIdle(executionID: intent.id, lease: intent.lease) == .requiresStop(.serviceUnavailable))
        #expect(service.phase == .repairRequired)
        #expect(service.error == .serviceUnavailable)
        #expect(!service.canTeleport)
        #expect(!service.canStart)
        #expect(!service.start())
        #expect(!service.teleport(to: TeleportCandidate(place: place(intent.route.end))))
        #expect(service.confirmedSimulatedLocation == nil)
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(await device.clears == 0)
        #expect(service.stop())
        await wait { !service.nativeBusy }
        #expect(await service.waitForRouteIdle(executionID: intent.id, lease: intent.lease) == .settled)
        #expect(service.phase == .stopped)
        #expect(service.canStart)
        #expect(await device.clears == 1)
    }

    @Test(arguments: [false, true])
    func stopAfterClaimedCancelSuppressesLateUnknownInsteadOfRelocking(firstPoint: Bool) async throws {
        let device = RouteControlledDevice()
        let service = ServiceController(service: device)
        let intent = try routeIntent()
        let begin = Task { await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }
        let tick: Task<RouteCommandOutcome, Never>?
        if firstPoint { tick = nil }
        else {
            await device.finish(.acknowledged)
            #expect(await begin.value == .acknowledged)
            tick = Task { await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1, coordinate: intent.route.end) }
            await wait { await device.waiting }
        }
        #expect(await device.claim())
        service.endRoute(executionID: intent.id, lease: intent.lease)
        #expect(service.stop())
        await device.finish(.unconfirmed(.serviceUnavailable))
        if let tick { #expect(await tick.value == .cancelled) }
        else { #expect(await begin.value == .cancelled) }
        await wait { !service.nativeBusy }
        #expect(service.phase == .stopped)
        #expect(service.canStart)
        #expect(service.canTeleport)
        #expect(await device.clears == 1)
        #expect(service.confirmedSimulatedLocation == nil)
    }

    @Test func routeBeginsAtTheExactSpecifiedStartAndOnlyPublishesAfterAcknowledgement() async throws {
        let device = RouteControlledDevice()
        let service = ServiceController(service: device)
        let start = GeoCoordinate(latitude: 25, longitude: 121)!
        let end = GeoCoordinate(latitude: 25.01, longitude: 121.01)!
        let draft = RouteDraft(start: .place(place(start)), destination: .place(place(end)))
        let intent = RouteExecutionIntent(draft: draft, route: try PlannedRoute(points: [start, end], from: start, to: end))
        let request = Task { await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }
        #expect(await device.coordinates == [start])
        #expect(service.confirmedSimulatedLocation == nil)
        await device.finish(.acknowledged)
        #expect(await request.value == .acknowledged)
        #expect(service.confirmedSimulatedLocation == start)
        #expect(service.movementAuthority.snapshot.lease == intent.lease)
        #expect(service.movementAuthority.snapshot.health == .confirmedHealthy)
        #expect(!service.nativeBusy)
    }
    @Test(arguments: [1, 2, 3, 4])
    func boundedPreparationKeepsItsAwaitAndRetriesTheSameImmutableRoute(successAt: Int) async throws {
        let device = RouteControlledDevice()
        let service = ServiceController(service: device)
        let intent = try routeIntent()
        var returned = false
        let request = Task {
            let result = await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision)
            returned = true
            return result
        }
        await wait { await device.waiting }
        let first = try #require(service.preparedOperation)
        for attempt in 1...min(successAt, 3) {
            if attempt > 1 { await wait { await device.waiting } }
            #expect(service.preparedOperation?.id == first.id)
            #expect(service.preparedOperation?.source == .route(intent))
            #expect(service.preparedOperation?.attempt.value == attempt)
            await device.finish(attempt < successAt ? .notSent(.pairingRequired) : .acknowledged)
        }
        if successAt > 3 {
            await wait { !service.nativeBusy }
            #expect(!returned)
            #expect(service.preparedOperation?.state == .failed(.pairingRequired))
            let admission = service.routeAdmissionRevision
            #expect(service.retryPreparedOperation(id: first.id))
            #expect(service.routeAdmissionRevision == admission)
            #expect(service.preparedOperation?.id != first.id)
            #expect(service.preparedOperation?.source == .route(intent))
            await wait { await device.waiting }
            await device.finish(.acknowledged)
        }
        #expect(await request.value == .acknowledged)
        #expect(service.confirmedSimulatedLocation == intent.route.start)
        #expect(await device.coordinates == Array(repeating: intent.route.start, count: min(successAt, 4)))
        #expect(await device.maxConcurrency == 1)
        service.endRoute(executionID: intent.id, lease: intent.lease)
    }

    @Test func cancellingAnExhaustedRoundFinishesItsAwaitWithoutClearingOrInstallingTheNewLease() async throws {
        let device = RouteControlledDevice()
        let controller = ServiceController(service: device)
        let intent = try routeIntent()
        let request = Task { await controller.beginRoute(intent, expectedAdmissionRevision: controller.routeAdmissionRevision) }
        for _ in 1...3 { await wait { await device.waiting }; await device.finish(.notSent(.pairingRequired)) }
        await wait { !controller.nativeBusy }
        let id = try #require(controller.preparedOperation?.id)
        #expect(controller.cancelPreparation(id: id))
        #expect(await request.value == .cancelled)
        #expect(controller.movementAuthority.snapshot.lease == nil)
        #expect(await device.clears == 0)
        #expect(!controller.retryPreparedOperation(id: id))
    }

    @Test func anOldTickActuallyRunsBetweenNewAttemptsAndQueuedOldWorkCannotCrossHandoff() async throws {
        let device = RouteControlledDevice()
        let controller = ServiceController(service: device)
        let old = try routeIntent()
        let begin = Task { await controller.beginRoute(old, expectedAdmissionRevision: controller.routeAdmissionRevision) }
        await wait { await device.waiting }; await device.finish(.acknowledged)
        #expect(await begin.value == .acknowledged)
        let target = GeoCoordinate(latitude: 26, longitude: 122)!
        #expect(controller.teleport(to: TeleportCandidate(place: place(target))))
        await wait { await device.waiting }
        var submitted = false
        let oldNext = GeoCoordinate(latitude: 25.00001, longitude: 121)!
        let tick = Task {
            submitted = true
            return await controller.sendRoutePoint(executionID: old.id, lease: old.lease, sequence: 1, coordinate: oldNext)
        }
        await wait { submitted }
        await device.finish(.notSent(.pairingRequired))
        await wait { await device.coordinates.count == 3 }
        #expect(await device.coordinates == [old.route.start, target, oldNext])
        #expect(controller.preparedOperation?.attempt.value == 1)
        await device.finish(.acknowledged)
        #expect(await tick.value == .acknowledged)
        await wait { await device.coordinates.count == 4 }
        #expect(controller.preparedOperation?.attempt.value == 2)
        #expect(controller.confirmedSimulatedLocation == oldNext)
        var queued = false
        let obsolete = Task {
            queued = true
            return await controller.sendRoutePoint(executionID: old.id, lease: old.lease, sequence: 2,
                coordinate: GeoCoordinate(latitude: 25.00002, longitude: 121)!)
        }
        await wait { queued }
        await device.finish(.acknowledged)
        #expect(await obsolete.value == .cancelled)
        await wait { !controller.nativeBusy }
        #expect(controller.confirmedSimulatedLocation == target)
        #expect(await device.coordinates == [old.route.start, target, oldNext, target])
        #expect(await device.maxConcurrency == 1)
    }

    @Test(arguments: [false, true])
    func stopWaitsForARealTickReturnAndItsMandatoryClearNeverOverlaps(afterClaim: Bool) async throws {
        let device = RouteControlledDevice()
        let service = ServiceController(service: device)
        let intent = try routeIntent()
        let begin = Task { await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }; await device.finish(.acknowledged)
        #expect(await begin.value == .acknowledged)
        let coordinate = GeoCoordinate(latitude: 25.00001, longitude: 121)!
        let tick = Task { await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1, coordinate: coordinate) }
        await wait { await device.waiting }
        #expect(!service.nativeBusy)
        if afterClaim { #expect(await device.claim()) }
        #expect(service.stop())
        #expect(service.nativeBusy)
        #expect(await device.clears == 0)
        await device.finish(.acknowledged)
        #expect(await tick.value == .cancelled)
        await wait { !service.nativeBusy }
        #expect(await device.clears == 1)
        #expect(await device.maxConcurrency == 1)
        #expect(service.confirmedSimulatedLocation == nil)
        #expect(service.phase == .stopped)
    }

    @Test func currentOriginRejectsAStaleGPSOrWaitingCacheAndPrefersConfirmedSimulation() async throws {
        let time = RouteWallTime()
        let device = RouteControlledDevice()
        let service = ServiceController(service: device, now: { time.now })
        let gps = RealLocationObservation(latitude: 24, longitude: 120, horizontalAccuracy: 5, observedAt: time.now)!
        service.observeRealLocation(gps)
        #expect(service.currentRouteOrigin == gps.coordinate)
        time.advance(16)
        #expect(service.currentRouteOrigin == nil)
        let intent = try routeIntent()
        let begin = Task { await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }; await device.finish(.acknowledged)
        #expect(await begin.value == .acknowledged)
        service.observeRealLocation(RealLocationObservation(latitude: 26, longitude: 122, horizontalAccuracy: 5, observedAt: time.now))
        #expect(service.currentRouteOrigin == intent.route.start)
        #expect(service.stop())
        await wait { !service.nativeBusy }
        #expect(service.positionMarker != nil)
        #expect(service.currentRouteOrigin == nil)
    }

    @Test(arguments: [false, true])
    func tickWatchdogCannotReleaseRepairBeforeNativeReturnOrPublishItsLateAcknowledgement(afterClaim: Bool) async throws {
        let device = RouteControlledDevice(), watchdog = ManualServiceWatchdog()
        let service = ServiceController(service: device, watchdogSleep: watchdog.sleep)
        let intent = try routeIntent()
        let begin = Task { await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }
        await wait { watchdog.requests.count == 1 }
        await device.finish(.acknowledged)
        #expect(await begin.value == .acknowledged)
        let tick = Task { await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1,
            coordinate: GeoCoordinate(latitude: 25.00001, longitude: 121)!) }
        await wait { await device.waiting }
        await wait { watchdog.requests.count == 2 }
        if afterClaim { #expect(await device.claim()) }
        watchdog.fireLatest()
        await wait { service.error == .operationTimedOut }
        #expect(service.nativeBusy)
        #expect(!service.canTeleport)
        #expect(await device.clears == 0)
        await device.finish(.acknowledged)
        #expect(await tick.value == (afterClaim ? .unconfirmed(.operationTimedOut) : .notSent(.operationTimedOut)))
        #expect(!service.nativeBusy)
        if afterClaim {
            #expect(service.confirmedSimulatedLocation == nil)
            #expect(service.movementAuthority.snapshot.health == .unknown)
            #expect(!service.canTeleport)
            #expect(service.stop())
            await wait { !service.nativeBusy }
        } else {
            #expect(service.confirmedSimulatedLocation == intent.route.start)
            #expect(service.movementAuthority.snapshot.health == .interrupted(.operationTimedOut))
            service.endRoute(executionID: intent.id, lease: intent.lease)
        }
    }

    @Test(arguments: [false, true])
    func routePreparationWatchdogKeepsActualOwnershipAndCompletesItsAwaitExactlyOnce(afterClaim: Bool) async throws {
        let device = RouteControlledDevice(), watchdog = ManualServiceWatchdog()
        let service = ServiceController(service: device, watchdogSleep: watchdog.sleep)
        let intent = try routeIntent()
        var returned = false
        let begin = Task {
            let value = await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision)
            returned = true
            return value
        }
        await wait { await device.waiting }
        await wait { watchdog.requests.count == 1 }
        let id = try #require(service.preparedOperation?.id)
        if afterClaim { #expect(await device.claim()) }
        watchdog.fireLatest()
        await wait { service.error == .operationTimedOut }
        #expect(service.nativeBusy)
        #expect(!service.retryPreparedOperation(id: id))
        if afterClaim {
            #expect(await begin.value == .unconfirmed(.operationTimedOut))
            #expect(service.stop())
            #expect(await device.clears == 0)
            await device.finish(.acknowledged)
            await wait { !service.nativeBusy }
            #expect(await device.clears == 1)
            #expect(service.confirmedSimulatedLocation == nil)
            #expect(service.phase == .stopped)
            #expect(!service.retryPreparedOperation(id: id))
        } else {
            #expect(!returned)
            await device.finish(.acknowledged)
            await wait { !service.nativeBusy }
            #expect(!returned)
            #expect(service.preparedOperation?.state == .failed(.operationTimedOut))
            #expect(service.retryPreparedOperation(id: id))
            await wait { await device.waiting }
            await device.finish(.acknowledged)
            #expect(await begin.value == .acknowledged)
            #expect(service.confirmedSimulatedLocation == intent.route.start)
            service.endRoute(executionID: intent.id, lease: intent.lease)
        }
        #expect(await device.maxConcurrency == 1)
    }

    private func routeIntent() throws -> RouteExecutionIntent {
        let start = GeoCoordinate(latitude: 25, longitude: 121)!, end = GeoCoordinate(latitude: 25.01, longitude: 121.01)!
        let draft = RouteDraft(start: .place(place(start)), destination: .place(place(end)))
        return RouteExecutionIntent(draft: draft, route: try PlannedRoute(points: [start, end], from: start, to: end))
    }
    private func place(_ coordinate: GeoCoordinate) -> MapPlace { MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate) }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

actor RouteControlledDevice: DeviceService {
    var coordinates: [GeoCoordinate] = []
    var clears = 0
    var maxConcurrency = 0
    private var concurrency = 0
    private var pending: CheckedContinuation<PointDeliveryOutcome, Never>?
    private var gate: PointDispatchGate?
    private var validateAcknowledgement = true
    var waiting: Bool { pending != nil }
    func prepare() async throws { maxConcurrency = max(maxConcurrency, concurrency + 1) }
    func clearLocation() async throws { maxConcurrency = max(maxConcurrency, concurrency + 1); clears += 1 }
    func resetClientConnection() async throws { maxConcurrency = max(maxConcurrency, concurrency + 1) }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        concurrency += 1; maxConcurrency = max(maxConcurrency, concurrency)
        coordinates.append(coordinate); gate = dispatch
        let outcome = await withCheckedContinuation { pending = $0 }
        concurrency -= 1
        if outcome == .acknowledged && validateAcknowledgement {
            return (dispatch.hasDispatched || dispatch.claim()) ? outcome : .notSent(.operationCancelled)
        }
        return outcome
    }
    func finish(_ outcome: PointDeliveryOutcome, validateAcknowledgement: Bool = true) {
        self.validateAcknowledgement = validateAcknowledgement
        pending?.resume(returning: outcome); pending = nil
    }
    func claim() -> Bool { gate?.claim() ?? false }
}

private final class RouteWallTime: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 10_000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}
