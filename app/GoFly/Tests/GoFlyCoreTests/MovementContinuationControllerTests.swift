import Combine
import Foundation
import Testing
import GoFlyCore

@Suite @MainActor
struct MovementContinuationControllerTests {
    @Test func presentationRefreshPreservesActualOwnerProgressAndWrites() async throws {
        let device = ContinuationCountingDevice()
        let service = ServiceController(service: device)
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "User start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "User end", coordinate: end))
        ]))
        let route = RouteExecutionController(draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: clock)
        let driver = ContinuationRecordingDriver()
        let presentation = ContinuationPresentationTitle()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: presentation.value, subtitle: "\(progress.acknowledgedWrites)")
            }
        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && controller.hasRuntime && !driver.updates.isEmpty }
        let intent = try #require(route.intent)
        let previous = try #require(driver.updates.last)
        let request = try #require(driver.requests.first)
        let writeCount = device.writeCount
        presentation.value = "路線"

        controller.refreshPresentation()

        let refreshed = try #require(driver.updates.last)
        #expect(refreshed.title == "路線")
        #expect(refreshed.subtitle == "1")
        #expect(refreshed.requestID == request.requestID)
        #expect(refreshed.progress == previous.progress)
        #expect(route.intent?.id == intent.id)
        #expect(route.intent?.lease == intent.lease)
        #expect(route.phase == .running)
        #expect(controller.hasRuntime)
        #expect(driver.submitCalls == 1)
        #expect(device.writeCount == writeCount)
        #expect(route.draft == draft)
        #expect(route.cancel())
        await waitForContinuation { route.phase == .editing }
    }

    @Test func initializationFencesTheSceneRegistersReadinessWithoutSubmitting() async throws {
        let service = ServiceController(service: ContinuationNoopDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        service.observeRealLocation(RealLocationObservation(latitude: start.latitude, longitude: start.longitude,
            horizontalAccuracy: 5, observedAt: Date()))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(
            draft: draft, planner: ContinuationPlanner(), commands: service, search: ContinuationSearch())
        let joystick = JoystickMovementController(commands: service)
        let recovery = ConnectionRecoveryController(
            service: service, route: route, joystick: joystick, probe: ContinuationProbe())
        let driver = ContinuationRecordingDriver()

        #expect(route.canStart)
        #expect(joystick.canBeginGesture)

        let controller = MovementContinuationController(
            service: service, route: route, joystick: joystick, recovery: recovery,
            driver: driver) { _, _ in (title: "Moving", subtitle: "Waiting") }

        #expect(driver.registerCalls == 1)
        #expect(driver.submitCalls == 0)
        #expect(controller.state == .idle)
        #expect(!controller.hasRuntime)
        #expect(controller.noticeKey == nil)
        #expect(!route.canStart)
        #expect(!joystick.canBeginGesture)
    }

    @Test func foregroundRouteStartPublishesInitialAckAndOneRuntimeCandidate() async throws {
        let service = ServiceController(service: ContinuationAcknowledgingDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }

        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(
            draft: draft, planner: ContinuationPlanner(), commands: service, search: ContinuationSearch())
        let joystick = JoystickMovementController(commands: service)
        let recovery = ConnectionRecoveryController(
            service: service, route: route, joystick: joystick, probe: ContinuationProbe())
        let driver = ContinuationHoldingDriver()
        let controller = MovementContinuationController(
            service: service, route: route, joystick: joystick, recovery: recovery,
            driver: driver) { _, progress in
                (title: "Moving \(progress.acknowledgedWrites)", subtitle: "\(progress.cumulativeAcknowledgedDistanceMeters)")
            }
        var routeAcknowledgements: [MovementAcknowledgement] = []
        let acknowledgementToken = route.movementAcknowledgements.sink { routeAcknowledgements.append($0) }
        defer { acknowledgementToken.cancel() }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && driver.submitCalls == 1 }

        #expect(route.phase == .running)
        #expect(routeAcknowledgements.count == 1)
        #expect(routeAcknowledgements.first?.sequence == 0)
        #expect(routeAcknowledgements.first?.acknowledgedDistanceMeters == 0)
        #expect(routeAcknowledgements.first?.routePositionMeters == 0)
        #expect(routeAcknowledgements.first?.finiteArrival == false)
        #expect(driver.requests.count == 1)
        #expect(controller.state == .submitting)
        #expect(!controller.hasRuntime)

        driver.launch()
        await waitForContinuation { controller.hasRuntime && driver.updates.count == 1 }
        #expect(controller.state == .running)
        #expect(driver.updates.count == 1)
        #expect(driver.updates.first?.progress.acknowledgedWrites == 1)
        #expect(driver.updates.first?.progress.cumulativeAcknowledgedDistanceMeters == 0)
        #expect(Set(controller.receipts.map(\.requestID)).count == 1)

        #expect(route.cancel())
        await waitForContinuation { route.phase == .editing }
    }

    @Test func foregroundRejectionPreservesRouteAndUserPauseClearsNoticeAfterCleanup() async throws {
        let service = ServiceController(service: ContinuationAcknowledgingDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(
            draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(
            service: service, route: route, joystick: joystick, probe: ContinuationProbe(), clock: clock)
        let driver = ContinuationRejectingDriver()
        let controller = MovementContinuationController(
            service: service, route: route, joystick: joystick, recovery: recovery,
            driver: driver) { _, _ in (title: "Moving", subtitle: "Waiting") }
        var routeAcknowledgements: [MovementAcknowledgement] = []
        let acknowledgementToken = route.movementAcknowledgements.sink { routeAcknowledgements.append($0) }
        defer { acknowledgementToken.cancel() }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && driver.submitCalls == 1 }
        await waitForContinuation { controller.noticeKey == "background.rejected" }

        #expect(route.phase == .running)
        #expect(!controller.hasRuntime)
        await waitForContinuation { clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await waitForContinuation { routeAcknowledgements.count == 2 }
        #expect(route.phase == .running)
        #expect(routeAcknowledgements.count == 2)
        #expect(controller.noticeKey == "background.rejected")

        #expect(route.pause())
        await waitForContinuation { route.phase == .paused }
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.noticeKey == nil)

        #expect(route.cancel())
        await waitForContinuation { route.phase == .editing }
    }

    @Test func validGrantedRouteContinuesAcrossInactiveSceneAndAcceptsNextAck() async throws {
        let service = ServiceController(service: ContinuationAcknowledgingDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(
            draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(
            service: service, route: route, joystick: joystick, probe: ContinuationProbe(), clock: clock)
        let driver = ContinuationRecordingDriver()
        let controller = MovementContinuationController(
            service: service, route: route, joystick: joystick, recovery: recovery,
            driver: driver) { _, progress in
                (title: "Moving \(progress.acknowledgedWrites)", subtitle: "\(progress.cumulativeAcknowledgedDistanceMeters)")
            }
        var routeAcknowledgements: [MovementAcknowledgement] = []
        let acknowledgementToken = route.movementAcknowledgements.sink { routeAcknowledgements.append($0) }
        defer { acknowledgementToken.cancel() }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && controller.hasRuntime && driver.submitCalls == 1 }
        #expect(routeAcknowledgements.count == 1)
        #expect(driver.requests.count == 1)

        controller.releaseForInactiveScene()
        #expect(route.phase == .running)
        #expect(!route.canStart)
        #expect(controller.hasRuntime)

        await waitForContinuation { clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await waitForContinuation { routeAcknowledgements.count == 2 }
        #expect(route.phase == .running)
        #expect(controller.hasRuntime)
        #expect(driver.submitCalls == 1)
        #expect(routeAcknowledgements[1].sequence == 1)
        #expect(routeAcknowledgements[1].acknowledgedDistanceMeters > 0)
        #expect(driver.updates.last?.progress.acknowledgedWrites == 2)

        controller.sceneDidBecomeActive()
        #expect(route.phase == .running)
        #expect(controller.hasRuntime)
        #expect(driver.submitCalls == 1)
        #expect(route.cancel())
        await waitForContinuation { route.phase == .editing }
    }

    @Test func expiredInactiveGrantNeedsExplicitResumeAndLateOldLaunchCannotReplaceNewCandidate() async throws {
        let service = ServiceController(service: ContinuationAcknowledgingDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(
            draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(
            service: service, route: route, joystick: joystick, probe: ContinuationProbe(), clock: clock)
        let driver = ContinuationGrantDriver()
        let controller = MovementContinuationController(
            service: service, route: route, joystick: joystick, recovery: recovery,
            driver: driver) { _, _ in (title: "Moving", subtitle: "Waiting") }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && controller.hasRuntime && driver.submitCalls == 1 }
        let oldRequestID = try #require(driver.requests.first?.requestID)

        controller.releaseForInactiveScene()
        #expect(route.phase == .running)
        driver.expire(oldRequestID)
        await waitForContinuation { route.phase == .paused && controller.noticeKey == "background.expired" }
        #expect(driver.submitCalls == 1)
        #expect(!controller.hasRuntime)

        controller.sceneDidBecomeActive()
        for _ in 0..<20 { await Task.yield() }
        #expect(route.phase == .paused)
        #expect(driver.submitCalls == 1)
        #expect(controller.noticeKey == "background.expired")

        #expect(route.resume())
        await waitForContinuation { route.phase == .running && controller.hasRuntime && driver.submitCalls == 2 }
        let newRequestID = try #require(driver.requests.last?.requestID)
        #expect(newRequestID != oldRequestID)
        driver.sendLateLaunch(for: oldRequestID)
        for _ in 0..<20 { await Task.yield() }
        #expect(driver.submitCalls == 2)
        #expect(controller.hasRuntime)
        #expect(driver.requests.last?.requestID == newRequestID)

        #expect(route.cancel())
        await waitForContinuation { route.phase == .editing }
    }

    @Test func closedGrantRTGoalChangePausesWithoutSubmittingUntilExplicitResume() async throws {
        let service = ServiceController(service: ContinuationAcknowledgingDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(
            draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(
            service: service, route: route, joystick: joystick, probe: ContinuationProbe(), clock: clock)
        let driver = ContinuationGrantDriver()
        let controller = MovementContinuationController(
            service: service, route: route, joystick: joystick, recovery: recovery,
            driver: driver) { _, _ in (title: "Moving", subtitle: "Waiting") }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && controller.hasRuntime && driver.submitCalls == 1 }
        let requestID = try #require(driver.requests.first?.requestID)
        driver.closeGrantWithoutEvent(for: requestID)

        #expect(route.setRoundTripEnabled(true))
        await waitForContinuation { route.phase == .paused }
        #expect(route.roundTripEnabled)
        #expect(controller.noticeKey == "background.expired")
        #expect(driver.submitCalls == 1)
        #expect(!controller.hasRuntime)

        #expect(route.resume())
        await waitForContinuation { route.phase == .running && controller.hasRuntime && driver.submitCalls == 2 }
        #expect(driver.submitCalls == 2)
        #expect(route.cancel())
        await waitForContinuation { route.phase == .editing }
    }

    @Test func rtOffCreatesFiniteRemainingGoalFromCapturedAxisAndCountsNextAckExactly() async throws {
        let service = ServiceController(service: ContinuationAcknowledgingDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(
            draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(
            service: service, route: route, joystick: joystick, probe: ContinuationProbe(), clock: clock)
        let driver = ContinuationGrantDriver()
        let controller = MovementContinuationController(
            service: service, route: route, joystick: joystick, recovery: recovery,
            driver: driver) { _, progress in
                (title: "Moving \(progress.acknowledgedWrites)", subtitle: "\(progress.cumulativeAcknowledgedDistanceMeters)")
            }
        var routeAcknowledgements: [MovementAcknowledgement] = []
        let acknowledgementToken = route.movementAcknowledgements.sink { routeAcknowledgements.append($0) }
        defer { acknowledgementToken.cancel() }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && controller.hasRuntime && driver.submitCalls == 1 }
        let total = try #require(route.progress?.totalDistanceMeters)
        #expect(route.setRoundTripEnabled(true))
        await waitForContinuation { driver.submitCalls == 2 && controller.hasRuntime }
        #expect(driver.requests[1].kind == .roundTrip)

        await waitForContinuation { clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await waitForContinuation { routeAcknowledgements.count == 2 }
        let capturedOrigin = try #require(route.progress?.committedDistanceMeters)
        #expect(capturedOrigin > 0)

        #expect(route.setRoundTripEnabled(false))
        await waitForContinuation { driver.submitCalls == 3 && controller.hasRuntime }
        guard case .finiteDistance(let remainingGoal) = driver.requests[2].goal else {
            Issue.record("expected RT-off finite remaining goal")
            return
        }
        #expect(abs(remainingGoal - (total - capturedOrigin)) < 0.000001)

        await waitForContinuation { clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await waitForContinuation { routeAcknowledgements.count == 3 }
        let nextPosition = try #require(route.progress?.committedDistanceMeters)
        let expectedDelta = abs(nextPosition - capturedOrigin)
        #expect(expectedDelta > 0)
        let finiteRequestID = driver.requests[2].requestID
        var finiteProgress: (requestID: UUID, progress: ContinuedProcessingProgress)?
        for _ in 0..<200 {
            finiteProgress = driver.updates.last {
                $0.requestID == finiteRequestID && $0.progress.acknowledgedWrites == 1 &&
                    $0.progress.cumulativeAcknowledgedDistanceMeters > 0
            }
            if finiteProgress != nil { break }
            await Task.yield()
        }
        let finiteUpdate = try #require(finiteProgress)
        #expect(abs(finiteUpdate.progress.cumulativeAcknowledgedDistanceMeters - expectedDelta) < 0.000001)

        #expect(route.cancel())
        await waitForContinuation { route.phase == .editing }
    }

    @Test func grantedWanderContinuesAcrossInactiveSceneWithSameRuntimeRequest() async throws {
        let service = ServiceController(service: ContinuationAcknowledgingDevice())
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: Date()))
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let route = RouteExecutionController(planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock,
            wanderBearingSamples: { [90] })
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: clock)
        let driver = ContinuationGrantDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: "Wandering", subtitle: "\(progress.acknowledgedWrites)")
            }

        controller.sceneDidBecomeActive()
        let gestureID = UUID()
        let input = try #require(JoystickInput(bearingDegrees: 90, strength: 1))
        #expect(joystick.beginGesture(id: gestureID, input: input))
        await waitForContinuation { joystick.phase == .moving }
        #expect(joystick.setWanderEnabled(true))
        await waitForContinuation { clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await waitForContinuation { driver.submitCalls == 1 && controller.hasRuntime }
        let requestID = try #require(driver.requests.first?.requestID)
        #expect(driver.requests.first?.kind == .wander)
        #expect(joystick.wanderEnabled && joystick.phase == .moving)

        controller.releaseForInactiveScene()
        #expect(joystick.input == nil)
        #expect(joystick.wanderEnabled && joystick.phase == .moving)
        #expect(controller.hasRuntime)
        #expect(driver.submitCalls == 1)

        await waitForContinuation { clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await waitForContinuation { driver.updates.contains { $0.requestID == requestID && $0.progress.acknowledgedWrites == 2 } }
        #expect(controller.hasRuntime)
        #expect(driver.submitCalls == 1)
    }

    @Test func inactiveGrantedWanderReleasesManualInputAndNextAckUsesAutoTarget() async throws {
        let service = ServiceController(service: ContinuationAcknowledgingDevice())
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: Date()))
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let route = RouteExecutionController(planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock,
            wanderBearingSamples: { [90] })
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: ContinuousRouteClock())
        let driver = ContinuationGrantDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: "Wandering", subtitle: "\(progress.acknowledgedWrites)")
            }
        var acknowledgements: [MovementAcknowledgement] = []
        let acknowledgementToken = service.movementAcknowledgements.sink { acknowledgements.append($0) }
        defer { acknowledgementToken.cancel() }

        controller.sceneDidBecomeActive()
        let gestureID = UUID()
        let manualInput = try #require(JoystickInput(bearingDegrees: 270, strength: 1))
        #expect(joystick.beginGesture(id: gestureID, input: manualInput))
        await waitForContinuation { joystick.phase == .moving }
        #expect(joystick.setWanderEnabled(true))
        await waitForContinuation { clock.sleepingCount > 0 }
        clock.advance(by: .milliseconds(500))
        await waitForContinuation { driver.submitCalls == 1 && controller.hasRuntime && acknowledgements.count >= 1 }
        let requestID = try #require(driver.requests.first?.requestID)
        let beforeInactive = try #require(service.confirmedSimulatedLocation)
        #expect(beforeInactive.longitude < 121)
        #expect(joystick.input == manualInput)

        controller.releaseForInactiveScene()
        #expect(joystick.input == nil)
        #expect(joystick.wanderEnabled && joystick.phase == .moving)
        #expect(controller.hasRuntime)
        #expect(driver.submitCalls == 1)

        let acknowledgementCount = acknowledgements.count
        await waitForContinuation { clock.sleepingCount > 0 }
        clock.advance(by: .milliseconds(500))
        await waitForContinuation { acknowledgements.count > acknowledgementCount }
        let afterInactive = try #require(service.confirmedSimulatedLocation)
        #expect(afterInactive.longitude > beforeInactive.longitude)
        #expect(driver.submitCalls == 1)
        #expect(driver.updates.last?.requestID == requestID)
        #expect(driver.updates.last?.progress.acknowledgedWrites == 2)
    }

    @Test func failedRoutePreparationPreservesGrantedWanderUntilSuccessfulRouteClaim() async throws {
        let device = ContinuationHandoverDevice()
        let service = ServiceController(service: device)
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: Date()))
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let joystickClock = ContinuationTestClock()
        let routeStart = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let routeEnd = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(routeStart), title: "Start", coordinate: routeStart)),
            .place(MapPlace(id: .coordinate(routeEnd), title: "End", coordinate: routeEnd))
        ]))
        let route = RouteExecutionController(draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: joystickClock,
            wanderBearingSamples: { [90] })
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: ContinuousRouteClock())
        let driver = ContinuationGrantDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: "Moving", subtitle: "\(progress.acknowledgedWrites)")
            }
        var acknowledgements: [MovementAcknowledgement] = []
        let acknowledgementToken = service.movementAcknowledgements.sink { acknowledgements.append($0) }
        defer { acknowledgementToken.cancel() }

        controller.sceneDidBecomeActive()
        let gestureID = UUID()
        let input = try #require(JoystickInput(bearingDegrees: 270, strength: 1))
        #expect(joystick.beginGesture(id: gestureID, input: input))
        await waitForContinuation { joystick.phase == .moving }
        #expect(joystick.setWanderEnabled(true))
        await waitForContinuation { joystickClock.sleepingCount > 0 }
        joystickClock.advance(by: .milliseconds(500))
        await waitForContinuation { driver.submitCalls == 1 && controller.hasRuntime && acknowledgements.count >= 1 }
        let oldRequest = try #require(driver.requests.first)
        let oldLease = try #require(joystick.intent?.lease)
        let oldAcknowledgementCount = acknowledgements.count

        device.failNextPreparation()
        #expect(route.start())
        for _ in 0..<2_000 {
            if route.phase == .interrupted { break }
            await Task.yield()
        }
        #expect(service.preparedOperation?.state == .failed(.serviceUnavailable))
        #expect(route.phase == .preparing)
        #expect(joystick.phase == .moving && joystick.wanderEnabled)
        #expect(controller.hasRuntime)
        #expect(driver.submitCalls == 1)

        await waitForContinuation { joystickClock.sleepingCount > 0 }
        joystickClock.advance(by: .milliseconds(500))
        await waitForContinuation { acknowledgements.count > oldAcknowledgementCount }
        #expect(controller.hasRuntime)
        #expect(driver.requests.first?.requestID == oldRequest.requestID)

        #expect(route.cancel())
        await waitForContinuation { route.phase == .editing }
        #expect(controller.hasRuntime)
        #expect(joystick.phase == .moving)

        #expect(route.start())
        await waitForContinuation { route.phase == .running && driver.submitCalls == 2 && controller.hasRuntime }
        let replacement = try #require(driver.requests.last)
        #expect(replacement.kind == .finiteRoute)
        #expect(replacement.lease != oldLease)
        await waitForContinuation { joystick.phase == .neutral }
        #expect(!joystick.wanderEnabled)
        #expect(controller.hasRuntime)
    }

    @Test func largeRoundTripHistoryThenFiniteToggleFinishesAtExactAxisGoal() async throws {
        let service = ServiceController(service: ContinuationAcknowledgingDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25, longitude: 121.005))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: ContinuousRouteClock())
        let driver = ContinuationGrantDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: "Moving", subtitle: "\(progress.acknowledgedWrites)")
            }
        var acknowledgements: [MovementAcknowledgement] = []
        var sawReverse = false
        var previousPosition: Double?
        let acknowledgementToken = route.movementAcknowledgements.sink { acknowledgement in
            acknowledgements.append(acknowledgement)
            if let position = acknowledgement.routePositionMeters, let previousPosition {
                sawReverse = sawReverse || position < previousPosition
            }
            previousPosition = acknowledgement.routePositionMeters
        }
        defer { acknowledgementToken.cancel() }
        func advanceAndAwaitAcknowledgement() async -> Bool {
            for _ in 0..<2_000 {
                guard clock.sleepingCount > 0 else {
                    await Task.yield()
                    continue
                }
                let count = acknowledgements.count
                clock.advance(by: .milliseconds(500))
                for _ in 0..<2_000 {
                    if acknowledgements.count > count { return true }
                    await Task.yield()
                }
                return false
            }
            return false
        }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && controller.hasRuntime && driver.submitCalls == 1 }
        #expect(route.setRoundTripEnabled(true))
        await waitForContinuation { driver.submitCalls == 2 && controller.hasRuntime }
        #expect(driver.requests[1].kind == .roundTrip)
        let total = try #require(route.progress?.totalDistanceMeters)

        for _ in 0..<4096 {
            #expect(await advanceAndAwaitAcknowledgement())
        }
        #expect(acknowledgements.count >= 4097)
        #expect(sawReverse)
        #expect(acknowledgements.contains { $0.routePositionMeters == total })
        let roundTripDistance = acknowledgements.dropFirst().reduce(0.0) {
            $0 + $1.acknowledgedDistanceMeters
        }
        #expect(roundTripDistance > total * 4)

        let origin = try #require(route.progress?.committedDistanceMeters)
        let heading = route.heading
        #expect(route.setRoundTripEnabled(false))
        await waitForContinuation { driver.submitCalls == 3 && controller.hasRuntime }
        let finiteRequest = try #require(driver.requests.last)
        guard case .finiteDistance(let finiteGoal) = finiteRequest.goal else {
            Issue.record("expected finite RT-off goal after large round-trip history")
            return
        }
        let expectedGoal = heading == .forward ? total - origin : origin
        #expect(abs(finiteGoal - expectedGoal) < 0.000001)

        for _ in 0..<600 where route.phase != .editing {
            if route.phase == .editing { break }
            #expect(await advanceAndAwaitAcknowledgement() || route.phase == .editing)
        }
        #expect(route.phase == .editing)
        let finiteUpdate = try #require(driver.updates.last {
            $0.requestID == finiteRequest.requestID
        })
        #expect(finiteUpdate.progress.cumulativeAcknowledgedDistanceMeters == finiteGoal)
        #expect(driver.finishOutcomes[finiteRequest.requestID] == .success)
        #expect(!controller.hasRuntime)
    }

    @Test func roundTripOffAtEndpointEmitsZeroGoalAndNoNewRuntimeCandidate() async throws {
        let service = ServiceController(service: ContinuationAcknowledgingDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25, longitude: 121.00002))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: ContinuousRouteClock())
        let driver = ContinuationGrantDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: "Moving", subtitle: "\(progress.acknowledgedWrites)")
            }
        var total: Double?
        var zeroDemand = false
        var toggledOff = false
        let controlToken = route.continuationControlEvents.sink { event in
            guard case .requested(let demand) = event else { return }
            if demand.goal == nil { zeroDemand = true }
        }
        let acknowledgementToken = route.movementAcknowledgements.sink { acknowledgement in
            guard !toggledOff, let position = acknowledgement.routePositionMeters,
                  let total, position == total else { return }
            toggledOff = route.setRoundTripEnabled(false)
        }
        defer {
            controlToken.cancel()
            acknowledgementToken.cancel()
        }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && controller.hasRuntime && driver.submitCalls == 1 }
        total = try #require(route.progress?.totalDistanceMeters)
        #expect(route.setRoundTripEnabled(true))
        await waitForContinuation { driver.submitCalls == 2 && controller.hasRuntime }
        #expect(driver.requests[1].kind == .roundTrip)

        for _ in 0..<8 where route.phase != .editing {
            await waitForContinuation { clock.sleepingCount > 0 }
            clock.advance(by: .milliseconds(500))
            await Task.yield()
        }
        await waitForContinuation { route.phase == .editing }
        #expect(toggledOff)
        #expect(zeroDemand)
        #expect(driver.submitCalls == 2)
        #expect(driver.requests.count == 2)
        #expect(!controller.hasRuntime)
    }

    @Test func acceptedSubmissionWithoutLaunchPausesOnInactiveAndStaysPaused() async throws {
        let service = ServiceController(service: ContinuationAcknowledgingDevice())
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: ContinuousRouteClock())
        let driver = ContinuationAcceptedWithoutLaunchDriver()
        let controller = MovementContinuationController(service: service, route: route, joystick: joystick,
            recovery: recovery, driver: driver) { _, progress in
                (title: "Moving", subtitle: "\(progress.acknowledgedWrites)")
            }

        controller.sceneDidBecomeActive()
        #expect(route.start())
        await waitForContinuation { route.phase == .running && driver.submitCalls == 1 }
        #expect(controller.state == .accepted)
        #expect(route.phase == .running)
        #expect(!controller.hasRuntime)

        controller.releaseForInactiveScene()
        await waitForContinuation { route.phase == .paused }
        #expect(route.phase == .paused)
        #expect(!controller.hasRuntime)
        #expect(driver.submitCalls == 1)
        #expect(controller.noticeKey == "background.unavailable" || controller.noticeKey == "background.rejected")

        controller.sceneDidBecomeActive()
        for _ in 0..<20 { await Task.yield() }
        #expect(route.phase == .paused)
        #expect(driver.submitCalls == 1)
        #expect(!controller.hasRuntime)
        #expect(controller.noticeKey == "background.unavailable" || controller.noticeKey == "background.rejected")

        #expect(route.cancel())
        await waitForContinuation { route.phase == .editing }
    }

    @Test func staleCancelledRouteBeginCannotWithdrawNewRouteDemand() async throws {
        let device = ContinuationLateRouteDevice()
        let service = ServiceController(service: device)
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: Date()))
        #expect(service.start())
        await waitForContinuation { service.phase == .ready }
        let clock = ContinuationTestClock()
        let start = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let end = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        let draft = try #require(RouteDraft(values: [
            .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
            .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))
        ]))
        let route = RouteExecutionController(draft: draft, planner: ContinuationPlanner(), commands: service,
            search: ContinuationSearch(), clock: clock)
        let joystick = JoystickMovementController(commands: service, clock: clock)
        let recovery = ConnectionRecoveryController(service: service, route: route, joystick: joystick,
            probe: ContinuationProbe(), clock: ContinuousRouteClock())
        var requested: [MovementContinuationIdentity] = []
        var withdrawn: [MovementContinuationIdentity] = []
        var oldStarted = false
        var newStartTriggered = false
        var newStartAccepted = false
        let controlToken = route.continuationControlEvents.sink { event in
            switch event {
            case .requested(let demand): requested.append(.init(movementID: demand.movementID, lease: demand.lease))
            case .withdrawn(let identity, _): withdrawn.append(identity)
            }
        }
        let availabilityToken = service.routeEvents.sink { event in
            guard oldStarted, !newStartTriggered, case .availabilityChanged = event,
                  route.phase == .editing, service.canBeginRoute, route.canStart else { return }
            newStartTriggered = true
            newStartAccepted = route.start()
        }
        defer {
            controlToken.cancel()
            availabilityToken.cancel()
        }

        #expect(route.start())
        await waitForContinuation { route.phase == .preparing && device.waitingCount == 1 && route.intent != nil }
        let oldIntent = try #require(route.intent)
        let oldIdentity = MovementContinuationIdentity(movementID: oldIntent.id, lease: oldIntent.lease)
        #expect(requested.contains(oldIdentity))
        oldStarted = true

        // The service emits a public ended event while the old preparation is
        // still awaiting its native return. The controller may prepare a new
        // route before that old begin task resumes.
        service.endRoute(executionID: oldIntent.id, lease: oldIntent.lease)
        await waitForContinuation { route.phase == .editing }
        #expect(withdrawn == [oldIdentity])

        // The next explicit start is admitted from the public service
        // availability event after the old native call settles. The old
        // begin continuation resumes immediately afterward.
        device.finishNext(.acknowledged)
        await waitForContinuation {
            route.phase == .preparing && route.intent?.id != oldIntent.id &&
                requested.count >= 2 && newStartTriggered
        }
        #expect(newStartAccepted)
        let newIntent = try #require(route.intent)
        let newIdentity = MovementContinuationIdentity(movementID: newIntent.id, lease: newIntent.lease)
        #expect(requested.contains(newIdentity))
        #expect(withdrawn == [oldIdentity])

        await waitForContinuation { device.waitingCount == 1 }
        #expect(withdrawn == [oldIdentity])
        device.finishNext(.acknowledged)
        await waitForContinuation { route.phase == .running }
        #expect(withdrawn == [oldIdentity])
        #expect(requested.contains(newIdentity))

        #expect(route.cancel())
        await waitForContinuation { route.phase == .editing }
    }

    @Test func validatedLaunchCallsTheRuntimeAvailableCallbackSynchronously() async {
        let driver = ContinuationLaunchDriver()
        var callbackGrants: [UUID] = []
        let controller = ContinuedProcessingController(
            driver: driver,
            onRuntimeAvailable: { grant in callbackGrants.append(grant.requestID) })
        #expect(controller.register())
        let movementID = UUID()
        let lease = MovementTaskLease()
        let request = ContinuedProcessingRequest(
            movementID: movementID, lease: lease, kind: .roundTrip,
            goal: .experimentalIndeterminate, title: "Moving", subtitle: "Waiting")!

        #expect(await controller.begin(request, isForeground: true))
        #expect(callbackGrants == [request.requestID])
        #expect(controller.hasRuntime)
    }
}

