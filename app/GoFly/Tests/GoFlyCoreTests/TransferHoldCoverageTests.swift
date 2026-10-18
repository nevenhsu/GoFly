import Combine
import Foundation
import Testing
import GoFlyCore

@Suite @MainActor
struct TransferHoldCoverageTests {
    @Test func allOwnersAcquireWithoutPublicationAndRejectForeignTokens() async throws {
        let service = ServiceController(service: CoverageDeviceService())
        #expect(service.restoreGPS())
        for _ in 0..<200 where !isConfirmed(service.clearState) { await Task.yield() }
        #expect(isConfirmed(service.clearState))

        let route = RouteExecutionController(planner: CoveragePlanner(), commands: CoverageRouteCommands(), search: CoverageSearch())
        let joystick = JoystickMovementController(commands: CoverageJoystickCommands())
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick, probe: CoverageProbe())
        let places = FavoritePlacesStore(persistence: CoveragePlacesPersistence())
        let imported = ImportedRoutesStore(persistence: CoverageImportedPersistence())
        await imported.load()
        let favoriteRoutes = FavoriteRoutesStore(persistence: CoverageFavoriteRoutesPersistence())
        await favoriteRoutes.load()
        let session = SessionRecoveryStore(persistence: CoverageSessionPersistence())

