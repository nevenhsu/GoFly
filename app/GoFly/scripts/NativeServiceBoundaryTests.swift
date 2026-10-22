// Host-only doubles. The harness compiles the unchanged production service,
// actual VerifiedDeviceSession and actual dispatch gate, without device access.
import Foundation
import GoFlyCore

private let scenario = CommandLine.arguments[1]

struct FFITrace {
    let totalMilliseconds = 0.0
    let callsText = ""
    let failureOperation: String? = nil
    let failureCode: Int32? = nil
    let failureSubcode: Int32? = nil
}
final class NativeDeviceSession: DeviceSession {
    init(pairingURL: URL) throws {}
    func beginTrace() {}
    func endTrace() -> FFITrace? { nil }
    func close() {}
    func deviceIdentifier() throws -> String { "test-device" }
    func isSupportPrepared() throws -> Bool { true }
    func mountProvisionedSupport() throws {}
    func validateLocationService() throws {
        if scenario == "preparation-failure" { throw DeviceServiceFailure.devicePreparationRequired }
    }
    func clearLocation() throws {
        if scenario == "clear-failure" { throw DeviceServiceFailure.operationTimedOut }
    }
    func setLocation(_ coordinate: GeoCoordinate) throws {}
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
        let service = NativeDeviceService()
        let gate = PointDispatchGate()
        let coordinate = GeoCoordinate(latitude: 25, longitude: 121)!
        switch scenario {
        case "missing-pairing", "preparation-failure":
            let failure: DeviceServiceFailure = scenario == "missing-pairing" ? .pairingRequired : .devicePreparationRequired
            let result = await service.movePoint(to: coordinate, dispatch: gate)
            precondition(result == .notSent(failure), "FAIL: unsent point acknowledged")
            precondition(!gate.hasDispatched, "FAIL: gate claimed without a native write")
            try await expectFailure(failure) { try await service.prepare() }
            if scenario == "missing-pairing" {
                try await expectFailure(failure) { try await service.clearLocation() }
            }
        case "clear-failure":
            let result = await service.movePoint(to: coordinate, dispatch: gate)
            precondition(result == .acknowledged)
            try await expectFailure(.operationTimedOut) { try await service.clearLocation() }
        case "reset-failure":
            try await expectFailure(.tunnelUnavailable) { try await service.resetClientConnection() }
        case "success":
            try await service.prepare()
            let result = await service.movePoint(to: coordinate, dispatch: gate)
            precondition(result == .acknowledged && gate.hasDispatched)
            try await expectFailure(.serviceUnavailable) { try await service.resetClientConnection() }
            try await service.clearLocation()
            try await service.resetClientConnection()
        default: fatalError("unknown scenario")
        }
        print("PASS \(scenario)")
    }
}
