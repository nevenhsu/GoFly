import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct PositionHoldServiceTests {
    @Test func fixedIntentRejectsManualAndTargetRecipes() async throws {
        let device = PositionHoldServiceDevice()
        let service = ServiceController(service: device)
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        service.observeRealLocation(realLocation(coordinate))
        let intent = JoystickMovementIntent(lease: MovementTaskLease(), fixedPosition: coordinate)
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let manual = await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 1, expectedInputRevision: input,
            recipe: .manual(JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1)!))
        #expect(manual == .notSent(.device(.operationCancelled)))
        let target = JoystickTargetStep(targetID: UUID(), coordinate: coordinate, maximumDistanceMeters: 1)!
        let targetResult = await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 1, expectedInputRevision: input, recipe: .target(target))
        #expect(targetResult == .notSent(.device(.operationCancelled)))
        #expect(await device.pendingCount == 0)
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .endGesture))
    }

    @Test func normalIntentRejectsFixedRecipe() async throws {
        let device = PositionHoldServiceDevice()
        let service = ServiceController(service: device)
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        service.observeRealLocation(realLocation(coordinate))
        let intent = JoystickMovementIntent()
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let result = await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 1, expectedInputRevision: input, recipe: .fixedPosition(coordinate))
        #expect(result == .notSent(.device(.operationCancelled)))
        #expect(await device.pendingCount == 0)
        #expect(service.releaseJoystick(executionID: intent.id, lease: intent.lease, disposition: .endGesture))
    }

    @Test func fixedIntentRejectsMismatchedCoordinateAndAcceptsExactCoordinate() async throws {
        let device = PositionHoldServiceDevice()
        let service = ServiceController(service: device)
        let origin = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let other = try #require(GeoCoordinate(latitude: 25.1, longitude: 121.1))
        service.observeRealLocation(realLocation(origin))
        let intent = JoystickMovementIntent(lease: MovementTaskLease(), fixedPosition: origin)
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let mismatched = await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
            sequence: 1, expectedInputRevision: input, recipe: .fixedPosition(other))
        #expect(mismatched == .notSent(.device(.operationCancelled)))
        #expect(await device.pendingCount == 0)

        let accepted = Task {
            await service.sendJoystickStep(executionID: intent.id, lease: intent.lease,
                sequence: 1, expectedInputRevision: input, recipe: .fixedPosition(origin))
        }
        await waitForPending(device)
        #expect(await device.claimNext())
        await device.finishNext(.acknowledged)
        #expect(await accepted.value == .acknowledged(JoystickStepReceipt(
            actualCoordinate: origin, actualBearingDegrees: nil, targetID: nil, arrived: false)))
        #expect(await device.coordinates == [origin])
    }

    @Test func explicitManualRouteAndTeleportHandoffsCancelInstalledFixedOwner() async throws {
        for mode in HandoffMode.allCases {
            let device = PositionHoldServiceDevice()
            let service = ServiceController(service: device)
            let origin = try #require(GeoCoordinate(latitude: 25, longitude: 121))
            service.observeRealLocation(realLocation(origin))
            let fixed = try await installFixedOwner(service: service, device: device, coordinate: origin)

            switch mode {
            case .manual:
                let next = JoystickMovementIntent()
                let preparation = Task {
                    await service.beginJoystick(next, expectedMovementAdmissionRevision: service.movementAdmissionRevision)
                }
                #expect(await preparation.value == .prepared)
                #expect(service.joystickInputRevision(executionID: fixed.id, lease: fixed.lease) == nil)
                #expect(service.joystickInputRevision(executionID: next.id, lease: next.lease) != nil)
                #expect(service.releaseJoystick(executionID: next.id, lease: next.lease, disposition: .endGesture))

            case .route:
                let destination = try #require(GeoCoordinate(latitude: 26, longitude: 122))
                let route = try routeIntent(start: origin, end: destination)
                let preparation = Task {
                    await service.beginRoute(route, expectedAdmissionRevision: service.routeAdmissionRevision)
                }
                await waitForPending(device)
                #expect(service.joystickInputRevision(executionID: fixed.id, lease: fixed.lease) == nil)
                #expect(await device.claimNext())
                await device.finishNext(.acknowledged)
                #expect(await preparation.value == .acknowledged)
                #expect(service.routeControlRevision(executionID: route.id, lease: route.lease) != nil)
                service.endRoute(executionID: route.id, lease: route.lease)

            case .teleport:
                let destination = try #require(GeoCoordinate(latitude: 26, longitude: 122))
                let candidate = TeleportCandidate(place: place(destination))
                #expect(service.teleport(to: candidate))
                #expect(service.joystickInputRevision(executionID: fixed.id, lease: fixed.lease) == nil)
                await waitForPending(device)
                #expect(await device.claimNext())
                await device.finishNext(.acknowledged)
                await waitUntilIdle(service)
                guard case .acknowledged(let acknowledged) = service.pointState else {
                    Issue.record("replacement teleport did not acknowledge")
                    continue
                }
                #expect(acknowledged.candidate == candidate)
            }
        }
    }

    @Test func failedReplacementPreparationCannotReviveTheFixedOwnerOrOverlapNativeCalls() async throws {
        let device = PositionHoldServiceDevice()
        let service = ServiceController(service: device)
        let origin = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        service.observeRealLocation(realLocation(origin))
        let fixed = try await installFixedOwner(service: service, device: device, coordinate: origin)
        await device.queueImmediate(.notSent(.pairingRequired))
        await device.queueImmediate(.notSent(.pairingRequired))
        await device.queueImmediate(.notSent(.pairingRequired))

        let destination = try #require(GeoCoordinate(latitude: 26, longitude: 122))
        #expect(service.teleport(to: TeleportCandidate(place: place(destination))))
        await waitUntilIdle(service)
        #expect(service.preparedOperation?.state == .failed(.pairingRequired))
        #expect(service.joystickInputRevision(executionID: fixed.id, lease: fixed.lease) == nil)
        #expect(await device.maxConcurrent <= 1)
        #expect(await device.pendingCount == 0)
        let coordinates = await device.coordinates
        #expect(coordinates.dropFirst().allSatisfy { $0 == destination })
    }

    @Test func staleTeleportAcknowledgementIsRejectedAfterSceneEpochLossAndRecovery() async throws {
        let device = PositionHoldServiceDevice()
        let service = ServiceController(service: device)
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        var acknowledgement: TeleportAcknowledgement?
        let subscription = service.teleportAcknowledgements.sink { acknowledgement = $0 }
        defer { subscription.cancel() }
        #expect(service.teleport(to: TeleportCandidate(place: place(coordinate))))
        await waitForPending(device)
        #expect(await device.claimNext())
        await device.finishNext(.acknowledged)
        await waitUntilIdle(service)
        let captured = try #require(acknowledgement)

        service.setMovementSceneActive(false)
        service.setMovementSceneActive(true)
        let intent = JoystickMovementIntent(lease: captured.lease, fixedPosition: captured.coordinate)
        #expect(await service.beginPositionHold(after: captured, intent: intent) == .cancelled)
    }

    @Test func staleTeleportAcknowledgementIsRejectedAfterNewExplicitPointOperation() async throws {
        let device = PositionHoldServiceDevice()
        let service = ServiceController(service: device)
        let first = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let second = try #require(GeoCoordinate(latitude: 26, longitude: 122))
        var acknowledgements: [TeleportAcknowledgement] = []
        let subscription = service.teleportAcknowledgements.sink { acknowledgements.append($0) }
        defer { subscription.cancel() }

        #expect(service.teleport(to: TeleportCandidate(place: place(first))))
        await waitForPending(device)
        #expect(await device.claimNext())
        await device.finishNext(.acknowledged)
        await waitUntilIdle(service)
        await wait { acknowledgements.count == 1 }
        let captured = acknowledgements[0]

        #expect(service.teleport(to: TeleportCandidate(place: place(second))))
        await waitForPending(device)
        #expect(await device.claimNext())
        await device.finishNext(.acknowledged)
        await waitUntilIdle(service)
        await wait { acknowledgements.count == 2 }
        let staleIntent = JoystickMovementIntent(lease: captured.lease, fixedPosition: captured.coordinate)
        #expect(await service.beginPositionHold(after: captured, intent: staleIntent) == .cancelled)
    }

    @Test func stopDuringHeldNativeCallSerializesClearAndEventuallyAcceptsNewOperation() async throws {
        let device = PositionHoldServiceDevice()
        let service = ServiceController(service: device)
        let origin = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        service.observeRealLocation(realLocation(origin))
        let fixed = try await installFixedOwner(service: service, device: device, coordinate: origin)
        let input = try #require(service.joystickInputRevision(executionID: fixed.id, lease: fixed.lease))
        let held = Task {
            await service.sendJoystickStep(executionID: fixed.id, lease: fixed.lease, sequence: 2,
                expectedInputRevision: input, recipe: .fixedPosition(origin))
        }
        await waitForPending(device)
        #expect(await device.claimNext())
        #expect(service.stop())
        let rejectedWhileBusy = service.teleport(to: TeleportCandidate(place: place(origin)))
        #expect(!rejectedWhileBusy)
        #expect(service.nativeBusy)
        await device.finishNext(.acknowledged)
        _ = await held.value
        await waitUntilIdle(service)
        #expect(await device.maxConcurrent <= 1)

        #expect(service.teleport(to: TeleportCandidate(place: place(origin))))
        await waitForPending(device)
        #expect(await device.claimNext())
        await device.finishNext(.acknowledged)
        await waitUntilIdle(service)
        #expect(await device.maxConcurrent <= 1)
    }

    private enum HandoffMode: String, CaseIterable {
        case manual
        case route
        case teleport
    }

    private func installFixedOwner(service: ServiceController,
                                   device: PositionHoldServiceDevice,
                                   coordinate: GeoCoordinate) async throws -> JoystickMovementIntent {
        let intent = JoystickMovementIntent(lease: MovementTaskLease(), fixedPosition: coordinate)
        #expect(await service.beginJoystick(intent, expectedMovementAdmissionRevision: service.movementAdmissionRevision) == .prepared)
        let input = try #require(service.joystickInputRevision(executionID: intent.id, lease: intent.lease))
        let first = Task {
            await service.sendJoystickStep(executionID: intent.id, lease: intent.lease, sequence: 1,
                expectedInputRevision: input, recipe: .fixedPosition(coordinate))
        }
        await waitForPending(device)
        #expect(await device.claimNext())
        await device.finishNext(.acknowledged)
        guard case .acknowledged = await first.value else {
            Issue.record("fixed owner did not receive an acknowledgement")
            return intent
        }
        await wait { service.movementAuthority.snapshot.lease == intent.lease }
        return intent
    }

    private func realLocation(_ coordinate: GeoCoordinate) -> RealLocationObservation {
        RealLocationObservation(latitude: coordinate.latitude, longitude: coordinate.longitude,
            horizontalAccuracy: 1, observedAt: Date())!
    }

    private func place(_ coordinate: GeoCoordinate) -> MapPlace {
        MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
    }

    private func routeIntent(start: GeoCoordinate, end: GeoCoordinate) throws -> RouteExecutionIntent {
        let draft = RouteDraft(start: .place(place(start)), destination: .place(place(end)))!
        return RouteExecutionIntent(draft: draft, route: try PlannedRoute(points: [start, end], from: start, to: end))
    }

    private func waitForPending(_ device: PositionHoldServiceDevice) async {
        await wait { await device.pendingCount > 0 }
    }

    private func waitUntilIdle(_ service: ServiceController) async {
        await wait { !service.nativeBusy }
    }

    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