        let serviceHold = try #require(acquireSilently(service) { service.acquireTransferHold() })
        let recoveryHold = try #require(acquireSilently(recovery) { recovery.acquireTransferHold() })
        let routeHold = try #require(acquireSilently(route) { route.acquireTransferHold() })
        let joystickHold = try #require(acquireSilently(joystick) { joystick.acquireTransferHold() })
        let placesHold = try #require(acquireSilently(places) { places.acquireTransferHold() })
        let importedHold = try #require(acquireSilently(imported) { imported.acquireTransferHold() })
        let favoriteRoutesHold = try #require(acquireSilently(favoriteRoutes) { favoriteRoutes.acquireTransferHold() })
        let sessionHold = try #require(acquireSilently(session) { session.acquireTransferHold() })

        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let place = MapPlace(id: .coordinate(coordinate), title: "Coverage", coordinate: coordinate)
        #expect(!places.toggle(place))
        #expect(!(await imported.importData(Data("late".utf8), filename: "late.gpx")))
        #expect(!session.capture(SessionRecoverySnapshot(mode: .route)))
        #expect(!service.releaseTransferHold(recoveryHold))
        #expect(!route.releaseTransferHold(joystickHold))
        #expect(!places.releaseTransferHold(importedHold))
        #expect(service.releaseTransferHold(serviceHold))
        #expect(recovery.releaseTransferHold(recoveryHold))
        #expect(route.releaseTransferHold(routeHold))
        #expect(joystick.releaseTransferHold(joystickHold))
        #expect(places.releaseTransferHold(placesHold))
        #expect(imported.releaseTransferHold(importedHold))
        #expect(favoriteRoutes.releaseTransferHold(favoriteRoutesHold))
        #expect(session.releaseTransferHold(sessionHold))
    }

    @Test func dirtySessionWriterDeniesHoldAndLateCaptureRemainsAccepted() async throws {
        let persistence = CoverageGatedSessionPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        #expect(store.capture(SessionRecoverySnapshot()))
        for _ in 0..<200 where !persistence.entered { await Task.yield() }
        #expect(persistence.entered)
        #expect(store.acquireTransferHold() == nil)
        #expect(store.capture(SessionRecoverySnapshot(mode: .route)))
        persistence.release()
        #expect(await store.flush())
        #expect(store.hasUnsavedChanges == false)
    }

    @Test func routeAdmissionRevisionRevokesSharedImportedAndFavoriteLoads() throws {
        let route = RouteExecutionController(planner: CoveragePlanner(), commands: CoverageRouteCommands(), search: CoverageSearch())
        let importedAdmission = try #require(route.beginImportedLoad())
        let favoriteAdmission = try #require(route.beginFavoriteLoad())
        #expect(importedAdmission != favoriteAdmission)
        #expect(!route.loadImportedRoute(try importedSnapshot(), expectedAdmissionRevision: importedAdmission))
        #expect(route.acquireTransferHold() != nil)
        #expect(route.beginImportedLoad() == nil)
        #expect(route.beginFavoriteLoad() == nil)
    }

    @Test func favoriteRouteSelectionNilRetainsPhysicalValidationTail() async throws {
        let snapshot = try favoriteRouteSnapshot()
        let persistence = CoverageGatedFavoriteRoutesPersistence(snapshot: snapshot)
        let store = FavoriteRoutesStore(persistence: persistence)
        await store.load()
        let selection = Task { @MainActor in await store.select(snapshot.record.id) }
        for _ in 0..<200 where !(await persistence.entered) { await Task.yield() }
        await store.select(nil)
        #expect(store.acquireTransferHold() == nil)
        await persistence.finish()
        await selection.value
        #expect(store.acquireTransferHold() != nil)
    }

    @Test func transferCopyKeepsHoldUntilPhysicalSnapshotReturns() async throws {
        let persistence = CoverageGatedTransferPersistence()
        let store = ImportedRoutesStore(persistence: persistence)
        await store.load()
        let hold = try #require(store.acquireTransferHold())
        let copy = Task { @MainActor in try? await store.transferArchive(using: hold) }
        for _ in 0..<200 where !(await persistence.entered) { await Task.yield() }
        #expect(await persistence.entered)
        #expect(!store.releaseTransferHold(hold))
        await persistence.finish()
        _ = await copy.value
        #expect(store.releaseTransferHold(hold))
    }

    @Test func canceledPlannerRetainsPhysicalOperationUntilPlannerReturns() async throws {
        let planner = CoverageGatedPlanner()
        let route = RouteExecutionController(draft: try #require(RouteDraft(values: [.place(place(25, 121)), .place(place(25.01, 121.01))])),
            planner: planner, commands: CoverageReadyRouteCommands(), search: CoverageSearch())
        #expect(route.start())
        for _ in 0..<200 where !(await planner.entered) { await Task.yield() }
        #expect(route.cancel())
        #expect(route.acquireTransferHold() == nil)
        await planner.finish()
        var hold: TransferHold?
        for _ in 0..<200 where hold == nil {
            hold = route.acquireTransferHold()
            if hold == nil { await Task.yield() }
        }
        #expect(hold != nil)
        if let hold { #expect(route.releaseTransferHold(hold)) }
    }

    @Test func joystickSettlementTailRetainsPhysicalOperationUntilIdleReturns() async throws {
        let commands = CoverageGatedJoystickCommands()
        let joystick = JoystickMovementController(commands: commands)
        let gesture = UUID()
        let input = try #require(JoystickInput(bearingDegrees: 90, strength: 1))
        #expect(joystick.beginGesture(id: gesture, input: input))
        #expect(joystick.endGesture(id: gesture))
        for _ in 0..<200 where !commands.idleEntered { await Task.yield() }
        #expect(commands.idleEntered)
        #expect(joystick.acquireTransferHold() == nil)
        commands.finishIdle()
        var hold: TransferHold?
        for _ in 0..<200 where hold == nil {
            hold = joystick.acquireTransferHold()
            if hold == nil { await Task.yield() }
        }
        #expect(hold != nil)
        if let hold { #expect(joystick.releaseTransferHold(hold)) }
    }

    @Test func queuedRecoveryCallbacksRespectHoldBeforeEvaluateOrPublish() async throws {
        let service = ServiceController(service: CoverageDeviceService())
        #expect(service.restoreGPS())
        for _ in 0..<200 where !isConfirmed(service.clearState) { await Task.yield() }
        #expect(isConfirmed(service.clearState))

        let route = RouteExecutionController(planner: CoveragePlanner(), commands: CoverageRouteCommands(), search: CoverageSearch())
        let joystick = JoystickMovementController(commands: CoverageJoystickCommands())
        let probe = CoverageCountingProbe()
        let recovery = MovementRecoveryController(service: service, route: route, joystick: joystick, probe: probe)
        var publications = 0
        let observer = recovery.objectWillChange.sink { _ in publications += 1 }

        // This queues both the checkpoint revision and the yielded service-state
        // evaluation before the owner acquires its transfer hold.
        route.sceneDidBecomeActive()
        let hold = try #require(recovery.acquireTransferHold())
        recovery.checkConnection()
        for _ in 0..<200 { await Task.yield() }

        #expect(recovery.checkpointRevision == 0)
        #expect(publications == 0)
        #expect(await probe.checks == 0)
        observer.cancel()
        #expect(recovery.releaseTransferHold(hold))
    }

    @Test func favoritePlacesTransferPreservesValidLegacyRawBytes() throws {
        let root = try coverageDirectory("places-transfer")
        defer { try? FileManager.default.removeItem(at: root) }
        let raw = Data("""
        {
          "favorites": [
            {
              "address": null,
              "coordinate": { "latitude": 25.0, "longitude": 121.0 },
              "identity": { "kind": "coordinate", "value": null },
              "label": "  Legacy label  ",
              "title": "Taipei"
            }
          ],
          "schemaVersion": 1
        }
        """.utf8)
        let file = root.appendingPathComponent("favorites.json")
        try raw.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: file.path)

        let store = FavoritePlacesStore(persistence: FileFavoritePlacesPersistence(directory: root))
        #expect(store.favorites.count == 1)
        let hold = try #require(store.acquireTransferHold())
        let exported = try store.transferArchive(using: hold)
        #expect(exported == raw)
        #expect(try TransferArchiveCodec.favoritePlaces(exported) == store.favorites)
        #expect(store.releaseTransferHold(hold))
    }

    @Test func allThreePublicStoresTransferValidRecordsAndFullPayloads() async throws {
        let placesRoot = try coverageDirectory("places-all-stores")
        let importedRoot = placesRoot.appendingPathComponent("imported", isDirectory: true)
        let favoriteRoot = placesRoot.appendingPathComponent("favorite-routes", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: placesRoot) }

        let placesStore = FavoritePlacesStore(persistence: FileFavoritePlacesPersistence(directory: placesRoot))
        let placesHold = try #require(placesStore.acquireTransferHold())
        let placesArchive = try placesStore.transferArchive(using: placesHold)
        #expect(try TransferArchiveCodec.favoritePlaces(placesArchive) == placesStore.favorites)
        #expect(placesStore.releaseTransferHold(placesHold))

        let points = [
            try #require(GeoCoordinate(latitude: 25, longitude: 121)),
            try #require(GeoCoordinate(latitude: 25.01, longitude: 121.01))
        ]
        let document = try GPXDocument(content: .waypoints(points))
        let importedArtifact = try ImportedRouteArtifact(document: document, filename: "coverage.gpx")
        let importedStore = ImportedRoutesStore(persistence: FileImportedRoutesPersistence(directory: importedRoot))
        await importedStore.load()
        #expect(await importedStore.importData(importedArtifact.payload, filename: importedArtifact.filename))
        let importedRecord = try #require(importedStore.records.first)
        let importedHold = try #require(importedStore.acquireTransferHold())
        let importedArchive = try await importedStore.transferArchive(using: importedHold)
        #expect(try TransferArchiveCodec.importedRoutes(importedArchive) == importedStore.records)
        #expect(importedArchive.payloads["\(importedRecord.id.uuidString).gpx"] == importedArtifact.payload)
        #expect(importedStore.releaseTransferHold(importedHold))

        let start = place(25, 121)
        let end = place(25.01, 121.01)
        let draft = try #require(RouteDraft(values: [.place(start), .place(end)]))
        let candidate = try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil)
        let favoriteArtifact = try FavoriteRouteArtifact(candidate: candidate)
        let favoriteStore = FavoriteRoutesStore(persistence: FileFavoriteRoutesPersistence(directory: favoriteRoot))
        await favoriteStore.load()
        let saved = try #require(await favoriteStore.save(candidate, label: "  Coverage route  "))
        let favoriteRecord = saved.record
        let favoriteHold = try #require(favoriteStore.acquireTransferHold())
        let favoriteArchive = try await favoriteStore.transferArchive(using: favoriteHold)
        #expect(try TransferArchiveCodec.favoriteRoutes(favoriteArchive) == favoriteStore.records)
        #expect(favoriteArchive.payloads["\(favoriteRecord.id.uuidString).route"] == favoriteArtifact.payload)
        #expect(favoriteStore.releaseTransferHold(favoriteHold))
    }

    @Test func validDifferentRecordsAreRejectedAfterTransferSnapshotValidation() async throws {
        let expected = try importedSnapshot()
        let different = try importedSnapshot()
        let persistence = try CoverageMismatchTransferPersistence(expected: expected.record, returned: different)
        let store = ImportedRoutesStore(persistence: persistence)
        await store.load()
        let hold = try #require(store.acquireTransferHold())
        await #expect(throws: ImportedRoutesFailure.metadataMismatch) {
            _ = try await store.transferArchive(using: hold)
        }
        #expect(await persistence.entered)
        #expect(store.releaseTransferHold(hold))
    }

    @Test func foreignReleasedAndStaleTokensDoNotEnterTransferPersistence() async throws {
        let persistence = CoverageCountingTransferPersistence()
        let first = ImportedRoutesStore(persistence: persistence)
        let second = ImportedRoutesStore(persistence: persistence)
        await first.load()
        await second.load()
        let firstHold = try #require(first.acquireTransferHold())
        let secondHold = try #require(second.acquireTransferHold())

        await #expect(throws: ImportedRoutesFailure.busy) {
            _ = try await first.transferArchive(using: secondHold)
        }
        #expect(!first.releaseTransferHold(secondHold))
        #expect(await persistence.transferCalls == 0)
        #expect(first.releaseTransferHold(firstHold))
        #expect(!first.releaseTransferHold(firstHold))
        await #expect(throws: ImportedRoutesFailure.busy) {
            _ = try await first.transferArchive(using: firstHold)
        }
        #expect(await persistence.transferCalls == 0)
        #expect(second.releaseTransferHold(secondHold))
    }

    @Test func successfulTransferCopyRetainsHoldUntilPhysicalSnapshotReturns() async throws {
        let source = try importedSnapshot()
        let persistence = CoverageGatedValidTransferPersistence(snapshot: source)
        let store = ImportedRoutesStore(persistence: persistence)
        await store.load()
        let hold = try #require(store.acquireTransferHold())
        let copy = Task { @MainActor in try await store.transferArchive(using: hold) }
        for _ in 0..<200 where !(await persistence.entered) { await Task.yield() }
        #expect(await persistence.entered)
        #expect(!store.releaseTransferHold(hold))
        try await persistence.finish()
        let returned = try await copy.value
        #expect(try TransferArchiveCodec.importedRoutes(returned) == [source.record])
        let expectedPayload = try ImportedRouteArtifact(document: source.document, filename: source.record.filename).payload
        #expect(returned.payloads["\(source.record.id.uuidString).gpx"] == expectedPayload)
        #expect(store.releaseTransferHold(hold))
    }

    private func isConfirmed(_ state: ClearState) -> Bool {
        if case .confirmed = state { return true }
        return false
    }

    private func importedSnapshot() throws -> ImportedRouteSnapshot {
        let a = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let b = try #require(GeoCoordinate(latitude: 25.001, longitude: 121.001))
        return try ImportedRouteSnapshot(document: GPXDocument(content: .waypoints([a, b])), filename: "coverage.gpx")
    }

    private func favoriteRouteSnapshot() throws -> FavoriteRouteSnapshot {
        try FavoriteRouteSnapshot(source: .manual([place(25, 121), place(25.01, 121.01)]), label: "Coverage")
    }

    private func place(_ latitude: Double, _ longitude: Double) -> MapPlace {
        let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)!
        return MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
    }

    private func coverageDirectory(_ name: String) throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/gofly-a2-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        return root
    }
}

