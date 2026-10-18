import Combine
import Foundation

@MainActor
public final class ImportedRoutesStore: ObservableObject {
    @Published public private(set) var records: [ImportedRouteRecord] = []
    @Published public private(set) var selectedID: UUID?
    @Published public private(set) var selectedSnapshot: ImportedRouteSnapshot?
    @Published public private(set) var isBusy = false
    @Published public private(set) var isValidatingSelection = false
    @Published public private(set) var loadState: ImportedRoutesLoadState = .loading
    @Published public private(set) var error: ImportedRoutesFailure?
    @Published public private(set) var canUndo = false
    private let persistence: any ImportedRoutesPersistence
    private var selectionRevision: UInt64 = 0
    private let transferOwnerID = UUID()
    private var transferHold: TransferHold?
    /// IDs represent calls that have actually entered persistence/parsing.
    /// They are removed only after the physical async body has returned.
    private var physicalOperations: Set<UUID> = []

    public init(persistence: any ImportedRoutesPersistence) { self.persistence = persistence }
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
              physicalOperations.isEmpty else { throw ImportedRoutesFailure.busy }
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        let snapshot = try await persistence.transferSnapshot()
        let transferred = try await Task.detached {
            try TransferArchiveCodec.importedRoutes(snapshot)
        }.value
        guard transferHold == token else { throw ImportedRoutesFailure.busy }
        guard transferred == records else { throw ImportedRoutesFailure.metadataMismatch }
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
            loadState = .ready
            error = nil
        } catch {
            let failure = ImportedRoutesFailure.mapped(error)
            loadState = .blocked(failure); self.error = failure
        }
    }

    @discardableResult public func importData(_ data: Data, filename: String) async -> Bool {
        guard canMutate, !Task.isCancelled else { return false }
        isBusy = true
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        let selectionAtStart = selectionRevision
        defer { isBusy = false }
        do {
            let artifact = try await Task.detached {
                try Task.checkCancellation()
                return try ImportedRouteArtifact(data: data, filename: filename)
            }.value
            try Task.checkCancellation()
            guard transferHold == nil else { return false }
            let receipt = try await persistence.importArtifact(artifact)
            guard transferHold == nil else { return false }
            publish(receipt)
            if selectionRevision == selectionAtStart { error = nil }
            if selectionRevision == selectionAtStart, let record = receipt.records.last {
                let snapshot = try await Task.detached {
                    try ImportedRouteSnapshot(record: record, document: artifact.document)
                }.value
                guard transferHold == nil, selectionRevision == selectionAtStart else { return true }
                selectionRevision &+= 1
                selectedID = record.id
                selectedSnapshot = snapshot
                isValidatingSelection = false
            }
            return true
        } catch is CancellationError { return false }
        catch {
            if selectionRevision == selectionAtStart { recordFailure(error) }
            return false
        }
    }

    /// Selecting the same ID intentionally revalidates its immutable payload.
    public func select(_ id: UUID?) async {
        guard transferAdmissionAllowed else { return }
        selectionRevision &+= 1
        let revision = selectionRevision
        selectedID = id
        selectedSnapshot = nil
        isValidatingSelection = false
        guard let id else { return }
        guard records.contains(where: { $0.id == id }) else { error = .notFound; return }
        isValidatingSelection = true
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        do {
            let snapshot = try await persistence.validate(id)
            guard transferHold == nil else { return }
            guard selectionRevision == revision, selectedID == id, records.contains(where: { $0.id == id }) else { return }
            guard !Task.isCancelled else { isValidatingSelection = false; return }
            selectedSnapshot = snapshot
            isValidatingSelection = false
            error = nil
        } catch {
            guard selectionRevision == revision, selectedID == id else { return }
            isValidatingSelection = false
            recordFailure(error)
        }
    }

    @discardableResult public func delete(_ id: UUID) async -> Bool {
        guard canMutate else { return false }
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
        } catch { recordFailure(error); return false }
    }

    @discardableResult public func undoDelete() async -> Bool {
        guard canMutate else { return false }
        isBusy = true
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        defer { isBusy = false }
        do {
            let receipt = try await persistence.undoDelete()
            guard transferHold == nil else { return false }
            publish(receipt)
            error = nil
            return true
        } catch { recordFailure(error); return false }
    }

    public func exportSelected() async throws -> Data {
        guard transferAdmissionAllowed, physicalOperations.isEmpty,
              let id = selectedID, selectedSnapshot != nil, !isValidatingSelection else { throw ImportedRoutesFailure.noSelection }
        let operation = beginPhysicalOperation()
        defer { finishPhysicalOperation(operation) }
        let revision = selectionRevision
        do {
            let snapshot = try await persistence.validate(id)
            guard transferHold == nil else { throw ImportedRoutesFailure.busy }
            guard selectionRevision == revision, selectedID == id else { throw ImportedRoutesFailure.noSelection }
            let data = try await Task.detached { try GPXCodec.encode(snapshot.document, name: snapshot.record.filename) }.value
            guard transferHold == nil, selectionRevision == revision, selectedID == id else { throw ImportedRoutesFailure.noSelection }
            return data
        } catch {
            if selectionRevision == revision { recordFailure(error) }
            throw ImportedRoutesFailure.mapped(error)
        }
    }

    private func publish(_ receipt: ImportedRoutesReceipt) {
        records = receipt.records; canUndo = receipt.canUndo
    }
    private func recordFailure(_ error: any Error) {
        let failure = ImportedRoutesFailure.mapped(error)
        self.error = failure
        switch failure {
        case .corruptArchive, .unsupportedSchema, .unsafeFile: loadState = .blocked(failure)
        default: break
        }
    }
}
