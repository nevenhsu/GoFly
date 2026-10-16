import XCTest
@testable import LocalGoCore

@MainActor
final class LocationCommandCoordinatorTests: XCTestCase {
    func testInvalidCoordinatesNeverReachEngine() {
        let engine = TestLocationEngine()
        let coordinator = LocationCommandCoordinator(engine: engine)

        coordinator.apply(latitude: .infinity, longitude: 0)

        XCTAssertEqual(engine.setCalls, [])
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.error?.code, 2001)
        XCTAssertEqual(coordinator.error?.stage, .validation)

        coordinator.apply(latitude: 0, longitude: -181)

        XCTAssertEqual(engine.setCalls, [])
        XCTAssertEqual(coordinator.error?.code, 2002)
    }

    func testInvalidCoordinatePreservesAcceptedCoordinateAndCorrectedApplyCanSucceed() {
        let engine = TestLocationEngine()
        let coordinator = LocationCommandCoordinator(engine: engine)
        let accepted = LocationCoordinate(latitude: 1, longitude: 2)
        let corrected = LocationCoordinate(latitude: 3, longitude: 4)

        coordinator.apply(latitude: accepted.latitude, longitude: accepted.longitude)
        XCTAssertTrue(engine.waitForSetStart())
        waitUntil { coordinator.phase == .accepted }

        coordinator.apply(latitude: 91, longitude: accepted.longitude)
        XCTAssertEqual(coordinator.phase, .accepted)
        XCTAssertEqual(coordinator.latestAcceptedCoordinate, accepted)
        XCTAssertEqual(coordinator.error?.stage, .validation)
        XCTAssertEqual(engine.setCalls, [accepted])

        coordinator.apply(latitude: corrected.latitude, longitude: corrected.longitude)
        XCTAssertTrue(engine.waitForSetStart())
        waitUntil { coordinator.phase == .accepted && coordinator.latestAcceptedCoordinate == corrected }
        XCTAssertEqual(coordinator.latestAcceptedCoordinate, corrected)
        XCTAssertNil(coordinator.error)
    }

    func testApplyTransitionsToAcceptedWithCoordinate() {
        let engine = TestLocationEngine()
        let coordinator = LocationCommandCoordinator(engine: engine)
        let expected = LocationCoordinate(latitude: 25.0330, longitude: 121.5654)

        coordinator.apply(latitude: expected.latitude, longitude: expected.longitude)

        XCTAssertTrue(engine.waitForSetStart())
        waitUntil { coordinator.phase == .accepted }
        XCTAssertEqual(coordinator.latestAcceptedCoordinate, expected)
        XCTAssertNil(coordinator.error)
    }

    func testApplyPublishesPreparingThenApplyingBeforeAcceptance() {
        let engine = TestLocationEngine()
        engine.blockNextSet()
        let coordinator = LocationCommandCoordinator(engine: engine)

        coordinator.apply(latitude: 25, longitude: 121)
        XCTAssertEqual(coordinator.phase, .preparing)
        XCTAssertTrue(engine.waitForSetStart())
        waitUntil { coordinator.phase == .applying }

        engine.releaseSet()
        waitUntil { coordinator.phase == .accepted }
    }

    func testOlderSetAcknowledgementCannotOverrideNewerApply() {
        let engine = TestLocationEngine()
        engine.blockNextSet()
        let coordinator = LocationCommandCoordinator(engine: engine)

        coordinator.apply(latitude: 1, longitude: 2)
        XCTAssertTrue(engine.waitForSetStart())
        coordinator.apply(latitude: 3, longitude: 4)

        engine.releaseSet()
        waitUntil { coordinator.phase == .accepted && coordinator.latestAcceptedCoordinate == LocationCoordinate(latitude: 3, longitude: 4) }
        XCTAssertEqual(coordinator.latestAcceptedCoordinate, LocationCoordinate(latitude: 3, longitude: 4))
    }

    func testStopInvalidatesLateSetAcknowledgementAndClearsNext() {
        let engine = TestLocationEngine()
        engine.blockNextSet()
        let coordinator = LocationCommandCoordinator(engine: engine)

        coordinator.apply(latitude: 1, longitude: 2)
        XCTAssertTrue(engine.waitForSetStart())

        coordinator.stop()
        XCTAssertEqual(coordinator.phase, .clearing)
        XCTAssertNil(coordinator.latestAcceptedCoordinate)

        engine.releaseSet()
        XCTAssertTrue(engine.waitForClearStart())
        XCTAssertEqual(coordinator.phase, .clearing)
        XCTAssertNil(coordinator.latestAcceptedCoordinate)

        engine.releaseClear()
        waitUntil { coordinator.phase == .idle }
        XCTAssertNil(coordinator.latestAcceptedCoordinate)
        XCTAssertEqual(engine.setCalls, [LocationCoordinate(latitude: 1, longitude: 2)])
        XCTAssertEqual(engine.clearCallCount, 1)
    }

    func testStopDropsQueuedSetsBeforeTheyStart() {
        let engine = TestLocationEngine()
        engine.blockNextSet()
        let coordinator = LocationCommandCoordinator(engine: engine)

        coordinator.apply(latitude: 1, longitude: 2)
        XCTAssertTrue(engine.waitForSetStart())
        coordinator.apply(latitude: 3, longitude: 4)
        coordinator.stop()

        engine.releaseSet()
        XCTAssertTrue(engine.waitForClearStart())
        engine.releaseClear()
        waitUntil { coordinator.phase == .idle }

        XCTAssertEqual(engine.setCalls, [LocationCoordinate(latitude: 1, longitude: 2)])
        XCTAssertEqual(engine.clearCallCount, 1)
    }

    func testFailedClearLeavesUnknownFailureAndRejectsNewApply() {
        let engine = TestLocationEngine()
        engine.failClear = true
        let coordinator = LocationCommandCoordinator(engine: engine)

        coordinator.apply(latitude: 1, longitude: 2)
        XCTAssertTrue(engine.waitForSetStart())
        waitUntil { coordinator.phase == .accepted }

        coordinator.stop()
        XCTAssertTrue(engine.waitForClearStart())
        engine.releaseClear()
        waitUntil { coordinator.phase == .unknownFailure }

        XCTAssertEqual(coordinator.error?.code, 5001)
        XCTAssertEqual(coordinator.error?.stage, .clearing)
        let setCount = engine.setCalls.count
        coordinator.apply(latitude: 3, longitude: 4)
        XCTAssertEqual(engine.setCalls.count, setCount)
        XCTAssertEqual(coordinator.phase, .unknownFailure)
    }

    func testSuccessfulClearStartsAFreshSessionAndRepeatedStopDoesNotDuplicateClear() {
        let engine = TestLocationEngine()
        let coordinator = LocationCommandCoordinator(engine: engine)

        coordinator.apply(latitude: 1, longitude: 2)
        XCTAssertTrue(engine.waitForSetStart())
        waitUntil { coordinator.phase == .accepted }
        coordinator.stop()
        XCTAssertTrue(engine.waitForClearStart())
        engine.releaseClear()
        waitUntil { coordinator.phase == .idle }
        coordinator.stop()
        XCTAssertEqual(engine.clearCallCount, 1)

        coordinator.apply(latitude: 3, longitude: 4)
        XCTAssertTrue(engine.waitForSetStart())
        waitUntil { coordinator.phase == .accepted }
        XCTAssertEqual(coordinator.latestAcceptedCoordinate, LocationCoordinate(latitude: 3, longitude: 4))
    }

    func testFailedStopCanRetryAfterConnectionRecoversAndStartAgain() {
        let engine = TestLocationEngine()
        let coordinator = LocationCommandCoordinator(engine: engine)
        coordinator.apply(latitude: 1, longitude: 2)
        XCTAssertTrue(engine.waitForSetStart())
        waitUntil { coordinator.phase == .accepted }

        engine.failClear = true
        coordinator.stop()
        XCTAssertTrue(engine.waitForClearStart())
        engine.releaseClear()
        waitUntil { coordinator.phase == .unknownFailure }

        engine.failClear = false
        coordinator.stop()
        XCTAssertTrue(engine.waitForClearStart())
        engine.releaseClear()
        waitUntil { coordinator.phase == .idle }
        XCTAssertNil(coordinator.error)
        XCTAssertNil(coordinator.latestAcceptedCoordinate)

        coordinator.apply(latitude: 3, longitude: 4)
        XCTAssertTrue(engine.waitForSetStart())
        waitUntil { coordinator.phase == .accepted }
        XCTAssertEqual(engine.clearCallCount, 2)
        XCTAssertEqual(coordinator.latestAcceptedCoordinate, LocationCoordinate(latitude: 3, longitude: 4))
    }

    func testExplicitRecoveryClearsWithoutAnySetAndCanRepeatAfterAcknowledgement() {
        let engine = TestLocationEngine()
        let coordinator = LocationCommandCoordinator(engine: engine)

        coordinator.stop(forceClear: true)
        XCTAssertTrue(engine.waitForClearStart())
        coordinator.stop(forceClear: true)
        XCTAssertEqual(engine.clearCallCount, 1, "Recovery must share an in-flight clear")
        engine.releaseClear()
        waitUntil { coordinator.phase == .idle }

        coordinator.stop(forceClear: true)
        XCTAssertTrue(engine.waitForClearStart())
        engine.releaseClear()
        waitUntil { coordinator.phase == .idle }
        XCTAssertEqual(engine.clearCallCount, 2, "A new recovery tap must send another clear")
        XCTAssertEqual(engine.setCalls, [])
    }

    func testMissingEnginePublishesSanitizedSetupFailure() {
        let coordinator = LocationCommandCoordinator(
            engine: nil,
            setupFailureMessage: "pairing\nnot ready"
        )

        XCTAssertEqual(coordinator.phase, .unknownFailure)
        XCTAssertEqual(coordinator.error?.code, 1001)
        XCTAssertEqual(coordinator.error?.stage, .setup)
        XCTAssertEqual(coordinator.error?.message, "pairing not ready")

        coordinator.apply(latitude: 1, longitude: 2)
        XCTAssertEqual(coordinator.phase, .unknownFailure)
        XCTAssertEqual(coordinator.error?.stage, .setup)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

private final class TestLocationEngine: LocationEngine, @unchecked Sendable {
    private let lock = NSLock()
    private let setStarted = DispatchSemaphore(value: 0)
    private let clearStarted = DispatchSemaphore(value: 0)
    private let setRelease = DispatchSemaphore(value: 0)
    private let clearRelease = DispatchSemaphore(value: 0)
    private var shouldBlockSet = false
    private var shouldFailSet = false
    private var shouldFailClear = false
    private(set) var setCalls: [LocationCoordinate] = []
    private(set) var clearCallCount = 0

    var failClear: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return shouldFailClear
        }
        set {
            lock.lock()
            shouldFailClear = newValue
            lock.unlock()
        }
    }

    func blockNextSet() {
        lock.lock()
        shouldBlockSet = true
        lock.unlock()
    }

    func releaseSet() {
        setRelease.signal()
    }

    func releaseClear() {
        clearRelease.signal()
    }

    func waitForSetStart() -> Bool {
        setStarted.wait(timeout: .now() + 2) == .success
    }

    func waitForClearStart() -> Bool {
        clearStarted.wait(timeout: .now() + 2) == .success
    }

    func set(latitude: Double, longitude: Double) throws {
        let coordinate = LocationCoordinate(latitude: latitude, longitude: longitude)
        lock.lock()
        setCalls.append(coordinate)
        let block = shouldBlockSet
        shouldBlockSet = false
        let fail = shouldFailSet
        lock.unlock()

        setStarted.signal()
        if block {
            setRelease.wait()
        }
        if fail {
            throw TestEngineError.operationFailed
        }
    }

    func clear() throws {
        lock.lock()
        clearCallCount += 1
        let fail = shouldFailClear
        lock.unlock()

        clearStarted.signal()
        if fail {
            throw TestEngineError.operationFailed
        }
        clearRelease.wait()
    }
}

private enum TestEngineError: Error {
    case operationFailed
}
