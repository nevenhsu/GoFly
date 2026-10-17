import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct WanderControllerIntegrationTests {
    @Test func realArrivalWithoutNextTargetPausesAuthorityAndGoThenRetryUsesTheSameLease() async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), samples = IntegrationWanderSamples([[0], []])
        let service = ServiceController(service: device)
        service.observeRealLocation(location())
        let controller = JoystickMovementController(commands: service, clock: clock, wanderBearingSamples: { samples.next() })
        #expect(controller.setWanderEnabled(true))
        let operation = try #require(controller.intent)
        let firstPoint = GeoCoordinate(latitude: 25.00001, longitude: 121)!
        #expect(controller.applyWanderTarget(place(firstPoint)))
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(await device.coordinates == [firstPoint])
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { controller.phase == .suspended }
        #expect(controller.suspensionReason == .targetUnavailable && controller.wanderNeedsTarget)
        #expect(service.movementAuthority.snapshot.lease == operation.lease)
        #expect(service.movementAuthority.snapshot.runState == .paused)
        #expect(service.movementAuthority.snapshot.health == .confirmedHealthy)
        #expect(service.confirmedSimulatedLocation == firstPoint)
        let nextPoint = GeoCoordinate(latitude: 25.00002, longitude: 121)!
        #expect(controller.applyWanderTarget(place(nextPoint)))
        #expect(controller.phase == .suspended && !controller.wanderNeedsTarget)
        clock.advance(by: .seconds(30))
        #expect(await device.coordinates.count == 1)
        #expect(service.movementAuthority.snapshot.runState == .paused)
        #expect(controller.retryWander())
        #expect(controller.intent == operation && service.movementAuthority.snapshot.runState == .running)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(await device.coordinates.last == nextPoint)
        #expect(await device.claim()); await device.finish(.acknowledged)
        await wait { controller.phase == .suspended }
        #expect(controller.lastAcknowledgedCoordinate == nextPoint)
        #expect(controller.setWanderEnabled(false)); await wait { controller.phase == .neutral }
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(await device.preparations == 1)
        #expect(await device.clears == 0)
    }

    @Test(arguments: ["stop", "claimUnknown", "availableCancel", "failedPrepare"])
    func retiredLocalWanderIsInvalidatedOnlyByAcceptedStopOrAnotherActualClaim(boundary: String) async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(location())
        let controller = JoystickMovementController(commands: service, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        await wait { clock.sleepingCount == 1 }
        controller.releaseForInactiveScene()
        await wait { controller.phase == .suspended && !service.nativeBusy }
        controller.sceneDidBecomeActive()
        #expect(controller.wanderEnabled && controller.intent == nil)
        if boundary == "stop" {
            #expect(service.stop())
            await wait { !service.nativeBusy }
        } else {
            #expect(service.teleport(to: TeleportCandidate(place: place(GeoCoordinate(latitude: 26, longitude: 122)!))))
            if boundary == "failedPrepare" {
                for _ in 0..<3 {
                    await wait { await device.waiting }
                    await device.finish(.notSent(.pairingRequired))
                }
                await wait { service.preparedOperation?.state == .failed(.pairingRequired) }
                #expect(controller.wanderEnabled && controller.phase == .suspended)
                #expect(service.cancelPreparation(id: try #require(service.preparedOperation?.id)))
            } else {
                await wait { await device.waiting }
                #expect(controller.wanderEnabled && controller.phase == .suspended)
                if boundary == "claimUnknown" {
                    #expect(await device.claim())
                    await wait { !controller.wanderEnabled }
                    await device.finish(.unconfirmed(.serviceUnavailable))
                } else {
                    #expect(service.cancelPreparation(id: try #require(service.preparedOperation?.id)))
                    #expect(!(await device.claim()))
                    await device.finish(.notSent(.operationCancelled))
                }
                await wait { !service.nativeBusy }
            }
        }
        if boundary == "stop" || boundary == "claimUnknown" {
            #expect(!controller.wanderEnabled && controller.phase == .neutral && controller.wanderTarget == nil)
            #expect(!controller.resume() && !controller.retryWander())
        } else {
            #expect(controller.wanderEnabled && controller.phase == .suspended && controller.canResume)
            #expect(controller.setWanderEnabled(false))
        }
        clock.advance(by: .seconds(30))
        #expect(await device.coordinates.count == (boundary == "stop" ? 0 : (boundary == "failedPrepare" ? 3 : 1)))
        if boundary == "claimUnknown" { #expect(service.stop()); await wait { !service.nativeBusy } }
    }

    @Test(arguments: [false, true])
    func unclaimedAutoFailureBeforeOrAfterInstallationAllowsExplicitRetryWithANewIntent(installed: Bool) async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(location())
        let controller = JoystickMovementController(commands: service, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        let old = try #require(controller.intent), target = try #require(controller.wanderTarget)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        if installed {
            #expect(await device.claim()); await device.finish(.acknowledged)
            await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
            await wait { await device.waiting }
        }
        let confirmed = service.confirmedSimulatedLocation
        await device.finish(.notSent(.pairingRequired))
        await wait { controller.phase == .neutral && !service.nativeBusy }
        #expect(controller.wanderEnabled && controller.wanderTarget == target && controller.canRetryWander)
        #expect(controller.error == .device(.pairingRequired) && !controller.requiresStop)
        #expect(service.confirmedSimulatedLocation == confirmed)
        #expect(controller.retryWander())
        #expect(controller.intent?.id != old.id && controller.intent?.lease != old.lease)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(controller.setWanderEnabled(false))
        #expect(!(await device.claim())); await device.finish(.notSent(.operationCancelled))
        await wait { controller.phase == .neutral && !service.nativeBusy }
        #expect(await device.preparations == 2)
        #expect(await device.clears == 0)
    }

    @Test func aClaimedUnknownAutoStepRequiresStopEvenAfterDisablingTheCheckbox() async throws {
        let device = JoystickControlledDevice(), clock = RouteTestClock(), service = ServiceController(service: device)
        service.observeRealLocation(location())
        let controller = JoystickMovementController(commands: service, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(await device.claim()); await device.finish(.unconfirmed(.serviceUnavailable))
        await wait { controller.requiresStop && !service.nativeBusy }
        #expect(!controller.retryWander() && !controller.resume())
        controller.clearError()
        #expect(controller.requiresStop && controller.error == .device(.serviceUnavailable))
        #expect(controller.setWanderEnabled(false))
        #expect(controller.requiresStop && controller.phase == .unknown)
        #expect(service.stop()); await wait { controller.phase == .neutral && !service.nativeBusy }
        #expect(!controller.wanderEnabled && controller.error == nil)
        clock.advance(by: .seconds(30))
        #expect(await device.coordinates.count == 1)
        #expect(await device.clears == 1)
    }

    private func location() -> RealLocationObservation { RealLocationObservation(latitude: 25, longitude: 121, horizontalAccuracy: 1, observedAt: Date())! }
    private func place(_ coordinate: GeoCoordinate) -> MapPlace { MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate) }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}
private final class IntegrationWanderSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[Double]]
    init(_ values: [[Double]]) { self.values = values }
    func next() -> [Double] { lock.withLock { values.isEmpty ? [] : values.removeFirst() } }
}
