import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct OnboardingControllerTests {
    @Test func backNavigationIgnoresPermissionAndVPNCallbacksFromDepartedPages() async {
        let permission = ControlledPermission()
        let probe = ControlledProbe()
        let controller = OnboardingController(probe: probe, location: permission)
        controller.advanceWelcome()
        let request = Task { await controller.allowLocation() }
        await wait { permission.isWaiting }
        controller.skipLocation()
        controller.setVPNActive(true)
        await wait { await probe.requests == 1 }
        controller.goBack()
        #expect(controller.step == .location)
        permission.finish(.authorized)
        await request.value
        await probe.finish()
        await wait { !controller.isChecking }
        #expect(controller.step == .location)
        #expect(controller.vpnState == .unknown)
        #expect(!controller.canAdvanceVPN)
        controller.goBack()
        #expect(controller.step == .welcome)
        #expect(!controller.isRequestingLocation)
    }

    @Test func foregroundCadenceChecksEveryFiveSecondsWithoutOverlappingOrFlickeringSuccess() async {
        let clock = ManualOnboardingClock()
        let probe = ControlledProbe()
        let controller = OnboardingController(probe: probe, location: PermissionStub(.denied), clock: clock.clock)
        controller.advanceWelcome()
        controller.skipLocation()
        controller.setVPNActive(true)
        await wait { await probe.requests == 1 && clock.hasSleeper }
        await probe.finish()
        await wait { controller.canAdvanceVPN }
        clock.advance(to: .seconds(4))
        for _ in 0..<10 { await Task.yield() }
        #expect(await probe.requests == 1)
        clock.advance(to: .seconds(5))
        await wait { await probe.requests == 2 }
        #expect(controller.vpnState == .reachable)
        clock.advance(to: .seconds(10))
        for _ in 0..<10 { await Task.yield() }
        #expect(await probe.requests == 2)
        await probe.finish(.failure(TunnelProbeFailure.unavailable))
        await wait { controller.vpnState == .unavailable }
        clock.advance(to: .seconds(15))
        await wait { await probe.requests == 3 }
        controller.setVPNActive(false)
        await probe.finish(.failure(CancellationError()))
        await wait { !controller.isChecking }
        clock.advance(to: .seconds(20))
        for _ in 0..<10 { await Task.yield() }
        #expect(await probe.requests == 3)
        #expect(controller.vpnState == .unknown)
        #expect(await probe.maximumConcurrent == 1)
    }

    @Test func backgroundInvalidatesQueuedNextAndReturnWaitsForOldProbeBeforeRechecking() async {
        let probe = ControlledProbe()
        let controller = OnboardingController(probe: probe, location: PermissionStub(.denied))
        controller.advanceWelcome()
        controller.skipLocation()
        controller.setVPNActive(true)
        await wait { await probe.requests == 1 }
        await probe.finish()
        await wait { controller.canAdvanceVPN }
        controller.checkConnection()
        await wait { await probe.requests == 2 }
        var advances = 0
        controller.advanceVPN { advances += 1 }
        controller.setVPNActive(false)
        #expect(!controller.canAdvanceVPN)
        #expect(!controller.isAdvancing)
        #expect(controller.vpnState == .unknown)
        controller.setVPNActive(true)
        #expect(await probe.requests == 2)
        await probe.finish() // Deliberately returns late success after cancellation.
        await wait { await probe.requests == 3 }
        #expect(advances == 0)
        await probe.finish()
        await wait { controller.canAdvanceVPN }
        #expect(controller.step == .vpn)
        #expect(advances == 0)
        controller.advanceVPN { advances += 1 }
        await wait { await probe.requests == 4 }
        await probe.finish(.failure(TunnelProbeFailure.timedOut))
        await wait { controller.vpnState == .timedOut }
        #expect(!controller.canAdvanceVPN)
        #expect(advances == 0)
        #expect(await probe.maximumConcurrent == 1)
        controller.setVPNActive(false)
    }

    @Test func nextRequiresNewProbeAfterTapAndNeverOverlapsExistingCheck() async {
        let probe = ControlledProbe()
        let controller = OnboardingController(probe: probe, location: PermissionStub(.denied))
        controller.advanceWelcome()
        controller.skipLocation()
        controller.setVPNActive(true)
        await wait { await probe.requests == 1 }
        await probe.finish()
        await wait { controller.canAdvanceVPN }
        controller.checkConnection()
        await wait { await probe.requests == 2 }
        var advances = 0
        controller.advanceVPN { advances += 1 }
        #expect(controller.isAdvancing)
        #expect(!controller.canAdvanceVPN)
        controller.advanceVPN { advances += 1 }
        controller.checkConnection()
        #expect(await probe.requests == 2)
        await probe.finish()
        await wait { await probe.requests == 3 }
        #expect(advances == 0)
        await probe.finish()
        await wait { advances == 1 }
        #expect(controller.step == .complete)
        #expect(await probe.maximumConcurrent == 1)
    }

    @Test func visibleVPNChecksActualReachabilityWithoutAutoAdvancing() async {
        let probe = ControlledProbe()
        let controller = OnboardingController(probe: probe, location: PermissionStub(.denied))
        controller.advanceWelcome()
        controller.skipLocation()
        controller.setVPNActive(true)
        await wait { await probe.requests == 1 }
        #expect(!controller.canAdvanceVPN)
        await probe.finish()
        await wait { controller.canAdvanceVPN }
        #expect(controller.step == .vpn)
        controller.checkConnection()
        await wait { await probe.requests == 2 }
        await probe.finish(.failure(TunnelProbeFailure.unavailable))
        await wait { controller.vpnState == .unavailable }
        #expect(!controller.canAdvanceVPN)
        #expect(controller.step == .vpn)
        controller.setVPNActive(false)
    }

    @Test(arguments: [LocationAuthorization.authorized, .denied])
    func permissionDecisionContinuesWithoutWaitingForGPS(decision: LocationAuthorization) async {
        let permission = PermissionStub(decision)
        let controller = OnboardingController(probe: ProbeStub(), location: permission)
        controller.advanceWelcome()
        await controller.allowLocation()
        #expect(controller.step == .vpn)
        #expect(controller.locationAuthorization == decision)
        #expect(permission.requests == 1)
        #expect(!controller.isRequestingLocation)
    }

    @Test func skippedLocationReachesVPNWithoutRequestingPermissionOrStartingService() async {
        let permission = PermissionStub(.notDetermined)
        let probe = ProbeStub()
        let controller = OnboardingController(probe: probe, location: permission)
        #expect(controller.step == .welcome)
        controller.advanceWelcome()
        #expect(controller.step == .location)
        controller.skipLocation()
        #expect(controller.step == .vpn)
        #expect(permission.requests == 0)
        #expect(await probe.requests == 0)
        #expect(!controller.canAdvanceVPN)
    }

    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

@MainActor
private final class PermissionStub: LocationAuthorizing {
    var authorization: LocationAuthorization
    var requests = 0
    init(_ authorization: LocationAuthorization) { self.authorization = authorization }
    func requestAuthorization() async -> LocationAuthorization {
        requests += 1
        return authorization
    }
}

@MainActor
private final class ControlledPermission: LocationAuthorizing {
    var authorization: LocationAuthorization = .notDetermined
    private var continuation: CheckedContinuation<LocationAuthorization, Never>?
    var isWaiting: Bool { continuation != nil }
    func requestAuthorization() async -> LocationAuthorization {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ result: LocationAuthorization) {
        authorization = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor ProbeStub: TunnelProbing {
    var requests = 0
    func check() async throws { requests += 1 }
}

private actor ControlledProbe: TunnelProbing {
    private var continuation: CheckedContinuation<Void, any Error>?
    var requests = 0
    var maximumConcurrent = 0
    private var concurrent = 0

    func check() async throws {
        requests += 1
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        defer { concurrent -= 1 }
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(_ result: Result<Void, any Error> = .success(())) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}

@MainActor
private final class ManualOnboardingClock {
    private var instant: Duration = .zero
    private var sleepers: [UUID: (Duration, CheckedContinuation<Void, any Error>)] = [:]
    var hasSleeper: Bool { !sleepers.isEmpty }
    var clock: OnboardingClock { OnboardingClock(now: { self.instant }, sleep: { try await self.sleep($0) }) }

    func advance(to instant: Duration) {
        self.instant = instant
        for (id, entry) in sleepers where entry.0 <= instant {
            sleepers.removeValue(forKey: id)?.1.resume()
        }
    }

    private func sleep(_ duration: Duration) async throws {
        try Task.checkCancellation()
        let id = UUID()
        let deadline = instant + duration
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { sleepers[id] = (deadline, $0) }
        } onCancel: {
            Task { @MainActor in
                self.sleepers.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
            }
        }
    }
}
