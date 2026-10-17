import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct JoystickControllerIntegrationTests {
    @Test func realPreparationRetryAndAvailableInputCancellationKeepTheControllerAndServiceInAgreement() async throws {
        let device = JoystickControlledDevice(failuresBeforeSuccess: 3), clock = RouteTestClock()
        let service = ServiceController(service: device)
        service.observeRealLocation(observation(25, 121))
        let controller = JoystickMovementController(commands: service, clock: clock)
        let finger = UUID()
        #expect(controller.beginGesture(id: finger, input: JoystickInput(bearingDegrees: 0, strength: 1)!))
        let operation = try #require(controller.intent)
        await wait { service.preparedOperation?.state == .failed(.pairingRequired) }
        #expect(controller.phase == .preparing && clock.sleepingCount == 0)
        #expect(service.confirmedSimulatedLocation == nil)
        #expect(await device.coordinates.isEmpty)
        await device.allowPreparationSuccess()
        #expect(service.retryPreparedOperation(id: try #require(service.preparedOperation?.id)))
        await wait { clock.sleepingCount == 1 }
        #expect(controller.intent == operation && !controller.canPause)
        service.observeRealLocation(observation(26, 122))
        let latestOrigin = try #require(service.currentJoystickOrigin)
        clock.advance(by: .milliseconds(500)); await wait { await device.waiting }
        let north = JoystickGeodesy.destination(from: latestOrigin, displacement: JoystickInput(bearingDegrees: 0, strength: 1)!.displacement(speed: .standard)!)
        #expect(await device.coordinates == [north])
        #expect(controller.updateGesture(id: finger, input: JoystickInput(bearingDegrees: 90, strength: 1)!))
        #expect(!(await device.claim()))
        await device.finish(.notSent(.operationCancelled))
        await wait { clock.sleepingCount == 1 }
        #expect(service.confirmedSimulatedLocation == nil && controller.lastAcknowledgedCoordinate == nil)
        clock.advance(by: .milliseconds(500)); await wait { await device.waiting }
        let east = JoystickGeodesy.destination(from: latestOrigin, displacement: JoystickInput(bearingDegrees: 90, strength: 1)!.displacement(speed: .standard)!)
        #expect(await device.coordinates.last == east)
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { controller.lastAcknowledgedCoordinate == east && clock.sleepingCount == 1 }
        #expect(service.confirmedSimulatedLocation == east && controller.canPause)
        #expect(controller.lastAcknowledgedBearingDegrees == 90)
        #expect(controller.endGesture(id: finger)); await wait { controller.phase == .neutral }
        #expect(await device.clears == 0)
    }

    @Test(arguments: [false, true])
    func realClaimedReleasePublishesACKTruthOrRequiresStopAndNeverQueuesAnotherGesture(unknown: Bool) async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(observation(25, 121))
        let controller = JoystickMovementController(commands: service, clock: clock)
        let finger = UUID(), input = JoystickInput(bearingDegrees: 135, strength: 1)!
        #expect(controller.beginGesture(id: finger, input: input))
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        let actual = try #require(await device.coordinates.last)
        #expect(await device.claim())
        #expect(controller.endGesture(id: finger))
        #expect(!controller.beginGesture(id: UUID(), input: input))
        await device.finish(unknown ? .unconfirmed(.serviceUnavailable) : .acknowledged)
        if unknown {
            await wait { controller.requiresStop && !service.nativeBusy }
            #expect(controller.lastAcknowledgedCoordinate == nil)
            #expect(service.stop())
            await wait { controller.phase == .neutral && !service.nativeBusy }
            #expect(await device.clears == 1)
        } else {
            await wait { controller.phase == .neutral }
            #expect(controller.lastAcknowledgedCoordinate == actual)
            #expect(controller.lastAcknowledgedBearingDegrees == 135)
            #expect(service.confirmedSimulatedLocation == actual)
            #expect(await device.clears == 0)
        }
        clock.advance(by: .seconds(30))
        #expect(await device.coordinates.count == 1)
    }

    @Test(arguments: [false, true])
    func firstUnclaimedFailurePreservesTheHealthyPreviousOwnerAndAllowsANewGesture(originUnavailable: Bool) async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(observation(25, 121))
        let oldLease = MovementTaskLease()
        #expect(service.movementAuthority.install(oldLease, replacing: service.movementAuthority.snapshot))
        #expect(service.movementAuthority.updateHealth(.confirmedHealthy, for: oldLease))
        let oldAuthority = service.movementAuthority.snapshot
        let controller = JoystickMovementController(commands: service, clock: clock)
        let input = JoystickInput(bearingDegrees: 0, strength: 1)!
        #expect(controller.beginGesture(id: UUID(), input: input))
        let first = try #require(controller.intent)
        await wait { clock.sleepingCount == 1 }
        if originUnavailable { service.observeRealLocation(nil) }
        clock.advance(by: .milliseconds(500))
        if !originUnavailable {
            await wait { await device.waiting }
            await device.finish(.notSent(.pairingRequired))
        }
        await wait { controller.phase == .neutral && !service.nativeBusy }
        #expect(!controller.requiresStop && !controller.canPause)
        #expect(controller.error == (originUnavailable ? .originUnavailable : .device(.pairingRequired)))
        #expect(controller.lastAcknowledgedCoordinate == nil)
        #expect(service.movementAuthority.snapshot == oldAuthority)
        #expect(await device.clears == 0)
        if originUnavailable { service.observeRealLocation(observation(25, 121)) }
        #expect(controller.canBeginGesture)
        let finger = UUID()
        #expect(controller.beginGesture(id: finger, input: input))
        let next = try #require(controller.intent)
        #expect(next.id != first.id && next.lease != first.lease)
        await wait { clock.sleepingCount == 1 }
        #expect(controller.endGesture(id: finger))
        await wait { controller.phase == .neutral }
        #expect(service.movementAuthority.snapshot == oldAuthority)
    }

    @Test(arguments: [false, true])
    func inactiveRetiresResumedNeutralOwnerEvenWhenANewGestureHasNotClaimed(duringPreparation: Bool) async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(observation(25, 121))
        let controller = JoystickMovementController(commands: service, clock: clock)
        let input = JoystickInput(bearingDegrees: 0, strength: 1)!
        var ended: Set<UUID> = []
        let subscription = service.joystickEvents.sink { if case .ended(let id) = $0 { ended.insert(id) } }
        #expect(controller.beginGesture(id: UUID(), input: input))
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { controller.canPause && clock.sleepingCount == 1 }
        let old = try #require(controller.intent), confirmed = service.confirmedSimulatedLocation
        #expect(controller.pause()); await wait { controller.phase == .paused }
        #expect(controller.resume())
        #expect(service.movementAuthority.snapshot.lease == old.lease)
        #expect(service.movementAuthority.snapshot.runState == .running)
        if duringPreparation { await device.holdPreparation() }
        #expect(controller.beginGesture(id: UUID(), input: input))
        let next = try #require(controller.intent)
        #expect(next.id != old.id)
        if duringPreparation { await wait { await device.preparing } }
        else { await wait { clock.sleepingCount == 1 } }
        #expect(service.movementAuthority.snapshot.lease == old.lease)
        controller.releaseForInactiveScene()
        if duringPreparation { await device.releasePreparation() }
        await wait { controller.phase == .neutral && !service.nativeBusy }
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(ended.contains(old.id) && ended.contains(next.id))
        #expect(controller.intent == nil && controller.input == nil && controller.activeGestureID == nil)
        clock.advance(by: .seconds(30))
        #expect(await device.coordinates.count == 1)
        #expect(service.confirmedSimulatedLocation == confirmed)
        #expect(await device.clears == 0)
        withExtendedLifetime(subscription) {}
    }

    @Test func laterUnclaimedFailureEndsInstalledGestureAndAllowsAFreshIntentWithoutLosingLastACK() async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(observation(25, 121))
        let controller = JoystickMovementController(commands: service, clock: clock)
        let finger = UUID(), input = JoystickInput(bearingDegrees: 90, strength: 1)!
        #expect(controller.beginGesture(id: finger, input: input))
        let first = try #require(controller.intent)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        let acknowledged = try #require(await device.coordinates.last)
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { controller.canPause && clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500)); await wait { await device.waiting }
        await device.finish(.notSent(.pairingRequired))
        await wait { controller.phase == .neutral && !service.nativeBusy && controller.error == .device(.pairingRequired) }
        #expect(controller.phase == .neutral && controller.input == nil && controller.activeGestureID == nil)
        #expect(controller.intent == nil && !controller.requiresStop)
        #expect(controller.lastAcknowledgedCoordinate == acknowledged)
        #expect(controller.lastAcknowledgedBearingDegrees == 90)
        #expect(service.confirmedSimulatedLocation == acknowledged)
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(controller.canBeginGesture)
        let nextFinger = UUID(), accepted = controller.beginGesture(id: nextFinger, input: input)
        #expect(accepted)
        guard accepted else { return }
        #expect(controller.intent?.id != first.id && controller.intent?.lease != first.lease)
        await wait { clock.sleepingCount == 1 }
        #expect(controller.endGesture(id: nextFinger)); await wait { controller.phase == .neutral }
        #expect(await device.coordinates.count == 2)
        #expect(await device.clears == 0)
    }

    private func observation(_ latitude: Double, _ longitude: Double) -> RealLocationObservation {
        RealLocationObservation(latitude: latitude, longitude: longitude, horizontalAccuracy: 1, observedAt: Date())!
    }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}