private struct ContinuationNoopDevice: DeviceService, Sendable {
    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        .notSent(.operationCancelled)
    }
}

private struct ContinuationAcknowledgingDevice: DeviceService, Sendable {
    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        return .acknowledged
    }
}

private final class ContinuationHandoverDevice: DeviceService, @unchecked Sendable {
    private let lock = NSLock()
    private var failedPreparationsRemaining = 0

    func failNextPreparation() {
        lock.withLock { failedPreparationsRemaining = 3 }
    }

    func prepare() async throws {}

    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        let shouldFail = lock.withLock {
            guard failedPreparationsRemaining > 0 else { return false }
            failedPreparationsRemaining -= 1
            return true
        }
        if shouldFail { return .notSent(.serviceUnavailable) }
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        return .acknowledged
    }
}

@MainActor
private final class ContinuationAcceptedWithoutLaunchDriver: ContinuedProcessingDriving {
    var registerCalls = 0
    var submitCalls = 0
    var requests: [ContinuedProcessingRequest] = []

    func register() -> Bool {
        registerCalls += 1
        return true
    }

    func submit(
        _ request: ContinuedProcessingRequest,
        onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void
    ) async throws {
        submitCalls += 1
        requests.append(request)
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {}
    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? { nil }
    func cancel(requestID: UUID) {}
}

private final class ContinuationLateRouteDevice: DeviceService, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [CheckedContinuation<PointDeliveryOutcome, Never>] = []

