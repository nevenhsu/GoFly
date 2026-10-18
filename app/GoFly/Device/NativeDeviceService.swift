import Foundation
import GoFlyCore

#if !targetEnvironment(simulator)
import idevice

/// Owns every native handle on one queue. A dispatched location channel stays
/// alive until its explicit clear has actually returned, including on errors.
final class NativeDeviceService: DeviceService, @unchecked Sendable {
    private struct OwnedSession {
        let native: NativeDeviceSession
        let verified: VerifiedDeviceSession
    }
    private let queue = DispatchQueue(label: "com.neven.gofly.device", qos: .userInitiated)
    // Access only on queue; neither handles nor the verified wrapper escape it.
    private var ownedSession: OwnedSession?

    init() {}

    func prepare() async throws {
        try await perform {
            if let owned = self.ownedSession {
                try owned.verified.prepare()
                return
            }
            try Self.consumeSetupHandoff()
            let fresh = try Self.makeSession()
            defer { fresh.native.close() }
            try fresh.verified.prepare()
        }
    }

    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                idevice_set_global_timeout(10)
                let candidate: OwnedSession
                let wasOwned = self.ownedSession != nil
                do {
                    if let owned = self.ownedSession {
                        candidate = owned
                    } else {
                        try Self.consumeSetupHandoff()
                        candidate = try Self.makeSession()
                    }
                } catch {
                    continuation.resume(returning: .notSent(Self.failure(error)))
                    return
                }
                do {
                    try candidate.verified.prepare()
                } catch {
                    if !wasOwned { candidate.native.close() }
                    continuation.resume(returning: .notSent(Self.failure(error)))
                    return
                }
                // VerifiedDeviceSession rechecks this same session's identity,
                // then atomically claims the gate immediately before set.
                let outcome = candidate.verified.movePoint(to: coordinate, dispatch: dispatch)
                switch outcome {
                case .acknowledged, .unconfirmed:
                    self.ownedSession = candidate
                case .notSent:
                    if !wasOwned { candidate.native.close() }
                }
                continuation.resume(returning: outcome)
            }
        }
    }

    func clearLocation() async throws {
        // Independent of DDI/GPS/cancellation. Never resend an uncertain clear.
        try await perform {
            let session = try self.ownedSession ?? Self.makeSession()
            defer {
                // Release only after the real clear call returns, even on error.
                session.native.close()
                self.ownedSession = nil
            }
            try session.verified.clearLocation()
        }
    }

    func resetClientConnection() async throws {
        try await perform {
            guard self.ownedSession == nil else { throw DeviceServiceFailure.serviceUnavailable }
            try TunnelProbe.run()
        }
    }

    private func perform(_ operation: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                // Never return early while an FFI call still owns handles.
                idevice_set_global_timeout(10)
                do { try operation(); continuation.resume() }
                catch { continuation.resume(throwing: Self.failure(error)) }
            }
        }
    }

    private static func failure(_ error: Error) -> DeviceServiceFailure {
        error as? DeviceServiceFailure ?? .serviceUnavailable
    }

    private static func consumeSetupHandoff() throws {
        // Only called without an owned location session.
        do {
            let store = SetupActivationStore(directory: try GoFlySetupPaths.directory())
            guard let activation = try store.activation() else {
                // Ordinary installations retain the legacy LocalGo handoff.
                try consumeLegacySetupHandoff()
                return
            }

            // A formal activation owns pairing and support resolution. Validate
            // the pointer and its bounded receipt history through Core before
            // deciding that legacy setup is unavailable. Never consume or
            // prepare the unrelated LocalGo file on this path.
            guard let activeSetupID = activation.activeSetupID,
                  let activeReceipt = activation.receipts.first(where: { $0.setupID == activeSetupID }),
                  try store.activeSupportDirectory(method: activeReceipt.method) != nil else {
                throw DeviceServiceFailure.devicePreparationRequired
            }
            return
        } catch let failure as DeviceServiceFailure {
            throw failure
        } catch {
            // Once formal state exists, malformed, unsafe, or incomplete
            // activation must block setup rather than fall through to legacy.
            throw DeviceServiceFailure.devicePreparationRequired
        }
    }

    private static func consumeLegacySetupHandoff() throws {
        let handoff = LocalGoSetupHandoff(importSetupData: {
            try PairingFileStore.importSetupData($0, expectedDeviceUDID: $1)
        })
        do { try handoff.prepare() } catch { throw DeviceServiceFailure.storageUnavailable }
        switch handoff.consume(commandsIdle: true, isPreparing: false) {
        case .noPayload, .imported: break
        case .rejected: throw DeviceServiceFailure.pairingRequired
        case .storageFailure: throw DeviceServiceFailure.storageUnavailable
        }
    }

    private static func makeSession() throws -> OwnedSession {
        let path = PairingFileStore.prepareURL()
        guard let expected = PairingFileStore.expectedDeviceUDID,
              PairingFileStore.verifyStoredRecord(expectedDeviceUDID: expected) else {
            throw DeviceServiceFailure.pairingRequired
        }
        let session = try NativeDeviceSession(pairingURL: path)
        return OwnedSession(native: session, verified: VerifiedDeviceSession(session: session, expectedIdentifier: expected))
    }
}

#else

final class NativeDeviceService: DeviceService, @unchecked Sendable {
    init() {}
    func prepare() async throws {
        await delayPreparationForUITest()
        throw DeviceServiceFailure.deviceRequired
    }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        await delayPreparationForUITest()
        return .notSent(.deviceRequired)
    }
    private func delayPreparationForUITest() async {
        #if DEBUG
        // Delay only the simulator's existing real failure; never claim the
        // dispatch gate or invent an acknowledged device operation.
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-preparation-delay") {
            try? await Task.sleep(for: .seconds(2))
        }
        #endif
    }
    func clearLocation() async throws { throw DeviceServiceFailure.deviceRequired }
    func resetClientConnection() async throws { throw DeviceServiceFailure.deviceRequired }
}

#endif
