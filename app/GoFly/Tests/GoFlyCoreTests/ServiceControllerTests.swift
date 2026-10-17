import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct ServiceControllerTests {
    @Test func startupPreparesServiceWithoutClearingOrClaimingGPS() async throws {
        let device = TestDevice()
        let controller = ServiceController(service: device)
        #expect(controller.clearState == .unknown)
        #expect(controller.start())
        await settle(controller)
        #expect(controller.phase == .ready)
        #expect(controller.clearState == .unknown)
        #expect(controller.realLocation == nil)
        #expect(await device.operations == ["prepare"])
    }

    @Test func stopDuringPreparationQueuesClearAndRejectsNewOperations() async throws {
        let device = ControlledDevice()
        let controller = ServiceController(service: device)
        #expect(controller.start())
        await device.waitForPrepare()
        #expect(controller.stop())
        #expect(!controller.start())
        #expect(!controller.restoreGPS())
        #expect(!controller.resetTunnel())
        #expect(!controller.stop())
        #expect(controller.clearState == .pending)
        #expect(await device.operations == ["prepare"])
        await device.finishPrepare()
        await device.waitForClear()
        #expect(controller.phase == .stopping)
        #expect(!controller.canStart)
        await device.finishClear()
        await settle(controller)
        #expect(controller.phase == .stopped)
        #expect(controller.clearState == .confirmed)
        #expect(controller.gpsStatusKey == "gps.clearedWaiting")
        #expect(await device.operations == ["prepare", "clear"])
    }

    @Test func timeoutCannotUnlockNativeWorkOrSkipMandatoryClear() async throws {
        let device = ControlledDevice()
        let controller = ServiceController(service: device, operationTimeout: .milliseconds(20))
        #expect(controller.start())
        await device.waitForPrepare()
        await wait { controller.phase == .repairRequired }
        #expect(controller.nativeBusy)
        #expect(!controller.start())
        #expect(!controller.restoreGPS())
        #expect(!controller.resetTunnel())
        #expect(controller.stop())
        await wait { controller.phase == .repairRequired }
        #expect(controller.nativeBusy)
        #expect(!controller.stop())
        await device.finishPrepare()
        await device.waitForClear()
        #expect(!controller.start())
        await device.finishClear()
        await settle(controller)
        #expect(controller.phase == .stopped)
        #expect(controller.error == .operationTimedOut)
        #expect(controller.clearState == .unknown)
        #expect(controller.canRestoreGPS)
        #expect(await device.operations == ["prepare", "clear"])
    }

    @Test func clearFailureLeavesServiceStoppedAndRepairAvailable() async throws {
        let device = TestDevice(failure: .tunnelUnavailable)
        let controller = ServiceController(service: device)
        #expect(controller.restoreGPS())
        await settle(controller)
        #expect(controller.phase == .stopped)
        #expect(controller.clearState == .unknown)
        #expect(controller.error == .tunnelUnavailable)
        #expect(controller.statusKey == "service.stoppedGPSPending")
        #expect(controller.canStart && controller.canRestoreGPS && controller.canResetTunnel)
    }

    @Test func resetDoesNotClearLocationOrPrepareService() async throws {
        let device = TestDevice()
        let controller = ServiceController(service: device)
        #expect(controller.resetTunnel())
        #expect(!controller.resetTunnel())
        await settle(controller)
        #expect(controller.phase == .stopped)
        #expect(controller.clearState == .unknown)
        #expect(await device.operations == ["reset"])
    }

    @Test func timedOutRestoreAlreadyOwnsTheOnlySafetyClear() async throws {
        let device = ControlledDevice()
        let controller = ServiceController(service: device, operationTimeout: .milliseconds(20))
        #expect(controller.restoreGPS())
        await device.waitForClear()
        await wait { controller.phase == .repairRequired }
        #expect(!controller.stop())
        #expect(!controller.start())
        #expect(!controller.resetTunnel())
        await device.finishClear()
        await settle(controller)
        #expect(await device.operations == ["clear"])
        #expect(controller.clearState == .unknown)
    }

    @Test func validGPSIsIndependentOfClearAcknowledgement() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let controller = ServiceController(service: TestDevice(failure: .tunnelUnavailable), now: { now })
        let observation = RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: now)
        controller.observeRealLocation(observation)
        #expect(controller.realLocation == observation)
        #expect(controller.clearState == .unknown)
        #expect(controller.gpsStatusKey == "gps.unknown")
        #expect(controller.restoreGPS())
        await settle(controller)
        controller.observeRealLocation(observation)
        #expect(controller.realLocation == observation)
        #expect(controller.clearState == .unknown)
    }

    @Test func staleOrSimulatedGPSDoesNotProveRestoration() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let controller = ServiceController(service: TestDevice(), now: { now })
        #expect(RealLocationObservation(latitude: 25, longitude: 121, horizontalAccuracy: 5,
                                       observedAt: now, isSoftwareSimulated: true) == nil)
        #expect(controller.restoreGPS())
        await settle(controller)
        controller.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: now.addingTimeInterval(-30)))
        #expect(controller.realLocation == nil)
        controller.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: now))
        #expect(controller.gpsStatusKey == "gps.observed")
        #expect(controller.resetTunnel())
        await settle(controller)
        #expect(controller.clearState == .confirmed)
        #expect(controller.realLocation?.latitude == 25)
    }

    private func wait(_ predicate: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !predicate() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(predicate())
    }

    private func settle(_ controller: ServiceController) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while controller.nativeBusy && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(!controller.nativeBusy)
    }
}

private actor TestDevice: DeviceService {
    var operations: [String] = []
    let failure: DeviceServiceFailure?
    init(failure: DeviceServiceFailure? = nil) { self.failure = failure }
    func prepare() async throws { operations.append("prepare"); try failIfNeeded() }
    func clearLocation() async throws { operations.append("clear"); try failIfNeeded() }
    func resetClientConnection() async throws { operations.append("reset"); try failIfNeeded() }
    private func failIfNeeded() throws { if let failure { throw failure } }
}

private actor ControlledDevice: DeviceService {
    var operations: [String] = []
    private var preparation: CheckedContinuation<Void, Never>?
    private var clearing: CheckedContinuation<Void, Never>?
    func prepare() async throws {
        operations.append("prepare")
        await withCheckedContinuation { preparation = $0 }
    }
    func clearLocation() async throws {
        operations.append("clear")
        await withCheckedContinuation { clearing = $0 }
    }
    func resetClientConnection() async throws { operations.append("reset") }
    func finishPrepare() { preparation?.resume(); preparation = nil }
    func finishClear() { clearing?.resume(); clearing = nil }
    func waitForPrepare() async { while preparation == nil { await Task.yield() } }
    func waitForClear() async { while clearing == nil { await Task.yield() } }
}