    var waitingCount: Int { lock.withLock { pending.count } }

    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}

    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        return await withCheckedContinuation { continuation in
            lock.withLock { pending.append(continuation) }
        }
    }

    func finishNext(_ outcome: PointDeliveryOutcome) {
        let continuation: CheckedContinuation<PointDeliveryOutcome, Never>? = lock.withLock {
            pending.isEmpty ? nil : pending.removeFirst()
        }
        continuation?.resume(returning: outcome)
    }
}


@MainActor
private final class ContinuationRecordingDriver: ContinuedProcessingDriving {
    var registerCalls = 0
    var submitCalls = 0
    var requests: [ContinuedProcessingRequest] = []
    var updates: [(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String)] = []

    func register() -> Bool {
        registerCalls += 1
        return true
    }

    func submit(
        _ request: ContinuedProcessingRequest,
        onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void
    ) async throws {
        submitCalls += 1
        requests.append(request)
        let grant = ContinuedProcessingGrant(
            requestID: request.requestID, movementID: request.movementID, lease: request.lease)
        onEvent(.launched(grant))
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {
        updates.append((requestID: requestID, progress: progress, title: title, subtitle: subtitle))
    }
    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? { nil }
    func cancel(requestID: UUID) {}
}

@MainActor
private final class ContinuationHoldingDriver: ContinuedProcessingDriving {
    private var pending: (ContinuedProcessingRequest, @MainActor @Sendable (ContinuedProcessingEvent) -> Void)?
    var registerCalls = 0
    var submitCalls = 0
    var requests: [ContinuedProcessingRequest] = []
    var updates: [(requestID: UUID, progress: ContinuedProcessingProgress)] = []

