import Foundation
import GoFlyCore

// This harness compiles the exact production service with deterministic session
// doubles. It never compiles or invokes the real device/FFI session class.
private final class State: @unchecked Sendable {
    let lock = NSLock()
    var created = 0
    var pairingAvailable = false
    var handoffFailure: DeviceServiceFailure?
    var events: [String] = []
    var setFailure = false
    var prepareFailure = false
    var clearFailure = false
    var pauseClear = false
    let clearEntered = DispatchSemaphore(value: 0)
    let clearRelease = DispatchSemaphore(value: 0)
    func event(_ value: String) { lock.withLock { events.append(value) } }
    func read<T>(_ body: (State) -> T) -> T { lock.withLock { body(self) } }
    func update(_ body: (State) -> Void) { lock.withLock { body(self) } }
    func reset() { update { $0.created = 0; $0.pairingAvailable = false; $0.handoffFailure = nil; $0.events = []; $0.setFailure = false; $0.prepareFailure = false; $0.clearFailure = false; $0.pauseClear = false } }
}
private let state = State()

final class NativeDeviceSession: DeviceSession {
    let id: Int
    init(pairingURL: URL) throws {
        id = state.lock.withLock { state.created += 1; return state.created }
        state.event("new\(id)")
    }
    func close() { state.event("close\(id)") }
    func deviceIdentifier() throws -> String { state.event("identity\(id)"); return "bound" }
    func isSupportPrepared() throws -> Bool {
        if state.read({ $0.prepareFailure }) { throw DeviceServiceFailure.devicePreparationRequired }
        return true
    }
    func mountProvisionedSupport() throws { fatalError("already prepared") }
    func validateLocationService() throws { state.event("open\(id)") }
    func setLocation(_ coordinate: GeoCoordinate) throws {
        state.event("set\(id):\(coordinate.displayText)")
        if state.read({ $0.setFailure }) { throw DeviceServiceFailure.operationTimedOut }
    }
    func clearLocation() throws {
        state.event("clear-enter\(id)")
        if state.read({ $0.pauseClear }) { state.clearEntered.signal(); state.clearRelease.wait() }
        state.event("clear-return\(id)")
        if state.read({ $0.clearFailure }) { throw DeviceServiceFailure.serviceUnavailable }
    }
}
enum PairingFileStore {
    static func prepareURL() -> URL { URL(fileURLWithPath: "/unused-test-double") }
    static var expectedDeviceUDID: String? { state.read { $0.pairingAvailable ? "bound" : nil } }
    static func verifyStoredRecord(expectedDeviceUDID: String) -> Bool { state.read { $0.pairingAvailable } }
    static func importSetupData(_ data: Data, expectedDeviceUDID: String?) throws {}
}
struct LocalGoSetupHandoff {
    enum Outcome { case noPayload, imported, rejected, storageFailure }
    init(importSetupData: (Data, String?) throws -> Void) {}
    func prepare() throws { state.event("handoff") }
    func consume(commandsIdle: Bool, isPreparing: Bool) -> Outcome {
        precondition(commandsIdle && !isPreparing)
        state.event("consume")
        if let failure = state.read({ $0.handoffFailure }) {
            return failure == .pairingRequired ? .rejected : .storageFailure
        }
        state.update { $0.pairingAvailable = true }
        return .imported
    }
}
enum TunnelProbe { static func run() throws { state.event("probe") } }

// The legacy-handoff harness must never read the host's real activation store.
// A unique absent namespace selects the ordinary-installation branch.
enum GoFlySetupPaths {
    private static let isolatedDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gofly-native-session-check-\(UUID().uuidString)", isDirectory: true)
    static func directory() throws -> URL { isolatedDirectory }
}