private func acquireSilently<Owner: ObservableObject>(_ owner: Owner, _ acquire: () -> TransferHold?) -> TransferHold? {
    var publications = 0
    let observer = owner.objectWillChange.sink { _ in publications += 1 }
    let hold = acquire()
    #expect(publications == 0)
    observer.cancel()
    return hold
}

private func importedManifestData(for record: ImportedRouteRecord) throws -> Data {
    let recordJSON: [String: Any] = [
        "id": record.id.uuidString,
        "filename": record.filename,
        "kind": record.kind.rawValue,
        "pointCount": record.pointCount,
        "byteCount": record.byteCount,
        "sha256": record.sha256,
        "start": ["latitude": record.start.latitude, "longitude": record.start.longitude],
        "end": ["latitude": record.end.latitude, "longitude": record.end.longitude]
    ]
    let manifest: [String: Any] = ["records": [recordJSON], "schemaVersion": 1]
    return try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
}

private func emptyImportedManifestData() -> Data {
    Data("{\"records\":[],\"schemaVersion\":1}".utf8)
}

private struct CoverageDeviceService: DeviceService, Sendable {
    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        .notSent(.operationCancelled)
    }
}

private struct CoveragePlanner: RoutePlanning, Sendable {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}

private struct CoverageSearch: PlaceSearching, Sendable {
    func search(query: String) async throws -> [MapPlace] { [] }
}