private actor PositionHoldServiceDevice: DeviceService {
    private struct Pending {
        let coordinate: GeoCoordinate
        let dispatch: PointDispatchGate
        let continuation: CheckedContinuation<PointDeliveryOutcome, Never>
    }

    private var pending: [Pending] = []
    private var immediate: [PointDeliveryOutcome] = []
    private var activeCalls = 0
    private(set) var maxConcurrent = 0
    private(set) var coordinates: [GeoCoordinate] = []

    var pendingCount: Int { pending.count }

    func prepare() async throws {}

    func clearLocation() async throws {
        activeCalls += 1
        maxConcurrent = max(maxConcurrent, activeCalls)
        activeCalls -= 1
    }

    func resetClientConnection() async throws {}

    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        activeCalls += 1
        maxConcurrent = max(maxConcurrent, activeCalls)
        coordinates.append(coordinate)
        if !immediate.isEmpty {
            let result = immediate.removeFirst()
            activeCalls -= 1
            return result
        }
        let result = await withCheckedContinuation { continuation in
            pending.append(Pending(coordinate: coordinate, dispatch: dispatch, continuation: continuation))
        }
        activeCalls -= 1
        return result
    }

    func queueImmediate(_ outcome: PointDeliveryOutcome) {
        immediate.append(outcome)
    }

    func claimNext() -> Bool {
        pending.first?.dispatch.claim() ?? false
    }

    func finishNext(_ outcome: PointDeliveryOutcome) {
        guard !pending.isEmpty else { return }
        let next = pending.removeFirst()
        next.continuation.resume(returning: outcome)
    }
}