@main struct NativeSessionLifetimeCheck {
    static let coordinate = GeoCoordinate(latitude: 37.5, longitude: -122.25)!
    static func events() -> [String] { state.read { $0.events } }
    static func expectFailure(_ operation: @Sendable () async throws -> Void, _ expected: DeviceServiceFailure) async {
        do { try await operation(); fatalError("expected \(expected)") }
        catch { precondition(error as? DeviceServiceFailure == expected) }
    }
    static func main() async throws {
        // First operation is Go: stored binding does not exist until consume.
        state.reset()
        let direct = NativeDeviceService()
        let directGate = PointDispatchGate()
        let directOutcome = await direct.movePoint(to: coordinate, dispatch: directGate)
        precondition(directOutcome == .acknowledged, "first-use Go must consume setup before reading the pairing store")
        precondition(events().firstIndex(of: "consume")! < events().firstIndex(of: "new1")!)
        state.update { $0.handoffFailure = .pairingRequired }
        let retainedOutcome = await direct.movePoint(to: coordinate, dispatch: PointDispatchGate())
        precondition(retainedOutcome == .acknowledged && state.read { $0.created } == 1)
        try await direct.prepare()
        precondition(events().filter { $0 == "consume" }.count == 1) // Active session never imports new pairing data.
        try await direct.clearLocation()
        for failure in [DeviceServiceFailure.pairingRequired, .storageUnavailable] {
            state.reset()
            state.update { $0.handoffFailure = failure }
            let rejected = NativeDeviceService()
            let gate = PointDispatchGate()
            let outcome = await rejected.movePoint(to: coordinate, dispatch: gate)
            precondition(outcome == .notSent(failure) && !gate.hasDispatched)
            precondition(state.read { $0.created } == 0 && !state.read { $0.pairingAvailable })
        }
        state.reset()
        let service = NativeDeviceService()
        try await service.prepare()
        precondition(events().contains("close1")) // Start's readiness probe is ephemeral.
        let first = await service.movePoint(to: coordinate, dispatch: PointDispatchGate())
        precondition(first == .acknowledged && !events().contains("close2"))
        let setIndex = events().firstIndex(where: { $0.hasPrefix("set2:") })!
        precondition(events()[setIndex - 1] == "identity2")
        try await service.prepare()
        precondition(state.read { $0.created } == 2 && !events().contains("close2"))
        await expectFailure({ try await service.resetClientConnection() }, .serviceUnavailable)
        precondition(!events().contains("probe"))
        state.update { $0.prepareFailure = true }
        let failedPreparation = await service.movePoint(to: coordinate, dispatch: PointDispatchGate())
        precondition(failedPreparation == .notSent(.devicePreparationRequired) && !events().contains("close2"))
        state.update { $0.prepareFailure = false; $0.setFailure = true }
        let unknown = await service.movePoint(to: coordinate, dispatch: PointDispatchGate())
        precondition(unknown == .unconfirmed(.operationTimedOut) && state.read { $0.created } == 2 && !events().contains("close2"))
        state.update { $0.pauseClear = true; $0.clearFailure = true }
        let clearing = Task.detached { await expectFailure({ try await service.clearLocation() }, .serviceUnavailable) }
        precondition(state.clearEntered.wait(timeout: .now() + 2) == .success)
        precondition(!events().contains("close2")) // FFI work has not returned.
        state.clearRelease.signal()
        await clearing.value
        precondition(events().filter { $0 == "close2" }.count == 1)
        precondition(events().firstIndex(of: "clear-return2")! < events().firstIndex(of: "close2")!)
        state.update { $0.pauseClear = false; $0.clearFailure = false; $0.setFailure = false }
        try await service.clearLocation() // A later explicit Restore creates a fresh session.
        precondition(events().contains("clear-return3") && events().contains("close3"))
        try await service.resetClientConnection()
        precondition(events().last == "probe")
        let gate = PointDispatchGate(); gate.invalidate()
        let cancelled = await service.movePoint(to: coordinate, dispatch: gate)
        precondition(cancelled == .notSent(.operationCancelled) && events().last == "close4")
        precondition(!events().contains(where: { $0.hasPrefix("set4:") }))
        print("PASS: first-use Go consumes setup before pairing, rejects failed handoff without dispatch, skips active-session imports; exact native service retains ACK/unknown sessions, reuses prepare, blocks reset, closes after real clear and honors dispatch gate")
    }
}
