import Foundation
import Testing
import GoFlyCore

@Suite @MainActor
struct TunnelResetRecoveryTests {
    @Test func resetIsRejectedWhileServiceHasActiveMovementPhase() async throws {
        let device = HeldResetRecoveryDevice(holdReset: false)
        let service = ServiceController(service: device)
        #expect(service.start())
        await wait { service.phase == .ready && !service.nativeBusy }
        let route = RouteExecutionController(
            planner: ResetRecoveryPlanner(), commands: service, search: ResetRecoverySearch()
        )
        let joystick = JoystickMovementController(commands: service)
        let recovery = MovementRecoveryController(
            service: service, route: route, joystick: joystick, probe: ImmediateResetRecoveryProbe()
        )

        recovery.sceneDidBecomeActive()
        await wait { recovery.connectionState == .reachable && !recovery.isChecking }
        #expect(!recovery.canResetTunnel)
        #expect(!recovery.resetTunnel())
        #expect(await device.resetCount == 0)

        recovery.releaseForInactiveScene()
        #expect(service.stop())
        await wait { !service.nativeBusy }
    }

    @Test func sceneInactiveSupersedesPendingResetWithoutNativeDispatch() async throws {
        let device = HeldResetRecoveryDevice()
        let service = ServiceController(service: device)
        let route = RouteExecutionController(
            planner: ResetRecoveryPlanner(), commands: service, search: ResetRecoverySearch()
        )
        let joystick = JoystickMovementController(commands: service)
        let probe = HeldResetRecoveryProbe()
        let recovery = MovementRecoveryController(
            service: service, route: route, joystick: joystick, probe: probe
        )

        recovery.sceneDidBecomeActive()
        recovery.checkConnection()
        await wait { await probe.count == 1 && recovery.isChecking }
        recovery.releaseForInactiveScene()
        recovery.sceneDidBecomeActive()
        #expect(recovery.resetTunnel())
        recovery.releaseForInactiveScene()
        await probe.release()
        await wait { !recovery.isResettingTunnel }
        #expect(await device.resetCount == 0)
        #expect(!service.nativeBusy)
    }

    @Test func resetIsRejectedWhileVisibleCheckIsActive() async throws {
        let device = HeldResetRecoveryDevice()
        let service = ServiceController(service: device)
        let route = RouteExecutionController(
            planner: ResetRecoveryPlanner(), commands: service, search: ResetRecoverySearch()
        )
        let joystick = JoystickMovementController(commands: service)
        let probe = HeldResetRecoveryProbe()
        let recovery = MovementRecoveryController(
            service: service, route: route, joystick: joystick, probe: probe
        )

        recovery.sceneDidBecomeActive()
        recovery.checkConnection()
        await wait { await probe.count == 1 && recovery.isChecking }
        #expect(!recovery.canResetTunnel)
        #expect(!recovery.resetTunnel())
        #expect(await device.resetCount == 0)

        recovery.releaseForInactiveScene()
        await probe.release()
    }

    @Test func restoreSupersedesPendingResetWhileOldProbeIsHeld() async throws {
        let device = HeldResetRecoveryDevice()
        let service = ServiceController(service: device)
        let route = RouteExecutionController(
            planner: ResetRecoveryPlanner(), commands: service, search: ResetRecoverySearch()
        )
        let joystick = JoystickMovementController(commands: service)
        let probe = HeldResetRecoveryProbe()
        let recovery = MovementRecoveryController(
            service: service, route: route, joystick: joystick, probe: probe
        )

        recovery.sceneDidBecomeActive()
        recovery.checkConnection()
        await wait { await probe.count == 1 && recovery.isChecking }
        recovery.releaseForInactiveScene()
        recovery.sceneDidBecomeActive()
        #expect(recovery.resetTunnel())
        #expect(recovery.isResettingTunnel)

        #expect(service.restoreGPS())
        await wait { service.clearState == .confirmed && !service.nativeBusy }
        await probe.release()
        await wait { !recovery.isResettingTunnel }
        #expect(await device.resetCount == 0)
        #expect(await device.clearCount == 1)
        #expect(service.clearState == .confirmed)
        recovery.releaseForInactiveScene()
    }