    func register() -> Bool {
        registerCalls += 1
        return true
    }

    func submit(
        _ request: ContinuedProcessingRequest,
        onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void
    ) async throws {
        submitCalls += 1
        requests.append(request)
        pending = (request, onEvent)
        while pending != nil { await Task.yield() }
    }

    func launch() {
        guard let (request, onEvent) = pending else { return }
        pending = nil
        let grant = ContinuedProcessingGrant(
            requestID: request.requestID, movementID: request.movementID, lease: request.lease)
        onEvent(.launched(grant))
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {
        updates.append((requestID: requestID, progress: progress))
    }
    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? { nil }
    func cancel(requestID: UUID) { pending = nil }
}

@MainActor
private final class ContinuationRejectingDriver: ContinuedProcessingDriving {
    var registerCalls = 0
    var submitCalls = 0

    func register() -> Bool {
        registerCalls += 1
        return true
    }

    func submit(
        _ request: ContinuedProcessingRequest,
        onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void
    ) async throws {
        submitCalls += 1
        throw ContinuedProcessingFailure.submissionRejected
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {}
    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? { nil }
    func cancel(requestID: UUID) {}
}

@MainActor
private final class ContinuationGrantDriver: ContinuedProcessingDriving {
    private var handlers: [UUID: @MainActor @Sendable (ContinuedProcessingEvent) -> Void] = [:]
    private var grants: [UUID: ContinuedProcessingGrant] = [:]
    private var completions: [UUID: ContinuedProcessingTaskCompletion] = [:]
    var registerCalls = 0
    var submitCalls = 0
    var requests: [ContinuedProcessingRequest] = []
    var updates: [(requestID: UUID, progress: ContinuedProcessingProgress)] = []
    var finishOutcomes: [UUID: ContinuedProcessingCompletionOutcome] = [:]

