import Combine
import Foundation
import Testing
import GoFlyCore

@Suite @MainActor
struct MovementContinuationSubmissionTests {
    @Test func oneHeldPhysicalSubmissionKeepsNewestSameLeaseDemandAndRejectsLateOldLoss() async throws {
        let service = ServiceController(service: SubmissionAcknowledgingDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }

        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let clock = ContinuationTestClock()
        let route = RouteExecutionController(draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: clock)
        let driver = SubmissionHoldingDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: "Moving", subtitle: "(progress.acknowledgedWrites)")
            }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && driver.submitCalls == 1 }
        let firstRequest = try #require(driver.requests.first)
        let lease = try #require(route.intent?.lease)
        #expect(firstRequest.lease == lease)
        #expect(firstRequest.kind == .finiteRoute)

        #expect(route.setRoundTripEnabled(true))
        #expect(route.setRoundTripEnabled(false))
        #expect(driver.submitCalls == 1)

        #expect(route.pause())
        await waitForContinuation { route.phase == .paused }
        #expect(route.resume())
        await waitForContinuation { route.phase == .running }
        #expect(driver.submitCalls == 1)

        guard let lateGrant = driver.launch(requestID: firstRequest.requestID) else {
            Issue.record("expected the held old submit to retain its callback")
            return
        }
        #expect(!lateGrant.isValid)
        driver.emitInvalidated(requestID: firstRequest.requestID)
        driver.finish(requestID: firstRequest.requestID)
        await waitForContinuation { driver.submitCalls == 2 }

        #expect(route.phase == .running)
        #expect(driver.requests.count == 2)
        #expect(driver.requests[1].requestID != firstRequest.requestID)
        #expect(driver.requests[1].lease == lease)
        #expect(driver.requests[1].kind == .finiteRoute)
    }

    @Test func inactiveAndStopDrainNewestPendingDemandWithoutAutomaticResubmission() async throws {
        let service = ServiceController(service: SubmissionAcknowledgingDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }

        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let clock = ContinuationTestClock()
        let route = RouteExecutionController(draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: clock)
        let driver = SubmissionHoldingDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, _ in
                (title: "Moving", subtitle: "Waiting")
            }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && driver.submitCalls == 1 }
        let oldRequest = try #require(driver.requests.first)

        #expect(route.cancel())
        await waitForContinuation { route.phase == .editing }
        #expect(driver.cancelCalls.contains(oldRequest.requestID))

        #expect(route.start())
        await waitForContinuation { route.phase == .running }
        #expect(driver.submitCalls == 1)
        let replacementLease = try #require(route.intent?.lease)
        #expect(replacementLease != oldRequest.lease)

        controller.releaseForInactiveScene()
        await waitForContinuation { route.phase == .paused }
        #expect(driver.submitCalls == 1)
        driver.finish(requestID: oldRequest.requestID)
        await waitForContinuation { driver.cancelCalls.contains(oldRequest.requestID) }
        #expect(driver.submitCalls == 1)

        controller.sceneDidBecomeActive()
        for _ in 0..<20 { await Task.yield() }
        #expect(route.phase == .paused)
        #expect(driver.submitCalls == 1)

        #expect(route.resume())
        await waitForContinuation { route.phase == .running && driver.submitCalls == 2 }
        let pendingReplacement = try #require(driver.requests.last)
        #expect(pendingReplacement.lease == replacementLease)
        #expect(pendingReplacement.requestID != oldRequest.requestID)

        #expect(service.stop())
        #expect(driver.cancelCalls.contains(pendingReplacement.requestID))
        driver.finish(requestID: pendingReplacement.requestID)
        await waitForContinuation { route.phase == .editing }
        #expect(driver.submitCalls == 2)
    }

    @Test func actualWanderOwnerAckPrecedesRuntimeSubmissionAndProgressUsesThatAck() async throws {
        let service = ServiceController(service: SubmissionAcknowledgingDevice())
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: Date()))
        let clock = ContinuationTestClock()
        let route = RouteExecutionController(planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock,
            wanderBearingSamples: { [90] })
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: clock)
        let driver = SubmissionHoldingDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: "Wandering", subtitle: "(progress.acknowledgedWrites)")
            }

        controller.sceneDidBecomeActive()
        let gestureID = UUID()
        let input = try #require(JoystickInput(bearingDegrees: 90, strength: 1))
        #expect(joystick.beginGesture(id: gestureID, input: input))
        await waitForContinuation { joystick.phase == .moving }
        #expect(joystick.setWanderEnabled(true))
        #expect(driver.submitCalls == 0)

        await waitForContinuation { clock.hasSleeper(for: .milliseconds(500)) }
        clock.advance(by: .milliseconds(500))
        await waitForContinuation { driver.submitCalls == 1 }
        let request = try #require(driver.requests.first)
        #expect(request.kind == .wander)
        #expect(controller.state == .submitting)

        guard let grant = driver.launch(requestID: request.requestID) else {
            Issue.record("expected the actual wander submission callback")
            return
        }
        let movementID = try #require(joystick.intent?.id)
        #expect(grant.movementID == movementID)
        await waitForContinuation { controller.hasRuntime }
        #expect(driver.updates.last?.progress.acknowledgedWrites == 1)
        #expect(driver.updates.last?.progress.cumulativeAcknowledgedDistanceMeters ?? 0 > 0)
    }
}

private struct SubmissionAcknowledgingDevice: DeviceService {
    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        return .acknowledged
    }
}


@MainActor
private final class SubmissionHoldingDriver: ContinuedProcessingDriving {
    private struct Pending {
        let request: ContinuedProcessingRequest
        let onEvent: @MainActor @Sendable (ContinuedProcessingEvent) -> Void
        let continuation: CheckedContinuation<Void, Error>
    }

    var submitCalls = 0
    var requests: [ContinuedProcessingRequest] = []
    var updates: [(requestID: UUID, progress: ContinuedProcessingProgress)] = []
    private var pending: [UUID: Pending] = [:]
    private var callbacks: [UUID: @MainActor @Sendable (ContinuedProcessingEvent) -> Void] = [:]
    private(set) var cancelCalls: [UUID] = []

    func register() -> Bool { true }

    func submit(
        _ request: ContinuedProcessingRequest,
        onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void
    ) async throws {
        submitCalls += 1
        requests.append(request)
        callbacks[request.requestID] = onEvent
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                pending[request.requestID] = Pending(request: request, onEvent: onEvent, continuation: continuation)
            }
        }, onCancel: {})
    }

    func launch(requestID: UUID) -> ContinuedProcessingGrant? {
        guard let pendingRequest = pending[requestID] else { return nil }
        let grant = ContinuedProcessingGrant(requestID: requestID, movementID: pendingRequest.request.movementID,
            lease: pendingRequest.request.lease)
        pendingRequest.onEvent(.launched(grant))
        return grant
    }

    func emitInvalidated(requestID: UUID) {
        callbacks[requestID]?(.invalidated(requestID: requestID))
    }

    func finish(requestID: UUID) {
        guard let pendingRequest = pending.removeValue(forKey: requestID) else { return }
        pendingRequest.continuation.resume()
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {
        updates.append((requestID: requestID, progress: progress))
    }
    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? { nil }
    func cancel(requestID: UUID) { cancelCalls.append(requestID) }
}
