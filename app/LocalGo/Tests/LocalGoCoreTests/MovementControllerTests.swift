import Foundation
import XCTest
@testable import LocalGoCore

@MainActor
final class MovementControllerTests: XCTestCase {
    func testClearFromAnotherControlSurfaceCancelsMotionBeforeNextTick() async throws {
        let engine = MovementTestEngine()
        let commands = LocationCommandCoordinator(engine: engine)
        let movement = MovementController(commands: commands, automaticScheduling: false) { true }
        let origin = try GeoPoint(latitude: 25, longitude: 121)
        XCTAssertTrue(movement.start(try RoutePath(points: [origin,
            origin.moved(distanceMeters: 100, headingDegrees: 90)])))
        try await wait { commands.phase == .accepted }
        let token = movement.generation
        commands.stop()
        try await wait { commands.phase == .idle && engine.clears == 1 }
        movement.tick(elapsed: 0.5, token: token)
        movement.tick(elapsed: 0.5, token: movement.generation)
        XCTAssertEqual(movement.state, .idle)
        XCTAssertEqual(engine.points.count, 1)
        XCTAssertFalse(movement.resume())
    }

    func testBackgroundHoldsPoseAndStaleTicksCannotResumeOrUndoStop() async throws {
        let engine = MovementTestEngine()
        let commands = LocationCommandCoordinator(engine: engine)
        let movement = MovementController(commands: commands, automaticScheduling: false) { true }
        let origin = try GeoPoint(latitude: 25, longitude: 121)
        let path = try RoutePath(points: [origin, origin.moved(distanceMeters: 100, headingDegrees: 90)])
        XCTAssertTrue(movement.start(path))
        try await wait { commands.phase == .accepted }
        let oldToken = movement.generation
        movement.backgrounded()
        XCTAssertEqual(movement.state, .paused)
        movement.tick(elapsed: 100, token: oldToken)
        XCTAssertEqual(engine.points.count, 1)
        XCTAssertEqual(engine.clears, 0)
        XCTAssertNotNil(commands.latestAcceptedCoordinate)

        XCTAssertTrue(movement.resume())
        let resumedToken = movement.generation
        movement.tick(elapsed: 0.5, token: resumedToken)
        try await wait { engine.points.count == 2 && commands.phase == .accepted }
        XCTAssertEqual(origin.distance(to: engine.points[1]), 1, accuracy: 0.03)
        movement.stop()
        try await wait { commands.phase == .idle && engine.clears == 1 }
        movement.tick(elapsed: 10, token: resumedToken)
        XCTAssertEqual(engine.points.count, 2)
        XCTAssertNil(commands.latestAcceptedCoordinate)
    }

    func testSlowEngineAdmitsOnePointAndStopWinsOverBlockedAcknowledgement() async throws {
        let engine = MovementTestEngine(blockSet: true)
        let commands = LocationCommandCoordinator(engine: engine)
        let movement = MovementController(commands: commands, automaticScheduling: false) { true }
        let origin = try GeoPoint(latitude: 25, longitude: 121)
        let route = try RoutePath(points: [origin, origin.moved(distanceMeters: 100, headingDegrees: 90)])
        XCTAssertTrue(movement.start(route))
        try await wait { engine.points.count == 1 && commands.phase == .applying }
        let token = movement.generation
        for _ in 0..<10 { movement.tick(elapsed: 0.5, token: token) }
        XCTAssertEqual(engine.points.count, 1)
        XCTAssertEqual(movement.distanceMeters, 0)
        movement.stop()
        engine.release.signal()
        try await wait { commands.phase == .idle && engine.clears == 1 }
        XCTAssertNil(commands.latestAcceptedCoordinate)
        movement.tick(elapsed: 1, token: token)
        XCTAssertEqual(engine.points.count, 1)
    }

    func testJoystickCenterKeepsSessionAliveAndLatestDirectionWinsAfterBlockedApply() async throws {
        let engine = MovementTestEngine(blockSet: true, blockFirstSetOnly: true)
        let commands = LocationCommandCoordinator(engine: engine)
        let movement = MovementController(commands: commands, automaticScheduling: false) { true }
        let origin = try GeoPoint(latitude: 25, longitude: 121)

        XCTAssertTrue(movement.updateJoystick(origin: origin, x: 1, y: 0))
        try await wait { commands.phase == .applying }
        let token = movement.generation

        XCTAssertTrue(movement.updateJoystick(origin: origin, x: 0, y: 0))
        XCTAssertEqual(movement.state, .joystick)
        XCTAssertTrue(movement.updateJoystick(origin: origin, x: 0, y: 1))

        engine.release.signal()
        try await wait { commands.phase == .accepted }
        movement.tick(elapsed: 0.5, token: token)
        try await wait { engine.points.count == 2 && commands.phase == .accepted }
        let expected = origin.moved(distanceMeters: 1, headingDegrees: 0)
        XCTAssertEqual(engine.points[1].distance(to: expected), 0, accuracy: 0.03)

        XCTAssertTrue(movement.updateJoystick(origin: origin, x: 0, y: 0))
        let centeredToken = movement.generation
        movement.tick(elapsed: 1, token: centeredToken)
        XCTAssertEqual(engine.points.count, 2)
        XCTAssertEqual(movement.state, .joystick)

        movement.endJoystick()
        movement.tick(elapsed: 10, token: centeredToken)
        XCTAssertEqual(movement.state, .idle)
        XCTAssertEqual(engine.points.count, 2)
    }