@MainActor
private class CoverageRouteCommands: RouteCommanding {
    private let subject = PassthroughSubject<RouteCommandEvent, Never>()
    var canBeginRoute: Bool { false }
    var routeEvents: AnyPublisher<RouteCommandEvent, Never> { subject.eraseToAnyPublisher() }
    var currentRouteOrigin: GeoCoordinate? { nil }
    var routeAdmissionRevision: UInt64 { 0 }
    func beginRoute(_ intent: RouteExecutionIntent, expectedAdmissionRevision: UInt64) async -> RouteCommandOutcome { .cancelled }
    func routeControlRevision(executionID: UUID, lease: MovementTaskLease) -> UInt64? { nil }
    func reviseRouteControl(executionID: UUID, lease: MovementTaskLease) -> UInt64? { nil }
    func sendRoutePoint(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedControlRevision: UInt64, coordinate: GeoCoordinate) async -> RouteCommandOutcome { .cancelled }
    func pauseRoute(executionID: UUID, lease: MovementTaskLease) -> Bool { false }
    func resumeRoute(executionID: UUID, lease: MovementTaskLease) -> Bool { false }
    func endRoute(executionID: UUID, lease: MovementTaskLease) {}
    func waitForRouteIdle(executionID: UUID, lease: MovementTaskLease) async -> RouteIdleSettlement { .settled }
}

