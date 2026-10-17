import Foundation
import Darwin
import Testing
import GoFlyCore

struct SessionRecoveryPersistenceTests {
    @Test func codecRoundTripsLiteralManualData() throws {
        let snapshot = try fixtureSnapshot()
        let data = try SessionRecoveryCodec.encode(snapshot, revision: 4)
        let record = try SessionRecoveryCodec.decodeRecord(data)
        #expect(record.revision == 4)
        #expect(record.snapshot == snapshot)

        let literal = Data(#"{"activeMovement":null,"draft":{"gpxData":null,"gpxFilename":null,"nodes":[{"id":"00000000-0000-0000-0000-000000000001","kind":"current","place":null}],"sourceKind":"manual","speed":20},"joystickSpeed":20,"mode":"teleport","position":{"coordinate":{"latitude":25,"longitude":121},"source":"gps"},"revision":9,"roundTripEnabled":false,"schemaVersion":1,"uncertainty":null}"#.utf8)
        let decoded = try SessionRecoveryCodec.decodeRecord(literal)
        #expect(decoded.revision == 9)
        #expect(decoded.snapshot.mode == .teleport)
        #expect(decoded.snapshot.position?.coordinate == GeoCoordinate(latitude: 25, longitude: 121)!)
        #expect(decoded.snapshot.draft.nodes.count == 1)
    }

    @Test func codecRoundTripsPublicActiveRouteLiteral() throws {
        let snapshot = try fixtureSnapshot()
        let start = GeoCoordinate(latitude: 25.01, longitude: 121.01)!
        let end = GeoCoordinate(latitude: 25.02, longitude: 121.02)!
        let route = try PlannedRoute(points: [start, end], from: start, to: end)
        let literal = try activeRouteLiteralData(
            base: SessionRecoveryCodec.encode(snapshot), points: route.points,
            totalDistanceMeters: route.totalDistanceMeters, heading: "reverse",
            roundTripEnabled: true, usesPositionAxis: true, state: "paused",
            committedDistanceMeters: route.totalDistanceMeters / 2,
            activeElapsedSeconds: 34, estimatedRemainingSeconds: 12)

        let decoded = try SessionRecoveryCodec.decode(literal)
        let active = try #require(decoded.activeMovement)
        guard case .route(let recovery) = active else {
            Issue.record("expected a public route recovery literal")
            return
        }
        #expect(decoded.draft.nodes.map(\.id) == snapshot.draft.nodes.map(\.id))
        #expect(recovery.draft == decoded.draft)
        #expect(recovery.route.points == route.points)
        #expect(recovery.progress.committedDistanceMeters == route.totalDistanceMeters / 2)
        #expect(recovery.progress.totalDistanceMeters == route.totalDistanceMeters)
        #expect(recovery.progress.activeElapsed == Duration(secondsComponent: 34, attosecondsComponent: 0))
        #expect(recovery.progress.estimatedRemaining == Duration(secondsComponent: 12, attosecondsComponent: 0))
        #expect(recovery.roundTripEnabled)
        #expect(recovery.usesPositionAxis)
        #expect(recovery.heading == .reverse)
        #expect(recovery.state == .paused)
        #expect(try SessionRecoveryCodec.decode(try SessionRecoveryCodec.encode(decoded)) == decoded)
    }

    @Test func codecPreservesGPXGroupingFilenameAndCoordinates() throws {
        let a = GeoCoordinate(latitude: 25, longitude: 121)!
        let b = GeoCoordinate(latitude: 25.001, longitude: 121.001)!
        let c = GeoCoordinate(latitude: 25.002, longitude: 121.002)!
        let document = try GPXDocument(content: .tracks([GPXTrack(segments: [[a, b], [b, c]])]))
        let source = try GPXRouteSource(document: document, displayFilename: "walk.gpx")
        let snapshot = SessionRecoverySnapshot(mode: .route, draft: RouteDraft(gpx: source), position: nil)
        let roundTripped = try SessionRecoveryCodec.decode(try SessionRecoveryCodec.encode(snapshot))
        #expect(roundTripped.draft.gpxSource?.displayFilename == "walk.gpx")
        #expect(roundTripped.draft.gpxSource?.document == document)
    }

    @Test func codecPreservesAllSupportedGPXKindsAndDataOnlyActiveStates() throws {
        let a = GeoCoordinate(latitude: 25, longitude: 121)!
        let b = GeoCoordinate(latitude: 25.001, longitude: 121.001)!
        let c = GeoCoordinate(latitude: 25.002, longitude: 121.002)!
        let documents: [GPXDocument] = [
            try GPXDocument(content: .tracks([GPXTrack(segments: [[a, b], [b, c]])])),
            try GPXDocument(content: .routes([GPXRoute(points: [a, b]), GPXRoute(points: [b, c])])),
            try GPXDocument(content: .waypoints([a, b]))
        ]
        for (index, document) in documents.enumerated() {
            let source = try GPXRouteSource(document: document, displayFilename: "kind-\(index).gpx")
            let snapshot = SessionRecoverySnapshot(mode: .route, draft: RouteDraft(gpx: source))
            let decoded = try SessionRecoveryCodec.decode(try SessionRecoveryCodec.encode(snapshot))
            #expect(decoded.draft.gpxSource?.document == document)
            #expect(decoded.draft.gpxSource?.displayFilename == "kind-\(index).gpx")
        }

        let target = WanderTarget(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!, place: place(a))
        let wander = SessionRecoverySnapshot(mode: .joystick,
            activeMovement: .wander(SessionWanderRecovery(target: target, speed: .standard,
                history: [a, b], lastAcknowledgedCoordinate: c,
                lastAcknowledgedBearingDegrees: 120, state: .uncertain)))
        #expect(try SessionRecoveryCodec.decode(try SessionRecoveryCodec.encode(wander)) == wander)
        let manual = SessionRecoverySnapshot(activeMovement: .manual)
        #expect(try SessionRecoveryCodec.decode(try SessionRecoveryCodec.encode(manual)) == manual)
        let terminal = SessionRecoverySnapshot(mode: .route)
        #expect(try SessionRecoveryCodec.decode(try SessionRecoveryCodec.encode(terminal)) == terminal)
    }

    @Test @MainActor func storeLoadsBeforeUseAndFlushesLatestAcceptedSnapshot() async throws {
        let persistence = MemorySessionRecoveryPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        let snapshot = try fixtureSnapshot()
        #expect(store.loadState == .ready)
        #expect(store.capture(snapshot))
        #expect(await store.flush())
        #expect(store.hasUnsavedChanges == false)

        let relaunched = SessionRecoveryStore(persistence: persistence)
        #expect(relaunched.initialSnapshot == snapshot)
        #expect(relaunched.loadState == .ready)
    }

    private func invalidHistorySnapshot(draft: RouteDraft) -> SessionRecoverySnapshot {
        let coordinate = GeoCoordinate(latitude: 25, longitude: 121)!
        let target = WanderTarget(place: place(coordinate))
        return SessionRecoverySnapshot(mode: .joystick, draft: draft,
            activeMovement: .wander(SessionWanderRecovery(target: target, speed: .standard,
                history: Array(repeating: coordinate, count: SessionRecoveryLimits.historyPoints + 1),
                lastAcknowledgedCoordinate: coordinate, lastAcknowledgedBearingDegrees: nil,
                state: .uncertain)))
    }

    @Test @MainActor func invalidLatestCannotRetryOlderGoodSnapshot() async throws {
        let persistence = MemorySessionRecoveryPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        let valid = try fixtureSnapshot()
        #expect(store.capture(valid))
        #expect(await store.flush())
        let invalid = invalidHistorySnapshot(draft: valid.draft)
        #expect(store.capture(invalid) == false)
        #expect(store.retrySaving() == false)
        #expect(store.hasUnsavedChanges)
        let saved = try #require(persistence.data)
        #expect(try SessionRecoveryCodec.decode(saved) == valid)
    }

    @Test @MainActor func failedInitialReadBlocksCaptureAndAutowrite() throws {
        let persistence = UnavailableSessionRecoveryPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        #expect(store.loadState == .blocked(.unavailable))
        #expect(store.capture(try fixtureSnapshot()) == false)
        #expect(store.retrySaving() == false)
        #expect(persistence.didWrite == false)
    }

    @Test @MainActor func revisionOverflowBlocksCaptureWithoutChangingAuthoritativeBytes() throws {
        let snapshot = SessionRecoverySnapshot()
        let record = try SessionRecoveryCodec.encode(snapshot, revision: UInt64.max)
        let persistence = MemorySessionRecoveryPersistence()
        persistence.seed(record)
        let store = SessionRecoveryStore(persistence: persistence)
        #expect(store.initialSnapshot == snapshot)
        #expect(store.capture(snapshot) == false)
        #expect(store.loadState == .blocked(.revisionExhausted))
        #expect(persistence.data == record)
    }

    @Test func codecRoundTripsTenThousandPointGPXRootAndActiveRouteOnce() throws {
        let points = try boundaryPoints(count: 10_000)
        let document = try GPXDocument(content: .routes([GPXRoute(points: points)]))
        let source = try GPXRouteSource(document: document, displayFilename: "boundary.gpx")
        let draft = RouteDraft(gpx: source)
        let snapshot = SessionRecoverySnapshot(mode: .route, draft: draft, roundTripEnabled: true)
        let route = try PlannedRoute(imported: document)
        let literal = try activeRouteLiteralData(
            base: SessionRecoveryCodec.encode(snapshot), points: route.points,
            totalDistanceMeters: route.totalDistanceMeters, heading: "forward",
            roundTripEnabled: true, usesPositionAxis: true, state: "running",
            committedDistanceMeters: 0, activeElapsedSeconds: 0, estimatedRemainingSeconds: 0)
        let decoded = try SessionRecoveryCodec.decode(literal)
        let roundTripped = try #require(decoded.draft.gpxSource)
        #expect(roundTripped.document.pointCount == 10_000)
        #expect(roundTripped.document.segments.first?.first == points.first)
        #expect(roundTripped.document.segments.first?.last == points.last)
        #expect(roundTripped.displayFilename == "boundary.gpx")
        let active = try #require(decoded.activeMovement)
        guard case .route(let recovery) = active else {
            Issue.record("expected a public ten-thousand-point route recovery literal")
            return
        }
        #expect(recovery.route.points == points)
        #expect(recovery.draft == decoded.draft)
        let encoded = try SessionRecoveryCodec.encode(decoded)
        #expect(encoded.count <= SessionRecoveryLimits.recordBytes)
        let encodedText = try #require(String(data: encoded, encoding: .utf8))
        #expect(encodedText.components(separatedBy: "gpxData").count - 1 == 1)
    }

    @Test func codecRejectsActivePathAboveTenThousandPoints() throws {
        let baselinePoints = try boundaryPoints(count: 10_000)
        let baselineRoute = try PlannedRoute(points: baselinePoints, from: baselinePoints[0], to: baselinePoints.last!)
        let baseline = try activeRouteLiteralData(
            base: SessionRecoveryCodec.encode(try fixtureSnapshot()), points: baselinePoints,
            totalDistanceMeters: baselineRoute.totalDistanceMeters, heading: "forward",
            roundTripEnabled: false, usesPositionAxis: false, state: "uncertain",
            committedDistanceMeters: 0, activeElapsedSeconds: 0, estimatedRemainingSeconds: 0)
        let valid = try SessionRecoveryCodec.decode(baseline)
        let validActive = try #require(valid.activeMovement)
        guard case .route(let validRoute) = validActive else {
            Issue.record("expected the ten-thousand-point baseline to decode")
            return
        }
        #expect(validRoute.route.points.count == 10_000)

        let tooManyPoints = baselinePoints + [GeoCoordinate(latitude: 25.1, longitude: 121.1)!]
        let malformed = try activeRouteLiteralData(
            base: SessionRecoveryCodec.encode(try fixtureSnapshot()), points: tooManyPoints,
            totalDistanceMeters: baselineRoute.totalDistanceMeters, heading: "forward",
            roundTripEnabled: false, usesPositionAxis: false, state: "uncertain",
            committedDistanceMeters: 0, activeElapsedSeconds: 0, estimatedRemainingSeconds: 0)
        #expect(throws: SessionRecoveryFailure.invalidSnapshot) {
            try SessionRecoveryCodec.decode(malformed)
        }
    }