    func testJoystickHeadingUsesClockwiseScreenAxes() async throws {
        let engine = MovementTestEngine()
        let commands = LocationCommandCoordinator(engine: engine)
        let movement = MovementController(commands: commands, automaticScheduling: false) { true }
        let origin = try GeoPoint(latitude: 25, longitude: 121)
        let directions: [(x: Double, y: Double, heading: Double)] = [
            (0, 1, 0),
            (1, 0, 90),
            (0, -1, 180),
            (-1, 0, 270),
            (1, 1, 45)
        ]

        for direction in directions {
            XCTAssertTrue(movement.updateJoystick(origin: origin, x: direction.x, y: direction.y))
            XCTAssertEqual(movement.headingDegrees, direction.heading, accuracy: 0.001)
        }

        movement.endJoystick()
        movement.stop()
        try await wait { commands.phase == .idle }
    }

    func testRouteHeadingFollowsMeaningfulSegment() async throws {
        let engine = MovementTestEngine()
        let commands = LocationCommandCoordinator(engine: engine)
        let movement = MovementController(commands: commands, automaticScheduling: false) { true }
        let origin = try GeoPoint(latitude: 25, longitude: 121)
        let destination = origin.moved(distanceMeters: 100, headingDegrees: 90)

        XCTAssertTrue(movement.start(try RoutePath(points: [origin, destination])))
        try await wait { commands.phase == .accepted }
        let token = movement.generation
        movement.tick(elapsed: 1, token: token)
        try await wait { engine.points.count == 2 && commands.phase == .accepted }

        XCTAssertEqual(movement.headingDegrees, 90, accuracy: 0.01)
        movement.stop()
        try await wait { commands.phase == .idle }
    }

    func testRepeatTravelsBackAlongRouteAndRequiresExplicitResume() async throws {
        let engine = MovementTestEngine()
        let commands = LocationCommandCoordinator(engine: engine)
        let movement = MovementController(commands: commands, automaticScheduling: false) { true }
        movement.speed = 28
        movement.repeats = true
        let origin = try GeoPoint(latitude: 0, longitude: 179.999)
        let destination = origin.moved(distanceMeters: 10, headingDegrees: 90)
        XCTAssertTrue(movement.start(try RoutePath(points: [origin, destination])))
        try await wait { commands.phase == .accepted }
        movement.tick(elapsed: 1, token: movement.generation)
        try await wait { engine.points.count == 2 && commands.phase == .accepted }
        XCTAssertEqual(engine.points.last?.distance(to: destination) ?? 100, 0, accuracy: 0.01)
        movement.tick(elapsed: 1, token: movement.generation)
        try await wait { engine.points.count == 3 && commands.phase == .accepted }
        XCTAssertEqual(engine.points.last?.distance(to: origin) ?? 100, 0, accuracy: 0.01)
        movement.backgrounded()
        let token = movement.generation
        movement.tick(elapsed: 1, token: token)
        XCTAssertEqual(engine.points.count, 3)
        movement.stop()
        try await wait { commands.phase == .idle }
    }

    func testLostReadinessCannotSendAndFailedClearStaysUnknown() async throws {
        let engine = MovementTestEngine(failClear: true)
        let commands = LocationCommandCoordinator(engine: engine)
        let readiness = TestReadiness()
        let movement = MovementController(commands: commands, automaticScheduling: false) { readiness.ready }
        let origin = try GeoPoint(latitude: 25, longitude: 121)
        XCTAssertTrue(movement.updateJoystick(origin: origin, x: 1, y: 0))
        try await wait { commands.phase == .accepted }
        readiness.ready = false
        movement.tick(elapsed: 0.5, token: movement.generation)
        XCTAssertEqual(movement.state, .failed)
        XCTAssertEqual(engine.points.count, 1)
        movement.stop()
        try await wait { commands.phase == .unknownFailure }
        XCTAssertEqual(movement.state, .failed)
        XCTAssertFalse(movement.resume())
    }

    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Device command did not reach expected test state")
        throw TestTimeout.timeout
    }
    private enum TestTimeout: Error { case timeout }
}

@MainActor
private final class TestReadiness {
    var ready = true
}

private final class MovementTestEngine: LocationEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [GeoPoint] = []
    private var clearCount = 0
    private var setCount = 0
    let release = DispatchSemaphore(value: 0)
    let blockSet: Bool
    let blockFirstSetOnly: Bool
    let failClear: Bool
    init(blockSet: Bool = false, blockFirstSetOnly: Bool = false, failClear: Bool = false) {
        self.blockSet = blockSet
        self.blockFirstSetOnly = blockFirstSetOnly
        self.failClear = failClear
    }
    var points: [GeoPoint] { lock.withLock { recorded } }
    var clears: Int { lock.withLock { clearCount } }
    func set(latitude: Double, longitude: Double) throws {
        let point = try GeoPoint(latitude: latitude, longitude: longitude)
        let shouldBlock = lock.withLock {
            recorded.append(point)
            setCount += 1
            return blockSet && (!blockFirstSetOnly || setCount == 1)
        }
        if shouldBlock { _ = release.wait(timeout: .now() + 3) }
    }
    func clear() throws {
        lock.withLock { clearCount += 1 }
        if failClear { throw ClearFailure.failed }
    }
    private enum ClearFailure: Error { case failed }
}
