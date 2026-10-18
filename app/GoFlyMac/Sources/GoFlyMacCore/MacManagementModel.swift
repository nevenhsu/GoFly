import Foundation
import Observation

public protocol MacManagementRunning: Sendable {
    func run(_ request: MacManagementRequest) async throws -> Data
}

@MainActor @Observable
public final class MacManagementModel {
    public private(set) var continuation: MacManagementContinuation?
    public private(set) var snapshot: MacManagementPayload?
    public private(set) var progressStage: MacManagementStage?
    public private(set) var failure: MacManagementFailure?
    public private(set) var isBusy = false
    public private(set) var cancellationRequested = false
    public private(set) var isRestored = false
    public private(set) var options: MacManagementOptions?

    @ObservationIgnored private let runner: any MacManagementRunning
    @ObservationIgnored private let journal: any MacManagementJournalReading
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var automaticTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var journalIdentity: MacManagementContinuation?
    @ObservationIgnored private var previousTerminalIdentity: MacManagementContinuation?
    @ObservationIgnored private var journalBlocked = false

    public init(runner: any MacManagementRunning, journal: any MacManagementJournalReading) {
        self.runner = runner
        self.journal = journal
    }

    public var hasRecordedTransaction: Bool { journalIdentity != nil }

    public var locksDevice: Bool {
        isBusy || journalBlocked || (journalIdentity != nil && !isTerminal)
    }

    public var canApply: Bool {
        isRestored && !isBusy && !journalBlocked && journalIdentity == nil && continuation != nil &&
            snapshot?.stage == .preflight && snapshot?.outcome == .ready && failure == nil
    }

    public var canResume: Bool {
        isRestored && !isBusy && !journalBlocked && journalIdentity != nil &&
            snapshot?.canResume == true && !isTerminal
    }

    public var canQuery: Bool {
        isRestored && !isBusy && !journalBlocked && journalIdentity != nil
    }

    public var canRelease: Bool {
        isRestored && !isBusy && !journalBlocked && journalIdentity != nil &&
            snapshot?.canRelease == true &&
            (snapshot?.stage == .artifact || snapshot?.stage == .source) &&
            snapshot?.proof.mutationSealed == false &&
            snapshot?.proof.updateConfirmed == false &&
            snapshot?.proof.pairingImported == false &&
            snapshot?.proof.adoptionCommitted == false &&
            snapshot?.adoptionReceipt == nil
    }

    public func restore() async {
        guard !isRestored, !isBusy else { return }
        isBusy = true
        do {
            let actual = try await journal.readContinuation()
            journalIdentity = actual
            continuation = actual
            options = actual?.options
            journalBlocked = false
        } catch {
            journalBlocked = true
            failure = error as? MacManagementFailure ?? .invalidResponse
        }
        isRestored = true
        isBusy = false
        if cancellationRequested || Task.isCancelled {
            if !journalBlocked { failure = .cancelled }
            cancellationRequested = false
            return
        }

        // Query is a pure journal/status operation in protocol 5.  Restoring
        // an existing transaction therefore does not initiate a device action.
        if journalIdentity != nil, !journalBlocked {
            start(.query, resumeSelection: nil)
            let restoring = task
            await withTaskCancellationHandler(operation: {
                await restoring?.value
            }, onCancel: { restoring?.cancel() })
        }
    }

    public func configure(deviceID: String, kind: MacManagementKind,
                          selection: MacManagementSelection,
                          options: MacManagementOptions? = nil) throws {
        guard isRestored, !isBusy, !journalBlocked else {
            throw MacManagementFailure.invalidResponse
        }
        guard journalIdentity == nil else {
            throw MacManagementFailure.service("transaction-conflict")
        }
        try configureUnchecked(deviceID: deviceID, kind: kind, selection: selection,
                               options: options)
    }

    public func resetSelection() {
        guard isRestored, !isBusy, !journalBlocked,
              journalIdentity == nil || isTerminal else { return }
        if let journalIdentity { previousTerminalIdentity = journalIdentity }
        journalIdentity = nil
        continuation = nil
        options = nil
        snapshot = nil
        progressStage = nil
        failure = nil
    }

    public func preflight() {
        guard continuation != nil, journalIdentity == nil, !isBusy, !journalBlocked else { return }
        start(.preflight, resumeSelection: nil)
    }

    public func apply() {
        guard canApply else { return }
        start(.apply, resumeSelection: nil)
    }

    public func query() {
        guard canQuery else { return }
        start(.query, resumeSelection: nil)
    }

    public func resume(using selection: MacManagementSelection? = nil) {
        guard canResume else { return }
        start(.resume, resumeSelection: selection)
    }

    public func release() {
        guard canRelease else { return }
        start(.release, resumeSelection: nil)
    }

