import Foundation
import Observation

public struct MacSetupContinuation: Equatable, Sendable {
    public let setupID: UUID
    public let deviceID: String
    public let mode: MacSetupMode

    public init(setupID: UUID, deviceID: String, mode: MacSetupMode = .install) throws {
        let normalized = deviceID.lowercased()
        guard setupFullMatch(normalized, "^(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})$") else {
            throw MacSetupFailure.invalidResponse
        }
        self.setupID = setupID
        self.deviceID = normalized
        self.mode = mode
    }
}

public protocol MacSetupJournalReading: Sendable {
    func readContinuation() async throws -> MacSetupContinuation?
}


@MainActor @Observable
public final class MacSetupModel {
    public private(set) var continuation: MacSetupContinuation?
    public private(set) var snapshot: MacSetupSnapshot?
    public private(set) var progressStage: MacSetupStage?
    public private(set) var failure: MacSetupFailure?
    public private(set) var isBusy = false
    public private(set) var cancellationRequested = false
    public private(set) var isRestored = false
    public private(set) var options: MacSetupOptions?
    public private(set) var mode: MacSetupMode = .install
    @ObservationIgnored private var applyAfterPreflight = false
    @ObservationIgnored private let runner: any MacSetupRunning
    @ObservationIgnored private let journal: any MacSetupJournalReading
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var journalBlocked = false
    @ObservationIgnored private var journalIdentity: MacSetupContinuation?
    @ObservationIgnored private var previousCompletedIdentity: MacSetupContinuation?

    public init(runner: any MacSetupRunning, journal: any MacSetupJournalReading) {
        self.runner = runner
        self.journal = journal
    }

    public var canApply: Bool {
        isRestored && !isBusy && !journalBlocked && journalIdentity == nil && options != nil &&
            snapshot?.stage == .preflight && snapshot?.outcome == .ready && failure == nil
    }
    public var canResume: Bool {
        isRestored && !isBusy && !journalBlocked && journalIdentity != nil && snapshot?.canResume == true
    }
    public var hasRecordedTransaction: Bool { journalIdentity != nil }
    public var locksDevice: Bool { isBusy || journalBlocked || (journalIdentity != nil && snapshot?.isComplete != true) }

    public func resetSelection() {
        guard isRestored, !isBusy, !journalBlocked,
              journalIdentity == nil || snapshot?.isComplete == true else { return }
        if let journalIdentity { previousCompletedIdentity = journalIdentity }
        journalIdentity = nil
        // Retire only the completed UI projection. The producer alone may
        // archive a fully validated completed journal under its global lock.
        continuation = nil
        options = nil
        snapshot = nil
        progressStage = nil
        failure = nil
        mode = .install
        applyAfterPreflight = false
    }
    public func restore() async {
        guard !isRestored, !isBusy else { return }
        isBusy = true
        await readJournal()
        isRestored = true
        isBusy = false
    }
    public func configure(deviceID: String, options: MacSetupOptions, mode: MacSetupMode = .install) throws {
        guard isRestored, !isBusy, !journalBlocked else { throw MacSetupFailure.invalidResponse }
        guard journalIdentity == nil else { throw MacSetupFailure.service("transaction-conflict") }
        continuation = try MacSetupContinuation(setupID: UUID(), deviceID: deviceID, mode: mode)
        self.options = options
        self.mode = mode
        snapshot = nil
        progressStage = nil
        failure = nil
    }
    public func preflight() {
        guard journalIdentity == nil, options != nil else { return }
        applyAfterPreflight = mode == .renew
        start(.preflight)
    }
    public func beginRenew(deviceID: String, options: MacSetupOptions) throws {
        if snapshot?.isComplete == true { resetSelection() }
        try configure(deviceID: deviceID, options: options, mode: .renew)
        preflight()
    }
    public func apply() {
        guard canApply else { return }
        start(.apply)
    }
    public func status() {
        guard journalIdentity != nil else { return }
        start(.status)
    }
    public func resume() {
        guard canResume else { return }
        start(.resume)
    }
    public func cancel() {
        guard isBusy, let task else { return }
        cancellationRequested = true
        task.cancel()
        progressTask?.cancel()
        // Keep both the task and admission fence until the process has returned.
    }

