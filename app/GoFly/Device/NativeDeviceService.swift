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
    private var sessionLastActivityAt: UInt64?
    private static let maximumIdleSessionNanoseconds: UInt64 = 30_000_000_000
    private static let pointOperationBudgetNanoseconds: UInt64 = 20_000_000_000

    init() {}

    func prepare() async throws {
        try await perform("prepare") {
            self.discardSessionIfIdle()
            if let owned = self.ownedSession {
                Self.recordSession("reused", age: self.sessionAgeMilliseconds())
                do {
                    try owned.verified.prepare()
                } catch {
                    let failure = Self.failure(error)
                    var suspect = owned
                    suspect.isPrepared = false
                    let retention = NativeSessionRetentionPolicy().retention(
                        afterPreparationFailure: failure, sessionWasOwned: true)
                    self.apply(retention, to: suspect, wasOwned: true)
                    throw failure
                }
                self.ownedSession = OwnedSession(native: owned.native, verified: owned.verified, isPrepared: true)
                self.sessionLastActivityAt = DispatchTime.now().uptimeNanoseconds
                return
            }
            try Self.consumeSetupHandoff()
            let fresh = try Self.makeSession()
            self.sessionCreatedAt = DispatchTime.now().uptimeNanoseconds
            Self.recordSession("created", age: 0)
            do {
                try fresh.verified.prepare()
                self.ownedSession = OwnedSession(native: fresh.native, verified: fresh.verified, isPrepared: true)
                self.sessionLastActivityAt = DispatchTime.now().uptimeNanoseconds
            } catch {
                let failure = Self.failure(error)
                self.apply(NativeSessionRetentionPolicy().retention(
                    afterPreparationFailure: failure, sessionWasOwned: false),
                    to: fresh, wasOwned: false)
                throw failure
            }
        }
    }

    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                // One deadline covers the first attempt and the one permitted
                // repair. It is deliberately shorter than the outer service
                // watchdog so an adapter timeout can still return cleanly.
                let deadline = DispatchTime.now().uptimeNanoseconds &+
                    Self.pointOperationBudgetNanoseconds
                let policy = NativeSessionRetentionPolicy()
                let first = self.movePointAttempt(to: coordinate, dispatch: dispatch,
                                                  deadline: deadline, recovering: false)
                let gateAvailable: Bool
                if case .available = dispatch.state { gateAvailable = true } else { gateAvailable = false }
                if case .notSent(let failure) = first,
                   policy.shouldRetryBeforeDispatch(after: failure), gateAvailable {
                    Diagnostics.shared.record("device.session.repair", category: .device, level: .notice, [
                        "reason": .text(failure.rawValue), "attempt": .count(2)
                    ])
                    continuation.resume(returning: self.movePointAttempt(
                        to: coordinate, dispatch: dispatch, deadline: deadline, recovering: false))
                    return
                }
                if case .unconfirmed(let failure) = first,
                   policy.shouldRetryAfterDispatch(after: failure) {
                    guard dispatch.canAttemptRecovery else {
                        Self.recordRecovery("aborted", reason: "gate")
                        continuation.resume(returning: first)
                        return
                    }
                    Self.recordRecovery("repair", reason: failure.rawValue)
                    let repaired = self.movePointAttempt(to: coordinate, dispatch: dispatch,
                                                         deadline: deadline, recovering: true)
                    if repaired == .acknowledged {
                        Self.recordRecovery("recovered", reason: failure.rawValue)
                        continuation.resume(returning: repaired)
                    } else {
                        Self.recordRecovery("aborted", reason: Self.outcomeReason(repaired))
                        // The original write crossed the gate. A failed repair
                        // cannot turn its delivery uncertainty into a new
                        // outcome.
                        continuation.resume(returning: first)
                    }
                    return
                }
                continuation.resume(returning: first)
            }
        }
    }

    /// Shared by teleport, route, and joystick/wander movement. The recovery
    /// flag selects the same-coordinate write after the original gate claim.
    private func movePointAttempt(to coordinate: GeoCoordinate,
                                  dispatch: PointDispatchGate,
                                  deadline: UInt64,
                                  recovering: Bool) -> PointDeliveryOutcome {
        if recovering {
            guard dispatch.hasDispatched else { return .notSent(.operationCancelled) }
        } else {
            guard case .available = dispatch.state else { return .notSent(.operationCancelled) }
        }
        discardSessionIfIdle()
        tickSequence &+= 1
        let sequence = tickSequence
        let tickStarted = DispatchTime.now().uptimeNanoseconds
        let wasOwned = ownedSession != nil
        var candidate: OwnedSession
        do {
            if let owned = ownedSession {
                Self.recordSession("reused", age: sessionAgeMilliseconds())
                candidate = owned
            } else {
                try Self.consumeSetupHandoff()
                candidate = try Self.makeSession(deadline: deadline)
                sessionCreatedAt = DispatchTime.now().uptimeNanoseconds
                Self.recordSession("created", age: 0)
            }
        } catch {
            let failure = Self.failure(error)
            recordTick(nil, sequence: sequence, outcome: .notSent(failure),
                       reused: wasOwned, startedAt: tickStarted, stage: "session")
            return .notSent(failure)
        }

        candidate.native.setOperationDeadline(deadline)
        defer { candidate.native.setOperationDeadline(nil) }
        candidate.native.beginTrace()
        if !candidate.isPrepared {
            do {
                try candidate.verified.prepare()
                candidate.isPrepared = true
            } catch {
                let failure = Self.failure(error)
                let trace = candidate.native.endTrace()
                recordTick(trace, sequence: sequence, outcome: .notSent(failure),
                           reused: wasOwned, startedAt: tickStarted, stage: "prepare")
                candidate.isPrepared = false
                apply(NativeSessionRetentionPolicy().retention(afterPreparationFailure: failure,
                                                               sessionWasOwned: wasOwned),
                      to: candidate, wasOwned: wasOwned)
                return .notSent(failure)
            }
        }

        // VerifiedDeviceSession checks this session's device identity, then
        // atomically claims the gate immediately before set.
        let outcome = candidate.verified.movePoint(to: coordinate, dispatch: dispatch,
                                                   recovering: recovering)
        let trace = candidate.native.endTrace()
        recordTick(trace, sequence: sequence, outcome: outcome,
                   reused: wasOwned, startedAt: tickStarted, stage: "dispatch")
        let retention = NativeSessionRetentionPolicy().retention(after: outcome, sessionWasOwned: wasOwned)
        apply(retention, to: candidate, wasOwned: wasOwned)
        if retention == .reuse { sessionLastActivityAt = DispatchTime.now().uptimeNanoseconds }
        return outcome
    }

    private func discardSessionIfIdle() {
        guard let session = ownedSession,
              NativeSessionRetentionPolicy().sessionHasExpired(
                lastActivityNanoseconds: sessionLastActivityAt,
                nowNanoseconds: DispatchTime.now().uptimeNanoseconds,
                maximumIdleNanoseconds: Self.maximumIdleSessionNanoseconds) else { return }
        Diagnostics.shared.record("device.session.repair", category: .device, level: .notice, [
            "reason": .text("idle"),
            "idle_ms": .milliseconds(Double(Self.maximumIdleSessionNanoseconds / 1_000_000))
        ])
        session.native.close()
        ownedSession = nil
        sessionCreatedAt = nil
        sessionLastActivityAt = nil
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
                self.sessionLastActivityAt = nil
            }
            session.native.beginTrace()
            let started = DispatchTime.now().uptimeNanoseconds
            do {
                try session.verified.clearLocation()
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
            self.ownedSession?.native.close()
            self.ownedSession = nil
            self.sessionCreatedAt = nil
            self.sessionLastActivityAt = nil
            try TunnelProbe.run()
        }
    }

    func resetClientConnection() async throws {
        try await perform("reset") {
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

    /// Apply the shared retention decision on the native queue, closing suspect
    /// handles before any caller can start another operation.
    private func apply(_ retention: NativeSessionRetention, to candidate: OwnedSession, wasOwned: Bool) {
        switch retention {
        case .reuse:
            ownedSession = candidate
        case .rebuild:
            candidate.native.close()
            ownedSession = nil
            sessionCreatedAt = nil
            sessionLastActivityAt = nil
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

    private static func recordRecovery(_ event: String, reason: String) {
        Diagnostics.shared.record("device.session.recovery", category: .device, level: .notice, [
            "event": .text(event), "reason": .text(reason)
        ])
    }

    private static func outcomeReason(_ outcome: PointDeliveryOutcome) -> String {
        switch outcome {
        case .acknowledged: return "acknowledged"
        case .notSent(let failure): return "notSent.\(failure.rawValue)"
        case .unconfirmed(let failure): return "unconfirmed.\(failure.rawValue)"
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
