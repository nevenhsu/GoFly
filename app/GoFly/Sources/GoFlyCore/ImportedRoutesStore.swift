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

    public init(persistence: any ImportedRoutesPersistence) { self.persistence = persistence }
    public var canMutate: Bool { loadState == .ready && !isBusy }
    public func clearError() { error = nil }

    public func load() async {
        guard !isBusy, loadState != .ready else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let receipt = try await persistence.read()
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
        let selectionAtStart = selectionRevision
        defer { isBusy = false }
        do {
            let artifact = try await Task.detached {
                try Task.checkCancellation()
                return try ImportedRouteArtifact(data: data, filename: filename)
            }.value
            try Task.checkCancellation()
            let receipt = try await persistence.importArtifact(artifact)
            publish(receipt)
            if selectionRevision == selectionAtStart { error = nil }
            if selectionRevision == selectionAtStart, let record = receipt.records.last {
                let snapshot = try await Task.detached {
                    try ImportedRouteSnapshot(record: record, document: artifact.document)
                }.value
                guard selectionRevision == selectionAtStart else { return true }
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
        selectionRevision &+= 1
        let revision = selectionRevision
        selectedID = id
        selectedSnapshot = nil
        isValidatingSelection = false
        guard let id else { return }
        guard records.contains(where: { $0.id == id }) else { error = .notFound; return }
        isValidatingSelection = true
        do {
            let snapshot = try await persistence.validate(id)
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
        defer { isBusy = false }
        do {
            let receipt = try await persistence.delete(id)
            publish(receipt)
            if selectedID == id { await select(nil) }
            error = nil
            return true
        } catch { recordFailure(error); return false }
    }

    @discardableResult public func undoDelete() async -> Bool {
        guard canMutate else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            publish(try await persistence.undoDelete())
            error = nil
            return true
        } catch { recordFailure(error); return false }
    }

    public func exportSelected() async throws -> Data {
        guard let id = selectedID, selectedSnapshot != nil, !isValidatingSelection else { throw ImportedRoutesFailure.noSelection }
        let revision = selectionRevision
        do {
            let snapshot = try await persistence.validate(id)
            guard selectionRevision == revision, selectedID == id else { throw ImportedRoutesFailure.noSelection }
            let data = try await Task.detached { try GPXCodec.encode(snapshot.document, name: snapshot.record.filename) }.value
            guard selectionRevision == revision, selectedID == id else { throw ImportedRoutesFailure.noSelection }
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
