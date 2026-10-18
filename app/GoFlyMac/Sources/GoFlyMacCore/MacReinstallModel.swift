import Foundation
import Observation

@MainActor @Observable
public final class MacReinstallModel {
    public private(set) var continuation: MacReinstallContinuation?
    public private(set) var snapshot: MacReinstallPayload?
    public private(set) var progressStage: MacReinstallStage?
    public private(set) var failure: MacReinstallFailure?
    public private(set) var isBusy = false
    public private(set) var cancellationRequested = false
    public private(set) var isRestored = false
    public private(set) var options: MacReinstallOptions?
    @ObservationIgnored private let runner: any MacReinstallRunning
    @ObservationIgnored private let journal: any MacReinstallJournalReading
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var journalIdentity: MacReinstallContinuation?
    @ObservationIgnored private var previousTerminalIdentity: MacReinstallContinuation?
    @ObservationIgnored private var journalBlocked = false

    public init(runner: any MacReinstallRunning, journal: any MacReinstallJournalReading) {
        self.runner = runner
        self.journal = journal
    }

    public var hasRecordedTransaction: Bool { journalIdentity != nil }
    public var locksDevice: Bool {
        isBusy || journalBlocked || (journalIdentity != nil && !isTerminal)
    }
    public var canApply: Bool {
        isRestored && !isBusy && !journalBlocked && journalIdentity == nil && options != nil &&
        snapshot?.stage == .preflight && snapshot?.outcome == .ready && failure == nil
    }
    public var canResume: Bool {
        isRestored && !isBusy && !journalBlocked && journalIdentity != nil && snapshot?.canResume == true
    }
    public var canStatus: Bool { isRestored && !isBusy && !journalBlocked && journalIdentity != nil }
    public var canAbandon: Bool {
        isRestored && !isBusy && !journalBlocked && journalIdentity != nil && snapshot?.canAbandon == true
    }
    private var isTerminal: Bool { snapshot?.isComplete == true || snapshot?.isAbandoned == true }

    public func restore() async {
        guard !isRestored, !isBusy else { return }
        isBusy = true
        do {
            journalIdentity = try await journal.readContinuation()
            continuation = journalIdentity
        } catch {
            journalBlocked = true
            failure = .invalidResponse
        }
        isRestored = true
        isBusy = false
    }

    public func configure(deviceID: String, options: MacReinstallOptions) throws {
        guard isRestored, !isBusy, !journalBlocked else { throw MacReinstallFailure.invalidResponse }
        guard journalIdentity == nil else { throw MacReinstallFailure.service("transaction-conflict") }
        continuation = try MacReinstallContinuation(transferID: UUID(), deviceID: deviceID, categories: options.categories)
        self.options = options
        snapshot = nil
        progressStage = nil
        failure = nil
    }

    public func resetSelection() {
        guard isRestored, !isBusy, !journalBlocked, journalIdentity == nil || isTerminal else { return }
        if let journalIdentity { previousTerminalIdentity = journalIdentity }
        journalIdentity = nil
        continuation = nil
        options = nil
        snapshot = nil
        progressStage = nil
        failure = nil
    }

    public func preflight() { if journalIdentity == nil, options != nil { start(.preflight) } }
    public func apply() { if canApply { start(.apply) } }
    public func status() { if journalIdentity != nil { start(.status) } }
    public func resume() { if canResume { start(.resume) } }
    public func abandon() { if canAbandon { start(.abandon) } }

    public func cancel() {
        guard isBusy, let task else { return }
        cancellationRequested = true
        task.cancel()
        progressTask?.cancel()
        // Cancellation only asks the running process to stop. Admission stays
        // closed until the operation and every progress observation return.
    }

    private func start(_ action: MacReinstallAction) {
        guard isRestored, !isBusy, !journalBlocked, let identity = continuation else { return }
        let request: MacReinstallRequest
        do {
            request = try MacReinstallRequest(action: action, transferID: identity.transferID,
                deviceID: identity.deviceID, options: action == .preflight || action == .apply ? options : nil)
        } catch {
            failure = .invalidRequest
            return
        }
        isBusy = true
        cancellationRequested = false
        snapshot = nil
        progressStage = nil
        failure = nil
        if action == .apply || action == .resume || action == .abandon {
            progressTask = Task { await observeProgress(identity) }
        }
        task = Task {
            var observed: MacReinstallPayload?
            var operationFailure: MacReinstallFailure?
            do {
                let raw = try await runner.run(request)
                try Task.checkCancellation()
                observed = try MacReinstallResponseDecoder.decode(raw, for: request, selectedCategories: identity.categories)
                operationFailure = observed?.errorCode.map(MacReinstallFailure.service)
            } catch {
                operationFailure = Task.isCancelled ? .cancelled : (error as? MacReinstallFailure ?? .invalidResponse)
            }
            let observing = progressTask
            observing?.cancel()
            await observing?.value
            progressTask = nil
            if action != .preflight || cancellationRequested {
                do {
                    let actual = try await journal.readContinuation()
                    guard actual != nil || journalIdentity == nil else {
                        throw MacReinstallFailure.invalidResponse
                    }
                    if let actual, actual != identity {
                        guard actual == previousTerminalIdentity else { throw MacReinstallFailure.invalidResponse }
                        journalIdentity = actual
                        continuation = actual
                        options = nil
                        observed = nil
                        operationFailure = .service("transaction-conflict")
                    } else {
                        if let observed, actual == nil {
                            guard action == .apply, observed.errorCode != nil,
                                  observed.stage == .preflight, !observed.proof.backupValidated,
                                  !observed.proof.sourceSealed, !observed.proof.removalConfirmed,
                                  !observed.proof.installationConfirmed else {
                                throw MacReinstallFailure.invalidResponse
                            }
                        }
                        journalIdentity = actual
                        if actual != nil { options = nil; previousTerminalIdentity = nil }
                    }
                } catch {
                    journalBlocked = true
                    observed = nil
                    operationFailure = .invalidResponse
                }
            }
            if cancellationRequested {
                observed = nil
                if !journalBlocked { operationFailure = .cancelled }
            }
            snapshot = observed
            progressStage = nil
            failure = operationFailure
            cancellationRequested = false
            isBusy = false
            task = nil
        }
    }

    private func observeProgress(_ identity: MacReinstallContinuation) async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            do {
                guard !Task.isCancelled, try await journal.readContinuation() == identity else { continue }
                let request = try MacReinstallRequest(action: .status, transferID: identity.transferID, deviceID: identity.deviceID)
                let raw = try await runner.run(request)
                let observed = try MacReinstallResponseDecoder.decode(raw, for: request, selectedCategories: identity.categories)
                guard !Task.isCancelled, isBusy, continuation == identity else { return }
                progressStage = observed.stage
            } catch {
                if Task.isCancelled { return }
                progressStage = nil
            }
        }
    }
}