    private func start(_ action: MacSetupAction) {
        guard isRestored, !isBusy, !journalBlocked, let identity = continuation else { return }
        let request: MacSetupRequest
        do {
            request = try MacSetupRequest(action: action, setupID: identity.setupID, deviceID: identity.deviceID,
                                          mode: mode,
                                          options: action == .preflight || action == .apply ? options : nil)
        } catch {
            failure = error as? MacSetupFailure ?? .invalidRequest
            return
        }
        isBusy = true
        cancellationRequested = false
        snapshot = nil
        progressStage = nil
        failure = nil
        if action == .apply || action == .resume {
            progressTask = Task { await observeProgress(identity) }
        }
        task = Task {
            var observed: MacSetupSnapshot?
            var operationFailure: MacSetupFailure?
            do {
                let data = try await runner.run(request)
                try Task.checkCancellation()
                observed = try MacSetupResponseDecoder.decode(data, for: request)
                operationFailure = observed?.failure
            } catch {
                operationFailure = Task.isCancelled ? .cancelled : (error as? MacSetupFailure ?? .invalidResponse)
            }
            let observing = progressTask
            observing?.cancel()
            await observing?.value
            progressTask = nil
            if action == .preflight, let observed, observed.stage == .preflight,
               observed.outcome == .ready, observed.errorCode == nil, applyAfterPreflight, !Task.isCancelled {
                applyAfterPreflight = false
                snapshot = observed
                isBusy = false
                task = nil
                apply()
                return
            }
            applyAfterPreflight = false
            if action != .preflight || Task.isCancelled {
                do {
                    let actual = try await journal.readContinuation()
                    if let actual, actual != identity {
                        guard actual == previousCompletedIdentity else { throw MacSetupFailure.invalidResponse }
                        // The producer did not replace the old completed journal.
                        // Rebind its actual header and require an explicit status
                        // before treating it as complete again.
                        journalIdentity = actual
                        continuation = actual
                        options = nil
                        observed = nil
                        operationFailure = .service("transaction-conflict")
                    } else {
                        if let observed, action != .preflight, actual == nil {
                            // The producer can reject apply before creating its
                            // transaction. Only that bounded error is retryable;
                            // success or evidence of a later stage without the
                            // durable journal remains an integrity failure.
                            guard action == .apply, observed.failure != nil,
                                  observed.stage == .preflight,
                                  !observed.installationConfirmed,
                                  !observed.pairingImported,
                                  !observed.supportObserved else {
                                throw MacSetupFailure.invalidResponse
                            }
                        }
                        journalIdentity = actual
                        if actual != nil { options = nil; previousCompletedIdentity = nil }
                    }
                } catch {
                    journalBlocked = true
                    observed = nil
                    operationFailure = error as? MacSetupFailure ?? .invalidResponse
                }
            }
            if cancellationRequested {
                observed = nil
                if !journalBlocked { operationFailure = .cancelled }
            }
            snapshot = observed
            progressStage = nil
            failure = operationFailure
            isBusy = false
            cancellationRequested = false
            task = nil
        }
    }

    private func observeProgress(_ identity: MacSetupContinuation) async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            do {
                guard !Task.isCancelled else { return }
                guard try await journal.readContinuation() == identity else { continue }
                let request = try MacSetupRequest(action: .status, setupID: identity.setupID,
                                                  deviceID: identity.deviceID, mode: mode)
                let data = try await runner.run(request)
                let observed = try MacSetupResponseDecoder.decode(data, for: request)
                guard !Task.isCancelled, isBusy, continuation == identity else { return }
                // A read-only journal observation supplies the stage only. It
                // cannot complete or release the still-running apply/resume.
                progressStage = observed.stage
            } catch {
                if Task.isCancelled { return }
                progressStage = nil
            }
        }
    }

    private func readJournal() async {
        do {
            journalIdentity = try await journal.readContinuation()
            continuation = journalIdentity
            mode = journalIdentity?.mode ?? .install
            options = nil
            snapshot = nil
            journalBlocked = false
        } catch {
            journalBlocked = true
            failure = error as? MacSetupFailure ?? .invalidResponse
        }
    }
}
