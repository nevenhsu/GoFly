import Foundation
import Testing
import GoFlyCore

@Suite @MainActor
struct ServiceJoystickRecipeTests {
    @Test func movementBoundaryPublishesEachProvenSameLeaseClaimAndOnlyAcceptedStop() async throws {
        let (service, device, intent) = await preparedService()
        var boundaries: [MovementTaskLease?] = []
        let subscription = service.joystickEvents.sink { if case .movementBoundary(let lease) = $0 { boundaries.append(lease) } }
        defer { subscription.cancel() }
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        for sequence in UInt64(1)...2 {
            let target = JoystickTargetStep(targetID: UUID(), coordinate: service.currentJoystickOrigin!, maximumDistanceMeters: 1)!
            let step = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: sequence,
                expectedInputRevision: input, recipe: .target(target)) }
            await wait { await device.waiting }
            #expect(boundaries.count == Int(sequence) - 1)
            #expect(await device.claim())
            await wait { boundaries.count == Int(sequence) }
            #expect(boundaries == Array(repeating: Optional(intent.lease), count: Int(sequence)))
            await device.finish(.acknowledged)
            #expect(await step.value == .acknowledged(JoystickStepReceipt(actualCoordinate: target.coordinate,
                actualBearingDegrees: nil, targetID: target.targetID, arrived: true)))
        }
        #expect(service.stop())
        #expect(boundaries == [intent.lease, intent.lease, nil])
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(!service.stop())
        #expect(boundaries.count == 3)
        await wait { !service.nativeBusy }
        #expect(!service.stop())
        #expect(boundaries.count == 3)
    }

    @Test func movementBoundaryDoesNotTreatFailedPreparationOrAvailableCancellationAsDispatch() async throws {
        let device = JoystickControlledDevice(failuresBeforeSuccess: 3), service = ServiceController(service: device)
        var boundaries: [MovementTaskLease?] = []
        let subscription = service.joystickEvents.sink { if case .movementBoundary(let lease) = $0 { boundaries.append(lease) } }
        defer { subscription.cancel() }
        #expect(!service.stop())
        let failed = JoystickMovementIntent()
        let beginning = Task { await service.beginJoystick(failed, expectedMovementAdmissionRevision: service.movementAdmissionRevision) }
        await wait { service.preparedOperation?.state == .failed(.pairingRequired) }
        #expect(boundaries.isEmpty)
        #expect(await device.coordinates.isEmpty)
        #expect(service.cancelPreparation(id: try #require(service.preparedOperation?.id)))
        #expect(await beginning.value == .cancelled)
        #expect(boundaries.isEmpty)
        await device.allowPreparationSuccess()
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121, horizontalAccuracy: 1, observedAt: Date()))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        #expect(boundaries.isEmpty)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let target = JoystickTargetStep(targetID: UUID(), coordinate: service.currentJoystickOrigin!, maximumDistanceMeters: 1)!
        let step = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, recipe: .target(target)) }
        await wait { await device.waiting }
        #expect(service.reviseJoystickInput(executionID: intent.id, lease: intent.lease) != nil)
        #expect(!(await device.claim()))
        await device.finish(.notSent(.operationCancelled))
        #expect(await step.value == .inputCancelled)
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .endGesture))
        #expect(boundaries.isEmpty)
    }

    @Test func movementBoundaryForAnotherPointIsDispatchProofBeforeAnUnknownReply() async {
        let (service, device, _) = await preparedService()
        var boundaries: [MovementTaskLease?] = []
        let subscription = service.joystickEvents.sink { if case .movementBoundary(let lease) = $0 { boundaries.append(lease) } }
        defer { subscription.cancel() }
        let coordinate = GeoCoordinate(latitude: 26, longitude: 122)!
        let candidate = TeleportCandidate(place: MapPlace(id: .coordinate(coordinate), title: "Target", coordinate: coordinate))
        #expect(service.teleport(to: candidate))
        await wait { await device.waiting }
        #expect(boundaries.isEmpty)
        #expect(await device.claim())
        await wait { !boundaries.isEmpty }
        #expect(boundaries.count == 1)
        #expect(boundaries == [service.movementAuthority.snapshot.lease])
        #expect(boundaries.compactMap { $0 }.count == 1)
        await device.finish(.unconfirmed(.tunnelUnavailable))
        await wait { !service.nativeBusy }
        #expect(service.phase == .repairRequired)
        #expect(service.confirmedSimulatedLocation == nil)
        #expect(boundaries.count == 1)
    }

    @Test func targetAtFIFOHeadUsesThePrecedingRoutesActualACKAndStillWritesZeroDistance() async throws {
        let device = JoystickControlledDevice(), service = ServiceController(service: device)
        let start = GeoCoordinate(latitude: 25, longitude: 121)!, targetCoordinate = GeoCoordinate(latitude: 26, longitude: 122)!
        let place: (GeoCoordinate) -> MapPlace = { MapPlace(id: .coordinate($0), title: $0.displayText, coordinate: $0) }
        let old = RouteExecutionIntent(draft: RouteDraft(start: .place(place(start)), destination: .place(place(targetCoordinate)))!,
            route: try PlannedRoute(points: [start, targetCoordinate], from: start, to: targetCoordinate))
        let begin = Task { await service.beginRoute(old, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }; #expect(await device.claim()); await device.finish(.acknowledged)
        #expect(await begin.value == .acknowledged)
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let oldTick = Task { await service.sendRoutePoint(executionID: old.id, lease: old.lease, sequence: 1,
            expectedControlRevision: service.routeControlRevision(executionID: old.id, lease: old.lease)!, coordinate: targetCoordinate) }
        await wait { await device.waiting }; #expect(await device.claim())
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let target = JoystickTargetStep(targetID: UUID(), coordinate: targetCoordinate, maximumDistanceMeters: 1)!
        var submitted = false, completed: JoystickRecipeStepOutcome?
        let next = Task { submitted = true; completed = await service.sendJoystickStep(executionID: intent.id,
            lease: intent.lease, sequence: 1, expectedInputRevision: input, recipe: .target(target)) }
        await wait { submitted }
        #expect(await device.coordinates == [start, targetCoordinate])
        await device.finish(.acknowledged)
        #expect(await oldTick.value == .acknowledged)
        await wait { await device.waiting }
        #expect(await device.coordinates == [start, targetCoordinate, targetCoordinate])
        #expect(completed == nil)
        #expect(service.movementAuthority.snapshot.lease == old.lease)
        #expect(await device.claim())
        await device.finish(.acknowledged)
        await next.value
        #expect(completed == .acknowledged(JoystickStepReceipt(actualCoordinate: targetCoordinate,
            actualBearingDegrees: nil, targetID: target.targetID, arrived: true)))
        #expect(service.confirmedSimulatedLocation == targetCoordinate)
        #expect(service.movementAuthority.snapshot.lease == intent.lease)
    }

    @Test(arguments: [false, true])
    func receiptCapturesTheSentTargetStepAndClampsOnlyTheFinalStep(finalStep: Bool) async throws {
        let (service, device, intent) = await preparedService()
        let origin = try #require(service.currentJoystickOrigin)
        let coordinate = JoystickGeodesy.destination(from: origin, displacement:
            JoystickDisplacement(bearingDegrees: 90, distanceMeters: finalStep ? 2 : 10)!)
        let target = JoystickTargetStep(targetID: UUID(), coordinate: coordinate, maximumDistanceMeters: 3)!
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let step = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, recipe: .target(target)) }
        await wait { await device.waiting }
        let sent = try #require(await device.coordinates.last)
        #expect(service.confirmedSimulatedLocation == nil)
        if finalStep { #expect(sent == target.coordinate) }
        else {
            #expect(sent != target.coordinate)
            #expect(abs(JoystickGeodesy.distanceMeters(from: origin, to: sent) - 3) < 0.000001)
        }
        #expect(await device.claim())
        await device.finish(.acknowledged)
        guard case .acknowledged(let receipt) = await step.value else { Issue.record("expected target ACK"); return }
        #expect(receipt.actualCoordinate == sent)
        #expect(receipt.targetID == target.targetID)
        #expect(receipt.arrived == finalStep)
        #expect(abs(try #require(receipt.actualBearingDegrees) - 90) < 0.000001)
        #expect(service.confirmedSimulatedLocation == sent)
    }

    @Test(arguments: [false, true])
    func switchingRecipesWithdrawsOnlyAvailableWorkAndReturnsClaimedTargetIdentity(claimed: Bool) async throws {
        let (service, device, intent) = await preparedService()
        let originalInput = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let firstTarget = JoystickTargetStep(targetID: UUID(), coordinate: service.currentJoystickOrigin!, maximumDistanceMeters: 1)!
        let first = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: originalInput, recipe: .target(firstTarget)) }
        await wait { await device.waiting }
        if claimed { #expect(await device.claim()) }
        let revised = try #require(service.reviseJoystickInput(executionID: intent.id, lease: intent.lease))
        if !claimed { #expect(!(await device.claim())) }
        await device.finish(claimed ? .acknowledged : .notSent(.operationCancelled))
        #expect(await first.value == (claimed ? .acknowledged(JoystickStepReceipt(actualCoordinate: firstTarget.coordinate,
            actualBearingDegrees: nil, targetID: firstTarget.targetID, arrived: true)) : .inputCancelled))
        let displacement = JoystickDisplacement(bearingDegrees: 180, distanceMeters: 2)!
        let next = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: claimed ? 2 : 1,
            expectedInputRevision: revised, recipe: .manual(displacement)) }
        await wait { await device.waiting }
        let sent = try #require(await device.coordinates.last)
        #expect(await device.claim()); await device.finish(.acknowledged)
        #expect(await next.value == .acknowledged(JoystickStepReceipt(actualCoordinate: sent,
            actualBearingDegrees: 180, targetID: nil, arrived: false)))
    }

    @Test func resumedStreamKeepsLeaseSequenceAndPreparesOnlyOnce() async throws {
        let (service, device, intent) = await preparedService()
        let initial = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let first = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: initial, recipe: .manual(JoystickDisplacement(bearingDegrees: 90, distanceMeters: 1)!)) }
        await wait { await device.waiting }
        #expect(await device.claim())
        await device.finish(.acknowledged)
        guard case .acknowledged(let receipt) = await first.value else { Issue.record("first step requires ACK"); return }
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .pause))
        #expect(await service.waitForJoystickIdle(executionID: intent.id, lease: intent.lease) == .settled)
        #expect(service.movementAuthority.snapshot.runState == .paused)
        #expect(service.resumeJoystickStream(executionID: intent.id, lease: intent.lease))
        let resumed = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        #expect(resumed.generation != initial.generation)
        #expect(service.movementAuthority.snapshot.lease == intent.lease)
        #expect(service.movementAuthority.snapshot.runState == .running)
        #expect(await device.preparations == 1)
        #expect(await device.coordinates.count == 1)
        #expect(await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: resumed, recipe: .manual(JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!)) == .cancelled)
        #expect(await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 2,
            expectedInputRevision: initial, recipe: .manual(JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!)) == .inputCancelled)
        let target = JoystickTargetStep(targetID: UUID(), coordinate: receipt.actualCoordinate, maximumDistanceMeters: 1)!
        let next = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 2,
            expectedInputRevision: resumed, recipe: .target(target)) }
        await wait { await device.waiting }
        #expect(await device.coordinates.last == target.coordinate)
        #expect(await device.claim())
        await device.finish(.acknowledged)
        #expect(await next.value == .acknowledged(JoystickStepReceipt(actualCoordinate: target.coordinate,
            actualBearingDegrees: nil, targetID: target.targetID, arrived: true)))
        #expect(await device.preparations == 1)
    }

    @Test(arguments: [false, true])
    func pauseRequiresActualRecipeReturnAndAnUnknownResultCannotResume(failedAfterClaim: Bool) async throws {
        let (service, device, intent) = await preparedService()
        #expect(!service.resumeJoystickStream(executionID: intent.id, lease: intent.lease))
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let displacement = JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!
        let first = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, displacement: displacement) }
        await wait { await device.waiting }; #expect(await device.claim()); await device.finish(.acknowledged)
        guard case .acknowledged(let coordinate) = await first.value else { Issue.record("first step requires ACK"); return }
        #expect(!service.resumeJoystickStream(executionID: intent.id, lease: intent.lease))
        let target = JoystickTargetStep(targetID: UUID(), coordinate: coordinate, maximumDistanceMeters: 1)!
        let next = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 2,
            expectedInputRevision: input, recipe: .target(target)) }
        await wait { await device.waiting }; #expect(await device.claim())
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .pause))
        #expect(!service.resumeJoystickStream(executionID: intent.id, lease: intent.lease))
        #expect(service.nativeBusy)
        var settlement: JoystickIdleSettlement?
        let idle = Task { settlement = await service.waitForJoystickIdle(executionID: intent.id, lease: intent.lease) }
        await Task.yield()
        #expect(settlement == nil)
        await device.finish(failedAfterClaim ? .notSent(.tunnelUnavailable) : .acknowledged)
        #expect(await next.value == (failedAfterClaim ? .unconfirmed(.tunnelUnavailable) :
            .acknowledged(JoystickStepReceipt(actualCoordinate: coordinate, actualBearingDegrees: nil,
                targetID: target.targetID, arrived: true))))
        await idle.value
        #expect(settlement == (failedAfterClaim ? .requiresStop(.tunnelUnavailable) : .settled))
        #expect(!service.resumeJoystickStream(executionID: UUID(), lease: intent.lease))
        #expect(!service.resumeJoystickStream(executionID: intent.id, lease: MovementTaskLease()))
        #expect(service.resumeJoystickStream(executionID: intent.id, lease: intent.lease) == !failedAfterClaim)
        #expect(await device.preparations == 1)
        #expect(await device.coordinates.count == 2)
        #expect(await device.clears == 0)
    }

    @Test(arguments: [false, true])
    func claimedRecipeTimeoutOrStopKeepsActualOwnershipAndLateACKCannotResume(stopped: Bool) async throws {
        let watchdog = ManualServiceWatchdog()
        let (service, device, intent) = await preparedService(watchdog: watchdog)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let target = JoystickTargetStep(targetID: UUID(), coordinate: service.currentJoystickOrigin!, maximumDistanceMeters: 1)!
        let step = Task { await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: input, recipe: .target(target)) }
        await wait { await device.waiting && watchdog.requests.count == 2 }
        #expect(await device.claim())
        if stopped { #expect(service.stop()) }
        else {
            watchdog.fireLatest()
            await wait { service.error == .operationTimedOut }
        }
        #expect(service.nativeBusy)
        #expect(!service.resumeJoystickStream(executionID: intent.id, lease: intent.lease))
        #expect(await device.clears == 0)
        await device.finish(.acknowledged)
        #expect(await step.value == (stopped ? .cancelled : .unconfirmed(.operationTimedOut)))
        #expect(service.confirmedSimulatedLocation == nil)
        #expect(!service.resumeJoystickStream(executionID: intent.id, lease: intent.lease))
        #expect(await service.waitForJoystickIdle(executionID: intent.id, lease: intent.lease) ==
            (stopped ? .settled : .requiresStop(.operationTimedOut)))
        if !stopped { #expect(service.stop()) }
        await wait { !service.nativeBusy }
        #expect(service.phase == .stopped)
        #expect(await device.clears == 1)
    }

    private func preparedService(watchdog: ManualServiceWatchdog? = nil) async -> (ServiceController, JoystickControlledDevice, JoystickMovementIntent) {
        let device = JoystickControlledDevice()
        let service = watchdog.map { ServiceController(service: device, watchdogSleep: $0.sleep) } ?? ServiceController(service: device)
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 1, observedAt: Date()))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        return (service, device, intent)
    }

    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}
