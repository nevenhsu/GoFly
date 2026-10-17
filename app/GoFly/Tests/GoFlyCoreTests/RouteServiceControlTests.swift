import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct RouteServiceControlTests {
    @Test func everyControlRevisionAdvancesWithoutPendingWorkAndRejectsStaleEntryBeforeNativeAdmission() async throws {
        let device = RouteControlledDevice()
        let controller = ServiceController(service: device)
        let intent = try await begin(controller, device)
        let initial = try #require(controller.routeControlRevision(executionID: intent.id, lease: intent.lease))
        #expect(controller.reviseRouteControl(executionID: intent.id, lease: intent.lease) == initial + 1)
        #expect(controller.reviseRouteControl(executionID: intent.id, lease: intent.lease) == initial + 2)
        #expect(controller.routeControlRevision(executionID: UUID(), lease: intent.lease) == nil)
        #expect(controller.reviseRouteControl(executionID: intent.id, lease: MovementTaskLease()) == nil)
        let stale = await controller.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedControlRevision: initial, coordinate: intent.route.end)
        #expect(stale == .controlCancelled)
        #expect(await device.coordinates == [intent.route.start])
        #expect(controller.confirmedSimulatedLocation == intent.route.start)
        #expect(controller.movementAuthority.snapshot.health == .confirmedHealthy)
        let fresh = Task { await controller.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedControlRevision: initial + 2, coordinate: intent.route.end) }
        await wait { await device.waiting }; await device.finish(.acknowledged)
        #expect(await fresh.value == .acknowledged)
        #expect(controller.confirmedSimulatedLocation == intent.route.end)
        #expect(await device.maxConcurrency == 1)
        controller.endRoute(executionID: intent.id, lease: intent.lease)
    }

    @Test func availableControlCancellationStopsTheWatchdogAndKeepsTheSameNextSequence() async throws {
        let device = RouteControlledDevice(), watchdog = ManualServiceWatchdog()
        let service = ServiceController(service: device, watchdogSleep: watchdog.sleep)
        let intent = try await begin(service, device, watchdog: watchdog)
        let revision = try #require(service.routeControlRevision(executionID: intent.id, lease: intent.lease))
        let tick = Task { await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedControlRevision: revision, coordinate: intent.route.end) }
        await wait { await device.waiting }
        await wait { watchdog.requests.count == 2 }
        #expect(service.reviseRouteControl(executionID: intent.id, lease: intent.lease) == revision + 1)
        #expect(await device.claim() == false)
        watchdog.fireLatest()
        await device.finish(.notSent(.operationCancelled))
        #expect(await tick.value == .controlCancelled)
        #expect(service.error == nil)
        #expect(service.movementAuthority.snapshot.health == .confirmedHealthy)
        #expect(service.confirmedSimulatedLocation == intent.route.start)
        let next = Task { await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedControlRevision: revision + 1, coordinate: intent.route.end) }
        await wait { await device.waiting }; await device.finish(.acknowledged)
        #expect(await next.value == .acknowledged)
        #expect(service.confirmedSimulatedLocation == intent.route.end)
        #expect(await device.maxConcurrency == 1)
        service.endRoute(executionID: intent.id, lease: intent.lease)
    }

    @Test func oldWorkWaitingBehindPreparationCannotDispatchOrCreateAnotherWatchdogAfterControlChanges() async throws {
        let device = RouteControlledDevice(), watchdog = ManualServiceWatchdog()
        let service = ServiceController(service: device, watchdogSleep: watchdog.sleep)
        let intent = try await begin(service, device, watchdog: watchdog)
        let revision = try #require(service.routeControlRevision(executionID: intent.id, lease: intent.lease))
        #expect(service.teleport(to: TeleportCandidate(place: place(intent.route.end))))
        await wait { await device.waiting }
        await wait { watchdog.requests.count == 2 }
        var submitted = false
        let waiting = Task {
            submitted = true
            return await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1,
                expectedControlRevision: revision, coordinate: intent.route.end)
        }
        await wait { submitted }
        // This asserts public FIFO outcome whether the caller entered before or after revision.
        #expect(service.reviseRouteControl(executionID: intent.id, lease: intent.lease) == revision + 1)
        await device.finish(.notSent(.pairingRequired))
        #expect(await waiting.value == .controlCancelled)
        for _ in 2...3 { await wait { await device.waiting }; await device.finish(.notSent(.pairingRequired)) }
        await wait { !service.nativeBusy }
        #expect(watchdog.requests.count == 2)
        #expect(await device.coordinates == [intent.route.start] + Array(repeating: intent.route.end, count: 3))
        #expect(await device.maxConcurrency == 1)
        #expect(service.movementAuthority.snapshot.lease == intent.lease)
        service.endRoute(executionID: intent.id, lease: intent.lease)
    }

    @Test(arguments: ["claimedNotSent", "claimedUnknown", "unclaimedUnknown", "unclaimedACK"])
    func controlChangesCannotHideUncertainProtocolResults(kind: String) async throws {
        let device = RouteControlledDevice()
        let controller = ServiceController(service: device)
        let intent = try await begin(controller, device)
        let revision = try #require(controller.routeControlRevision(executionID: intent.id, lease: intent.lease))
        let tick = Task { await controller.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedControlRevision: revision, coordinate: intent.route.end) }
        await wait { await device.waiting }
        if kind.hasPrefix("claimed") { #expect(await device.claim()) }
        #expect(controller.reviseRouteControl(executionID: intent.id, lease: intent.lease) == revision + 1)
        let outcome: PointDeliveryOutcome = kind == "claimedNotSent" ? .notSent(.serviceUnavailable)
            : kind == "unclaimedACK" ? .acknowledged : .unconfirmed(.serviceUnavailable)
        await device.finish(outcome, validateAcknowledgement: false)
        #expect(await tick.value == .unconfirmed(.serviceUnavailable))
        #expect(controller.movementAuthority.snapshot.health == .unknown)
        #expect(!controller.canTeleport)
        #expect(controller.reviseRouteControl(executionID: intent.id, lease: intent.lease) == nil)
        #expect(controller.confirmedSimulatedLocation != intent.route.end)
        #expect(controller.stop())
        await wait { !controller.nativeBusy }
    }

    @Test(arguments: [false, true])
    func pauseAndStopKeepTheirOwnCancellationReasonRatherThanBecomingControlCancellation(stop: Bool) async throws {
        let device = RouteControlledDevice()
        let service = ServiceController(service: device)
        let intent = try await begin(service, device)
        let revision = try #require(service.routeControlRevision(executionID: intent.id, lease: intent.lease))
        let tick = Task { await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedControlRevision: revision, coordinate: intent.route.end) }
        await wait { await device.waiting }
        if stop {
            #expect(service.reviseRouteControl(executionID: intent.id, lease: intent.lease) != nil)
            #expect(service.stop())
            #expect(service.reviseRouteControl(executionID: intent.id, lease: intent.lease) == nil)
        } else {
            #expect(service.pauseRoute(executionID: intent.id, lease: intent.lease))
            #expect(service.reviseRouteControl(executionID: intent.id, lease: intent.lease) == revision + 1)
        }
        await device.finish(.notSent(.operationCancelled))
        #expect(await tick.value == .cancelled)
        if stop {
            await wait { !service.nativeBusy }
            #expect(service.phase == .stopped)
            #expect(await device.clears == 1)
        } else {
            #expect(service.movementAuthority.snapshot.runState == .paused)
            #expect(service.movementAuthority.snapshot.health == .confirmedHealthy)
            service.endRoute(executionID: intent.id, lease: intent.lease)
        }
    }

    @Test(arguments: [false, true])
    func aWatchdogWhichAlreadyWonCannotBeReclassifiedByControlAndNeverPublishesLateACK(claimed: Bool) async throws {
        let device = RouteControlledDevice(), watchdog = ManualServiceWatchdog()
        let service = ServiceController(service: device, watchdogSleep: watchdog.sleep)
        let intent = try await begin(service, device, watchdog: watchdog)
        let revision = try #require(service.routeControlRevision(executionID: intent.id, lease: intent.lease))
        let tick = Task { await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedControlRevision: revision, coordinate: intent.route.end) }
        await wait { await device.waiting }
        await wait { watchdog.requests.count == 2 }
        if claimed { #expect(await device.claim()) }
        watchdog.fireLatest()
        await wait { service.error == .operationTimedOut }
        #expect(service.reviseRouteControl(executionID: intent.id, lease: intent.lease) == nil)
        await device.finish(.acknowledged)
        #expect(await tick.value == (claimed ? .unconfirmed(.operationTimedOut) : .notSent(.operationTimedOut)))
        #expect(service.confirmedSimulatedLocation != intent.route.end)
        #expect(service.stop())
        await wait { !service.nativeBusy }
    }

    private func begin(_ service: ServiceController, _ device: RouteControlledDevice, watchdog: ManualServiceWatchdog? = nil) async throws -> RouteExecutionIntent {
        let from = GeoCoordinate(latitude: 25, longitude: 121)!, to = GeoCoordinate(latitude: 25.01, longitude: 121)!
        let draft = RouteDraft(values: [.place(place(from)), .place(place(to))])!
        let intent = RouteExecutionIntent(draft: draft, route: try PlannedRoute(points: [from, to], from: from, to: to))
        let begun = Task { await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }
        if let watchdog { await wait { watchdog.requests.count == 1 } }
        await device.finish(.acknowledged)
        #expect(await begun.value == .acknowledged)
        return intent
    }
    private func place(_ coordinate: GeoCoordinate) -> MapPlace { MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate) }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}
