import Foundation
import Testing
@testable import GoFlyCore

@Suite
struct DeviceSessionKeeperTests {
    private let coordinate = GeoCoordinate(latitude: 25.033, longitude: 121.565)!

    @Test
    func acknowledgedWriteKeepsTheSession() {
        let link = ScriptedLink([.ack])
        let keeper = DeviceSessionKeeper()

        #expect(keeper.deliver(coordinate, dispatch: PointDispatchGate(), using: link) == .acknowledged)
        #expect(link.ownsSession)
        #expect(link.closes == 0)
    }

    @Test
    func transientFailureBeforeDispatchRebuildsAndRetriesOnce() {
        let link = ScriptedLink([.notSent(.serviceUnavailable, dispatched: false), .ack], owned: true)
        let keeper = DeviceSessionKeeper()

        #expect(keeper.deliver(coordinate, dispatch: PointDispatchGate(), using: link) == .acknowledged)
        #expect(link.attempts.map(\.recovering) == [false, false])
        #expect(link.closes == 1)
    }

    @Test
    func secondTransientFailureBeforeDispatchIsReturnedWithoutAThirdAttempt() {
        let link = ScriptedLink([.notSent(.tunnelUnavailable, dispatched: false),
                                 .notSent(.tunnelUnavailable, dispatched: false)], owned: true)
        let keeper = DeviceSessionKeeper()

        #expect(keeper.deliver(coordinate, dispatch: PointDispatchGate(), using: link) == .notSent(.tunnelUnavailable))
        #expect(link.attempts.count == 2)
        #expect(!link.ownsSession)
    }

    @Test
    func identityFailureIsNeverRetried() {
        let link = ScriptedLink([.notSent(.identityMismatch, dispatched: true)], owned: true)
        let keeper = DeviceSessionKeeper()

        #expect(keeper.deliver(coordinate, dispatch: PointDispatchGate(), using: link) == .notSent(.identityMismatch))
        #expect(link.attempts.count == 1)
        #expect(link.ownsSession, "a non-transient failure keeps an owned session")
    }

    @Test
    func failureOnASessionThisAttemptOpenedClosesIt() {
        let link = ScriptedLink([.notSent(.devicePreparationRequired, dispatched: false)])
        let keeper = DeviceSessionKeeper()

        _ = keeper.deliver(coordinate, dispatch: PointDispatchGate(), using: link)
        #expect(!link.ownsSession)
    }

    @Test
    func unconfirmedWriteRecoversTheSamePointOnce() {
        let authority = MovementTaskAuthority()
        let lease = MovementTaskLease()
        let gate = PointDispatchGate(authority: authority, lease: lease, replacing: authority.snapshot)
        let link = ScriptedLink([.unconfirmed(.operationTimedOut), .ack], owned: true)
        let keeper = DeviceSessionKeeper()

        #expect(keeper.deliver(coordinate, dispatch: gate, using: link) == .acknowledged)
        #expect(link.attempts.map(\.recovering) == [false, true])
        #expect(link.attempts.allSatisfy { $0.coordinate == coordinate })
    }

    @Test
    func failedRecoveryKeepsTheOriginalUncertainty() {
        let authority = MovementTaskAuthority()
        let lease = MovementTaskLease()
        let gate = PointDispatchGate(authority: authority, lease: lease, replacing: authority.snapshot)
        let link = ScriptedLink([.unconfirmed(.operationTimedOut), .unconfirmed(.serviceUnavailable)], owned: true)
        let keeper = DeviceSessionKeeper()

        #expect(keeper.deliver(coordinate, dispatch: gate, using: link) == .unconfirmed(.operationTimedOut))
        #expect(link.attempts.count == 2)
    }

    @Test
    func recoveryWithoutAuthorityPermissionIsNotAttempted() {
        let link = ScriptedLink([.unconfirmed(.operationTimedOut)], owned: true)
        let keeper = DeviceSessionKeeper()

        // A plain gate has no lease, so recovery is never permitted.
        #expect(keeper.deliver(coordinate, dispatch: PointDispatchGate(), using: link) == .unconfirmed(.operationTimedOut))
        #expect(link.attempts.count == 1)
    }

    @Test
    func idleSessionIsClosedBeforeTheNextWrite() {
        let clock = Clock()
        let link = ScriptedLink([.ack, .ack, .ack])
        let keeper = DeviceSessionKeeper(maximumIdleNanoseconds: 100, now: clock.read)

        _ = keeper.deliver(coordinate, dispatch: PointDispatchGate(), using: link)
        clock.value += 99
        _ = keeper.deliver(coordinate, dispatch: PointDispatchGate(), using: link)
        #expect(link.closes == 0)
        clock.value += 100
        _ = keeper.deliver(coordinate, dispatch: PointDispatchGate(), using: link)
        #expect(link.closes == 1)
    }

    @Test
    func invalidatedGateIsNotAttempted() {
        let link = ScriptedLink([.ack])
        let keeper = DeviceSessionKeeper()
        let gate = PointDispatchGate()
        gate.invalidate()

        #expect(keeper.deliver(coordinate, dispatch: gate, using: link) == .notSent(.operationCancelled))
        #expect(link.attempts.isEmpty)
    }

    @Test
    func preparationFailureRebuildsOnlyAfterTransientFailure() {
        let keeper = DeviceSessionKeeper()
        let transient = ScriptedLink([], owned: true)
        transient.prepareFailure = .serviceUnavailable
        #expect(throws: DeviceServiceFailure.serviceUnavailable) { try keeper.prepare(using: transient) }
        #expect(!transient.ownsSession)

        let permanent = ScriptedLink([], owned: true)
        permanent.prepareFailure = .devicePreparationRequired
        #expect(throws: DeviceServiceFailure.devicePreparationRequired) { try keeper.prepare(using: permanent) }
        #expect(permanent.ownsSession)
    }
}

private final class Clock: @unchecked Sendable {
    var value: UInt64 = 1_000
    func read() -> UInt64 { value }
}

private final class ScriptedLink: DeviceSessionLink {
    enum Step {
        case ack
        case notSent(DeviceServiceFailure, dispatched: Bool)
        case unconfirmed(DeviceServiceFailure)
    }

    struct Attempt {
        let coordinate: GeoCoordinate
        let recovering: Bool
    }

    private var steps: [Step]
    private(set) var attempts: [Attempt] = []
    private(set) var closes = 0
    private(set) var ownsSession: Bool
    var prepareFailure: DeviceServiceFailure?

    init(_ steps: [Step], owned: Bool = false) {
        self.steps = steps
        self.ownsSession = owned
    }

    func prepareSession() throws {
        ownsSession = true
        if let prepareFailure { throw prepareFailure }
    }

    func attemptPoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate,
                      recovering: Bool, deadline: UInt64) -> DeviceSessionAttempt {
        attempts.append(Attempt(coordinate: coordinate, recovering: recovering))
        ownsSession = true
        switch steps.removeFirst() {
        case .ack:
            _ = recovering ? dispatch.claimRecovery() : dispatch.claim()
            return DeviceSessionAttempt(outcome: .acknowledged, reachedDispatch: true)
        case .notSent(let failure, let dispatched):
            return DeviceSessionAttempt(outcome: .notSent(failure), reachedDispatch: dispatched)
        case .unconfirmed(let failure):
            if !recovering { _ = dispatch.claim() } else { _ = dispatch.claimRecovery() }
            return DeviceSessionAttempt(outcome: .unconfirmed(failure), reachedDispatch: true)
        }
    }

    func closeSession() {
        if ownsSession { closes += 1 }
        ownsSession = false
    }
}