    @Test func codecRejectsUnknownTagsAndInvalidCoordinates() throws {
        let encoded = try SessionRecoveryCodec.encode(try fixtureSnapshot())
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        root["mode"] = "unknown-mode"
        let unknownTag = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: SessionRecoveryFailure.corruptArchive) {
            try SessionRecoveryCodec.decode(unknownTag)
        }

        root["mode"] = "route"
        var position = try #require(root["position"] as? [String: Any])
        var coordinate = try #require(position["coordinate"] as? [String: Any])
        coordinate["latitude"] = 91
        position["coordinate"] = coordinate
        root["position"] = position
        let invalidCoordinate = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: SessionRecoveryFailure.invalidSnapshot) {
            try SessionRecoveryCodec.decode(invalidCoordinate)
        }
    }

    @Test @MainActor func failedWriteKeepsLatestDirtyAndRetriesOnlyThatSnapshot() async throws {
        let persistence = FailingSessionRecoveryPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        let snapshot = try fixtureSnapshot()
        #expect(store.capture(snapshot))
        #expect(await store.flush() == false)
        #expect(await store.flush() == false)
        #expect(store.error == .writeFailed)
        #expect(store.hasUnsavedChanges)
        persistence.failWrites = false
        #expect(store.retrySaving())
        #expect(await store.flush())
        #expect(store.hasUnsavedChanges == false)
        #expect(try SessionRecoveryCodec.decode(try #require(persistence.data)) == snapshot)
    }

    @Test @MainActor func retryIsRejectedWhileWriteIsActiveAndFlushWaitsForRetry() async throws {
        let persistence = GatedSessionRecoveryPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        #expect(store.capture(try fixtureSnapshot()))
        await persistence.waitUntilFirstWriteStarts()
        #expect(store.retrySaving() == false)
        let waiter = Task { @MainActor in await store.flush() }
        persistence.releaseFirstWrite()
        #expect(await waiter.value)
        #expect(store.hasUnsavedChanges == false)
    }

    @Test @MainActor func flushAfterRetryWaitsForTheRetryResult() async throws {
        let persistence = RetryGatedSessionRecoveryPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        #expect(store.capture(try fixtureSnapshot()))
        #expect(await store.flush() == false)
        persistence.allowRetry()
        #expect(store.retrySaving())
        await persistence.waitUntilRetryStarts()
        let waiter = Task { @MainActor in await store.flush() }
        persistence.releaseRetry()
        #expect(await waiter.value)
        #expect(store.hasUnsavedChanges == false)
    }

    @Test @MainActor func writerKeepsOneNewestPendingRevisionAndFlushWaitsForCutline() async throws {
        let persistence = GatedSessionRecoveryPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        var snapshot = try fixtureSnapshot()
        #expect(store.capture(snapshot))
        await persistence.waitUntilFirstWriteStarts()
        snapshot = SessionRecoverySnapshot(mode: .joystick, draft: snapshot.draft, joystickSpeed: .standard)
        #expect(store.capture(snapshot))
        snapshot = SessionRecoverySnapshot(mode: .teleport, draft: snapshot.draft)
        #expect(store.capture(snapshot))
        persistence.releaseFirstWrite()
        #expect(await store.flush())
        let records = persistence.writes.compactMap { try? SessionRecoveryCodec.decodeRecord($0).revision }
        #expect(records == [1, 3])
        #expect(store.hasUnsavedChanges == false)
    }

    @Test @MainActor func cancellingFlushWaiterDoesNotCancelUnderlyingAtomicWrite() async throws {
        let persistence = GatedSessionRecoveryPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        #expect(store.capture(try fixtureSnapshot()))
        await persistence.waitUntilFirstWriteStarts()
        let waiter = Task { @MainActor in await store.flush() }
        waiter.cancel()
        #expect(await waiter.value == false)
        persistence.releaseFirstWrite()
        await persistence.waitUntilWriteCount(1)
        #expect(store.hasUnsavedChanges == false)
    }

    @Test @MainActor func anInvalidLatestAttemptCannotBeClearedByAnOlderInFlightCompletion() async throws {
        let persistence = GatedSessionRecoveryPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        let valid = try fixtureSnapshot()
        #expect(store.capture(valid))
        await persistence.waitUntilFirstWriteStarts()
        let invalid = invalidHistorySnapshot(draft: valid.draft)
        #expect(store.capture(invalid) == false)
        persistence.releaseFirstWrite()
        await persistence.waitUntilWriteCount(1)
        try? await Task.sleep(for: .milliseconds(5))
        #expect(store.error == .limitExceeded)
        #expect(store.isSaving == false)
        #expect(store.hasUnsavedChanges)
        #expect(store.retrySaving() == false)
    }

    @Test func filePersistenceUsesDedicatedSessionFileAndRoundTripsBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GoFlySession-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileSessionRecoveryPersistence(directory: directory)
        #expect(try persistence.read() == nil)
        let bytes = Data("known checkpoint".utf8)
        try persistence.replaceAtomically(with: bytes)
        #expect(try persistence.read() == bytes)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("session.json").path))
    }

    @Test func filePersistenceRejectsAuthoritativeSymlinkWithoutChangingTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GoFlySession-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("outside.json")
        try Data("old".utf8).write(to: target)
        let session = directory.appendingPathComponent("session.json")
        try FileManager.default.createSymbolicLink(at: session, withDestinationURL: target)
        let persistence = FileSessionRecoveryPersistence(directory: directory)
        #expect(throws: SessionRecoveryFailure.unsafeFile) { try persistence.read() }
        #expect(throws: SessionRecoveryFailure.unsafeFile) { try persistence.replaceAtomically(with: Data("new".utf8)) }
        #expect(try Data(contentsOf: target) == Data("old".utf8))
    }

    @Test func filePersistencePrecommitFaultPreservesAuthoritativeBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GoFlySession-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileSessionRecoveryPersistence(directory: directory)
        let old = Data("old checkpoint".utf8)
        try persistence.replaceAtomically(with: old)
        let failing = FileSessionRecoveryPersistence(directory: directory) { point in
            if point == .beforeCommit { throw SessionRecoveryFailure.writeFailed }
        }
        #expect(throws: SessionRecoveryFailure.writeFailed) {
            try failing.replaceAtomically(with: Data("new checkpoint".utf8))
        }
        #expect(try persistence.read() == old)
    }

    @Test func filePersistenceRejectsSymlinkDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GoFlySession-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let realDirectory = root.appendingPathComponent("real")
        let linkedDirectory = root.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: realDirectory)
        let persistence = FileSessionRecoveryPersistence(directory: linkedDirectory)
        #expect(throws: SessionRecoveryFailure.unsafeFile) { try persistence.read() }
        #expect(throws: SessionRecoveryFailure.unsafeFile) {
            try persistence.replaceAtomically(with: Data("blocked".utf8))
        }
    }

    @Test func filePersistenceRejectsFIFOAuthoritativePath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GoFlySession-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = directory.appendingPathComponent("session.json")
        #expect(mkfifo(session.path, 0o600) == 0)
        let persistence = FileSessionRecoveryPersistence(directory: directory)
        #expect(throws: SessionRecoveryFailure.unsafeFile) { try persistence.read() }
        #expect(throws: SessionRecoveryFailure.unsafeFile) {
            try persistence.replaceAtomically(with: Data("blocked".utf8))
        }
    }

    @Test func filePersistenceCleansOnlyOwnedStagingAndUsesPrivateModes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GoFlySession-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let owned = directory.appendingPathComponent(".session-\(UUID().uuidString).staging")
        let foreign = directory.appendingPathComponent(".session-foreign.staging")
        try Data("owned orphan".utf8).write(to: owned)
        try Data("foreign orphan".utf8).write(to: foreign)
        let persistence = FileSessionRecoveryPersistence(directory: directory)
        try persistence.replaceAtomically(with: Data("checkpoint".utf8))
        #expect(FileManager.default.fileExists(atPath: owned.path) == false)
        #expect(FileManager.default.fileExists(atPath: foreign.path))
        let directoryMode = try #require(FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber).intValue & 0o777
        let sessionMode = try #require(FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("session.json").path)[.posixPermissions] as? NSNumber).intValue & 0o777
        #expect(directoryMode == 0o700)
        #expect(sessionMode == 0o600)
    }

    private func fixtureSnapshot() throws -> SessionRecoverySnapshot {
        let start = GeoCoordinate(latitude: 25, longitude: 121)!
        let end = GeoCoordinate(latitude: 25.001, longitude: 121.001)!
        let draft = try #require(RouteDraft(values: [.place(place(start)), .place(place(end))]))
        return SessionRecoverySnapshot(mode: .route, draft: draft, roundTripEnabled: true,
            joystickSpeed: .standard, position: SessionDisplayPosition(coordinate: start, source: .simulation),
            uncertainty: SessionMovementUncertainty(source: .route, requestedPlace: place(end)))
    }

    private func place(_ coordinate: GeoCoordinate) -> MapPlace {
        MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
    }

    private func boundaryPoints(count: Int) throws -> [GeoCoordinate] {
        try (0..<count).map { index in
            try #require(GeoCoordinate(latitude: 25 + Double(index) * 0.00001,
                                        longitude: 121 + Double(index) * 0.00001))
        }
    }

    private func activeRouteLiteralData(
        base: Data, points: [GeoCoordinate], totalDistanceMeters: Double,
        heading: String, roundTripEnabled: Bool, usesPositionAxis: Bool,
        state: String, committedDistanceMeters: Double,
        activeElapsedSeconds: Int64, estimatedRemainingSeconds: Int64) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: base) as? [String: Any])
        let pointObjects = points.map { ["latitude": $0.latitude, "longitude": $0.longitude] }
        root["activeMovement"] = [
            "kind": "route",
            "route": [
                "draft": NSNull(),
                "heading": heading,
                "points": pointObjects,
                "progress": [
                    "activeElapsed": ["attoseconds": 0, "seconds": activeElapsedSeconds],
                    "committed": committedDistanceMeters,
                    "estimatedRemaining": ["attoseconds": 0, "seconds": estimatedRemainingSeconds],
                    "total": totalDistanceMeters
                ],
                "roundTripEnabled": roundTripEnabled,
                "state": state,
                "usesPositionAxis": usesPositionAxis
            ]
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}

