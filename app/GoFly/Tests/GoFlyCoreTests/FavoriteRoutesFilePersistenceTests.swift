import Darwin
import CryptoKit
import Foundation
import Testing
@testable import GoFlyCore

struct FavoriteRoutesFilePersistenceTests {
    @Test func duplicatesRelaunchWithFullMetadataAndLabelEditsChangeOnlyManifest() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileFavoriteRoutesPersistence(directory: directory)
        let places = [FavoriteRoutesStoreTests.place(1), FavoriteRoutesStoreTests.place(1), FavoriteRoutesStoreTests.place(2)]
        let candidate = try FavoriteRouteSaveBuilder.build(draft: RouteDraft(values: places.map(RouteNodeValue.place))!, currentRouteOrigin: nil)
        let first = try await disk.save(candidate, label: "Label").result.record
        let second = try await disk.save(candidate, label: "Label").result.record
        #expect(first.id != second.id)
        #expect(first.sha256 == second.sha256)
        #expect(first.startTitle == "Place 1")
        #expect(first.endTitle == "Place 2")
        let payloadURL = directory.appendingPathComponent(first.id.uuidString + ".route")
        let payload = try Data(contentsOf: payloadURL)
        let beforeManifest = try Data(contentsOf: disk.manifestURL)
        let renamed = try await disk.updateLabel(first.id, label: "  Renamed  ")
        #expect(renamed.records[0].label == "Renamed")
        #expect(renamed.records[1] == second)
        #expect(renamed.records[0].sha256 == first.sha256)
        #expect(try Data(contentsOf: payloadURL) == payload)
        #expect(try Data(contentsOf: disk.manifestURL) != beforeManifest)
        let relaunched = FileFavoriteRoutesPersistence(directory: directory)
        #expect(try await relaunched.read() == renamed)
        #expect(try await relaunched.validate(first.id).source == .manual(places))
        #expect(try await relaunched.validate(second.id).source == .manual(places))
    }
    @Test func manualTwentySevenAndGPXTenThousandRelaunchWithCompleteSources() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileFavoriteRoutesPersistence(directory: directory)
        let places = (0..<27).map { FavoriteRoutesStoreTests.place($0 % 3 + 1) }
        let manual = try FavoriteRouteSaveBuilder.build(draft: RouteDraft(values: places.map(RouteNodeValue.place))!, currentRouteOrigin: nil)
        let savedManual = try await disk.save(manual, label: nil).result.record
        let a = GeoCoordinate(latitude: 25.123456789012345, longitude: 121.12345678901234)!
        let b = GeoCoordinate(latitude: 26, longitude: 122)!
        let document = try GPXDocument(content: .tracks([GPXTrack(segments: [Array(repeating: a, count: 5_000)]),
            GPXTrack(segments: [[a] + Array(repeating: b, count: 4_999)])]))
        let source = try GPXRouteSource(document: document, displayFilename: "10k.gpx")
        let gpx = try FavoriteRouteSaveBuilder.build(draft: RouteDraft(gpx: source), currentRouteOrigin: nil)
        let savedGPX = try await disk.save(gpx, label: "Full GPX").result.record
        let relaunched = FileFavoriteRoutesPersistence(directory: directory)
        #expect(try await relaunched.read().records == [savedManual, savedGPX])
        #expect(try await relaunched.validate(savedManual.id).source == .manual(places))
        #expect(try await relaunched.validate(savedGPX.id).source == .gpx(source))
        let payload = try Data(contentsOf: directory.appendingPathComponent(savedGPX.id.uuidString + ".route"))
        #expect(try GPXCodec.decode(payload) == document)
        #expect(!String(decoding: payload, as: UTF8.self).hasPrefix("{"))
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            #expect((try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        #expect((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test(arguments: [FavoriteRoutesWriteCheckpoint.payloadSecured, .payloadWritten, .payloadFlushed,
                      .manifestSecured, .manifestWritten, .manifestFlushed, .beforeManifestCommit])
    func everySavePrecommitFaultPreservesAuthoritativeBytes(point: FavoriteRoutesWriteCheckpoint) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let normal = FileFavoriteRoutesPersistence(directory: directory)
        let candidate = try sample()
        let original = try await normal.save(candidate, label: "Original")
        let bytes = try Data(contentsOf: normal.manifestURL)
        let failing = FileFavoriteRoutesPersistence(directory: directory) { if $0 == point { throw CocoaError(.fileWriteUnknown) } }
        await #expect(throws: FavoriteRoutesFailure.writeFailed) { try await failing.save(candidate, label: "New") }
        #expect(try Data(contentsOf: normal.manifestURL) == bytes)
        #expect(try await normal.read().records == original.archive.records)
        #expect(try await normal.validate(original.result.record.id).source == candidate.source)
    }

    @Test func failedLabelDeleteAndUndoKeepOriginalBytesAndUndoCanRetryWithTheSameIDAndIndex() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fault = FavoriteFileFault()
        let disk = FileFavoriteRoutesPersistence(directory: directory) { try fault.check($0) }
        let first = try await disk.save(sample(), label: "First").result.record
        let second = try await disk.save(sample(), label: "Second").result.record
        let originalBytes = try Data(contentsOf: disk.manifestURL)
        fault.set(.beforeManifestCommit)
        await #expect(throws: FavoriteRoutesFailure.writeFailed) { try await disk.updateLabel(first.id, label: "Changed") }
        await #expect(throws: FavoriteRoutesFailure.writeFailed) { try await disk.delete(first.id) }
        #expect(try Data(contentsOf: disk.manifestURL) == originalBytes)
        #expect(!(try await disk.read().canUndo))
        fault.set(nil)
        #expect(try await disk.delete(first.id).records == [second])
        let deletedBytes = try Data(contentsOf: disk.manifestURL)
        fault.set(.beforeManifestCommit)
        await #expect(throws: FavoriteRoutesFailure.writeFailed) { try await disk.undoDelete() }
        #expect(try Data(contentsOf: disk.manifestURL) == deletedBytes)
        #expect(try await disk.read().canUndo)
        fault.set(nil)
        #expect(try await disk.undoDelete().records == [first, second])
    }

    @Test func cleanupFailureCannotChangeCommitSuccessAndActualQuotaIncludesUndoAndRetainedOrphans() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fault = FavoriteFileFault()
        let disk = FileFavoriteRoutesPersistence(directory: directory) { try fault.check($0) }
        let first = try await disk.save(sample(), label: nil).result.record
        let second = try await disk.save(sample(), label: nil).result.record
        fault.set(.cleanup)
        _ = try await disk.delete(first.id)
        #expect(try await disk.delete(second.id).records.isEmpty)
        let orphan = directory.appendingPathComponent(UUID().uuidString + ".route")
        try Data().write(to: orphan)
        let handle = try FileHandle(forWritingTo: orphan)
        try handle.truncate(atOffset: UInt64(FavoriteRoutesLimits.payloadBytes - first.byteCount - second.byteCount))
        try handle.close()
        await #expect(throws: FavoriteRoutesFailure.limitExceeded) { try await disk.save(sample(), label: nil) }
        #expect(try await disk.read().records.isEmpty)
        #expect(try await disk.read().canUndo)
        fault.set(nil)
        #expect(try await disk.undoDelete().records == [second])
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func corruptUnknownDuplicateAndOversizedManifestsNeverMutateOrCleanPayloads() async throws {
        for problem in ["corrupt", "schema", "duplicate", "oversize"] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let disk = FileFavoriteRoutesPersistence(directory: directory)
            _ = try await disk.save(sample(), label: nil)
            var object = try manifestObject(disk.manifestURL)
            let bytes: Data
            switch problem {
            case "corrupt": bytes = Data("not-json".utf8)
            case "schema": object["schemaVersion"] = 99; bytes = try JSONSerialization.data(withJSONObject: object)
            case "duplicate":
                let records = try #require(object["records"] as? [[String: Any]])
                object["records"] = records + records
                bytes = try JSONSerialization.data(withJSONObject: object)
            default: bytes = Data(repeating: 32, count: FavoriteRoutesLimits.manifestBytes + 1)
            }
            try bytes.write(to: disk.manifestURL)
            let orphan = directory.appendingPathComponent(UUID().uuidString + ".route")
            try Data("keep owned orphan".utf8).write(to: orphan)
            await #expect(throws: (any Error).self) { try await disk.read() }
            await #expect(throws: (any Error).self) { try await disk.save(sample(), label: nil) }
            #expect(try Data(contentsOf: disk.manifestURL) == bytes)
            #expect(try String(contentsOf: orphan, encoding: .utf8) == "keep owned orphan")
        }
    }

    @Test func selectionRevalidatesHashAndEveryImmutableManualMetadataField() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileFavoriteRoutesPersistence(directory: directory)
        let record = try await disk.save(sample(), label: "Label").result.record
        let payload = directory.appendingPathComponent(record.id.uuidString + ".route")
        let original = try Data(contentsOf: payload)
        var damaged = original; damaged[damaged.startIndex] = 32
        try damaged.write(to: payload)
        #expect(try await disk.read().records == [record])
        await #expect(throws: FavoriteRoutesFailure.hashMismatch) { try await disk.validate(record.id) }
        try original.write(to: payload)
        for field in ["count", "start", "end", "startTitle", "endTitle"] {
            let originalManifest = try Data(contentsOf: disk.manifestURL)
            var object = try manifestObject(disk.manifestURL)
            var records = try #require(object["records"] as? [[String: Any]])
            switch field {
            case "count": records[0][field] = 3
            case "start", "end": records[0][field] = ["latitude": 8, "longitude": 9]
            default: records[0][field] = "Changed title"
            }
            object["records"] = records
            try JSONSerialization.data(withJSONObject: object).write(to: disk.manifestURL)
            await #expect(throws: FavoriteRoutesFailure.metadataMismatch) { try await disk.validate(record.id) }
            try originalManifest.write(to: disk.manifestURL)
        }
    }

    @Test(arguments: ["manifestSymlink", "payloadSymlink", "payloadFIFO", "payloadOversize", "directorySymlink", "manifestDirectory"])
    func unsafeOrOversizedFilesCannotBeFollowedOrReplaced(kind: String) async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("FavoriteRoutes")
        let outside = root.appendingPathComponent("sentinel")
        let disk = FileFavoriteRoutesPersistence(directory: directory)
        let record = try await disk.save(sample(), label: nil).result.record
        let sentinel = Data(repeating: 65, count: record.byteCount)
        try sentinel.write(to: outside)
        let manifestBefore = try Data(contentsOf: disk.manifestURL)
        if kind == "directorySymlink" {
            try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("old"))
            try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: root.appendingPathComponent("old"))
        } else {
            let target = kind.hasPrefix("payload") ? directory.appendingPathComponent(record.id.uuidString + ".route") : disk.manifestURL
            try FileManager.default.removeItem(at: target)
            if kind == "manifestDirectory" { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
            else if kind == "payloadFIFO" { #expect(mkfifo(target.path, 0o600) == 0) }
            else if kind == "payloadOversize" { try Data(repeating: 32, count: FavoriteRoutesLimits.fileBytes + 1).write(to: target) }
            else { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside) }
        }
        let expected: FavoriteRoutesFailure = kind == "payloadOversize" ? .metadataMismatch : .unsafeFile
        await #expect(throws: expected) { try await disk.read() }
        await #expect(throws: expected) { try await disk.save(sample(), label: nil) }
        #expect(try Data(contentsOf: outside) == sentinel)
        if kind.hasPrefix("payload") { #expect(try Data(contentsOf: disk.manifestURL) == manifestBefore) }
    }

    @Test func parallelSaveAndReadCannotCleanInFlightPayloadOrLoseACommittedRecord() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let barrier = FavoriteFileBarrier()
        let disk = FileFavoriteRoutesPersistence(directory: directory) { barrier.reach($0) }
        let candidate = try sample()
        let first = Task { try await disk.save(candidate, label: "One") }
        await barrier.waitUntilReached()
        let reader = Task { try await disk.read() }
        let second = Task { try await disk.save(candidate, label: "Two") }
        barrier.release()
        _ = try await first.value; _ = try await reader.value; _ = try await second.value
        let final = try await disk.read()
        #expect(final.records.count == 2)
        for record in final.records { #expect(try await disk.validate(record.id).source == candidate.source) }
    }

    @Test func cancellationBeforeAdmissionRejectsSaveButAfterTransactionBeginsReturnsItsRealReceipt() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let barrier = FavoriteFileBarrier()
        let disk = FileFavoriteRoutesPersistence(directory: directory) { barrier.reach($0) }
        let candidate = try sample()
        let first = Task { try await disk.save(candidate, label: "Committed") }
        await barrier.waitUntilReached()
        let cancelled = Task { try await disk.save(candidate, label: "Cancelled") }
        cancelled.cancel(); first.cancel(); barrier.release()
        let receipt = try await first.value
        #expect(receipt.result.record.label == "Committed")
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try await disk.read().records == receipt.archive.records)
    }

    @Test func manualPayloadSchemaAndEveryMapPlaceFieldAreRevalidatedEvenWithMatchingHashAndSize() async throws {
        for problem in ["schema", "identity", "missingIdentity", "longIdentity", "coordinate", "title", "address"] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let disk = FileFavoriteRoutesPersistence(directory: directory)
            let record = try await disk.save(sample(), label: nil).result.record
            let payloadURL = directory.appendingPathComponent(record.id.uuidString + ".route")
            var payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: payloadURL)) as? [String: Any])
            var places = try #require(payload["places"] as? [[String: Any]])
            switch problem {
            case "schema": payload["schemaVersion"] = 99
            case "identity": places[0]["identity"] = ["kind": "unknown"]
            case "missingIdentity": places[0]["identity"] = ["kind": "mapKit"]
            case "longIdentity": places[0]["identity"] = ["kind": "mapKit", "value": String(repeating: "x", count: 2_049)]
            case "coordinate": places[0]["coordinate"] = ["latitude": 91, "longitude": 121]
            case "title": places[0]["title"] = " "
            default: places[0]["address"] = String(repeating: "x", count: 2_049)
            }
            payload["places"] = places
            let bytes = try JSONSerialization.data(withJSONObject: payload)
            try bytes.write(to: payloadURL)
            var manifest = try manifestObject(disk.manifestURL)
            var records = try #require(manifest["records"] as? [[String: Any]])
            records[0]["byteCount"] = bytes.count
            records[0]["sha256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            manifest["records"] = records
            try JSONSerialization.data(withJSONObject: manifest).write(to: disk.manifestURL)
            let expected: FavoriteRoutesFailure = problem == "schema" ? .unsupportedSchema : .corruptArchive
            await #expect(throws: expected) { try await disk.validate(record.id) }
            #expect(try Data(contentsOf: payloadURL) == bytes)
        }
    }

    @Test func gpxFilenameIsImmutableCrossvalidatedMetadataAndCannotBeReplacedByAManualRecord() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileFavoriteRoutesPersistence(directory: directory)
        let document = try GPXDocument(content: .waypoints([FavoriteRoutesStoreTests.place(1).coordinate, FavoriteRoutesStoreTests.place(2).coordinate]))
        let source = try GPXRouteSource(document: document, displayFilename: "original.gpx")
        let candidate = try FavoriteRouteSaveBuilder.build(draft: RouteDraft(gpx: source), currentRouteOrigin: nil)
        let record = try await disk.save(candidate, label: nil).result.record
        var object = try manifestObject(disk.manifestURL)
        var records = try #require(object["records"] as? [[String: Any]])
        records[0]["displayFilename"] = "different.gpx"
        object["records"] = records
        try JSONSerialization.data(withJSONObject: object).write(to: disk.manifestURL)
        await #expect(throws: FavoriteRoutesFailure.metadataMismatch) { try await disk.validate(record.id) }
        records[0]["sourceKind"] = "manual"
        object["records"] = records
        try JSONSerialization.data(withJSONObject: object).write(to: disk.manifestURL)
        await #expect(throws: FavoriteRoutesFailure.corruptArchive) { try await disk.read() }
    }

    @Test func recordLimitIsExactlyOneHundredAndNewDeletionReplacesTransientUndo() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileFavoriteRoutesPersistence(directory: directory)
        let candidate = try sample()
        for _ in 0..<100 { _ = try await disk.save(candidate, label: nil) }
        let records = try await disk.read().records
        #expect(records.count == 100)
        let bytes = try Data(contentsOf: disk.manifestURL)
        await #expect(throws: FavoriteRoutesFailure.limitExceeded) { try await disk.save(candidate, label: nil) }
        #expect(try Data(contentsOf: disk.manifestURL) == bytes)
        _ = try await disk.delete(records[0].id)
        _ = try await disk.delete(records[1].id)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(records[0].id.uuidString + ".route").path))
        let relaunched = FileFavoriteRoutesPersistence(directory: directory)
        #expect(!(try await relaunched.read().canUndo))
        await #expect(throws: FavoriteRoutesFailure.nothingToUndo) { try await relaunched.undoDelete() }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(records[1].id.uuidString + ".route").path))
    }

    private func sample() throws -> FavoriteRouteSaveCandidate {
        try FavoriteRouteSaveBuilder.build(draft: RouteDraft(values: [.place(FavoriteRoutesStoreTests.place(1)),
            .place(FavoriteRoutesStoreTests.place(2))])!, currentRouteOrigin: nil)
    }
    private func manifestObject(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/private/tmp/gofly10-file-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class FavoriteFileFault: @unchecked Sendable {
    private let lock = NSLock()
    private var point: FavoriteRoutesWriteCheckpoint?
    func set(_ point: FavoriteRoutesWriteCheckpoint?) { lock.lock(); defer { lock.unlock() }; self.point = point }
    func check(_ reached: FavoriteRoutesWriteCheckpoint) throws {
        lock.lock(); defer { lock.unlock() }
        if reached == point { throw CocoaError(.fileWriteUnknown) }
    }
}
private final class FavoriteFileBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private var reached = false
    private var released = false
    func reach(_ point: FavoriteRoutesWriteCheckpoint) {
        guard point == .payloadFlushed else { return }
        condition.lock(); defer { condition.unlock() }
        reached = true
        while !released { condition.wait() }
    }
    func waitUntilReached() async { while !hasReached() { await Task.yield() } }
    private func hasReached() -> Bool { condition.lock(); defer { condition.unlock() }; return reached }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}
