import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct ImportedRoutesStoreTests {
    @Test func importAndSelectionPublishOnlyCommittedValidatedRecords() async throws {
        let disk = MemoryImportedRoutesPersistence()
        let store = ImportedRoutesStore(persistence: disk)
        await store.load()
        #expect(store.loadState == .ready)
        #expect(await store.importData(Self.xml, filename: "sample.gpx"))
        let record = try #require(store.records.first)
        #expect(store.selectedID == record.id)
        #expect(store.selectedSnapshot?.document.pointCount == 2)
        #expect(try await store.exportSelected() == GPXCodec.encode(store.selectedSnapshot!.document, name: "sample.gpx"))
        await store.select(nil)
        #expect(store.selectedSnapshot == nil)
        #expect(store.selectedID == nil)
    }
    @Test func aFailedFileCommitKeepsSelectionRecordsAndObserversUnchanged() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/gofly09-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let normal = FileImportedRoutesPersistence(directory: directory)
        let receipt = try await normal.importArtifact(ImportedRouteArtifact(data: Self.xml, filename: "old.gpx"))
        let failing = FileImportedRoutesPersistence(directory: directory) { point in
            if point == .beforeManifestCommit { throw CocoaError(.fileWriteUnknown) }
        }
        let store = ImportedRoutesStore(persistence: failing)
        await store.load()
        await store.select(receipt.records[0].id)
        let selection = store.selectedSnapshot
        var publications = 0
        let observation = store.$records.dropFirst().sink { _ in publications += 1 }
        #expect(!(await store.importData(Self.xml, filename: "new.gpx")))
        #expect(store.records == receipt.records)
        #expect(store.selectedSnapshot == selection)
        #expect(store.selectedID == selection?.record.id)
        #expect(store.error == .writeFailed)
        #expect(publications == 0)
        withExtendedLifetime(observation) {}
    }

    @Test func lateSelectionCannotReplaceANewerSelectionOrResurrectADeletedRecord() async throws {
        let disk = MemoryImportedRoutesPersistence()
        let store = ImportedRoutesStore(persistence: disk)
        await store.load()
        #expect(await store.importData(Self.xml, filename: "first.gpx"))
        let first = try #require(store.records.first)
        #expect(await store.importData(Self.xml, filename: "second.gpx"))
        let second = try #require(store.records.last)
        await disk.deferValidation(first.id)
        let late = Task { await store.select(first.id) }
        while !(await disk.isValidationWaiting(first.id)) { await Task.yield() }
        await store.select(second.id)
        await disk.resumeValidation(first.id)
        await late.value
        #expect(store.selectedID == second.id)
        #expect(store.selectedSnapshot?.record.id == second.id)
        #expect(!store.isValidatingSelection)

        await disk.deferValidation(first.id)
        let deletedSelection = Task { await store.select(first.id) }
        while !(await disk.isValidationWaiting(first.id)) { await Task.yield() }
        #expect(await store.delete(first.id))
        await disk.resumeValidation(first.id)
        await deletedSelection.value
        #expect(store.selectedID == nil)
        #expect(store.selectedSnapshot == nil)
        #expect(store.records == [second])
        #expect(await store.undoDelete())
        #expect(store.selectedID == nil)
    }

    @Test func lateImportPublishesItsReceiptButDoesNotOverrideANewerSelectionAndBusyRejectsOtherMutation() async throws {
        let disk = MemoryImportedRoutesPersistence()
        let store = ImportedRoutesStore(persistence: disk)
        await store.load()
        #expect(await store.importData(Self.xml, filename: "first.gpx"))
        let first = try #require(store.records.first)
        await disk.deferImport()
        let late = Task { await store.importData(Self.xml, filename: "second.gpx") }
        while !(await disk.isImportWaiting()) { await Task.yield() }
        #expect(store.isBusy)
        #expect(!(await store.delete(first.id)))
        #expect(!(await store.importData(Self.xml, filename: "third.gpx")))
        await store.select(nil)
        await disk.resumeImport()
        #expect(await late.value)
        #expect(store.records.count == 2)
        #expect(store.selectedID == nil)
        #expect(store.selectedSnapshot == nil)
        #expect(!store.isBusy)
    }

    @Test func invalidImportAndBlockedArchiveNeverBecomeAHealthyEmptyList() async throws {
        let store = ImportedRoutesStore(persistence: MemoryImportedRoutesPersistence())
        await store.load()
        #expect(!(await store.importData(Data("bad".utf8), filename: "bad.gpx")))
        #expect(store.error == .gpx(.invalidXML))
        #expect(store.records.isEmpty)
        let unavailable = ImportedRoutesStore(persistence: UnavailableImportedRoutesPersistence())
        await unavailable.load()
        #expect(unavailable.loadState == .blocked(.unavailable))
        #expect(!unavailable.canMutate)
        #expect(!(await unavailable.importData(Self.xml, filename: "x.gpx")))
    }

    @Test func cancelledSelectionCannotPublishAndPrecancelledImportDoesNotCommit() async throws {
        let disk = MemoryImportedRoutesPersistence()
        let store = ImportedRoutesStore(persistence: disk)
        await store.load()
        let cancelledImport = Task { await store.importData(Self.xml, filename: "cancelled.gpx") }
        cancelledImport.cancel()
        #expect(!(await cancelledImport.value))
        #expect(store.records.isEmpty)
        #expect(await disk.read().records.isEmpty)
        #expect(await store.importData(Self.xml, filename: "first.gpx"))
        let id = try #require(store.selectedID)
        await disk.deferValidation(id)
        let selection = Task { await store.select(id) }
        while !(await disk.isValidationWaiting(id)) { await Task.yield() }
        selection.cancel()
        await disk.resumeValidation(id)
        await selection.value
        #expect(store.selectedSnapshot == nil)
        #expect(!store.isValidatingSelection)
        await #expect(throws: ImportedRoutesFailure.noSelection) { try await store.exportSelected() }
    }
    nonisolated static let xml = Data("<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" version=\"1.1\"><wpt lat=\"1\" lon=\"2\"/><wpt lat=\"3\" lon=\"4\"/></gpx>".utf8)
}

