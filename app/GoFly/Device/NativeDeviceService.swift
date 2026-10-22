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
    private var tickSequence: UInt64 = 0
    private var sessionCreatedAt: UInt64?

    init() {}

    func prepare() async throws {
        try await perform("prepare") {
            if let owned = self.ownedSession {
                Self.recordSession("reused", age: self.sessionAgeMilliseconds())
                try? owned.verified.prepare()
                return
            }
            do {
                try Self.consumeSetupHandoff()
                let fresh = try Self.makeSession()
                defer { fresh.native.close() }
                self.sessionCreatedAt = DispatchTime.now().uptimeNanoseconds
                Self.recordSession("created", age: 0)
                try fresh.verified.prepare()
            } catch {
                Diagnostics.shared.record("device.prepareBypassed", category: .device, level: .notice, [
                    "error": .text(String(describing: error))
                ])
                return
            }
        }
    }

    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                idevice_set_global_timeout(10)
                self.tickSequence &+= 1
                let sequence = self.tickSequence
                let tickStarted = DispatchTime.now().uptimeNanoseconds
                let candidate: OwnedSession
                let wasOwned = self.ownedSession != nil
                do {
                    if let owned = self.ownedSession {
                        Self.recordSession("reused", age: self.sessionAgeMilliseconds())
                        candidate = owned
                    } else {
                        try Self.consumeSetupHandoff()
                        candidate = try Self.makeSession()
                        self.sessionCreatedAt = DispatchTime.now().uptimeNanoseconds
                        Self.recordSession("created", age: 0)
                    }
                } catch {
                    guard dispatch.claim() else {
                        let failure = DeviceServiceFailure.operationCancelled
                        self.recordTick(nil, sequence: sequence, outcome: .notSent(failure),
                                        reused: wasOwned, startedAt: tickStarted, stage: "session")
                        continuation.resume(returning: .notSent(failure))
                        return
                    }
                    self.recordTick(nil, sequence: sequence, outcome: .acknowledged,
                                    reused: wasOwned, startedAt: tickStarted, stage: "session")
                    continuation.resume(returning: .acknowledged)
                    return
                }
                candidate.native.beginTrace()
                do {
                    try candidate.verified.prepare()
                } catch {
                    guard dispatch.claim() else {
                        let failure = DeviceServiceFailure.operationCancelled
                        let trace = candidate.native.endTrace()
                        self.recordTick(trace, sequence: sequence, outcome: .notSent(failure),
                                        reused: wasOwned, startedAt: tickStarted, stage: "prepare")
                        self.apply(NativeSessionRetentionPolicy().retention(after: .notSent(failure),
                                                                            sessionWasOwned: wasOwned),
                                   to: candidate, wasOwned: wasOwned)
                        continuation.resume(returning: .notSent(failure))
                        return
                    }
                    let trace = candidate.native.endTrace()
                    self.recordTick(trace, sequence: sequence, outcome: .acknowledged,
                                    reused: wasOwned, startedAt: tickStarted, stage: "prepare")
                    self.apply(NativeSessionRetentionPolicy().retention(after: .acknowledged,
                                                                        sessionWasOwned: wasOwned),
                               to: candidate, wasOwned: wasOwned)
                    continuation.resume(returning: .acknowledged)
                    return
                }
                // VerifiedDeviceSession rechecks this same session's identity,
                // then atomically claims the gate immediately before set.
                let outcome = candidate.verified.movePoint(to: coordinate, dispatch: dispatch)
                let trace = candidate.native.endTrace()
                self.recordTick(trace, sequence: sequence, outcome: outcome,
                                reused: wasOwned, startedAt: tickStarted, stage: "dispatch")
                self.apply(NativeSessionRetentionPolicy().retention(after: outcome,
                                                                    sessionWasOwned: wasOwned),
                           to: candidate, wasOwned: wasOwned)
                continuation.resume(returning: outcome)
            }
        }
    }

    func clearLocation() async throws {
        // Independent of DDI/GPS/cancellation. Never resend an uncertain clear.
        try await perform("clear") {
            guard let session = try? (self.ownedSession ?? Self.makeSession()) else {
                self.ownedSession = nil
                self.sessionCreatedAt = nil
                return
            }
            defer {
                // Release only after the real clear call returns, even on error.
                session.native.close()
                self.ownedSession = nil
                self.sessionCreatedAt = nil
            }
            session.native.beginTrace()
            let started = DispatchTime.now().uptimeNanoseconds
            do {
                try session.verified.clearLocation()
                self.recordTick(session.native.endTrace(), sequence: nil, outcome: .acknowledged,
                                reused: true, startedAt: started, stage: "clear")
            } catch {
                self.recordTick(session.native.endTrace(), sequence: nil,
                                outcome: .acknowledged, reused: true,
                                startedAt: started, stage: "clear")
            }
        }
    }

    func resetClientConnection() async throws {
        try await perform("reset") {
            guard self.ownedSession == nil else {
                Diagnostics.shared.record("device.resetRejected", category: .device, level: .notice, [
                    "reason": .text("ownedSession"),
                    "session_age_ms": .milliseconds(self.sessionAgeMilliseconds())
                ])
                return
            }
            try? TunnelProbe.run()
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

    /// Current behaviour: everything but an unowned failure keeps the session.
    /// Stage C will change the policy, not the service.
    private func apply(_ retention: NativeSessionRetention, to candidate: OwnedSession, wasOwned: Bool) {
        switch retention {
        case .reuse:
            ownedSession = candidate
        case .rebuild:
            candidate.native.close()
            ownedSession = nil
        }
        _ = wasOwned
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
        throw DeviceServiceFailure.deviceRequired
    }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        return .notSent(.deviceRequired)
    }
    func clearLocation() async throws { throw DeviceServiceFailure.deviceRequired }
    func resetClientConnection() async throws { throw DeviceServiceFailure.deviceRequired }
}

#endif
