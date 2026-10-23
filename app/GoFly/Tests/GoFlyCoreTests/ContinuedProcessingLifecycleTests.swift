import Foundation
import Testing
@testable import GoFlyCore

@MainActor
struct ContinuedProcessingLifecycleTests {
    @Test func singleRouteCompletesBackgroundTaskAtDestinationAcknowledgement() async {
        let driver = TestContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        let request = makeRequest(kind: .finiteRoute, goal: .finiteDistance(meters: 40))

        #expect(controller.register())
        #expect(await controller.begin(request, isForeground: true))
        driver.launch(request)
        #expect(controller.hasRuntime)
        #expect(controller.update(requestID: request.requestID,
            progress: ContinuedProcessingProgress(acknowledgedWrites: 4,
                cumulativeAcknowledgedDistanceMeters: 40)!,
            title: request.title, subtitle: request.subtitle))

        #expect(controller.finishFiniteArrival(requestID: request.requestID))
        #expect(controller.state == .finished)
        #expect(controller.completionOutcome == .success)
        #expect(driver.finishCalls == 1)
        #expect(driver.lastFinishSuccess == true)
    }

    @Test func roundTripDoesNotCompleteBackgroundTaskAtRouteEndpoint() async {
        let driver = TestContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        let request = makeRequest(kind: .roundTrip, goal: .experimentalIndeterminate)

        #expect(controller.register())
        #expect(await controller.begin(request, isForeground: true))
        driver.launch(request)
        #expect(controller.hasRuntime)
        #expect(controller.update(requestID: request.requestID,
            progress: ContinuedProcessingProgress(acknowledgedWrites: 4,
                cumulativeAcknowledgedDistanceMeters: 40)!,
            title: request.title, subtitle: request.subtitle))

        #expect(!controller.finishFiniteArrival(requestID: request.requestID))
        #expect(controller.state == .running)
        #expect(controller.hasRuntime)
        #expect(driver.finishCalls == 0)
    }

    private func makeRequest(kind: ContinuedProcessingKind,
                             goal: ContinuedProcessingGoal) -> ContinuedProcessingRequest {
        ContinuedProcessingRequest(movementID: UUID(), lease: MovementTaskLease(),
            kind: kind, goal: goal, title: "Route", subtitle: "Continuing")!
    }
}

@MainActor
private final class TestContinuedProcessingDriver: ContinuedProcessingDriving {
    private var eventHandler: (@MainActor @Sendable (ContinuedProcessingEvent) -> Void)?
    private(set) var finishCalls = 0
    private(set) var lastFinishSuccess: Bool?

    func register() -> Bool { true }

    func submit(_ request: ContinuedProcessingRequest,
                onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void) async throws {
        eventHandler = onEvent
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {}

    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? {
        finishCalls += 1
        lastFinishSuccess = success
        return success ? .success : .failed
    }

    func cancel(requestID: UUID) {}

    func launch(_ request: ContinuedProcessingRequest) {
        eventHandler?(.launched(ContinuedProcessingGrant(
            requestID: request.requestID, movementID: request.movementID, lease: request.lease)))
    }
}
