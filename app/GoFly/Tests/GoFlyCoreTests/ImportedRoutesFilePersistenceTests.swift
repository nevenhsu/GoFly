import Darwin
import Foundation
import Testing
@testable import GoFlyCore

struct ImportedRoutesFilePersistenceTests {
    @Test func duplicateImportsRemainIndependentAndDeleteUndoRestoresOriginalIdentityAndOrder() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileImportedRoutesPersistence(directory: directory)
        #expect(try await disk.read().records.isEmpty)
        let artifact = try sample()
        let firstReceipt = try await disk.importArtifact(artifact)
        let first = try #require(firstReceipt.records.first)
        let both = try await disk.importArtifact(artifact)
        let second = try #require(both.records.last)
        #expect(first.id != second.id)
        #expect(first.sha256 == second.sha256)
        #expect(try await disk.validate(first.id).document == artifact.document)
        let deleted = try await disk.delete(first.id)
        #expect(deleted.records == [second])
        #expect(deleted.canUndo)
        let restored = try await disk.undoDelete()
        #expect(restored.records == [first, second])
        #expect(!restored.canUndo)
        let relaunched = FileImportedRoutesPersistence(directory: directory)
        #expect(try await relaunched.read().records == [first, second])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }

    @Test(arguments: [ImportedRoutesWriteCheckpoint.payloadSecured, .payloadWritten, .payloadFlushed,
                      .manifestSecured, .manifestWritten, .manifestFlushed, .beforeManifestCommit])
    func everyPrecommitFaultKeepsOriginalManifestAndDoesNotPublishAnImport(point: ImportedRoutesWriteCheckpoint) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let normal = FileImportedRoutesPersistence(directory: directory)
        let original = try await normal.importArtifact(sample())
        let originalBytes = try Data(contentsOf: normal.manifestURL)
        let failing = FileImportedRoutesPersistence(directory: directory) { reached in
            if reached == point { throw CocoaError(.fileWriteUnknown) }
        }
        await #expect(throws: ImportedRoutesFailure.writeFailed) { try await failing.importArtifact(sample()) }
        #expect(try Data(contentsOf: normal.manifestURL) == originalBytes)
        #expect(try await normal.read().records == original.records)
        #expect(try await normal.validate(original.records[0].id).document == sample().document)
    }

    @Test func failedUndoPreservesItsTokenAndRetryUsesTheSameIdentityAndIndex() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fault = FileFault()
        let disk = FileImportedRoutesPersistence(directory: directory) { try fault.check($0) }
        let first = try await disk.importArtifact(sample()).records[0]
        let both = try await disk.importArtifact(sample()).records
        _ = try await disk.delete(first.id)
        let bytesAfterDelete = try Data(contentsOf: disk.manifestURL)
        fault.set(.beforeManifestCommit)
        await #expect(throws: ImportedRoutesFailure.writeFailed) { try await disk.undoDelete() }
        #expect(try Data(contentsOf: disk.manifestURL) == bytesAfterDelete)
        #expect(try await disk.read().canUndo)
        fault.set(nil)
        #expect(try await disk.undoDelete().records == both)
    }

    @Test func cleanupFailureDoesNotReportAnAlreadyCommittedDeleteAsFailureAndQuotaCountsTheRetainedBytes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fault = FileFault()
        let disk = FileImportedRoutesPersistence(directory: directory) { try fault.check($0) }
        let first = try await disk.importArtifact(sample()).records[0]
        let second = try await disk.importArtifact(sample()).records[1]
        fault.set(.cleanup)
        #expect(try await disk.delete(first.id).records == [second])
        #expect(try await disk.delete(second.id).records.isEmpty)
        // The old undo is now an orphan; both it and the current undo remain on
        // disk because cleanup fails. An extra recognized orphan fills quota.
        let orphan = directory.appendingPathComponent(UUID().uuidString + ".gpx")
        try Data().write(to: orphan)
        let handle = try FileHandle(forWritingTo: orphan)
        try handle.truncate(atOffset: UInt64(ImportedRoutesLimits.payloadBytes - first.byteCount - second.byteCount))
        try handle.close()
        await #expect(throws: ImportedRoutesFailure.limitExceeded) { try await disk.importArtifact(sample()) }
        #expect(try await disk.read().records.isEmpty)
        #expect(try await disk.read().canUndo)
        fault.set(nil)
        #expect(try await disk.undoDelete().records == [second])
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func corruptUnknownAndDuplicateIdentityManifestsBlockWritesAndNeverCleanOrphans() async throws {
        for problem in ["corrupt", "schema", "duplicate", "oversize"] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let disk = FileImportedRoutesPersistence(directory: directory)
            _ = try await disk.importArtifact(sample())
            var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: disk.manifestURL)) as? [String: Any])
            let bytes: Data
            switch problem {
            case "corrupt": bytes = Data("not-json".utf8)
            case "schema": object["schemaVersion"] = 99; bytes = try JSONSerialization.data(withJSONObject: object)
            case "duplicate":
                let records = try #require(object["records"] as? [[String: Any]])
                object["records"] = records + records
                bytes = try JSONSerialization.data(withJSONObject: object)
            default: bytes = Data(repeating: 32, count: ImportedRoutesLimits.manifestBytes + 1)
            }
            try bytes.write(to: disk.manifestURL)
            let orphan = directory.appendingPathComponent(UUID().uuidString + ".gpx")
            try Data("orphan must remain".utf8).write(to: orphan)
            await #expect(throws: (any Error).self) { try await disk.read() }
            await #expect(throws: (any Error).self) { try await disk.importArtifact(sample()) }
            #expect(try Data(contentsOf: disk.manifestURL) == bytes)
            #expect(try String(contentsOf: orphan, encoding: .utf8) == "orphan must remain")
        }
    }

    @Test func startupUsesBoundedMetadataButSelectionRevalidatesHashAndEveryManifestField() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileImportedRoutesPersistence(directory: directory)
        let record = try await disk.importArtifact(sample()).records[0]
        let payload = directory.appendingPathComponent(record.id.uuidString + ".gpx")
        let original = try Data(contentsOf: payload)
        var damaged = original
        damaged[damaged.startIndex] = 32
        try damaged.write(to: payload)
        #expect(try await disk.read().records == [record])
        await #expect(throws: ImportedRoutesFailure.hashMismatch) { try await disk.validate(record.id) }
        try original.write(to: payload)
        for field in ["kind", "pointCount", "filename", "start"] {
            let originalManifest = try Data(contentsOf: disk.manifestURL)
            var object = try #require(try JSONSerialization.jsonObject(with: originalManifest) as? [String: Any])
            var records = try #require(object["records"] as? [[String: Any]])
            switch field {
            case "kind": records[0][field] = "routes"
            case "pointCount": records[0][field] = 3
            case "filename": records[0][field] = "other.gpx"
            default: records[0][field] = ["latitude": 8, "longitude": 9]
            }
            object["records"] = records
            try JSONSerialization.data(withJSONObject: object).write(to: disk.manifestURL)
            await #expect(throws: ImportedRoutesFailure.metadataMismatch) { try await disk.validate(record.id) }
            try originalManifest.write(to: disk.manifestURL)
        }
    }

    @Test(arguments: ["manifestSymlink", "payloadSymlink", "payloadFIFO", "directorySymlink", "manifestDirectory"])
    func unsafeFilesAreRejectedWithoutFollowingOrReplacingThem(kind: String) async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("ImportedRoutes")
        let outside = root.appendingPathComponent("sentinel")
        let disk = FileImportedRoutesPersistence(directory: directory)
        let record = try await disk.importArtifact(sample()).records[0]
        let sentinel = Data(repeating: 65, count: record.byteCount)
        try sentinel.write(to: outside)
        let manifestBefore = try Data(contentsOf: disk.manifestURL)
        if kind == "directorySymlink" {
            try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("old"))
            try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: root.appendingPathComponent("old"))
        } else {
            let target = kind.hasPrefix("payload") ? directory.appendingPathComponent(record.id.uuidString + ".gpx") : disk.manifestURL
            try FileManager.default.removeItem(at: target)
            if kind == "manifestDirectory" { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
            else if kind == "payloadFIFO" { #expect(mkfifo(target.path, 0o600) == 0) }
            else { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside) }
        }
        await #expect(throws: ImportedRoutesFailure.unsafeFile) { try await disk.read() }
        await #expect(throws: ImportedRoutesFailure.unsafeFile) { try await disk.importArtifact(sample()) }
        #expect(try Data(contentsOf: outside) == sentinel)
        if kind.hasPrefix("payload") { #expect(try Data(contentsOf: disk.manifestURL) == manifestBefore) }
    }

    @Test func concurrentAdmissionsSerializeAgainstTheLatestManifestAndNeverCleanAnInflightPayload() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let barrier = FileBarrier()
        let disk = FileImportedRoutesPersistence(directory: directory) { barrier.reach($0) }
        let artifact = try sample()
        let first = Task { try await disk.importArtifact(artifact) }
        await barrier.waitUntilPayloadFlushed()
        let cleanupRead = Task { try await disk.read() }
        let second = Task { try await disk.importArtifact(artifact) }
        barrier.release()
        _ = try await first.value
        _ = try await cleanupRead.value
        _ = try await second.value
        let final = try await disk.read()
        #expect(final.records.count == 2)
        for record in final.records { #expect(try await disk.validate(record.id).document == artifact.document) }
    }

    @Test func recordLimitIsExactAndUnknownPathsRemainUntouchedByHealthyCleanup() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileImportedRoutesPersistence(directory: directory)
        let artifact = try sample()
        for _ in 0..<100 { _ = try await disk.importArtifact(artifact) }
        let before = try Data(contentsOf: disk.manifestURL)
        await #expect(throws: ImportedRoutesFailure.limitExceeded) { try await disk.importArtifact(artifact) }
        #expect(try Data(contentsOf: disk.manifestURL) == before)
        #expect(try await disk.read().records.count == 100)
        let unknown = directory.appendingPathComponent("user-file.gpx")
        try Data("keep me".utf8).write(to: unknown)
        let orphan = directory.appendingPathComponent(UUID().uuidString + ".gpx")
        try Data("owned orphan".utf8).write(to: orphan)
        _ = try await disk.read()
        #expect(try String(contentsOf: unknown, encoding: .utf8) == "keep me")
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func aNewDeletionReplacesUndoAndRelaunchDoesNotRestoreTransientUndo() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileImportedRoutesPersistence(directory: directory)
        let first = try await disk.importArtifact(sample()).records[0]
        let second = try await disk.importArtifact(sample()).records[1]
        _ = try await disk.delete(first.id)
        _ = try await disk.delete(second.id)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(first.id.uuidString + ".gpx").path))
        let relaunched = FileImportedRoutesPersistence(directory: directory)
        let receipt = try await relaunched.read()
        #expect(receipt.records.isEmpty)
        #expect(!receipt.canUndo)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(second.id.uuidString + ".gpx").path))
        await #expect(throws: ImportedRoutesFailure.nothingToUndo) { try await relaunched.undoDelete() }
    }

    @Test func cancellingAQueuedAdmissionDoesNotCommitButCancellationAfterTheTransactionStartsKeepsItsRealReceipt() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let barrier = FileBarrier()
        let disk = FileImportedRoutesPersistence(directory: directory) { barrier.reach($0) }
        let artifact = try sample()
        let first = Task { try await disk.importArtifact(artifact) }
        await barrier.waitUntilPayloadFlushed()
        let revoked = Task { try await disk.importArtifact(artifact) }
        revoked.cancel()
        first.cancel()
        barrier.release()
        let committed = try await first.value
        #expect(committed.records.count == 1)
        await #expect(throws: CancellationError.self) { try await revoked.value }
        #expect(try await disk.read().records == committed.records)
    }
    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/private/tmp/gofly09-file-\(UUID().uuidString)", isDirectory: true)
    }
    private func sample() throws -> ImportedRouteArtifact {
        try ImportedRouteArtifact(data: ImportedRoutesStoreTests.xml, filename: "../../display & sample.gpx")
    }
}

private final class FileFault: @unchecked Sendable {
    private let lock = NSLock()
    private var point: ImportedRoutesWriteCheckpoint?
    func set(_ point: ImportedRoutesWriteCheckpoint?) { lock.lock(); defer { lock.unlock() }; self.point = point }
    func check(_ reached: ImportedRoutesWriteCheckpoint) throws {
        lock.lock(); defer { lock.unlock() }
        if reached == point { throw CocoaError(.fileWriteUnknown) }
    }
}

private final class FileBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private var reached = false
    private var released = false
    func reach(_ point: ImportedRoutesWriteCheckpoint) {
        guard point == .payloadFlushed else { return }
        condition.lock(); defer { condition.unlock() }
        reached = true
        while !released { condition.wait() }
    }
    func waitUntilPayloadFlushed() async {
        while !hasReached() { await Task.yield() }
    }
    private func hasReached() -> Bool { condition.lock(); defer { condition.unlock() }; return reached }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}
