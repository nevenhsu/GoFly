import Foundation
import Observation

/// Main-actor admission for the local backup manager.  The model exposes only
/// rows returned by the actual bridge and keeps mutation admission closed until
/// the bounded process and its streams have returned.
@MainActor @Observable
public final class MacBackupModel {
    public private(set) var entries: [MacBackupEntry] = []
    public private(set) var pendingDeletion = false
    public private(set) var isBusy = false
    public private(set) var cancellationRequested = false
    public private(set) var failure: MacBackupFailure?

    @ObservationIgnored private let runner: any MacBackupRunning
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(runner: any MacBackupRunning) {
        self.runner = runner
    }

    public func list() {
        start(action: .list)
    }

    public func maintain() {
        guard !isBusy else {
            failure = .service("busy")
            return
        }
        start(action: .maintain)
    }

    public func deleteExact(_ entry: MacBackupEntry) {
        guard !isBusy else {
            failure = .service("busy")
            return
        }
        guard entry.canDelete else {
            failure = .service("backup-not-complete")
            return
        }
        start(action: .delete, transferID: entry.transferID)
    }

    public func cancel() {
        guard isBusy else { return }
        cancellationRequested = true
        task?.cancel()
        // The busy boundary remains closed until BackupProcessBridge's child
        // process and bounded stdout/stderr readers have returned.
    }

    private func start(action: MacBackupAction, transferID: UUID? = nil) {
        guard !isBusy else { failure = .service("busy"); return }
        let request: MacBackupRequest
        do {
            request = try MacBackupRequest(action: action, transferID: transferID,
                                           confirmed: action == .delete ? true : nil)
        } catch {
            failure = .invalidRequest
            return
        }
        isBusy = true
        cancellationRequested = false
        failure = nil
        task = Task { [weak self] in
            guard let self else { return }
            var observed: MacBackupPayload?
            var operationFailure: MacBackupFailure?
            do {
                let raw = try await runner.run(request)
                try Task.checkCancellation()
                observed = try MacBackupResponseDecoder.decode(raw, for: request)
            } catch {
                operationFailure = Task.isCancelled ? .cancelled : (error as? MacBackupFailure ?? .invalidResponse)
            }
            if let observed {
                entries = observed.entries
                pendingDeletion = observed.pendingDeletion
            }
            failure = operationFailure
            cancellationRequested = false
            isBusy = false
            task = nil
        }
    }
}
