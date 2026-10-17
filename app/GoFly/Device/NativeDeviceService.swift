import Foundation
import GoFlyCore

#if !targetEnvironment(simulator)
import idevice

/// The only native device boundary in the production app. Every handle is
/// created, used and released on this queue before its continuation resumes.
final class NativeDeviceService: DeviceService, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.neven.gofly.device", qos: .userInitiated)

    init() {}

    func prepare() async throws {
        try await perform {
            // This queue has no active native session at the handoff boundary.
            let handoff = LocalGoSetupHandoff(importSetupData: {
                try PairingFileStore.importSetupData($0, expectedDeviceUDID: $1)
            })
            do { try handoff.prepare() } catch { throw DeviceServiceFailure.storageUnavailable }
            switch handoff.consume(commandsIdle: true, isPreparing: false) {
            case .noPayload, .imported: break
            case .rejected: throw DeviceServiceFailure.pairingRequired
            case .storageFailure: throw DeviceServiceFailure.storageUnavailable
            }
            try Self.withVerifiedSession { try $0.prepare() }
        }
    }

    func clearLocation() async throws {
        // Deliberately independent of DDI preparation, GPS and cancellation.
        // An uncertain clear result is reported once; it is never resent here.
        try await perform { try Self.withVerifiedSession { try $0.clearLocation() } }
    }

    func resetClientConnection() async throws {
        // Sessions are scoped to each operation, so all our client state is
        // already released. A fresh TCP probe changes no remote service state.
        try await perform { try TunnelProbe.run() }
    }

    private func perform(_ operation: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                // Never return early while an FFI call still owns handles.
                idevice_set_global_timeout(10)
                do { try operation(); continuation.resume() }
                catch let failure as DeviceServiceFailure { continuation.resume(throwing: failure) }
                catch { continuation.resume(throwing: DeviceServiceFailure.serviceUnavailable) }
            }
        }
    }

    private static func withVerifiedSession(_ operation: (VerifiedDeviceSession) throws -> Void) throws {
        let path = PairingFileStore.prepareURL()
        guard let expected = PairingFileStore.expectedDeviceUDID,
              PairingFileStore.verifyStoredRecord(expectedDeviceUDID: expected) else {
            throw DeviceServiceFailure.pairingRequired
        }
        let session = try NativeDeviceSession(pairingURL: path)
        defer { session.close() }
        try operation(VerifiedDeviceSession(session: session, expectedIdentifier: expected))
    }

}

#else

final class NativeDeviceService: DeviceService, @unchecked Sendable {
    init() {}
    func prepare() async throws { throw DeviceServiceFailure.deviceRequired }
    func clearLocation() async throws { throw DeviceServiceFailure.deviceRequired }
    func resetClientConnection() async throws { throw DeviceServiceFailure.deviceRequired }
}

#endif