    @Test func directServiceResetSupersedesPendingRecoveryConsentWithoutDuplicateReset() async throws {
        let device = HeldResetRecoveryDevice()
        let service = ServiceController(service: device)
        let route = RouteExecutionController(
            planner: ResetRecoveryPlanner(), commands: service, search: ResetRecoverySearch()
        )
        let joystick = JoystickMovementController(commands: service)
        let probe = HeldResetRecoveryProbe()
        let recovery = MovementRecoveryController(
            service: service, route: route, joystick: joystick, probe: probe
        )

        recovery.sceneDidBecomeActive()
        recovery.checkConnection()
        await wait { await probe.count == 1 && recovery.isChecking }
        recovery.releaseForInactiveScene()
        recovery.sceneDidBecomeActive()
        #expect(recovery.resetTunnel())
        #expect(await device.resetCount == 0)

        #expect(service.resetTunnel())
        await wait { await device.resetStarted }
        #expect(await device.resetCount == 1)
        await probe.release()
        await Task.yield()
        #expect(await device.resetCount == 1)

        await device.releaseReset()
        await wait { !service.nativeBusy && !recovery.isResettingTunnel }
        #expect(await device.resetCount == 1)
        #expect(recovery.connectionState == .reachable)
        recovery.releaseForInactiveScene()
    }

    @Test func recoveryResetFailurePublishesUnavailableWithoutClaimingRecovery() async throws {
        let device = HeldResetRecoveryDevice(resetFailure: .tunnelUnavailable)
        let service = ServiceController(service: device)
        let route = RouteExecutionController(
            planner: ResetRecoveryPlanner(), commands: service, search: ResetRecoverySearch()
        )
        let joystick = JoystickMovementController(commands: service)
        let recovery = MovementRecoveryController(
            service: service, route: route, joystick: joystick, probe: HeldResetRecoveryProbe()
        )

        recovery.sceneDidBecomeActive()
        #expect(recovery.resetTunnel())
        await wait { await device.resetStarted }
        await device.releaseReset()
        await wait { !service.nativeBusy && !recovery.isResettingTunnel }
        #expect(recovery.connectionState == .unavailable)
        #expect(!service.movementConnectionAvailable)
        #expect(service.error == .tunnelUnavailable)
        recovery.releaseForInactiveScene()
    }