private actor MemoryImportedRoutesPersistence: ImportedRoutesPersistence {
    var snapshots: [ImportedRouteSnapshot] = []
    var undo: ImportedRouteSnapshot?
    private var deferredValidations = Set<UUID>()
    private var validationWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var shouldDeferImport = false
    private var importWaiter: CheckedContinuation<Void, Never>?
    func deferValidation(_ id: UUID) { deferredValidations.insert(id) }
    func isValidationWaiting(_ id: UUID) -> Bool { validationWaiters[id] != nil }
    func resumeValidation(_ id: UUID) { validationWaiters.removeValue(forKey: id)?.resume() }
    func deferImport() { shouldDeferImport = true }
    func isImportWaiting() -> Bool { importWaiter != nil }
    func resumeImport() { importWaiter?.resume(); importWaiter = nil }
    func read() -> ImportedRoutesReceipt { ImportedRoutesReceipt(records: snapshots.map(\.record), canUndo: undo != nil) }
    func importArtifact(_ artifact: ImportedRouteArtifact) async throws -> ImportedRoutesReceipt {
        if shouldDeferImport {
            shouldDeferImport = false
            await withCheckedContinuation { importWaiter = $0 }
        }
        snapshots.append(try ImportedRouteSnapshot(document: artifact.document, filename: artifact.filename))
        return read()
    }
    func validate(_ id: UUID) async throws -> ImportedRouteSnapshot {
        guard let snapshot = snapshots.first(where: { $0.record.id == id }) else { throw ImportedRoutesFailure.notFound }
        if deferredValidations.remove(id) != nil {
            await withCheckedContinuation { validationWaiters[id] = $0 }
        }
        return snapshot
    }
    func delete(_ id: UUID) throws -> ImportedRoutesReceipt {
        guard let snapshot = snapshots.first(where: { $0.record.id == id }) else { throw ImportedRoutesFailure.notFound }
        undo = snapshot
        snapshots.removeAll { $0.record.id == id }
        return read()
    }
    func undoDelete() throws -> ImportedRoutesReceipt {
        guard let undo else { throw ImportedRoutesFailure.nothingToUndo }
        snapshots.append(undo); self.undo = nil
        return read()
    }
}