@MainActor
private class CoverageJoystickCommands: JoystickCommanding {
    private let subject = PassthroughSubject<JoystickCommandEvent, Never>()
    var canBeginJoystick: Bool { false }
    var currentJoystickOrigin: GeoCoordinate? { nil }
    var movementAdmissionRevision: UInt64 { 0 }
    var joystickEvents: AnyPublisher<JoystickCommandEvent, Never> { subject.eraseToAnyPublisher() }
    func beginJoystick(_ intent: JoystickMovementIntent, expectedMovementAdmissionRevision: UInt64) async -> JoystickPreparationOutcome { .cancelled }
    func joystickInputRevision(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? { nil }
    func reviseJoystickInput(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? { nil }
    func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedInputRevision: JoystickInputRevision, displacement: JoystickDisplacement) async -> JoystickStepOutcome { .cancelled }
    func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedInputRevision: JoystickInputRevision, recipe: JoystickStepRecipe) async -> JoystickRecipeStepOutcome { .cancelled }
    func releaseJoystick(executionID: UUID, lease: MovementTaskLease, disposition: JoystickReleaseDisposition) -> Bool { false }
    func resumeJoystick(executionID: UUID, lease: MovementTaskLease) -> Bool { false }
    func resumeJoystickStream(executionID: UUID, lease: MovementTaskLease) -> Bool { false }
    func waitForJoystickIdle(executionID: UUID, lease: MovementTaskLease) async -> JoystickIdleSettlement { .settled }
}

private struct CoverageProbe: TunnelProbing, Sendable {
    func check() async throws {}
}

private actor CoverageCountingProbe: TunnelProbing {
    private(set) var checks = 0
    func check() async throws { checks += 1 }
}

