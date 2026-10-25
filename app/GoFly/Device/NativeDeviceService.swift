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
        var isPrepared: Bool
    }
    private let queue = DispatchQueue(label: "com.neven.gofly.device", qos: .userInitiated)
    // Access only on queue; neither handles nor the verified wrapper escape it.
    private var ownedSession: OwnedSession?
    private var tickSequence: UInt64 = 0
    private var sessionCreatedAt: UInt64?
    private let keeper = DeviceSessionKeeper()

    init() {}

    func prepare() async throws {
        try await perform("prepare") { try self.keeper.prepare(using: self) }
    }

    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.keeper.deliver(coordinate, dispatch: dispatch, using: self))
            }
        }
    }

    func clearLocation() async throws {
        // Independent of DDI/GPS/cancellation. Never resend an uncertain clear.
        try await perform("clear") {
            let session = try self.ownedSession ?? Self.makeSession()
            defer {
                // Release only after the real clear call returns, even on error.
                session.native.close()
                self.ownedSession = nil
                self.sessionCreatedAt = nil
                self.keeper.sessionDidClose()
            }
            session.native.beginTrace()
            let started = DispatchTime.now().uptimeNanoseconds
            do {
                try session.verified.clearLocation()
                self.keeper.locationDidClear()
                self.recordTick(session.native.endTrace(), sequence: nil, outcome: .acknowledged,
                                reused: true, startedAt: started, stage: "clear")
            } catch {
                self.recordTick(session.native.endTrace(), sequence: nil,
                                outcome: .notSent(Self.failure(error)), reused: true,
                                startedAt: started, stage: "clear")
                throw error
            }
        }
    }

    func rebuildClientConnection() async throws {
        try await perform("connection.rebuild") {
            self.closeSession()
            self.keeper.sessionDidClose()
            self.keeper.reconnectWasRequested()
            try TunnelProbe.run()
        }
    }

    func resetClientConnection() async throws {
        try await perform("reset") {
            // After an acknowledged clear an owned session is only an idle
            // warmup; closing it cannot return the device to real GPS.
            if self.ownedSession != nil, !self.keeper.mayHoldSimulatedPosition {
                self.closeSession()
                self.keeper.sessionDidClose()
            }
            guard self.ownedSession == nil else {
                Diagnostics.shared.record("device.resetRejected", category: .device, level: .notice, [
                    "reason": .text("ownedSession"),
                    "session_age_ms": .milliseconds(self.sessionAgeMilliseconds())
                ])
                throw DeviceServiceFailure.serviceUnavailable
            }
            try TunnelProbe.run()
        }
    }

    private func perform(_ label: String, _ operation: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                // Never return early while an FFI call still owns handles.
                idevice_set_global_timeout(10)
                do {
                    try operation()
                    continuation.resume()
                } catch {
                    let failure = Self.failure(error)
                    Diagnostics.shared.record("device.operationFailed", category: .device, level: .notice, [
                        "op": .text(label),
                        "failure": .text(failure.rawValue)
                    ])
                    continuation.resume(throwing: failure)
                }
            }
        }
    }

    private func recordTick(_ trace: FFITrace?, sequence: UInt64?, outcome: PointDeliveryOutcome,
                            reused: Bool, startedAt: UInt64, stage: String) {
        var fields: [String: DiagnosticsField] = [
            "stage": .text(stage),
            "reused": .flag(reused),
            "session_age_ms": .milliseconds(sessionAgeMilliseconds()),
            "total_ms": .milliseconds(Double(DispatchTime.now().uptimeNanoseconds &- startedAt) / 1_000_000)
        ]
        if let sequence { fields["seq"] = .count(Int(truncatingIfNeeded: sequence)) }
        if let trace {
            fields["ffi_ms"] = .milliseconds(trace.totalMilliseconds)
            fields["calls"] = .text(trace.callsText)
            if let operation = trace.failureOperation { fields["fail_op"] = .text(operation) }
            if let code = trace.failureCode { fields["code"] = .code(code) }
            if let subcode = trace.failureSubcode { fields["subcode"] = .code(subcode) }
        }
        var level = DiagnosticsLevel.debug
        switch outcome {
        case .acknowledged:
            fields["outcome"] = .text("acked")
        case .notSent(let failure):
            fields["outcome"] = .text("notSent")
            fields["failure"] = .text(failure.rawValue)
            level = .notice
        case .unconfirmed(let failure):
            fields["outcome"] = .text("unconfirmed")
            fields["failure"] = .text(failure.rawValue)
            level = .notice
        }
        Diagnostics.shared.record("device.tick", category: .device, level: level, fields)
    }

    private func sessionAgeMilliseconds() -> Double {
        guard let sessionCreatedAt else { return 0 }
        return Double(DispatchTime.now().uptimeNanoseconds &- sessionCreatedAt) / 1_000_000
    }

    private static func recordSession(_ event: String, age: Double) {
        Diagnostics.shared.record("device.session", category: .device, level: .notice, [
            "event": .text(event),
            "age_ms": .milliseconds(age)
        ])
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

    private static func makeSession(deadline: UInt64? = nil) throws -> OwnedSession {
        let path = PairingFileStore.prepareURL()
        guard let expected = PairingFileStore.expectedDeviceUDID,
              PairingFileStore.verifyStoredRecord(expectedDeviceUDID: expected) else {
            throw DeviceServiceFailure.pairingRequired
        }
        let session = try NativeDeviceSession(pairingURL: path,
                                              operationDeadlineNanoseconds: deadline)
        return OwnedSession(native: session,
                            verified: VerifiedDeviceSession(session: session, expectedIdentifier: expected),
                            isPrepared: false)
    }
}


