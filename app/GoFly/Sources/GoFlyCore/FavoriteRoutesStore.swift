import Combine
import Foundation

@MainActor
public final class FavoriteRoutesStore: ObservableObject {
    @Published public private(set) var records: [FavoriteRouteRecord] = []
    @Published public private(set) var selectedID: UUID?
    @Published public private(set) var selectedSnapshot: FavoriteRouteSnapshot?
    @Published public private(set) var isBusy = false
    @Published public private(set) var isValidatingSelection = false
    @Published public private(set) var loadState: FavoriteRoutesLoadState = .loading
    @Published public private(set) var error: FavoriteRoutesFailure?
    @Published public private(set) var canUndo = false
    private let persistence: any FavoriteRoutesPersistence
    private var selectionRevision: UInt64 = 0
    private let transferOwnerID = UUID()
    private var transferHold: TransferHold?
    /// Retained until each entered persistence or detached parse call returns.
    private var physicalOperations: Set<UUID> = []

    public init(persistence: any FavoriteRoutesPersistence) { self.persistence = persistence }
    public var canMutate: Bool { loadState == .ready && !isBusy && transferHold == nil }
    private var transferAdmissionAllowed: Bool { transferHold == nil }
    private func beginPhysicalOperation() -> UUID {
        let id = UUID(); physicalOperations.insert(id); return id
    }
    private func finishPhysicalOperation(_ id: UUID) { physicalOperations.remove(id) }

    public func acquireTransferHold() -> TransferHold? {
        guard transferHold == nil, loadState == .ready, error == nil, !isBusy,
              !isValidatingSelection, physicalOperations.isEmpty else { return nil }
        let hold = TransferHold(ownerID: transferOwnerID, tokenID: UUID())
        transferHold = hold
        return hold
    }
    @discardableResult
    public func releaseTransferHold(_ token: TransferHold) -> Bool {
        guard transferHold == token, token.ownerID == transferOwnerID,
              physicalOperations.isEmpty else { return false }
        transferHold = nil
        return true
    }
    public func transferArchive(using token: TransferHold) async throws -> TransferArchiveSnapshot {
        guard transferHold == token, token.ownerID == transferOwnerID,
              loadState == .ready, error == nil, !isBusy, !isValidatingSelection,
              physicalOperations.isEmpty else { throw FavoriteRoutesFailure.busy }
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        let snapshot = try await persistence.transferSnapshot()
        let transferred = try await Task.detached {
            try TransferArchiveCodec.favoriteRoutes(snapshot)
        }.value
        guard transferHold == token else { throw FavoriteRoutesFailure.busy }
        guard transferred == records else { throw FavoriteRoutesFailure.metadataMismatch }
        return snapshot
    }

    public func clearError() { guard transferAdmissionAllowed else { return }; error = nil }
    public func load() async {
        guard transferAdmissionAllowed, !isBusy, loadState != .ready else { return }
        isBusy = true
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        defer { isBusy = false }
        do {
            let receipt = try await persistence.read()
            guard transferHold == nil else { return }
            publish(receipt)
            loadState = .ready; error = nil
        } catch {
            let failure = FavoriteRoutesFailure.mapped(error)
            loadState = .blocked(failure); self.error = failure
        }
    }

    /// The candidate is the actual Save action's immutable value. Saving adds a
    /// record and reports the real commit; it never changes the current selection.
    public func save(_ candidate: FavoriteRouteSaveCandidate, label: String?) async -> FavoriteRouteSaveResult? {
        guard canMutate, !Task.isCancelled else { return nil }
        isBusy = true
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        let revision = selectionRevision
        defer { isBusy = false }
        do {
            let receipt = try await persistence.save(candidate, label: label)
            guard transferHold == nil else { return nil }
            publish(receipt.archive)
            if selectionRevision == revision { error = nil }
            return receipt.result
        } catch is CancellationError { return nil }
        catch { recordFailure(error, display: selectionRevision == revision); return nil }
    }

    public func select(_ id: UUID?) async {
        guard transferAdmissionAllowed else { return }
        selectionRevision &+= 1
        let revision = selectionRevision
        selectedID = id; selectedSnapshot = nil; isValidatingSelection = false
        guard let id else { return }
        guard loadState == .ready else { return }
        guard records.contains(where: { $0.id == id }) else { error = .notFound; return }
        isValidatingSelection = true
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        do {
            let snapshot = try await persistence.validate(id)
            guard transferHold == nil else { return }
            guard selectionRevision == revision, selectedID == id, records.contains(where: { $0.id == id }) else { return }
            isValidatingSelection = false
            guard !Task.isCancelled, loadState == .ready else { return }
            selectedSnapshot = snapshot; error = nil
        } catch {
            guard selectionRevision == revision, selectedID == id else { return }
            isValidatingSelection = false
            if !(error is CancellationError) { recordFailure(error, validatingPayload: true) }
        }
    }

    @discardableResult public func updateLabel(_ id: UUID, label: String?) async -> Bool {
        guard canMutate, !Task.isCancelled else { return false }
        isBusy = true
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        defer { isBusy = false }
        do {
            let receipt = try await persistence.updateLabel(id, label: label)
            guard transferHold == nil else { return false }
            publish(receipt)
            error = nil
            if selectedID == id { await select(id) }
            return true
        } catch is CancellationError { return false }
        catch { recordFailure(error); return false }
    }
    @discardableResult public func delete(_ id: UUID) async -> Bool {
        guard canMutate, !Task.isCancelled else { return false }
        isBusy = true
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        defer { isBusy = false }
        do {
            let receipt = try await persistence.delete(id)
            guard transferHold == nil else { return false }
            publish(receipt)
            if selectedID == id { await select(nil) }
            error = nil
            return true
        } catch is CancellationError { return false }
        catch { recordFailure(error); return false }
    }
    @discardableResult public func undoDelete() async -> Bool {
        guard canMutate, !Task.isCancelled else { return false }
        isBusy = true
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        defer { isBusy = false }
        do {
            let receipt = try await persistence.undoDelete()
            guard transferHold == nil else { return false }
            publish(receipt); error = nil; return true
        }
        catch is CancellationError { return false }
        catch { recordFailure(error); return false }
    }
    private func publish(_ receipt: FavoriteRoutesReceipt) { records = receipt.records; canUndo = receipt.canUndo }
    private func recordFailure(_ error: any Error, display: Bool = true, validatingPayload: Bool = false) {
        let failure = FavoriteRoutesFailure.mapped(error)
        if display { self.error = failure }
        switch failure {
        case .corruptArchive, .unsupportedSchema, .unsafeFile, .metadataMismatch, .hashMismatch:
            loadState = .blocked(failure)
        case .gpx where validatingPayload: loadState = .blocked(failure)
        default: break
        }
    }
}