private struct CoveragePlacesPersistence: FavoritePlacesPersistence, Sendable {
    func read() throws -> Data? { nil }
    func transferSnapshot() throws -> Data? { nil }
    func replaceAtomically(with data: Data) throws {}
}

private struct CoverageImportedPersistence: ImportedRoutesPersistence, Sendable {
    func read() async throws -> ImportedRoutesReceipt { ImportedRoutesReceipt(records: [], canUndo: false) }
    func importArtifact(_: ImportedRouteArtifact) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
    func validate(_: UUID) async throws -> ImportedRouteSnapshot { throw ImportedRoutesFailure.busy }
    func delete(_: UUID) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
    func undoDelete() async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
}

private struct CoverageFavoriteRoutesPersistence: FavoriteRoutesPersistence, Sendable {
    func read() async throws -> FavoriteRoutesReceipt { FavoriteRoutesReceipt(records: [], canUndo: false) }
    func save(_: FavoriteRouteSaveCandidate, label: String?) async throws -> FavoriteRouteSaveReceipt { throw FavoriteRoutesFailure.busy }
    func validate(_: UUID) async throws -> FavoriteRouteSnapshot { throw FavoriteRoutesFailure.busy }
    func updateLabel(_: UUID, label: String?) async throws -> FavoriteRoutesReceipt { throw FavoriteRoutesFailure.busy }
    func delete(_: UUID) async throws -> FavoriteRoutesReceipt { throw FavoriteRoutesFailure.busy }
    func undoDelete() async throws -> FavoriteRoutesReceipt { throw FavoriteRoutesFailure.busy }
}

private actor CoverageGatedFavoriteRoutesPersistence: FavoriteRoutesPersistence {
    let snapshot: FavoriteRouteSnapshot
    var entered = false
    var continuation: CheckedContinuation<FavoriteRouteSnapshot, Never>?
    init(snapshot: FavoriteRouteSnapshot) { self.snapshot = snapshot }
    func read() async throws -> FavoriteRoutesReceipt { FavoriteRoutesReceipt(records: [snapshot.record], canUndo: false) }
    func save(_: FavoriteRouteSaveCandidate, label: String?) async throws -> FavoriteRouteSaveReceipt { throw FavoriteRoutesFailure.busy }
    func validate(_: UUID) async throws -> FavoriteRouteSnapshot {
        entered = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func updateLabel(_: UUID, label: String?) async throws -> FavoriteRoutesReceipt { throw FavoriteRoutesFailure.busy }
    func delete(_: UUID) async throws -> FavoriteRoutesReceipt { throw FavoriteRoutesFailure.busy }
    func undoDelete() async throws -> FavoriteRoutesReceipt { throw FavoriteRoutesFailure.busy }
    func finish() { continuation?.resume(returning: snapshot); continuation = nil }
}

private actor CoverageGatedTransferPersistence: ImportedRoutesPersistence {
    var entered = false
    var continuation: CheckedContinuation<TransferArchiveSnapshot, Error>?
    func read() async throws -> ImportedRoutesReceipt { ImportedRoutesReceipt(records: [], canUndo: false) }
    func importArtifact(_: ImportedRouteArtifact) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
    func validate(_: UUID) async throws -> ImportedRouteSnapshot { throw ImportedRoutesFailure.busy }
    func transferSnapshot() async throws -> TransferArchiveSnapshot {
        entered = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func delete(_: UUID) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
    func undoDelete() async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
    func finish() { continuation?.resume(throwing: ImportedRoutesFailure.busy); continuation = nil }
}

private actor CoverageMismatchTransferPersistence: ImportedRoutesPersistence {
    let expected: ImportedRouteRecord
    let returned: TransferArchiveSnapshot
    var entered = false

    init(expected: ImportedRouteRecord, returned: ImportedRouteSnapshot) throws {
        self.expected = expected
        let artifact = try ImportedRouteArtifact(document: returned.document, filename: returned.record.filename)
        self.returned = TransferArchiveSnapshot(
            manifest: try importedManifestData(for: returned.record),
            payloads: ["\(returned.record.id.uuidString).gpx": artifact.payload]
        )
    }

    func read() async throws -> ImportedRoutesReceipt {
        ImportedRoutesReceipt(records: [expected], canUndo: false)
    }
    func transferSnapshot() async throws -> TransferArchiveSnapshot {
        entered = true
        return returned
    }
    func importArtifact(_: ImportedRouteArtifact) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
    func validate(_: UUID) async throws -> ImportedRouteSnapshot { throw ImportedRoutesFailure.busy }
    func delete(_: UUID) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
    func undoDelete() async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
}

private actor CoverageCountingTransferPersistence: ImportedRoutesPersistence {
    var transferCalls = 0

    func read() async throws -> ImportedRoutesReceipt {
        ImportedRoutesReceipt(records: [], canUndo: false)
    }
    func transferSnapshot() async throws -> TransferArchiveSnapshot {
        transferCalls += 1
        return TransferArchiveSnapshot(
            manifest: emptyImportedManifestData(), payloads: [:]
        )
    }
    func importArtifact(_: ImportedRouteArtifact) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
    func validate(_: UUID) async throws -> ImportedRouteSnapshot { throw ImportedRoutesFailure.busy }
    func delete(_: UUID) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
    func undoDelete() async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
}

private actor CoverageGatedValidTransferPersistence: ImportedRoutesPersistence {
    let snapshot: ImportedRouteSnapshot
    var entered = false
    var continuation: CheckedContinuation<TransferArchiveSnapshot, Never>?

    init(snapshot: ImportedRouteSnapshot) { self.snapshot = snapshot }
    func read() async throws -> ImportedRoutesReceipt {
        ImportedRoutesReceipt(records: [snapshot.record], canUndo: false)
    }
    func transferSnapshot() async throws -> TransferArchiveSnapshot {
        entered = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() throws {
        let artifact = try ImportedRouteArtifact(document: snapshot.document, filename: snapshot.record.filename)
        let transfer = TransferArchiveSnapshot(
            manifest: try importedManifestData(for: snapshot.record),
            payloads: ["\(snapshot.record.id.uuidString).gpx": artifact.payload]
        )
        continuation?.resume(returning: transfer)
        continuation = nil
    }
    func importArtifact(_: ImportedRouteArtifact) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
    func validate(_: UUID) async throws -> ImportedRouteSnapshot { throw ImportedRoutesFailure.busy }
    func delete(_: UUID) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
    func undoDelete() async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.busy }
}

private actor CoverageGatedPlanner: RoutePlanning {
    var entered = false
    var continuation: CheckedContinuation<[GeoCoordinate], Error>?
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        entered = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: []); continuation = nil }
}