    public func cancel() {
        guard isBusy else { return }
        cancellationRequested = true
        task?.cancel()
        automaticTask?.cancel()
        progressTask?.cancel()
        // Admission remains closed until the process and every read-only
        // progress query have returned.
    }

    /// Starts the one-shot automatic renew flow after the caller has made an
    /// explicit selection.  The journal lookup is durable duplicate
    /// suppression; transport authentication remains the bridge's job.
    public func automaticRenew(deviceID: String, selection: MacManagementSelection,
                               options: MacManagementOptions) async {
        guard isRestored, !isBusy, !journalBlocked else { return }
        // Claim model admission synchronously.  The durable lookup below is
        // the first suspension point, so a second event cannot enter before
        // this flow owns the model.
        isBusy = true
        cancellationRequested = false
        let operation = Task { await runAutomaticRenew(deviceID: deviceID, selection: selection,
                                                        options: options) }
        automaticTask = operation
        await withTaskCancellationHandler(operation: {
            await operation.value
        }, onCancel: {
            operation.cancel()
        })
    }

    private func runAutomaticRenew(deviceID: String, selection: MacManagementSelection,
                                   options: MacManagementOptions) async {
        guard isRestored, !journalBlocked else {
            isBusy = false
            automaticTask = nil
            return
        }
        defer {
            isBusy = false
            cancellationRequested = false
            automaticTask = nil
        }
        do {
            if let consumed = try await journal.findSelection(selection.selectionID) {
                // A repeated event for the current transaction resolves by
                // querying that transaction.  A historical match is a
                // consumed identity and cannot start a new operation.
                let actual = try await journal.readContinuation()
                try Task.checkCancellation()
                if let actual, sameOperation(actual, consumed),
                   actual.deviceID == deviceID.lowercased(), actual.kind == .renew,
                   actual.options == options {
                    journalIdentity = actual
                    continuation = actual
                    self.options = actual.options
                    await execute(.query, resumeSelection: nil, admissionHeld: true)
                    return
                }
                journalBlocked = true
                failure = .service("transaction-conflict")
                return
            }
            try Task.checkCancellation()
            try configureUnchecked(deviceID: deviceID, kind: .renew, selection: selection, options: options)
            await execute(.preflight, resumeSelection: nil, admissionHeld: true)
            guard failure == nil, snapshot?.stage == .preflight,
                  snapshot?.outcome == .ready else { return }
            await execute(.apply, resumeSelection: nil, admissionHeld: true)
        } catch {
            failure = Task.isCancelled ? .cancelled : (error as? MacManagementFailure ?? .invalidRequest)
        }
    }

    private var isTerminal: Bool {
        guard let snapshot else { return false }
        if snapshot.isComplete { return true }
        return snapshot.stage == .release && snapshot.outcome == .confirmed &&
            !snapshot.canResume && !snapshot.canRelease
    }

    private func start(_ action: MacManagementAction, resumeSelection: MacManagementSelection?) {
        guard task == nil, isRestored, !isBusy, !journalBlocked, continuation != nil else { return }
        isBusy = true
        cancellationRequested = false
        task = Task {
            defer { isBusy = false; cancellationRequested = false }
            await execute(action, resumeSelection: resumeSelection, admissionHeld: true)
        }
    }

    private func configureUnchecked(deviceID: String, kind: MacManagementKind,
                                    selection: MacManagementSelection,
                                    options: MacManagementOptions?) throws {
        let identity = try MacManagementContinuation(
            managementID: UUID(), deviceID: deviceID, selectionID: selection.selectionID,
            kind: kind, initialTransport: selection.transport, connectionRevision: 0,
            currentTransport: selection.transport, options: options)
        continuation = identity
        self.options = options
        snapshot = nil
        progressStage = nil
        failure = nil
    }

