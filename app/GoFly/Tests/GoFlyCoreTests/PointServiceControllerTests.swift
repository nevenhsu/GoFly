import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct PointServiceControllerTests {
    @Test func simulationHasDisplayPriorityAndStopRetainsOnlyAWaitingArrowUntilFreshGPS() async throws {
        let device = ControlledPointDevice()
        let now = Date()
        let controller = ServiceController(service: device, now: { now })
        #expect(controller.restoreGPS())
        await wait { !controller.nativeBusy }
        let observation = RealLocationObservation(latitude: 24, longitude: 120, horizontalAccuracy: 5, observedAt: now)
        controller.observeRealLocation(observation)
        #expect(controller.gpsStatusKey == "gps.observed")
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let candidate = TeleportCandidate(place: MapPlace(id: .coordinate(coordinate), title: "Target", coordinate: coordinate))
        try #require(controller.teleport(to: candidate))
        await wait { await device.waitingForPreparation }
        #expect(controller.positionMarker?.freshness == .fresh)
        await device.finishPreparation()
        await wait { if case .sending = controller.pointState { true } else { false } }
        #expect(controller.phase == .ready)
        #expect(controller.positionMarker?.freshness == .waiting)
        #expect(controller.realLocation == nil)
        #expect(controller.gpsStatusKey == "gps.unknown")
        await device.finishReply(.acknowledged)
        await wait { !controller.nativeBusy }
        controller.observeRealLocation(observation)
        #expect(controller.positionMarker?.source == .simulation)
        #expect(controller.positionMarker?.coordinate == coordinate)
        #expect(controller.positionMarker?.freshness == .fresh)
        #expect(controller.stop())
        #expect(controller.confirmedSimulatedLocation == nil)
        #expect(controller.realLocation == nil)
        #expect(controller.positionMarker?.coordinate == coordinate)
        #expect(controller.positionMarker?.freshness == .waiting)
        await wait { !controller.nativeBusy }
        #expect(controller.positionMarker?.freshness == .waiting)
        controller.observeRealLocation(observation)
        #expect(controller.positionMarker?.source == .gps)
        #expect(controller.positionMarker?.coordinate == observation?.coordinate)
        #expect(controller.positionMarker?.freshness == .fresh)
        #expect(controller.gpsStatusKey == "gps.observed")
    }

    @Test(arguments: [false, true])
    func preparationFailurePreservesPriorPositionEvidenceAndAllowsExplicitRetry(priorSimulation: Bool) async throws {
        let device = ControlledPointDevice()
        let now = Date()
        let controller = ServiceController(service: device, now: { now })
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let candidate = TeleportCandidate(place: MapPlace(id: .coordinate(coordinate), title: "Target", coordinate: coordinate))
        controller.observeRealLocation(RealLocationObservation(latitude: 24, longitude: 120, horizontalAccuracy: 5, observedAt: now))
        if priorSimulation {
            try #require(controller.teleport(to: candidate))
            await wait { await device.waitingForPreparation }
            await device.finishPreparation()
            await wait { await device.waitingForReply }
            await device.finishReply(.acknowledged)
            await wait { !controller.nativeBusy }
        }
        let prior = try #require(controller.positionMarker)
        try #require(controller.teleport(to: candidate))
        await wait { await device.waitingForPreparation }
        #expect(controller.positionMarker == prior)
        for attempt in 1...3 {
            if attempt > 1 { await wait { await device.waitingForPreparation } }
            #expect(controller.preparedOperation?.attempt.value == attempt)
            await device.finishPreparation(failure: .pairingRequired)
        }
        await wait { !controller.nativeBusy }
        #expect(controller.positionMarker == prior)
        #expect(controller.canTeleport)
        #expect(controller.error == .pairingRequired)
        #expect(await device.sent.count == (priorSimulation ? 1 : 0))
    }

    @Test(arguments: [false, true])
    func stopInvalidatesPointPublicationAndWaitsForActualReturnBeforeClearing(afterDispatch: Bool) async throws {
        let device = ControlledPointDevice()
        let controller = ServiceController(service: device)
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let candidate = TeleportCandidate(place: MapPlace(id: .coordinate(coordinate), title: "Target", coordinate: coordinate))
        try #require(controller.teleport(to: candidate))
        await wait { await device.waitingForPreparation }
        if afterDispatch {
            await device.finishPreparation()
            await wait { await device.waitingForReply }
        }
        #expect(controller.stop())
        #expect(!controller.stop())
        #expect(!controller.start())
        #expect(!controller.teleport(to: candidate))
        #expect(controller.nativeBusy)
        #expect(await device.clears == 0)
        if afterDispatch { await device.finishReply(.acknowledged) }
        else { await device.finishPreparation() }
        await wait { !controller.nativeBusy }
        #expect(await device.sent == (afterDispatch ? [coordinate] : []))
        #expect(await device.clears == 1)
        #expect(controller.confirmedSimulatedLocation == nil)
        #expect(controller.pointState == .idle)
        #expect(controller.phase == .stopped)
        #expect(controller.clearState == .confirmed)
        #expect(controller.canTeleport)
    }

    @Test func unconfirmedPointRemainsLockedEvenWhenNewGPSArrivesUntilExplicitStop() async throws {
        let device = ControlledPointDevice()
        let now = Date()
        let controller = ServiceController(service: device, now: { now })
        controller.observeRealLocation(RealLocationObservation(latitude: 24, longitude: 120, horizontalAccuracy: 5, observedAt: now))
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let candidate = TeleportCandidate(place: MapPlace(id: .coordinate(coordinate), title: "Target", coordinate: coordinate))
        try #require(controller.teleport(to: candidate))
        await wait { await device.waitingForPreparation }
        await device.finishPreparation()
        await wait { await device.waitingForReply }
        await device.finishReply(.unconfirmed(.operationTimedOut))
        await wait { !controller.nativeBusy }
        #expect(!controller.canTeleport)
        #expect(!controller.teleport(to: candidate))
        #expect(controller.canStop)
        #expect(!controller.restoreGPS())
        #expect(!controller.resetTunnel())
        #expect(controller.positionMarker?.freshness == .waiting)
        controller.observeRealLocation(RealLocationObservation(latitude: 26, longitude: 122, horizontalAccuracy: 5, observedAt: now))
        #expect(controller.positionMarker?.freshness == .fresh)
        #expect(controller.positionMarker?.source == .gps)
        #expect(!controller.canTeleport)
        #expect(await device.sent.count == 1)
        #expect(controller.stop())
        await wait { !controller.nativeBusy }
        #expect(controller.canTeleport)
        #expect(controller.pointState == .idle)
    }

    @Test(arguments: [false, true])
    func watchdogCannotPermitLateDispatchOrLateAcknowledgement(afterDispatch: Bool) async throws {
        let device = ControlledPointDevice()
        let clock = ManualServiceWatchdog()
        let controller = ServiceController(service: device, operationTimeout: .milliseconds(20), watchdogSleep: clock.sleep)
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let candidate = TeleportCandidate(place: MapPlace(id: .coordinate(coordinate), title: "Target", coordinate: coordinate))
        try #require(controller.teleport(to: candidate))
        await wait { await device.waitingForPreparation }
        if afterDispatch {
            await device.finishPreparation()
            await wait { await device.waitingForReply }
        }
        await wait { clock.requests.count == 1 }
        clock.fireLatest()
        await wait { controller.error == .operationTimedOut }
        #expect(controller.nativeBusy)
        #expect(!controller.canTeleport)
        if afterDispatch { await device.finishReply(.acknowledged) }
        else { await device.finishPreparation() }
        await wait { !controller.nativeBusy }
        #expect(controller.confirmedSimulatedLocation == nil)
        #expect(await device.sent == (afterDispatch ? [coordinate] : []))
        #expect(controller.canTeleport == !afterDispatch)
        if afterDispatch {
            #expect(controller.canStop)
            #expect(controller.stop())
            await wait { !controller.nativeBusy }
            #expect(await device.clears == 1)
            #expect(controller.canTeleport)
        }
    }

    @Test func goKeepsItsOriginalCandidateAndPublishesPositionOnlyAfterAcknowledgement() async throws {
        let device = ControlledPointDevice()
        let controller = ServiceController(service: device)
        let coordinate = try #require(GeoCoordinate(latitude: 25.033, longitude: 121.5654))
        let candidate = TeleportCandidate(place: MapPlace(id: .mapKit("original"), title: "Original", coordinate: coordinate))
        try #require(controller.teleport(to: candidate))
        #expect(!controller.teleport(to: candidate))
        await wait { await device.waitingForPreparation }
        #expect(controller.confirmedSimulatedLocation == nil)
        await device.finishPreparation()
        await wait { await device.waitingForReply }
        #expect(controller.confirmedSimulatedLocation == nil)
        await device.finishReply(.acknowledged)
        await wait { !controller.nativeBusy }
        guard case .acknowledged(let intent) = controller.pointState else {
            Issue.record("A validated point reply must publish the original intent")
            return
        }
        #expect(intent.candidate == candidate)
        #expect(controller.confirmedSimulatedLocation == coordinate)
        #expect(controller.positionMarker?.coordinate == coordinate)
        #expect(controller.positionMarker?.source == .simulation)
        #expect(controller.positionMarker?.freshness == .fresh)
        #expect(controller.realLocation == nil)
        #expect(await device.sent == [coordinate])
        #expect(controller.phase == .ready)
    }

    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

private actor ControlledPointDevice: DeviceService {
    private var preparation: CheckedContinuation<Void, Never>?
    private var reply: CheckedContinuation<PointDeliveryOutcome, Never>?
    private var preparationFailure: DeviceServiceFailure?
    var sent: [GeoCoordinate] = []
    var clears = 0
    var waitingForPreparation: Bool { preparation != nil }
    var waitingForReply: Bool { reply != nil }
    func prepare() async throws {}
    func clearLocation() async throws { clears += 1 }
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        await withCheckedContinuation { preparation = $0 }
        if let failure = preparationFailure {
            preparationFailure = nil
            return .notSent(failure)
        }
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        sent.append(coordinate)
        return await withCheckedContinuation { reply = $0 }
    }
    func finishPreparation(failure: DeviceServiceFailure? = nil) {
        preparationFailure = failure
        preparation?.resume()
        preparation = nil
    }
    func finishReply(_ outcome: PointDeliveryOutcome) { reply?.resume(returning: outcome); reply = nil }
}