@MainActor
private final class CoverageReadyRouteCommands: CoverageRouteCommands {
    override var canBeginRoute: Bool { true }
}

@MainActor
private final class CoverageGatedJoystickCommands: CoverageJoystickCommands {
    override var canBeginJoystick: Bool { true }
    override var currentJoystickOrigin: GeoCoordinate? { GeoCoordinate(latitude: 25, longitude: 121) }
    private(set) var idleEntered = false
    private var idleContinuation: CheckedContinuation<JoystickIdleSettlement, Never>?
    override func beginJoystick(_ intent: JoystickMovementIntent, expectedMovementAdmissionRevision: UInt64) async -> JoystickPreparationOutcome { .prepared }
    override func waitForJoystickIdle(executionID: UUID, lease: MovementTaskLease) async -> JoystickIdleSettlement {
        idleEntered = true
        return await withCheckedContinuation { idleContinuation = $0 }
    }
    func finishIdle() { idleContinuation?.resume(returning: .settled); idleContinuation = nil }
}

private struct CoverageSessionPersistence: SessionRecoveryPersistence, Sendable {
    func read() throws -> Data? { nil }
    func replaceAtomically(with data: Data) throws {}
}

private final class CoverageGatedSessionPersistence: SessionRecoveryPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var _entered = false
    private var _released = false
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return _entered }
    func read() throws -> Data? { nil }
    func replaceAtomically(with data: Data) throws {
        lock.lock(); _entered = true; lock.unlock()
        while true {
            lock.lock(); let released = _released; lock.unlock()
            if released { return }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }
    func release() { lock.lock(); _released = true; lock.unlock() }
}
