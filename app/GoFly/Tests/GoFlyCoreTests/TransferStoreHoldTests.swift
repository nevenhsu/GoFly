import Foundation
import Testing
import GoFlyCore

@Suite @MainActor
struct TransferStoreHoldTests {
    @Test func heldSessionOwnerFlushesCurrentSnapshotWithoutReleasingOrdinaryWriters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = FileSessionRecoveryPersistence(directory: root)
        let store = SessionRecoveryStore(persistence: persistence)
        let other = SessionRecoveryStore(persistence: FileSessionRecoveryPersistence(
            directory: root.appendingPathComponent("other")))
        let token = try #require(store.acquireTransferHold())
        let foreign = try #require(other.acquireTransferHold())
        let current = SessionRecoverySnapshot(mode: .route)
        #expect(!store.capture(current, using: foreign))
        #expect(!store.capture(current))
        #expect(store.capture(current, using: token))
        #expect(await store.flush(using: token))
        #expect(!store.capture(SessionRecoverySnapshot()))
        #expect(SessionRecoveryStore(persistence: persistence).initialSnapshot == current)
        #expect(store.releaseTransferHold(token))
    }

    @Test func selectNilDoesNotReleaseAStillRunningValidation() async throws {
        let point = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let document = try GPXDocument(content: .waypoints([point, GeoCoordinate(latitude: 25.01, longitude: 121.01)!]))
        let snapshot = try ImportedRouteSnapshot(document: document, filename: "held.gpx")
        let persistence = HeldImportedPersistence(snapshot: snapshot)
        let store = ImportedRoutesStore(persistence: persistence)
        await store.load()
        let selection = Task { @MainActor in await store.select(snapshot.record.id) }
        while !(await persistence.entered) { await Task.yield() }
        await store.select(nil)
        #expect(store.isValidatingSelection == false)
        #expect(store.acquireTransferHold() == nil)
        await persistence.finish()
        await selection.value
        #expect(store.acquireTransferHold() != nil)
    }
}

private actor HeldImportedPersistence: ImportedRoutesPersistence {
    let snapshot: ImportedRouteSnapshot
    var entered = false
    var continuation: CheckedContinuation<ImportedRouteSnapshot, Never>?

    init(snapshot: ImportedRouteSnapshot) { self.snapshot = snapshot }

    func read() async throws -> ImportedRoutesReceipt {
        ImportedRoutesReceipt(records: [snapshot.record], canUndo: false)
    }

    func importArtifact(_: ImportedRouteArtifact) async throws -> ImportedRoutesReceipt {
        throw ImportedRoutesFailure.busy
    }

    func validate(_: UUID) async throws -> ImportedRouteSnapshot {
        entered = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func transferSnapshot() async throws -> TransferArchiveSnapshot {
        throw ImportedRoutesFailure.unavailable
    }

    func delete(_: UUID) async throws -> ImportedRoutesReceipt {
        throw ImportedRoutesFailure.busy
    }

    func undoDelete() async throws -> ImportedRoutesReceipt {
        throw ImportedRoutesFailure.busy
    }

    func finish() {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}