private final class MemorySessionRecoveryPersistence: SessionRecoveryPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var data: Data?

    func read() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return data
    }

    func replaceAtomically(with data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        self.data = data
    }

    func seed(_ data: Data) {
        lock.lock(); self.data = data; lock.unlock()
    }
}

private final class UnavailableSessionRecoveryPersistence: SessionRecoveryPersistence, @unchecked Sendable {
    private(set) var didWrite = false

    func read() throws -> Data? { throw SessionRecoveryFailure.unavailable }

    func replaceAtomically(with data: Data) throws {
        didWrite = true
    }
}

private final class FailingSessionRecoveryPersistence: SessionRecoveryPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?
    private var shouldFail = true

    var data: Data? {
        lock.lock(); defer { lock.unlock() }
        return storedData
    }

    var failWrites: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return shouldFail
        }
        set {
            lock.lock(); shouldFail = newValue; lock.unlock()
        }
    }

    func read() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storedData
    }

    func replaceAtomically(with data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if shouldFail { throw SessionRecoveryFailure.writeFailed }
        storedData = data
    }
}

private final class GatedSessionRecoveryPersistence: SessionRecoveryPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var released = false
    private var storedWrites: [Data] = []

    var writes: [Data] {
        lock.lock(); defer { lock.unlock() }
        return storedWrites
    }

    func read() throws -> Data? { nil }

    func replaceAtomically(with data: Data) throws {
        lock.lock()
        let first = storedWrites.isEmpty
        if first { started = true }
        let shouldWait = first && !released
        lock.unlock()
        if shouldWait {
            while true {
                lock.lock(); let done = released; lock.unlock()
                if done { break }
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
        lock.lock(); storedWrites.append(data); lock.unlock()
    }

    func releaseFirstWrite() {
        lock.lock(); released = true; lock.unlock()
    }

    func waitUntilFirstWriteStarts() async {
        while true {
            if isFirstWriteStarted { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func waitUntilWriteCount(_ count: Int) async {
        while true {
            if writeCount >= count { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private var isFirstWriteStarted: Bool {
        lock.lock(); defer { lock.unlock() }
        return started
    }

    private var writeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return storedWrites.count
    }
}

private final class RetryGatedSessionRecoveryPersistence: SessionRecoveryPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var retryAllowed = false
    private var retryStarted = false
    private var retryReleased = false
    private var storedData: Data?

    func read() throws -> Data? { nil }

    func replaceAtomically(with data: Data) throws {
        lock.lock()
        guard retryAllowed else {
            lock.unlock()
            throw SessionRecoveryFailure.writeFailed
        }
        retryStarted = true
        lock.unlock()
        while true {
            lock.lock(); let released = retryReleased; lock.unlock()
            if released { break }
            Thread.sleep(forTimeInterval: 0.001)
        }
        lock.lock(); storedData = data; lock.unlock()
    }

    func allowRetry() {
        lock.lock(); retryAllowed = true; lock.unlock()
    }

    func releaseRetry() {
        lock.lock(); retryReleased = true; lock.unlock()
    }

    func waitUntilRetryStarts() async {
        while true {
            if isRetryStarted { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private var isRetryStarted: Bool {
        lock.lock(); defer { lock.unlock() }
        return retryStarted
    }
}
