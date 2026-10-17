import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct FavoriteRoutesStoreTests {
    @Test func savePublishesTheActualOmissionResultWithoutChangingSelection() async throws {
        let disk = MemoryFavoriteRoutesPersistence()
        let store = FavoriteRoutesStore(persistence: disk)
        await store.load()
        let draft = RouteDraft(values: [.current, .place(Self.place(1)), .place(Self.place(2))])!
        let candidate = try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil)
        let result = try #require(await store.save(candidate, label: "  My route  "))
        #expect(result.omittedUnavailableCurrent)
        #expect(result.record.label == "My route")
        #expect(store.records == [result.record])
        #expect(store.selectedID == nil)
        #expect(store.selectedSnapshot == nil)
        await store.select(result.record.id)
        #expect(store.selectedSnapshot?.source == .manual([Self.place(1), Self.place(2)]))
        #expect(await store.updateLabel(result.record.id, label: "Renamed"))
        #expect(store.records.count == 1)
        #expect(store.records[0].id == result.record.id)
        #expect(store.selectedSnapshot?.record.label == "Renamed")
    }
    @Test func failedMutationCannotPublishAFalseSuccessOrChangeSelectionAndUndoRetainsItsToken() async throws {
        let disk = MemoryFavoriteRoutesPersistence()
        let store = FavoriteRoutesStore(persistence: disk)
        await store.load()
        let candidate = try sample()
        let first = try #require(await store.save(candidate, label: "First"))
        await store.select(first.record.id)
        let old = store.selectedSnapshot
        var publications = 0
        let observer = store.$records.dropFirst().sink { _ in publications += 1 }
        await disk.failMutations(.writeFailed)
        #expect(await store.save(candidate, label: "Second") == nil)
        #expect(!(await store.updateLabel(first.record.id, label: "Changed")))
        #expect(!(await store.delete(first.record.id)))
        #expect(store.records == [first.record])
        #expect(store.selectedSnapshot == old)
        #expect(store.error == .writeFailed)
        #expect(publications == 0)
        await disk.failMutations(nil)
        #expect(await store.delete(first.record.id))
        #expect(store.selectedSnapshot == nil)
        #expect(store.canUndo)
        await disk.failMutations(.writeFailed)
        #expect(!(await store.undoDelete()))
        #expect(store.canUndo)
        #expect(store.records.isEmpty)
        await disk.failMutations(nil)
        #expect(await store.undoDelete())
        #expect(store.records == [first.record])
        #expect(store.selectedID == nil)
        withExtendedLifetime(observer) {}
    }
    @Test func lateSelectionCannotReplaceTheNewSelectionOrResurrectADeletedRecord() async throws {
        let disk = MemoryFavoriteRoutesPersistence()
        let store = FavoriteRoutesStore(persistence: disk)
        await store.load()
        let first = try #require(await store.save(sample(), label: "First")).record
        let second = try #require(await store.save(sample(), label: "Second")).record
        await disk.deferValidation(first.id)
        let late = Task { await store.select(first.id) }
        while !(await disk.isValidationWaiting(first.id)) { await Task.yield() }
        await store.select(second.id)
        await disk.resumeValidation(first.id)
        await late.value
        #expect(store.selectedSnapshot?.record.id == second.id)
        await disk.deferValidation(first.id)
        let removed = Task { await store.select(first.id) }
        while !(await disk.isValidationWaiting(first.id)) { await Task.yield() }
        #expect(await store.delete(first.id))
        await disk.resumeValidation(first.id)
        await removed.value
        #expect(store.selectedID == nil)
        #expect(store.selectedSnapshot == nil)
        #expect(store.records == [second])
    }
    @Test func aCommittedSaveReceiptSurvivesCancellationAndDoesNotOverrideNewSelection() async throws {
        let disk = MemoryFavoriteRoutesPersistence()
        let store = FavoriteRoutesStore(persistence: disk)
        await store.load()
        let first = try #require(await store.save(sample(), label: "First")).record
        await store.select(first.id)
        await disk.deferSaveResponse()
        let save = Task { await store.save(try sample(), label: "Second") }
        while !(await disk.isSaveWaiting()) { await Task.yield() }
        #expect(store.isBusy)
        #expect(!(await store.delete(first.id)))
        #expect(await store.save(try sample(), label: "Busy") == nil)
        await store.select(nil)
        save.cancel()
        await disk.resumeSave()
        let result = try #require(await save.value)
        #expect(result.record.label == "Second")
        #expect(store.records.count == 2)
        #expect(store.selectedID == nil)
        #expect(store.selectedSnapshot == nil)
        #expect(!store.isBusy)
    }
    @Test func cancelledSelectionAndPrecancelledSaveNeverPublishSnapshotsOrRecords() async throws {
        let disk = MemoryFavoriteRoutesPersistence()
        let store = FavoriteRoutesStore(persistence: disk)
        await store.load()
        let candidate = try sample()
        let cancelled = Task { await store.save(candidate, label: "Cancelled") }
        cancelled.cancel()
        #expect(await cancelled.value == nil)
        #expect(store.records.isEmpty)
        let first = try #require(await store.save(candidate, label: "First")).record
        await disk.deferValidation(first.id)
        let selection = Task { await store.select(first.id) }
        while !(await disk.isValidationWaiting(first.id)) { await Task.yield() }
        selection.cancel(); await disk.resumeValidation(first.id); await selection.value
        #expect(store.selectedSnapshot == nil)
        #expect(!store.isValidatingSelection)
    }
    @Test func corruptPayloadOrUnavailableStartupBlocksMutationsWithoutPretendingTheArchiveIsEmpty() async throws {
        let disk = MemoryFavoriteRoutesPersistence()
        let store = FavoriteRoutesStore(persistence: disk)
        await store.load()
        let first = try #require(await store.save(sample(), label: "First")).record
        await disk.failValidation(.hashMismatch)
        await store.select(first.id)
        #expect(store.loadState == .blocked(.hashMismatch))
        #expect(!store.canMutate)
        #expect(store.records == [first])
        #expect(store.selectedSnapshot == nil)
        #expect(await store.save(try sample(), label: "Blocked") == nil)
        #expect(!(await store.delete(first.id)))
        #expect(!(await store.undoDelete()))
        let unavailable = FavoriteRoutesStore(persistence: UnavailableFavoriteRoutesPersistence())
        await unavailable.load()
        #expect(unavailable.loadState == .blocked(.unavailable))
    }
    private func sample() throws -> FavoriteRouteSaveCandidate {
        try FavoriteRouteSaveBuilder.build(draft: RouteDraft(values: [.place(Self.place(1)), .place(Self.place(2))])!, currentRouteOrigin: nil)
    }
    nonisolated static func place(_ number: Int) -> MapPlace {
        MapPlace(id: .mapKit("place-\(number)"), title: "Place \(number)",
            coordinate: GeoCoordinate(latitude: Double(number), longitude: 121)!, address: "Address \(number)")
    }
}

