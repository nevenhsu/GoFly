// Host-only doubles. The harness compiles the unchanged production service,
// actual VerifiedDeviceSession and actual dispatch gate, without device access.
import Foundation
import GoFlyCore

private let scenario = CommandLine.arguments[1]

private final class HarnessState: @unchecked Sendable {
    static let shared = HarnessState()
    private let lock = NSLock()
    private var nextSessionID = 0
    private var coordinates: [GeoCoordinate] = []
    private var deadlineChecks = 0
    private var constructorDeadlines: [UInt64?] = []
    private var onFirstSet: (@Sendable () -> Void)?

    func newSession(deadline: UInt64?) -> Int {
        lock.withLock {
            nextSessionID += 1
            constructorDeadlines.append(deadline)
            return nextSessionID
        }
    }

    func record(_ coordinate: GeoCoordinate) {
        lock.withLock { coordinates.append(coordinate) }
    }

    func snapshot() -> (sessions: Int, coordinates: [GeoCoordinate], deadlineChecks: Int,
                        constructorDeadlines: [UInt64?]) {
        lock.withLock { (nextSessionID, coordinates, deadlineChecks, constructorDeadlines) }
    }

    func installFirstSetHook(_ hook: (@Sendable () -> Void)?) {
        lock.withLock { onFirstSet = hook }
    }

    func fireFirstSetHook() {
        let hook = lock.withLock { () -> (@Sendable () -> Void)? in
            let hook = onFirstSet
            onFirstSet = nil
            return hook
        }
        hook?()
    }

    func noteDeadlineCheck() {
        lock.withLock { deadlineChecks += 1 }
    }
}

struct FFITrace {
    let totalMilliseconds = 0.0
    let callsText = ""
    let failureOperation: String? = nil
    let failureCode: Int32? = nil
    let failureSubcode: Int32? = nil
}
final class NativeDeviceSession: DeviceSession {
    private let sessionID: Int
    private var operationDeadlineNanoseconds: UInt64?

    init(pairingURL: URL, operationDeadlineNanoseconds: UInt64? = nil) throws {
        sessionID = HarnessState.shared.newSession(deadline: operationDeadlineNanoseconds)
        self.operationDeadlineNanoseconds = operationDeadlineNanoseconds
    }
    func beginTrace() {}
    func endTrace() -> FFITrace? { nil }
    func close() {}
    func setOperationDeadline(_ deadline: UInt64?) { operationDeadlineNanoseconds = deadline }
    private func requireBudget() throws {
        guard let deadline = operationDeadlineNanoseconds else { return }
        HarnessState.shared.noteDeadlineCheck()
        let now = DispatchTime.now().uptimeNanoseconds
        if scenario == "deadline-exhaustion" || deadline <= now || deadline - now < 1_000_000_000 {
            throw DeviceServiceFailure.operationTimedOut
        }
    }
    func deviceIdentifier() throws -> String {
        try requireBudget()
        return "test-device"
    }
    func isSupportPrepared() throws -> Bool { try requireBudget(); return true }
    func mountProvisionedSupport() throws {}
    func validateLocationService() throws {
        try requireBudget()
        if scenario == "preparation-failure" { throw DeviceServiceFailure.devicePreparationRequired }
    }
    func clearLocation() throws {
        if scenario == "clear-failure" { throw DeviceServiceFailure.operationTimedOut }
    }
    func setLocation(_ coordinate: GeoCoordinate) throws {
        try requireBudget()
        HarnessState.shared.record(coordinate)
        if scenario == "explicit-gate-invalidated" && sessionID == 1 {
            HarnessState.shared.fireFirstSetHook()
        }
        switch scenario {
        case "single-attempt-failure" where sessionID == 1,
             "explicit-gate-invalidated" where sessionID == 1:
            throw DeviceServiceFailure.serviceUnavailable
        case "known-nontransient" where sessionID == 1:
            throw DeviceServiceFailure.devicePreparationRequired
        default:
            return
        }
    }
}
enum PairingFileStore {
    static var expectedDeviceUDID: String? { scenario == "missing-pairing" ? nil : "test-device" }
    static func prepareURL() -> URL { URL(fileURLWithPath: "/unused-test-pairing") }
    static func verifyStoredRecord(expectedDeviceUDID: String) -> Bool { true }
    static func importSetupData(_ data: Data, expectedDeviceUDID: String) throws {}
}
enum GoFlySetupPaths {
    static func directory() throws -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gofly-boundary-\(UUID())")
    }
}
struct LocalGoSetupHandoff {
    enum Result { case noPayload, imported, rejected, storageFailure }
    init(importSetupData: (Data, String) throws -> Void) {}
    func prepare() throws {}
    func consume(commandsIdle: Bool, isPreparing: Bool) -> Result { .noPayload }
}
enum TunnelProbe {
    static func run() throws {
        if scenario == "reset-failure" { throw DeviceServiceFailure.tunnelUnavailable }
    }
}

private func makeBoundGate() -> (MovementTaskAuthority, MovementTaskLease, PointDispatchGate) {
    let authority = MovementTaskAuthority()
    let lease = MovementTaskLease()
    let gate = PointDispatchGate(authority: authority, lease: lease,
                                 replacing: authority.snapshot)
    return (authority, lease, gate)
}