    @Test func resetWatchdogSealsFailureAgainstLateNativeSuccess() async throws {
        let watchdog = ManualServiceWatchdog()
        let device = HeldResetRecoveryDevice()
        let service = ServiceController(service: device, watchdogSleep: watchdog.sleep)
        let route = RouteExecutionController(
            planner: ResetRecoveryPlanner(), commands: service, search: ResetRecoverySearch()
        )
        let joystick = JoystickMovementController(commands: service)
        let recovery = MovementRecoveryController(
            service: service, route: route, joystick: joystick, probe: HeldResetRecoveryProbe()
        )

        recovery.sceneDidBecomeActive()
        #expect(recovery.resetTunnel())
        await wait { await device.resetStarted && watchdog.requests.count == 1 }
        let resetID = try #require({
            if case .running(let id) = service.tunnelResetState { return id }
            return nil
        }())
        watchdog.fireLatest()
        await wait { recovery.connectionState == .timedOut && !recovery.isResettingTunnel }
        #expect(!service.movementConnectionAvailable)

        await device.releaseReset()
        await wait { !service.nativeBusy }
        #expect(service.tunnelResetState == .failed(id: resetID, failure: .operationTimedOut))
        #expect(recovery.connectionState == .timedOut)
        #expect(!service.movementConnectionAvailable)
        recovery.releaseForInactiveScene()
    }

    @Test func stopAfterResetWatchdogKeepsFailureSealedThroughQueuedClear() async throws {
        let watchdog = ManualServiceWatchdog()
        let device = HeldResetRecoveryDevice()
        let service = ServiceController(service: device, watchdogSleep: watchdog.sleep)
        let route = RouteExecutionController(
            planner: ResetRecoveryPlanner(), commands: service, search: ResetRecoverySearch()
        )
        let joystick = JoystickMovementController(commands: service)
        let recovery = MovementRecoveryController(
            service: service, route: route, joystick: joystick, probe: HeldResetRecoveryProbe()
        )

        recovery.sceneDidBecomeActive()
        #expect(recovery.resetTunnel())
        await wait { await device.resetStarted && watchdog.requests.count == 1 }
        let resetID = try #require({
            if case .running(let id) = service.tunnelResetState { return id }
            return nil
        }())
        watchdog.fireLatest()
        await wait { service.phase == .repairRequired }
        #expect(service.stop())
        await device.releaseReset()
        await wait { !service.nativeBusy }

        #expect(service.tunnelResetState == .failed(id: resetID, failure: .operationTimedOut))
        #expect(!service.movementConnectionAvailable)
        #expect(recovery.connectionState == .unknown)
        #expect(!recovery.isResettingTunnel)
        #expect(await device.clearCount == 1)
        recovery.releaseForInactiveScene()
    }

    @Test func recoveryResetDrainsHeldProbeBeforeNativeReset() async throws {
        let device = HeldResetRecoveryDevice()
        let service = ServiceController(service: device)
        let route = RouteExecutionController(
            planner: ResetRecoveryPlanner(), commands: service, search: ResetRecoverySearch()
        )
        let joystick = JoystickMovementController(commands: service)
        let probe = HeldResetRecoveryProbe()
        let recovery = MovementRecoveryController(
            service: service, route: route, joystick: joystick, probe: probe
        )

        recovery.sceneDidBecomeActive()
        recovery.checkConnection()
        await wait { await probe.count == 1 && recovery.isChecking }
        recovery.releaseForInactiveScene()
        recovery.sceneDidBecomeActive()
        #expect(await probe.count == 1)
        #expect(!recovery.isChecking)
        #expect(!recovery.canCheck)
        #expect(recovery.canResetTunnel)

        #expect(recovery.resetTunnel())
        #expect(recovery.isResettingTunnel)
        #expect(await device.resetCount == 0)

        await probe.release()
        await wait { await device.resetStarted }
        #expect(await device.resetCount == 1)

        await device.releaseReset()
        await wait { !service.nativeBusy && !recovery.isResettingTunnel }
        #expect(recovery.connectionState == .reachable)
        #expect(service.movementConnectionAvailable)
        #expect(await device.resetCount == 1)
        recovery.releaseForInactiveScene()
    }

    @Test func directResetInvalidatesHeldProbeBeforeNativeReset() async throws {
        let device = HeldResetRecoveryDevice()
        let service = ServiceController(service: device)
        let route = RouteExecutionController(
            planner: ResetRecoveryPlanner(), commands: service, search: ResetRecoverySearch()
        )
        let joystick = JoystickMovementController(commands: service)
        let probe = HeldResetRecoveryProbe()
        let recovery = MovementRecoveryController(
            service: service, route: route, joystick: joystick, probe: probe
        )

        recovery.sceneDidBecomeActive()
        recovery.checkConnection()
        await wait { await probe.count == 1 && recovery.isChecking }

        #expect(service.phase == .stopped)
        #expect(service.canResetTunnel)
        #expect(service.resetTunnel())

        // This is intentionally before the first await after admission: the
        // old probe must be invalidated in the same MainActor turn.
        #expect(recovery.connectionState == .unknown)
        #expect(!service.movementConnectionAvailable)
        #expect({
            if case .running = service.tunnelResetState { return true }
            return false
        }())

        await wait { await device.resetStarted }

        // The reset admission boundary must synchronously close the existing
        // connection proof before the native reset work begins.
        #expect(recovery.connectionState == .unknown)
        #expect(!service.movementConnectionAvailable)

        // A success from the old, cancellation-insensitive probe must not
        // reopen the fence while the accepted reset is still in flight.
        await probe.release()
        await wait { await probe.returned && !recovery.isChecking }
        #expect(recovery.connectionState == .unknown)
        #expect(!service.movementConnectionAvailable)
        #expect(await device.resetCount == 1)

        await device.releaseReset()
        await wait { !service.nativeBusy }
        #expect({
            if case .succeeded = service.tunnelResetState { return true }
            return false
        }())
        #expect(recovery.connectionState == .reachable)
        recovery.releaseForInactiveScene()
    }

    private func wait(_ predicate: @escaping @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await predicate()) && ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(await predicate())
    }
}

private actor HeldResetRecoveryProbe: TunnelProbing {
    private(set) var count = 0
    private(set) var returned = false
    private var waiter: CheckedContinuation<Void, Never>?

    func check() async throws {
        count += 1
        await withCheckedContinuation { waiter = $0 }
        returned = true
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }
}

private actor ImmediateResetRecoveryProbe: TunnelProbing {
    func check() async throws {}
}

private actor HeldResetRecoveryDevice: DeviceService {
    let holdReset: Bool
    let resetFailure: DeviceServiceFailure?
    private(set) var resetStarted = false
    private(set) var resetCount = 0
    private(set) var clearCount = 0
    private var resetWaiter: CheckedContinuation<Void, Never>?

    init(holdReset: Bool = true, resetFailure: DeviceServiceFailure? = nil) {
        self.holdReset = holdReset
        self.resetFailure = resetFailure
    }

    func prepare() async throws {}
    func clearLocation() async throws { clearCount += 1 }

    func resetClientConnection() async throws {
        resetStarted = true
        resetCount += 1
        if holdReset { await withCheckedContinuation { resetWaiter = $0 } }
        if let resetFailure { throw resetFailure }
    }

    func releaseReset() {
        resetWaiter?.resume()
        resetWaiter = nil
    }

    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        .notSent(.deviceRequired)
    }
}

private struct ResetRecoveryPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}

private struct ResetRecoverySearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