/// Single attempts only; `DeviceSessionKeeper` decides reuse, rebuild and
/// retries. Called only on `queue`.
extension NativeDeviceService: DeviceSessionLink {
    var ownsSession: Bool { ownedSession != nil }

    func prepareSession() throws {
        if let owned = ownedSession {
            Self.recordSession("reused", age: sessionAgeMilliseconds())
            do {
                try owned.verified.prepare()
            } catch {
                ownedSession?.isPrepared = false
                throw error
            }
            ownedSession?.isPrepared = true
            return
        }
        try Self.consumeSetupHandoff()
        let fresh = try Self.makeSession()
        sessionCreatedAt = DispatchTime.now().uptimeNanoseconds
        Self.recordSession("created", age: 0)
        ownedSession = fresh
        try fresh.verified.prepare()
        ownedSession?.isPrepared = true
    }

    func attemptPoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate,
                      recovering: Bool, deadline: UInt64) -> DeviceSessionAttempt {
        tickSequence &+= 1
        let sequence = tickSequence
        let tickStarted = DispatchTime.now().uptimeNanoseconds
        let wasOwned = ownedSession != nil
        let candidate: OwnedSession
        do {
            if let owned = ownedSession {
                Self.recordSession("reused", age: sessionAgeMilliseconds())
                candidate = owned
            } else {
                try Self.consumeSetupHandoff()
                candidate = try Self.makeSession(deadline: deadline)
                sessionCreatedAt = DispatchTime.now().uptimeNanoseconds
                Self.recordSession("created", age: 0)
                ownedSession = candidate
            }
        } catch {
            let failure = Self.failure(error)
            recordTick(nil, sequence: sequence, outcome: .notSent(failure),
                       reused: wasOwned, startedAt: tickStarted, stage: "session")
            return DeviceSessionAttempt(outcome: .notSent(failure), reachedDispatch: false)
        }

        candidate.native.setOperationDeadline(deadline)
        defer { candidate.native.setOperationDeadline(nil) }
        candidate.native.beginTrace()
        if !candidate.isPrepared {
            do {
                try candidate.verified.prepare()
                ownedSession?.isPrepared = true
            } catch {
                let failure = Self.failure(error)
                let trace = candidate.native.endTrace()
                recordTick(trace, sequence: sequence, outcome: .notSent(failure),
                           reused: wasOwned, startedAt: tickStarted, stage: "prepare")
                ownedSession?.isPrepared = false
                return DeviceSessionAttempt(outcome: .notSent(failure), reachedDispatch: false)
            }
        }

        // VerifiedDeviceSession checks this session's device identity, then
        // atomically claims the gate immediately before set.
        let outcome = candidate.verified.movePoint(to: coordinate, dispatch: dispatch,
                                                   recovering: recovering)
        let trace = candidate.native.endTrace()
        recordTick(trace, sequence: sequence, outcome: outcome,
                   reused: wasOwned, startedAt: tickStarted, stage: "dispatch")
        return DeviceSessionAttempt(outcome: outcome, reachedDispatch: true)
    }

    func closeSession() {
        ownedSession?.native.close()
        ownedSession = nil
        sessionCreatedAt = nil
    }
}

#else

final class NativeDeviceService: DeviceService, @unchecked Sendable {
    init() {}
    func prepare() async throws {
        throw DeviceServiceFailure.deviceRequired
    }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        return .notSent(.deviceRequired)
    }
    func clearLocation() async throws { throw DeviceServiceFailure.deviceRequired }
    func resetClientConnection() async throws { throw DeviceServiceFailure.deviceRequired }
}

#endif