    func register() -> Bool {
        registerCalls += 1
        return true
    }

    func submit(
        _ request: ContinuedProcessingRequest,
        onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void
    ) async throws {
        submitCalls += 1
        requests.append(request)
        handlers[request.requestID] = onEvent
        let grant = ContinuedProcessingGrant(
            requestID: request.requestID, movementID: request.movementID, lease: request.lease)
        grants[request.requestID] = grant
        completions[request.requestID] = ContinuedProcessingTaskCompletion(grant: grant)
        onEvent(.launched(grant))
    }

    func expire(_ requestID: UUID) {
        _ = completions[requestID]?.claim(.expired)
        handlers[requestID]?(.expired(requestID: requestID))
    }

    func sendLateLaunch(for requestID: UUID) {
        guard let handler = handlers[requestID], let grant = grants[requestID] else { return }
        handler(.launched(grant))
    }

    func closeGrantWithoutEvent(for requestID: UUID) {
        grants[requestID]?.revoke()
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {
        updates.append((requestID: requestID, progress: progress))
    }
    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? {
        guard let completion = completions[requestID] else { return nil }
        let outcome = completion.claim(success ? .success : .cancelled).outcome
        finishOutcomes[requestID] = outcome
        return outcome
    }
    func cancel(requestID: UUID) {
        _ = completions[requestID]?.claim(.cancelled)
        grants[requestID]?.revoke()
    }
}


@MainActor
private final class ContinuationLaunchDriver: ContinuedProcessingDriving {
    private var grant: ContinuedProcessingGrant?
    private var completion: ContinuedProcessingTaskCompletion?

    func register() -> Bool { true }

    func submit(
        _ request: ContinuedProcessingRequest,
        onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void
    ) async throws {
        let grant = ContinuedProcessingGrant(
            requestID: request.requestID, movementID: request.movementID, lease: request.lease)
        self.grant = grant
        completion = ContinuedProcessingTaskCompletion(grant: grant)
        onEvent(.launched(grant))
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {}
    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? {
        completion?.claim(success ? .success : .cancelled).outcome
    }
    func cancel(requestID: UUID) { _ = completion?.claim(.cancelled) }
}

private final class ContinuationCountingDevice: DeviceService, @unchecked Sendable {
    private let lock = NSLock()
    private var writes = 0
    var writeCount: Int { lock.withLock { writes } }
    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        lock.withLock { writes += 1 }
        return .acknowledged
    }
}

@MainActor
private final class ContinuationPresentationTitle {
    var value = "Route"
}