    private func execute(_ action: MacManagementAction,
                         resumeSelection: MacManagementSelection?, admissionHeld: Bool) async {
        guard isRestored, !journalBlocked, let identity = continuation else {
            task = nil
            return
        }
        if !admissionHeld, isBusy { task = nil; return }
        if action == .preflight || action == .apply {
            guard journalIdentity == nil else { task = nil; return }
        } else {
            guard journalIdentity != nil else { task = nil; return }
        }

        let request: MacManagementRequest
        do {
            request = try MacManagementRequest(
                action: action, managementID: identity.managementID, deviceID: identity.deviceID,
                selectionID: identity.selectionID, kind: identity.kind,
                transport: identity.initialTransport, connectionRevision: identity.connectionRevision,
                options: action == .preflight || action == .apply ? options : nil,
                resumeSelection: action == .resume ? resumeSelection : nil)
        } catch {
            failure = error as? MacManagementFailure ?? .invalidRequest
            task = nil
            return
        }

        isBusy = true
        if !admissionHeld { cancellationRequested = false }
        snapshot = nil
        progressStage = nil
        failure = nil

        var observed: MacManagementPayload?
        var operationFailure: MacManagementFailure?

        do {
            try Task.checkCancellation()
            if action == .preflight || action == .apply {
                try await checkNewOperationAdmission()
            }
            try Task.checkCancellation()
            if action == .apply || action == .resume {
                progressTask = Task { await observeProgress(identity) }
            }
            let raw = try await runner.run(request)
            try Task.checkCancellation()
            observed = try MacManagementResponseDecoder.decode(raw, for: request)
        } catch {
            if case MacManagementFailure.service("transaction-conflict") = error {
                journalBlocked = true
            }
            operationFailure = Task.isCancelled ? .cancelled :
                (error as? MacManagementFailure ?? .invalidResponse)
        }

        let observing = progressTask
        observing?.cancel()
        await observing?.value
        progressTask = nil

        let needsReadback = action != .preflight || cancellationRequested
        if needsReadback {
            do {
                let actual = try await journal.readContinuation()
                try reconcile(actual: actual, expected: identity, action: action,
                              observed: observed, operationFailure: operationFailure)
            } catch {
                journalBlocked = true
                observed = nil
                operationFailure = error as? MacManagementFailure ?? .invalidResponse
            }
        } else if let payload = observed, payload.connectionRevision != identity.connectionRevision ||
                    payload.currentTransport != identity.currentTransport {
            // Preflight cannot advance a connection revision or transport.
            operationFailure = .invalidResponse
            observed = nil
        }

        if cancellationRequested {
            observed = nil
            if !journalBlocked { operationFailure = .cancelled }
        }
        snapshot = observed
        progressStage = nil
        failure = operationFailure
        if !admissionHeld {
            isBusy = false
            cancellationRequested = false
        }
        task = nil
    }

    private func checkNewOperationAdmission() async throws {
        guard let actual = try await journal.readContinuation() else { return }
        if let previousTerminalIdentity, actual == previousTerminalIdentity {
            return
        }
        throw MacManagementFailure.service("transaction-conflict")
    }

    private func reconcile(actual: MacManagementContinuation?, expected: MacManagementContinuation,
                           action: MacManagementAction, observed: MacManagementPayload?,
                           operationFailure: MacManagementFailure?) throws {
        if let actual {
            guard sameOperation(actual, expected) else {
                if action == .apply, actual == previousTerminalIdentity {
                    journalIdentity = actual
                    continuation = actual
                    options = actual.options
                    throw MacManagementFailure.service("transaction-conflict")
                }
                throw MacManagementFailure.invalidResponse
            }
            guard actual.connectionRevision >= expected.connectionRevision else {
                throw MacManagementFailure.invalidResponse
            }
            if let observed {
                guard observed.connectionRevision == actual.connectionRevision,
                      observed.currentTransport == actual.currentTransport else {
                    throw MacManagementFailure.invalidResponse
                }
            }
            journalIdentity = actual
            continuation = actual
            options = actual.options
            previousTerminalIdentity = nil
            return
        }

        // An apply can be rejected before the producer consumes a transaction.
        // No successful payload is accepted without the corresponding header.
        if action == .preflight, observed == nil, operationFailure != nil,
           journalIdentity == nil, cancellationRequested { return }
        guard action == .apply, observed == nil, operationFailure != nil,
              operationFailure != .invalidResponse,
              journalIdentity == nil, previousTerminalIdentity == nil,
              !cancellationRequested else {
            throw MacManagementFailure.invalidResponse
        }
    }

    private func observeProgress(_ identity: MacManagementContinuation) async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            do {
                guard !Task.isCancelled, isBusy,
                      let actual = try await journal.readContinuation(),
                      sameOperation(actual, identity) else { continue }
                let request = try MacManagementRequest(
                    action: .query, managementID: actual.managementID, deviceID: actual.deviceID,
                    selectionID: actual.selectionID, kind: actual.kind,
                    transport: actual.initialTransport, connectionRevision: actual.connectionRevision)
                let raw = try await runner.run(request)
                let payload = try MacManagementResponseDecoder.decode(raw, for: request)
                guard !Task.isCancelled, isBusy,
                      let current = try await journal.readContinuation(),
                      sameOperation(current, identity),
                      payload.connectionRevision == current.connectionRevision,
                      payload.currentTransport == current.currentTransport else { continue }
                // This is display-only progress. It cannot publish completion
                // or release, and it never replaces the authoritative header.
                progressStage = payload.stage
            } catch {
                if Task.isCancelled { return }
                progressStage = nil
            }
        }
    }

    private func sameOperation(_ left: MacManagementContinuation,
                               _ right: MacManagementContinuation) -> Bool {
        left.managementID == right.managementID && left.deviceID == right.deviceID &&
            left.selectionID == right.selectionID && left.kind == right.kind &&
            left.initialTransport == right.initialTransport && left.options == right.options
    }
}
