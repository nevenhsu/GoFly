import Combine
import Foundation
import Testing
import GoFlyCore

@Suite @MainActor
struct MovementContinuationServiceTests {
    @Test func serviceBindsOnlyAHealthyRunningOwnerAndClosedGrantCannotDetachItAsOwnerPaused() async {
        let service = ServiceController(service: ImmediateContinuationDevice())
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: Date()))
        let intent = JoystickMovementIntent()
        let preparation = await service.beginJoystick(intent,
            expectedMovementAdmissionRevision: service.movementAdmissionRevision)
        #expect(preparation == .prepared)
        guard let inputRevision = service.joystickInputRevision(executionID: intent.id, lease: intent.lease),
              let displacement = JoystickDisplacement(bearingDegrees: 90, distanceMeters: 10) else {
            Issue.record("expected a prepared joystick owner")
            return
        }
        var acknowledgements: [MovementAcknowledgement] = []
        let token = service.movementAcknowledgements.sink { acknowledgements.append($0) }
        let outcome = await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 1, expectedInputRevision: inputRevision, displacement: displacement)
        guard case .acknowledged(let coordinate) = outcome else {
            Issue.record("expected an acknowledged joystick step")
            return
        }
        #expect(coordinate != GeoCoordinate(latitude: 25, longitude: 121)!)
        #expect(acknowledgements.count == 1)
        #expect(acknowledgements.first?.movementID == intent.id)
        #expect(acknowledgements.first?.sequence == 1)
        #expect(acknowledgements.first?.acknowledgedDistanceMeters.isFinite == true)

        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: intent.lease)
        #expect(service.bindMovementContinuation(grant))
        #expect(service.hasMovementContinuation(movementID: intent.id, lease: intent.lease,
            requestID: grant.requestID))
        grant.revoke()
        #expect(!service.hasMovementContinuation(movementID: intent.id, lease: intent.lease,
            requestID: grant.requestID))
        #expect(!service.retireMovementContinuation(requestID: grant.requestID, lease: intent.lease,
            reason: .foregroundGoalChange))
        #expect(!service.retireMovementContinuation(requestID: grant.requestID, lease: intent.lease,
            reason: .ownerPausedOrEnded))
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .pause))
        #expect(service.retireMovementContinuation(requestID: grant.requestID, lease: intent.lease,
            reason: .ownerPausedOrEnded))
        token.cancel()
    }

    @Test func inactiveSceneDoesNotAdmitAFirstOwnerClaim() async throws {
        let service = ServiceController(service: ImmediateContinuationDevice())
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(RealLocationObservation(latitude: origin.latitude, longitude: origin.longitude,
            horizontalAccuracy: 5, observedAt: Date()))
        service.setMovementSceneActive(false)
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent,
            expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let displacement = try #require(JoystickDisplacement(bearingDegrees: 0, distanceMeters: 5))
        var acknowledgements: [MovementAcknowledgement] = []
        let token = service.movementAcknowledgements.sink { acknowledgements.append($0) }
        #expect(await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 1, expectedInputRevision: input, displacement: displacement) ==
            .notSent(.device(.operationCancelled)))
        #expect(acknowledgements.isEmpty)
        #expect(service.movementAuthority.snapshot.lease == nil)
        token.cancel()
    }

    @Test func inactiveHealthyOwnerNeedsAValidBoundGrantForEachClaim() async throws {
        let service = ServiceController(service: ImmediateContinuationDevice())
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(RealLocationObservation(latitude: origin.latitude, longitude: origin.longitude,
            horizontalAccuracy: 5, observedAt: Date()))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent,
            expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let firstInput = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let displacement = try #require(JoystickDisplacement(bearingDegrees: 0, distanceMeters: 5))
        guard case .acknowledged = await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 1, expectedInputRevision: firstInput, displacement: displacement) else {
            Issue.record("expected the foreground seed acknowledgement")
            return
        }
        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: intent.lease)
        #expect(service.bindMovementContinuation(grant))
        service.setMovementSceneActive(false)
        let runningInput = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        guard case .acknowledged = await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 2, expectedInputRevision: runningInput, displacement: displacement) else {
            Issue.record("expected the bound healthy owner to dispatch while inactive")
            return
        }

        grant.revoke()
        let closedInput = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        #expect(await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 3, expectedInputRevision: closedInput, displacement: displacement) == .cancelled)
        #expect(service.movementAuthority.snapshot.lease == intent.lease)
        #expect(service.movementAuthority.snapshot.runState == .paused)
        #expect(service.movementAuthority.snapshot.health == .confirmedHealthy)
    }

    @Test func expiryBeforeClaimDeniesDetachedGateButClaimedCallAcknowledgesExactlyOnce() async throws {
        let device = HeldContinuationDevice()
        let (service, intent, displacement) = try await preparedHealthyOwner(device: device)
        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: intent.lease)
        #expect(service.bindMovementContinuation(grant))
        service.setMovementSceneActive(false)
        var acknowledgements: [MovementAcknowledgement] = []
        let token = service.movementAcknowledgements.sink { acknowledgements.append($0) }

        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let detached = Task {
            await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 2,
                expectedInputRevision: input, displacement: displacement)
        }
        await waitForPending(device)
        grant.revoke()
        #expect(!(await device.claim()))
        await device.finish(.notSent(.operationCancelled))
        #expect(await detached.value == .cancelled)
        #expect(service.movementAuthority.snapshot.lease == intent.lease)
        #expect(service.movementAuthority.snapshot.runState == .paused)
        #expect(service.movementAuthority.snapshot.health == .confirmedHealthy)
        #expect(acknowledgements.isEmpty)
        token.cancel()

        let claimedDevice = HeldContinuationDevice()
        let (claimedService, claimedIntent, claimedDisplacement) = try await preparedHealthyOwner(device: claimedDevice)
        let claimedGrant = ContinuedProcessingGrant(requestID: UUID(), movementID: claimedIntent.id,
            lease: claimedIntent.lease)
        #expect(claimedService.bindMovementContinuation(claimedGrant))
        claimedService.setMovementSceneActive(false)
        var claimedAcknowledgements: [MovementAcknowledgement] = []
        let claimedToken = claimedService.movementAcknowledgements.sink { claimedAcknowledgements.append($0) }
        let claimedInput = try #require(claimedService.joystickInputRevision(executionID: claimedIntent.id,
            lease: claimedIntent.lease))
        let claimedOrigin = try #require(claimedService.currentJoystickOrigin)
        let claimedCoordinate = JoystickGeodesy.destination(from: claimedOrigin,
            displacement: claimedDisplacement)
        let claimed = Task {
            await claimedService.sendJoystickStep(executionID: claimedIntent.id, lease: claimedIntent.lease,
                sequence: 2, expectedInputRevision: claimedInput, displacement: claimedDisplacement)
        }
        await waitForPending(claimedDevice)
        #expect(await claimedDevice.claim())
        claimedGrant.revoke()
        await claimedDevice.finish(.acknowledged)
        guard case .acknowledged(let actualCoordinate) = await claimed.value else {
            Issue.record("expected an already-claimed native acknowledgement")
            return
        }
        #expect(actualCoordinate == claimedCoordinate)
        #expect(claimedAcknowledgements.count == 1)
        #expect(claimedAcknowledgements.filter { $0.sequence == 2 }.count == 1)
        claimedToken.cancel()
    }

    @Test func foregroundReturnDoesNotReopenClosedGrantAndExplicitResumeRespectsIndependentFences() async throws {
        let device = HeldContinuationDevice()
        let (service, intent, displacement) = try await preparedHealthyOwner(device: device)
        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: intent.lease)
        #expect(service.bindMovementContinuation(grant))
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .pause))
        service.setMovementSceneActive(false)
        grant.revoke()
        #expect(!service.resumeJoystickStream(executionID: intent.id, lease: intent.lease))
        service.setMovementSceneActive(true)
        #expect(service.joystickInputRevision(executionID: intent.id, lease: intent.lease) == nil)
        #expect(service.resumeJoystickStream(executionID: intent.id, lease: intent.lease))
        let resumedInput = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let resumed = Task {
            await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 2,
                expectedInputRevision: resumedInput, displacement: displacement)
        }
        await waitForPending(device)
        #expect(await device.claim())
        await device.finish(.acknowledged)
        #expect(await resumed.value != .cancelled)

        let connectionService = ServiceController(service: ImmediateContinuationDevice())
        let connectionLease = MovementTaskLease()
        connectionService.setMovementConnectionAvailable(false)
        #expect(!connectionService.movementAuthority.install(connectionLease,
            replacing: connectionService.movementAuthority.snapshot))
        connectionService.setMovementConnectionAvailable(true)
        #expect(connectionService.movementAuthority.install(connectionLease,
            replacing: connectionService.movementAuthority.snapshot))

        let coldService = ServiceController(service: ImmediateContinuationDevice())
        #expect(coldService.restoreColdRecovery(position: nil))
        coldService.setMovementConnectionAvailable(false)
        coldService.setMovementConnectionAvailable(true)
    }

    @Test func bindingRejectsWrongIdentitiesAndNeverOverwritesAValidBinding() async throws {
        let service = ServiceController(service: ImmediateContinuationDevice())
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: Date()))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent,
            expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let displacement = try #require(JoystickDisplacement(bearingDegrees: 0, distanceMeters: 5))
        guard case .acknowledged = await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 1, expectedInputRevision: input, displacement: displacement) else {
            Issue.record("expected the owner to become healthy")
            return
        }

        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: intent.lease)
        #expect(service.bindMovementContinuation(grant))
        #expect(service.bindMovementContinuation(grant))
        let wrongMovement = ContinuedProcessingGrant(requestID: UUID(), movementID: UUID(), lease: intent.lease)
        let wrongLease = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: MovementTaskLease())
        let differentBinding = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: intent.lease)
        #expect(!service.bindMovementContinuation(wrongMovement))
        #expect(!service.bindMovementContinuation(wrongLease))
        #expect(!service.bindMovementContinuation(differentBinding))
        #expect(service.hasMovementContinuation(movementID: intent.id, lease: intent.lease,
            requestID: grant.requestID))
        #expect(!service.hasMovementContinuation(movementID: UUID(), lease: intent.lease,
            requestID: grant.requestID))
    }

    @Test func healthyOwnerCanBindWhileClaimedAndDuringAnotherPreparation() async throws {
        let device = HeldContinuationDevice()
        let (service, intent, displacement) = try await preparedHealthyOwner(device: device)
        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: intent.lease)
        #expect(service.bindMovementContinuation(grant))

        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let claimedTick = Task {
            await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 2,
                expectedInputRevision: input, displacement: displacement)
        }
        await waitForPending(device)
        #expect(service.nativeBusy)
        #expect(service.bindMovementContinuation(grant))
        #expect(service.hasMovementContinuation(movementID: intent.id, lease: intent.lease,
            requestID: grant.requestID))
        #expect(await device.claim())
        await device.finish(.acknowledged)
        #expect(await claimedTick.value != .cancelled)

        let routeIntent = try routeIntentForContinuationTest()
        let routeBegin = Task {
            await service.beginRoute(routeIntent, expectedAdmissionRevision: service.routeAdmissionRevision)
        }
        await waitForPending(device)
        #expect(service.nativeBusy)
        #expect(service.bindMovementContinuation(grant))
        #expect(service.hasMovementContinuation(movementID: intent.id, lease: intent.lease,
            requestID: grant.requestID))
        let preparationID = try #require(service.preparedOperation?.id)
        #expect(service.cancelPreparation(id: preparationID))
        await device.finish(.notSent(.operationCancelled))
        #expect(await routeBegin.value == .cancelled)
    }

    @Test func manualRetirementIsForegroundOnlyAndClosedGoalRetirementIsDenied() async throws {
        let service = ServiceController(service: ImmediateContinuationDevice())
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: Date()))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent,
            expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let displacement = try #require(JoystickDisplacement(bearingDegrees: 90, distanceMeters: 5))
        guard case .acknowledged = await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 1, expectedInputRevision: input, displacement: displacement) else {
            Issue.record("expected the owner to become healthy")
            return
        }

        let foregroundGrant = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: intent.lease)
        #expect(service.bindMovementContinuation(foregroundGrant))
        #expect(service.retireMovementContinuation(requestID: foregroundGrant.requestID, lease: intent.lease,
            reason: .foregroundManualAfterAutoOff))

        let inactiveGrant = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: intent.lease)
        #expect(service.bindMovementContinuation(inactiveGrant))
        service.setMovementSceneActive(false)
        #expect(!service.retireMovementContinuation(requestID: inactiveGrant.requestID, lease: intent.lease,
            reason: .foregroundManualAfterAutoOff))
        service.setMovementSceneActive(true)
        inactiveGrant.revoke()
        #expect(service.retireMovementContinuation(requestID: inactiveGrant.requestID, lease: intent.lease,
            reason: .foregroundManualAfterAutoOff))

        let closedGoal = ContinuedProcessingGrant(requestID: UUID(), movementID: intent.id, lease: intent.lease)
        #expect(service.bindMovementContinuation(closedGoal))
        closedGoal.revoke()
        #expect(!service.retireMovementContinuation(requestID: closedGoal.requestID, lease: intent.lease,
            reason: .foregroundGoalChange))
    }

    @Test func jsAcknowledgementUsesActualGeodesicDistanceAndDeduplicatesRetiredWork() async throws {
        let device = HeldContinuationDevice()
        let service = ServiceController(service: device)
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(RealLocationObservation(latitude: origin.latitude, longitude: origin.longitude,
            horizontalAccuracy: 5, observedAt: Date()))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent,
            expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let displacement = try #require(JoystickDisplacement(bearingDegrees: 90, distanceMeters: 5))
        var acknowledgements: [MovementAcknowledgement] = []
        let token = service.movementAcknowledgements.sink { acknowledgements.append($0) }
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let task = Task {
            await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
                expectedInputRevision: input, displacement: displacement)
        }
        await waitForPending(device)
        #expect(await device.claim())
        await device.finish(.acknowledged)
        #expect(await task.value != .cancelled)
        let expected = JoystickGeodesy.distanceMeters(from: origin,
            to: JoystickGeodesy.destination(from: origin, displacement: displacement))
        #expect(acknowledgements.count == 1)
        #expect(abs(acknowledgements[0].acknowledgedDistanceMeters - expected) < 0.000_001)

        let duplicateInput = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        #expect(await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
            expectedInputRevision: duplicateInput, displacement: displacement) == .cancelled)
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .endGesture))
        #expect(await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 2,
            expectedInputRevision: duplicateInput, displacement: displacement) == .cancelled)
        #expect(acknowledgements.count == 1)
        token.cancel()
    }

    private func preparedHealthyOwner(device: HeldContinuationDevice) async throws ->
        (ServiceController, JoystickMovementIntent, JoystickDisplacement) {
        let service = ServiceController(service: device)
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        service.observeRealLocation(RealLocationObservation(latitude: origin.latitude, longitude: origin.longitude,
            horizontalAccuracy: 5, observedAt: Date()))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent,
            expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let displacement = try #require(JoystickDisplacement(bearingDegrees: 0, distanceMeters: 5))
        let first = Task {
            await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
                expectedInputRevision: input, displacement: displacement)
        }
        await waitForPending(device)
        #expect(await device.claim())
        await device.finish(.acknowledged)
        #expect(await first.value != .cancelled)
        return (service, intent, displacement)
    }

    private func waitForPending(_ device: HeldContinuationDevice) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await device.waiting) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await device.waiting)
    }

    private func routeIntentForContinuationTest() throws -> RouteExecutionIntent {
        let start = GeoCoordinate(latitude: 25, longitude: 121)!
        let end = GeoCoordinate(latitude: 25.01, longitude: 121.01)!
        let place: (GeoCoordinate) -> MapPlace = {
            MapPlace(id: .coordinate($0), title: $0.displayText, coordinate: $0)
        }
        let draft = try #require(RouteDraft(start: .place(place(start)), destination: .place(place(end))))
        let route = try PlannedRoute(points: [start, end], from: start, to: end)
        return RouteExecutionIntent(draft: draft, route: route)
    }
}

private struct ImmediateContinuationDevice: DeviceService {
    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        return .acknowledged
    }
}

private actor HeldContinuationDevice: DeviceService {
    private var pending: CheckedContinuation<PointDeliveryOutcome, Never>?
    private var gate: PointDispatchGate?
    var waiting: Bool { pending != nil }

    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}

    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        gate = dispatch
        return await withCheckedContinuation { pending = $0 }
    }

    func claim() -> Bool { gate?.claim() ?? false }

    func finish(_ outcome: PointDeliveryOutcome) {
        pending?.resume(returning: outcome)
        pending = nil
        gate = nil
    }
}