private actor MemoryFavoriteRoutesPersistence: FavoriteRoutesPersistence {
    private var snapshots: [FavoriteRouteSnapshot] = []
    private var undo: (snapshot: FavoriteRouteSnapshot, index: Int)?
    private var mutationFailure: FavoriteRoutesFailure?
    private var validationFailure: FavoriteRoutesFailure?
    private var deferredValidations = Set<UUID>()
    private var validationWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var deferSave = false
    private var saveWaiter: CheckedContinuation<Void, Never>?
    func failMutations(_ failure: FavoriteRoutesFailure?) { mutationFailure = failure }
    func failValidation(_ failure: FavoriteRoutesFailure?) { validationFailure = failure }
    func deferValidation(_ id: UUID) { deferredValidations.insert(id) }
    func isValidationWaiting(_ id: UUID) -> Bool { validationWaiters[id] != nil }
    func resumeValidation(_ id: UUID) { validationWaiters.removeValue(forKey: id)?.resume() }
    func deferSaveResponse() { deferSave = true }
    func isSaveWaiting() -> Bool { saveWaiter != nil }
    func resumeSave() { saveWaiter?.resume(); saveWaiter = nil }
    func read() -> FavoriteRoutesReceipt { FavoriteRoutesReceipt(records: snapshots.map(\.record), canUndo: undo != nil) }
    func save(_ candidate: FavoriteRouteSaveCandidate, label: String?) async throws -> FavoriteRouteSaveReceipt {
        if let mutationFailure { throw mutationFailure }
        let snapshot = try FavoriteRouteSnapshot(source: candidate.source, label: label)
        snapshots.append(snapshot)
        let receipt = FavoriteRouteSaveReceipt(archive: read(), result: FavoriteRouteSaveResult(record: snapshot.record,
            omittedUnavailableCurrent: candidate.omittedUnavailableCurrent))
        if deferSave { deferSave = false; await withCheckedContinuation { saveWaiter = $0 } }
        return receipt
    }
    func validate(_ id: UUID) async throws -> FavoriteRouteSnapshot {
        if let validationFailure { throw validationFailure }
        guard let snapshot = snapshots.first(where: { $0.record.id == id }) else { throw FavoriteRoutesFailure.notFound }
        if deferredValidations.remove(id) != nil { await withCheckedContinuation { validationWaiters[id] = $0 } }
        return snapshot
    }
    func updateLabel(_ id: UUID, label: String?) throws -> FavoriteRoutesReceipt {
        if let mutationFailure { throw mutationFailure }
        guard let index = snapshots.firstIndex(where: { $0.record.id == id }) else { throw FavoriteRoutesFailure.notFound }
        let old = snapshots[index]
        snapshots[index] = try FavoriteRouteSnapshot(source: old.source, label: label, id: id)
        return read()
    }
    func delete(_ id: UUID) throws -> FavoriteRoutesReceipt {
        if let mutationFailure { throw mutationFailure }
        guard let index = snapshots.firstIndex(where: { $0.record.id == id }) else { throw FavoriteRoutesFailure.notFound }
        undo = (snapshots.remove(at: index), index)
        return read()
    }
    func undoDelete() throws -> FavoriteRoutesReceipt {
        if let mutationFailure { throw mutationFailure }
        guard let undo else { throw FavoriteRoutesFailure.nothingToUndo }
        snapshots.insert(undo.snapshot, at: min(undo.index, snapshots.count)); self.undo = nil
        return read()
    }
}
