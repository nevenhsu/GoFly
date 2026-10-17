import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct PreparedOperationTests {
    @Test(arguments: [1, 2, 3, 4])
    func startPublishesEachBoundedAttemptAndRetriesOnlyItsStoredSource(successAt: Int) async throws {
        let device = PreparationDevice(successAt: successAt)
        let controller = ServiceController(service: device)
        #expect(controller.start())
        let first = try #require(controller.preparedOperation)
        #expect(first.source == .start)
        var attempts: [Int] = []
        for _ in 1...min(successAt, 3) {
            await wait { await device.isWaiting }
            let snapshot = try #require(controller.preparedOperation)
            #expect(snapshot.id == first.id)
            #expect(snapshot.source == .start)
            attempts.append(snapshot.attempt.value)
            await device.finish()
        }
        await wait { !controller.nativeBusy }
        #expect(attempts == Array(1...min(successAt, 3)))
        #expect(await device.calls == min(successAt, 3))
        if successAt > 3 {
            #expect(controller.preparedOperation?.state == .failed(.pairingRequired))
            #expect(controller.phase == .stopped)
            #expect(controller.retryPreparedOperation(id: first.id))
            #expect(controller.preparedOperation?.id != first.id)
            #expect(controller.preparedOperation?.attempt.value == 1)
            await wait { await device.isWaiting }
            await device.finish()
            await wait { !controller.nativeBusy }
        } else {
            #expect(controller.phase == .ready)
            #expect(controller.preparedOperation == nil)
        }
    }

    @Test(arguments: [1, 2, 3, 4])
    func pointRetriesKeepTheOriginalIntentAndNeverSendBeforeClaim(successAt: Int) async throws {
        let device = RetryPointDevice()
        let controller = ServiceController(service: device)
        let candidate = target()
        #expect(controller.teleport(to: candidate))
        let first = try #require(controller.preparedOperation)
        guard case .point(let original) = first.source else { Issue.record("Expected point source"); return }
        #expect(original.candidate == candidate)
        for attempt in 1...min(successAt, 3) {
            await wait { await device.isPreparing }
            #expect(controller.preparedOperation?.id == first.id)
            #expect(controller.preparedOperation?.attempt.value == attempt)
            #expect(controller.preparedOperation?.source == first.source)
            #expect(await device.sent.isEmpty)
            await device.finishPreparation(failure: attempt < successAt ? .pairingRequired : nil)
        }
        if successAt <= 3 {
            await wait { await device.isReplying }
            #expect(!controller.cancelPreparation(id: first.id))
            await device.finishReply(.acknowledged)
        }
        await wait { !controller.nativeBusy }
        #expect(await device.calls == min(successAt, 3))
        if successAt <= 3 {
            #expect(await device.sent == [candidate.place.coordinate])
            #expect(controller.pointState == .acknowledged(original))
            #expect(controller.movementAuthority.snapshot.health == .confirmedHealthy)
        } else {
            #expect(controller.preparedOperation?.state == .failed(.pairingRequired))
            #expect(controller.retryPreparedOperation(id: first.id))
            #expect(controller.preparedOperation?.source == first.source)
            #expect(controller.preparedOperation?.id != first.id)
            #expect(controller.preparedOperation?.attempt.value == 1)
            await wait { await device.isPreparing }
            await device.finishPreparation()
            await wait { await device.isReplying }
            await device.finishReply(.acknowledged)
            await wait { !controller.nativeBusy }
            #expect(controller.pointState == .acknowledged(original))
            #expect(await device.sent == [candidate.place.coordinate])
        }
    }

    @Test(arguments: ["cancel", "stop", "watchdog"], [false, true])
    func endingPreparationPreventsAnyLaterAttemptAndHoldsBusyUntilActualReturn(action: String, start: Bool) async throws {
        let device = RetryPointDevice()
        let authority = MovementTaskAuthority()
        let old = MovementTaskLease()
        #expect(authority.install(old, replacing: authority.snapshot))
        #expect(authority.updateHealth(.confirmedHealthy, for: old))
        let original = authority.snapshot
        let controller = ServiceController(service: device,
            operationTimeout: action == "watchdog" ? .milliseconds(25) : .seconds(30),
            movementAuthority: authority)
        let candidate = target()
        #expect(start ? controller.start() : controller.teleport(to: candidate))
        let id = try #require(controller.preparedOperation?.id)
        await wait { await device.isPreparing }
        await device.finishPreparation(failure: .tunnelUnavailable)
        await wait {
            let calls = await device.calls
            let preparing = await device.isPreparing
            return calls == 2 && preparing
        }
        switch action {
        case "cancel":
            #expect(controller.cancelPreparation(id: id))
            #expect(controller.preparedOperation?.state == .cancelled)
            #expect(authority.snapshot == original)
        case "stop":
            #expect(controller.stop())
            #expect(authority.snapshot.lease == nil)
        default:
            await wait { controller.error == .operationTimedOut }
            #expect(authority.snapshot == original)
        }
        #expect(controller.nativeBusy)
        #expect(!controller.retryPreparedOperation(id: id))
        #expect(await device.clears == 0)
        await device.finishPreparation(failure: .pairingRequired)
        await wait { !controller.nativeBusy }
        #expect(await device.calls == 2)
        #expect(await device.sent.isEmpty)
        #expect(await device.clears == (action == "stop" ? 1 : 0))
        #expect(controller.confirmedSimulatedLocation == nil)
        if action != "stop" { #expect(authority.snapshot == original) }
        if action == "cancel" { #expect(controller.preparedOperation == nil) }
    }

    @Test(arguments: [false, true])
    func claimedFailureAndTimeoutKeepTheNewLeaseUnknownAndNeverReviveOld(lateAcknowledgement: Bool) async throws {
        let device = RetryPointDevice()
        let authority = MovementTaskAuthority()
        let old = MovementTaskLease()
        #expect(authority.install(old, replacing: authority.snapshot))
        #expect(authority.updateHealth(.confirmedHealthy, for: old))
        let controller = ServiceController(service: device,
            operationTimeout: lateAcknowledgement ? .milliseconds(25) : .seconds(30), movementAuthority: authority)
        #expect(controller.teleport(to: target()))
        let id = try #require(controller.preparedOperation?.id)
        await wait { await device.isPreparing }
        await device.finishPreparation()
        await wait { await device.isReplying }
        let new = try #require(authority.snapshot.lease)
        #expect(new != old)
        #expect(!controller.cancelPreparation(id: id))
        if lateAcknowledgement {
            await wait { controller.error == .operationTimedOut }
            #expect(controller.nativeBusy)
            await device.finishReply(.acknowledged)
        } else {
            await device.finishReply(.notSent(.serviceUnavailable))
        }
        await wait { !controller.nativeBusy }
        #expect(authority.snapshot.lease == new)
        #expect(authority.snapshot.health == .unknown)
        #expect(!PointDispatchGate(authority: authority, lease: old).claim())
        #expect(!controller.canTeleport)
        #expect(!controller.retryPreparedOperation(id: id))
        #expect(controller.preparedOperation == nil)
        #expect(await device.calls == 1)
        #expect(controller.stop())
        #expect(authority.snapshot.lease == nil)
        await wait { !controller.nativeBusy }
        #expect(controller.canTeleport)
        #expect(await device.clears == 1)
    }

    @Test(arguments: [false, true])
    func failedOrCancelledNewPreparationPreservesExactPausedOldTaskAndDisplay(cancel: Bool) async throws {
        let authority = MovementTaskAuthority()
        let old = MovementTaskLease()
        #expect(authority.install(old, replacing: authority.snapshot))
        #expect(authority.updateHealth(.confirmedHealthy, for: old))
        #expect(authority.updateRunState(.paused, for: old))
        let original = authority.snapshot
        let device = RetryPointDevice()
        let now = Date()
        let controller = ServiceController(service: device, now: { now }, movementAuthority: authority)
        controller.observeRealLocation(RealLocationObservation(latitude: 24, longitude: 120, horizontalAccuracy: 5, observedAt: now))
        let marker = controller.positionMarker
        #expect(controller.teleport(to: target()))
        let id = try #require(controller.preparedOperation?.id)
        if cancel {
            await wait { await device.isPreparing }
            #expect(controller.cancelPreparation(id: id))
            await device.finishPreparation()
        } else {
            for _ in 1...3 {
                await wait { await device.isPreparing }
                await device.finishPreparation(failure: .pairingRequired)
            }
        }
        await wait { !controller.nativeBusy }
        #expect(authority.snapshot == original)
        #expect(controller.positionMarker == marker)
        #expect(await device.sent.isEmpty)
        #expect(await device.clears == 0)
        if !cancel {
            #expect(controller.cancelPreparation(id: id))
            #expect(controller.preparedOperation == nil)
            #expect(!controller.retryPreparedOperation(id: id))
        }
    }

    @Test func explicitOldInterruptionDuringPreparationRejectsTheHandoffWithoutRetryOrFalseHealth() async throws {
        let authority = MovementTaskAuthority()
        let old = MovementTaskLease()
        #expect(authority.install(old, replacing: authority.snapshot))
        #expect(authority.updateHealth(.confirmedHealthy, for: old))
        let device = RetryPointDevice()
        let controller = ServiceController(service: device, movementAuthority: authority)
        #expect(controller.teleport(to: target()))
        await wait { await device.isPreparing }
        #expect(authority.updateHealth(.interrupted(.tunnelUnavailable), for: old))
        let interrupted = authority.snapshot
        await device.finishPreparation()
        await wait { !controller.nativeBusy }
        #expect(authority.snapshot == interrupted)
        #expect(await device.calls == 1)
        #expect(await device.sent.isEmpty)
        #expect(controller.preparedOperation?.state == .failed(.operationCancelled))
    }

    @Test func watchdogBeforeHandoffPreservesTheReadyOldTaskAndItsFreshPosition() async throws {
        let device = RetryPointDevice()
        let controller = ServiceController(service: device, operationTimeout: .milliseconds(40))
        let candidate = target()
        #expect(controller.teleport(to: candidate))
        await wait { await device.isPreparing }
        await device.finishPreparation()
        await wait { await device.isReplying }
        await device.finishReply(.acknowledged)
        await wait { !controller.nativeBusy }
        let authority = controller.movementAuthority.snapshot
        let marker = controller.positionMarker
        #expect(controller.phase == .ready)
        #expect(controller.teleport(to: candidate))
        await wait { await device.isPreparing }
        await wait { controller.error == .operationTimedOut }
        #expect(controller.nativeBusy)
        #expect(controller.phase == .ready)
        #expect(controller.movementAuthority.snapshot == authority)
        #expect(controller.positionMarker == marker)
        await device.finishPreparation(failure: .pairingRequired)
        await wait { !controller.nativeBusy }
        #expect(controller.phase == .ready)
        #expect(controller.movementAuthority.snapshot == authority)
        #expect(controller.positionMarker == marker)
        #expect(controller.canTeleport)
        #expect(await device.calls == 2)
        #expect(await device.sent == [candidate.place.coordinate])
    }

    @Test(arguments: [PointDeliveryOutcome.acknowledged, .unconfirmed(.serviceUnavailable)])
    func anUnknownAdapterOutcomeWithoutClaimCannotLeaveAnUndismissiblePreparation(outcome: PointDeliveryOutcome) async throws {
        let authority = MovementTaskAuthority()
        let old = MovementTaskLease()
        #expect(authority.install(old, replacing: authority.snapshot))
        #expect(authority.updateHealth(.confirmedHealthy, for: old))
        let controller = ServiceController(service: UnclaimedOutcomeDevice(outcome: outcome), movementAuthority: authority)
        #expect(controller.teleport(to: target()))
        let id = try #require(controller.preparedOperation?.id)
        await wait { !controller.nativeBusy }
        #expect(controller.preparedOperation == nil)
        #expect(!controller.retryPreparedOperation(id: id))
        #expect(!PointDispatchGate(authority: authority, lease: old).claim())
        #expect(authority.snapshot.lease == nil)
        #expect(!controller.canTeleport)
        #expect(controller.canStop)
        #expect(controller.stop())
        await wait { !controller.nativeBusy }
        #expect(controller.canTeleport)
    }

    private func target() -> TeleportCandidate {
        let coordinate = GeoCoordinate(latitude: 25.033, longitude: 121.5654)!
        return TeleportCandidate(place: MapPlace(id: .mapKit("original"), title: "Original", coordinate: coordinate))
    }

    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

private actor PreparationDevice: DeviceService {
    let successAt: Int
    var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }
    init(successAt: Int) { self.successAt = successAt }
    func prepare() async throws {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
        if calls < successAt { throw DeviceServiceFailure.pairingRequired }
    }
    func finish() { continuation?.resume(); continuation = nil }
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome { .notSent(.deviceRequired) }
}

private actor RetryPointDevice: DeviceService {
    var calls = 0
    var sent: [GeoCoordinate] = []
    var clears = 0
    private var preparation: CheckedContinuation<DeviceServiceFailure?, Never>?
    private var reply: CheckedContinuation<PointDeliveryOutcome, Never>?
    var isPreparing: Bool { preparation != nil }
    var isReplying: Bool { reply != nil }
    func prepare() async throws {
        calls += 1
        if let failure = await withCheckedContinuation({ preparation = $0 }) { throw failure }
    }
    func clearLocation() async throws { clears += 1 }
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        calls += 1
        let failure = await withCheckedContinuation { preparation = $0 }
        if let failure { return .notSent(failure) }
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        sent.append(coordinate)
        return await withCheckedContinuation { reply = $0 }
    }
    func finishPreparation(failure: DeviceServiceFailure? = nil) { preparation?.resume(returning: failure); preparation = nil }
    func finishReply(_ outcome: PointDeliveryOutcome) { reply?.resume(returning: outcome); reply = nil }
}

private struct UnclaimedOutcomeDevice: DeviceService {
    let outcome: PointDeliveryOutcome
    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome { outcome }
}