private func expectAuthorityGateRules() {
    do {
        let (authority, lease, gate) = makeBoundGate()
        precondition(gate.claim(), "initial authority gate did not install")
        precondition(authority.permitsRecovery(for: lease), "initial unknown health should permit recovery")
        precondition(gate.claimRecovery(), "initial same-point recovery was denied")
        precondition(!gate.claimRecovery(), "recovery was claimed twice")
    }
    do {
        let (authority, lease, gate) = makeBoundGate()
        precondition(gate.claim())
        precondition(authority.updateHealth(.confirmedHealthy, for: lease))
        precondition(authority.updateRunState(.paused, for: lease))
        precondition(!gate.claimRecovery(), "paused owner replayed")
    }
    do {
        let (authority, oldLease, oldGate) = makeBoundGate()
        precondition(oldGate.claim())
        precondition(authority.updateHealth(.confirmedHealthy, for: oldLease))
        let captured = authority.snapshot
        let newLease = MovementTaskLease()
        let newGate = PointDispatchGate(authority: authority, lease: newLease, replacing: captured)
        precondition(newGate.claim(), "new lease did not install")
        precondition(!oldGate.claimRecovery(), "old lease replayed after handoff")
    }
    do {
        let (_, _, gate) = makeBoundGate()
        precondition(gate.claim())
        gate.invalidate()
        precondition(gate.hasDispatched, "invalidation rewrote dispatched truth")
        precondition(!gate.claimRecovery(), "invalidated gate replayed")
    }
}

@main struct NativeServiceBoundaryTests {
    static func expectFailure(_ expected: DeviceServiceFailure,
                              _ operation: @Sendable () async throws -> Void) async throws {
        do {
            try await operation()
        } catch let failure as DeviceServiceFailure {
            precondition(failure == expected, "wrong failure: \(failure)")
            return
        }
        fatalError("FAIL \(scenario): failure was reported as success")
    }
    static func main() async throws {
        let coordinate = GeoCoordinate(latitude: 25, longitude: 121)!
        switch scenario {
        case "missing-pairing", "preparation-failure":
            let service = NativeDeviceService()
            let gate = PointDispatchGate()
            let failure: DeviceServiceFailure = scenario == "missing-pairing" ? .pairingRequired : .devicePreparationRequired
            let result = await service.movePoint(to: coordinate, dispatch: gate)
            precondition(result == .notSent(failure), "FAIL: unsent point acknowledged")
            precondition(!gate.hasDispatched, "FAIL: gate claimed without a native write")
            try await expectFailure(failure) { try await service.prepare() }
            if scenario == "missing-pairing" {
                try await expectFailure(failure) { try await service.clearLocation() }
            }
        case "clear-failure":
            let service = NativeDeviceService()
            let gate = PointDispatchGate()
            let result = await service.movePoint(to: coordinate, dispatch: gate)
            precondition(result == .acknowledged)
            try await expectFailure(.operationTimedOut) { try await service.clearLocation() }
        case "reset-failure":
            let service = NativeDeviceService()
            try await expectFailure(.tunnelUnavailable) { try await service.resetClientConnection() }
        case "success":
            let service = NativeDeviceService()
            let gate = PointDispatchGate()
            try await service.prepare()
            let result = await service.movePoint(to: coordinate, dispatch: gate)
            precondition(result == .acknowledged && gate.hasDispatched)
            try await expectFailure(.serviceUnavailable) { try await service.resetClientConnection() }
            try await service.clearLocation()
            try await service.resetClientConnection()
        case "single-attempt-failure", "known-nontransient",
             "explicit-gate-invalidated", "deadline-exhaustion":
            let service = NativeDeviceService()
            let authority: MovementTaskAuthority
            let lease: MovementTaskLease
            let gate: PointDispatchGate
            (authority, lease, gate) = makeBoundGate()
            if scenario == "explicit-gate-invalidated" {
                HarnessState.shared.installFirstSetHook { gate.invalidate() }
            }
            let result = await service.movePoint(to: coordinate, dispatch: gate)
            let observed = HarnessState.shared.snapshot()
            switch scenario {
            case "single-attempt-failure":
                precondition(result == .unconfirmed(.serviceUnavailable), "native service retried a dispatched point")
                precondition(observed.coordinates == [coordinate], "native service sent more than one point")
                precondition(observed.sessions == 1, "native service rebuilt inside the point attempt")
                precondition(gate.hasDispatched && authority.snapshot.lease == lease)
            case "known-nontransient":
                precondition(result == .unconfirmed(.devicePreparationRequired))
                precondition(observed.coordinates == [coordinate] && observed.sessions == 1)
            case "explicit-gate-invalidated":
                precondition(result == .unconfirmed(.serviceUnavailable),
                             "invalidated outer gate allowed replay")
                precondition(observed.coordinates == [coordinate])
            case "deadline-exhaustion":
                precondition(result == .notSent(.operationTimedOut))
                precondition(observed.sessions == 1 && observed.deadlineChecks > 0,
                             "point attempt did not enforce its deadline")
                precondition(observed.constructorDeadlines.count == 1,
                             "native service opened more than one session for a point")
                precondition(observed.constructorDeadlines.allSatisfy { $0 != nil },
                             "constructor started without the point budget")
            default:
                fatalError("unreachable")
            }
        case "authority-gates":
            expectAuthorityGateRules()
        default: fatalError("unknown scenario")
        }
        print("PASS \(scenario)")
    }
}
