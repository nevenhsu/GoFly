import Darwin
import CryptoKit
import Foundation
import XCTest
import GoFlyCore

final class TransferCoreTests: XCTestCase {
    private let device = String(repeating: "a", count: 40)

    func testEmptyManifestFixtureRoundTripsAndRetainsRawDigest() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Transfer/empty-manifest.json")
        let raw = try Data(contentsOf: fixture)
        let input = try TransferInput(data: raw)
        XCTAssertEqual(input.rawManifest, raw)
        XCTAssertEqual(input.rawManifestSHA256, sha256(raw))
        let encoded = try TransferCodec.encodeManifest(input.manifest)
        XCTAssertEqual(try TransferCodec.decodeManifest(encoded), input.manifest)
    }

    func testSettingsAndDraftCodecsRejectRuntimeState() throws {
        let settings = try TransferSettings(language: "en", appearance: "dark", mode: .route,
                                            roundTripEnabled: true, joystickSpeed: .standard)
        XCTAssertEqual(try TransferCodec.decodeSettings(TransferCodec.encodeSettings(settings)), settings)
        let draft = try XCTUnwrap(RouteDraft(values: [.current, .place(MapPlace(
            id: .coordinate(GeoCoordinate(latitude: 25, longitude: 121)!),
            title: "Destination", coordinate: GeoCoordinate(latitude: 25, longitude: 121)!))]))
        XCTAssertEqual(try TransferCodec.decodeDraft(TransferCodec.encodeDraft(draft)), draft)

        let runtime = Data("{\"activeMovement\":null,\"draft\":{}}".utf8)
        XCTAssertThrowsError(try TransferCodec.decodeDraft(runtime))
    }

    func testMissingAndOrphanedSourceNamespacesAreReadOnly() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/gofly-transfer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = FileImportedRoutesPersistence(directory: root)
        let missingSnapshot = try await missing.transferSnapshot()
        XCTAssertTrue(missingSnapshot.payloads.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let orphan = root.appendingPathComponent("\(UUID().uuidString).gpx")
        try Data("orphan".utf8).write(to: orphan)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: orphan.path)
        let snapshot = try await FileImportedRoutesPersistence(directory: root).transferSnapshot()
        XCTAssertTrue(snapshot.payloads.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testRouteSnapshotsPreserveRecordIdentityLabelsAndRawPayloads() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/gofly-route-transfer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let importedRoot = root.appendingPathComponent("imported", isDirectory: true)
        let favoriteRoot = root.appendingPathComponent("favorites", isDirectory: true)
        let points: [GeoCoordinate] = [GeoCoordinate(latitude: 25, longitude: 121)!, GeoCoordinate(latitude: 25.1, longitude: 121.1)!]
        let document = try GPXDocument(content: .tracks([GPXTrack(segments: [[points[0], points[0]], [points[1], points[1], points[1]]])]))
        let importedArtifact = try ImportedRouteArtifact(document: document, filename: "trip.gpx")
        let importedDisk = FileImportedRoutesPersistence(directory: importedRoot)
        let importedReceipt = try await importedDisk.importArtifact(importedArtifact)
        let importedRecord = try XCTUnwrap(importedReceipt.records.first)
        let importedSnapshot = try await importedDisk.transferSnapshot()
        XCTAssertEqual(importedSnapshot.payloads["\(importedRecord.id.uuidString).gpx"], importedArtifact.payload)
        XCTAssertEqual(try TransferArchiveCodec.importedRoutes(importedSnapshot), [importedRecord])

        let start = MapPlace(id: .mapKit("start-id"), title: "Start", coordinate: points[0])
        let end = MapPlace(id: .mapKit("end-id"), title: "End", coordinate: points[1])
        let draft = try XCTUnwrap(RouteDraft(values: [.place(start), .place(end)]))
        let candidate = try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil)
        let rawFavoritePayload = try FavoriteRouteArtifact(candidate: candidate).payload
        let favoriteDisk = FileFavoriteRoutesPersistence(directory: favoriteRoot)
        let favoriteReceipt = try await favoriteDisk.save(candidate, label: "  My saved route  ")
        let favoriteRecord = favoriteReceipt.result.record
        let favoriteSnapshot = try await favoriteDisk.transferSnapshot()
        XCTAssertEqual(try TransferArchiveCodec.favoriteRoutes(favoriteSnapshot), [favoriteRecord])
        XCTAssertEqual(favoriteRecord.label, "My saved route")
        XCTAssertEqual(favoriteSnapshot.payloads["\(favoriteRecord.id.uuidString).route"], rawFavoritePayload)
    }

    func testEmptyPackageValidatorUsesClosedRootInventory() throws {
        let root = URL(fileURLWithPath: "/private/tmp/gofly-package-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let identity = try SetupAppIdentity(bundleID: SetupAppIdentity.formalBundleID, build: "1",
                                             profileSHA256: String(repeating: "b", count: 64),
                                             executableSHA256: String(repeating: "c", count: 64))
        let manifest = try TransferManifest(transferID: UUID(), dataSetID: UUID(), nonce: UUID(),
                                             sourceDeviceUDID: device, destinationDeviceUDID: device,
                                             sourceApp: identity, targetApp: identity, setupID: UUID(),
                                             categories: [], artifacts: [])
        let manifestURL = root.appendingPathComponent("manifest.json")
        try TransferCodec.encodeManifest(manifest).write(to: manifestURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: manifestURL.path)
        let validated = try TransferPackageValidator.validate(directory: root)
        XCTAssertEqual(validated.input.manifest, manifest)
        XCTAssertEqual(validated.counts.favorites, 0)
        XCTAssertEqual(validated.counts.importedRoutes, 0)
        XCTAssertEqual(validated.counts.favoriteRoutes, 0)
        XCTAssertEqual(validated.counts.draftNodes, 0)
        XCTAssertEqual(validated.counts.gpxPoints, 0)
        XCTAssertNil(validated.settings)
        XCTAssertNil(validated.draft)
    }

    func testPackageValidatorAcceptsAllEightCategorySelections() throws {
        let identity = try SetupAppIdentity(bundleID: SetupAppIdentity.formalBundleID, build: "1",
                                             profileSHA256: String(repeating: "b", count: 64),
                                             executableSHA256: String(repeating: "c", count: 64))
        let emptyRouteManifest = Data("{\"records\":[],\"schemaVersion\":1}".utf8)
        for mask in 0..<8 {
            let root = URL(fileURLWithPath: "/private/tmp/gofly-package-combo-\(mask)-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: NSNumber(value: 0o700)])
            var categories: [TransferCategory] = []
            var values: [String: Data] = [:]
            if mask & 1 != 0 {
                categories.append(.favorites)
                values["favorites/archive.json"] = try TransferArchiveCodec.emptyFavoritePlaces()
            }
            if mask & 2 != 0 {
                categories.append(.routes)
                values["routes/imported/manifest.json"] = emptyRouteManifest
                values["routes/favorites/manifest.json"] = emptyRouteManifest
                values["routes/draft.json"] = try TransferCodec.encodeDraft(RouteDraft())
            }
            if mask & 4 != 0 {
                categories.append(.settings)
                values["settings/preferences.json"] = try TransferCodec.encodeSettings(
                    TransferSettings(language: "system", appearance: "system", mode: .teleport,
                                     roundTripEnabled: false, joystickSpeed: .standard))
            }
            let artifacts = try values.keys.sorted().map { path in
                try TransferArtifact(id: UUID(), path: path, byteCount: Int64(values[path]!.count), sha256: sha256(values[path]!))
            }
            let manifest = try TransferManifest(transferID: UUID(), dataSetID: UUID(), nonce: UUID(),
                                                sourceDeviceUDID: device, destinationDeviceUDID: device,
                                                sourceApp: identity, targetApp: identity, setupID: UUID(),
                                                categories: categories, artifacts: artifacts)
            let manifestURL = root.appendingPathComponent("manifest.json")
            try TransferCodec.encodeManifest(manifest).write(to: manifestURL)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: manifestURL.path)
            for (path, data) in values {
                let file = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: NSNumber(value: 0o700)])
                try data.write(to: file)
                try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: file.path)
            }
            let validated = try TransferPackageValidator.validate(directory: root)
            XCTAssertEqual(validated.input.manifest.categories, categories)
        }
    }

    func testClosedPayloadPathsAndEveryRuntimeFieldAreRejected() throws {
        XCTAssertThrowsError(try TransferArtifact(id: UUID(), path: "routes/imported/extra/\(UUID().uuidString).gpx",
                                                  byteCount: 1, sha256: String(repeating: "a", count: 64)))
        XCTAssertThrowsError(try TransferArtifact(id: UUID(), path: "routes/imported/\(UUID().uuidString.lowercased()).gpx",
                                                  byteCount: 1, sha256: String(repeating: "a", count: 64)))

        let coordinate = try XCTUnwrap(GeoCoordinate(latitude: 25, longitude: 121))
        let runtimeSnapshots = [
            SessionRecoverySnapshot(mode: .route),
            SessionRecoverySnapshot(roundTripEnabled: true),
            SessionRecoverySnapshot(joystickSpeed: try XCTUnwrap(RouteSpeed(kilometersPerHour: 21))),
            SessionRecoverySnapshot(position: SessionDisplayPosition(coordinate: coordinate, source: .gps)),
            SessionRecoverySnapshot(activeMovement: .manual),
            SessionRecoverySnapshot(uncertainty: SessionMovementUncertainty(source: .point))
        ]
        for snapshot in runtimeSnapshots {
            let encoded = try SessionRecoveryCodec.encode(snapshot)
            XCTAssertThrowsError(try TransferCodec.decodeDraft(encoded))
        }
        XCTAssertThrowsError(try TransferCodec.decodeDraft(
            SessionRecoveryCodec.encode(SessionRecoverySnapshot(), revision: 1)))

        let boundaryPoints = Array(repeating: coordinate, count: GPXLimits.points)
        let boundaryDocument = try GPXDocument(content: .routes([GPXRoute(points: boundaryPoints)]))
        let boundarySource = try GPXRouteSource(document: boundaryDocument, displayFilename: "boundary.gpx")
        let boundaryDraft = RouteDraft(gpx: boundarySource)
        XCTAssertEqual(try TransferCodec.decodeDraft(TransferCodec.encodeDraft(boundaryDraft)), boundaryDraft)
    }

    func testMalformedOuterJSONLexicalFormsAndUnsupportedLegacyVersionPrecedence() async throws {
        XCTAssertThrowsError(try TransferCodec.decodeSettings(Data("{\"version\":1e0,\"language\":\"en\",\"appearance\":\"system\",\"mode\":\"teleport\",\"roundTripEnabled\":false,\"joystickSpeed\":20}".utf8)))
        XCTAssertThrowsError(try TransferCodec.decodeSettings(Data("{\"version\":true,\"language\":\"en\",\"appearance\":\"system\",\"mode\":\"teleport\",\"roundTripEnabled\":false,\"joystickSpeed\":20}".utf8)))
        XCTAssertThrowsError(try TransferCodec.decodeManifest(Data("{\"version\":1,\"version\":1}".utf8)))

        let root = uniqueRoot("gofly-legacy-version")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let imported = root.appendingPathComponent("manifest.json")
        try Data("{\"schemaVersion\":2,\"records\":[{\"malformed\":true}] }".utf8).write(to: imported)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: imported.path)
        do {
            _ = try await FileImportedRoutesPersistence(directory: root).read()
            XCTFail("unsupported legacy schema must win before record decoding")
        } catch let failure as ImportedRoutesFailure {
            XCTAssertEqual(failure, .unsupportedSchema)
        }

        let favoriteRoot = uniqueRoot("gofly-legacy-favorite-version")
        defer { try? FileManager.default.removeItem(at: favoriteRoot) }
        try FileManager.default.createDirectory(at: favoriteRoot, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let favorite = favoriteRoot.appendingPathComponent("manifest.json")
        try Data("{\"schemaVersion\":2,\"records\":[{\"malformed\":true}] }".utf8).write(to: favorite)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: favorite.path)
        do {
            _ = try await FileFavoriteRoutesPersistence(directory: favoriteRoot).read()
            XCTFail("unsupported legacy favorite schema must win before record decoding")
        } catch let failure as FavoriteRoutesFailure {
            XCTAssertEqual(failure, .unsupportedSchema)
        }
    }

    func testValidatorRejectsFilesystemKindsLinksModesAndClosedInventory() throws {
        let mutations: [(String, (URL) throws -> Void)] = [
            ("extra", { root in
                let file = root.appendingPathComponent("extra")
                try Data("x".utf8).write(to: file)
                try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: file.path)
            }),
            ("symlink", { root in
                try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("extra").path,
                                                           withDestinationPath: "manifest.json")
            }),
            ("hardlink", { root in
                guard Darwin.link(root.appendingPathComponent("manifest.json").path,
                                  root.appendingPathComponent("extra").path) == 0 else { throw TransferFailure.unavailable }
            }),
            ("mode", { root in
                try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)],
                                                       ofItemAtPath: root.appendingPathComponent("manifest.json").path)
            }),
            ("fifo", { root in
                guard Darwin.mkfifo(root.appendingPathComponent("extra").path, mode_t(0o600)) == 0 else {
                    throw TransferFailure.unavailable
                }
            })
        ]
        for (name, mutate) in mutations {
            let root = uniqueRoot("gofly-unsafe-\(name)")
            defer { try? FileManager.default.removeItem(at: root) }
            try makeEmptyPackage(at: root, device: device)
            try mutate(root)
            XCTAssertThrowsError(try TransferPackageValidator.validate(directory: root), "\(name) must be rejected")
        }
    }

    func testValidatorRejectsAncestorDepthEntryCountHashAndClaimedLimits() throws {
        let root = uniqueRoot("gofly-hash")
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = try TransferCodec.encodeSettings(TransferSettings(language: "en", appearance: "system",
                                                                          mode: .teleport, roundTripEnabled: false,
                                                                          joystickSpeed: .standard))
        try makePackage(at: root, device: device, categories: [.settings], files: ["settings/preferences.json": settings])
        let settingsURL = root.appendingPathComponent("settings/preferences.json")
        var changed = try Data(contentsOf: settingsURL)
        changed[changed.startIndex] ^= 1
        try changed.write(to: settingsURL)
        XCTAssertThrowsError(try TransferPackageValidator.validate(directory: root))

        let deepRoot = uniqueRoot("gofly-depth")
        defer { try? FileManager.default.removeItem(at: deepRoot) }
        try makeEmptyPackage(at: deepRoot, device: device)
        var current = deepRoot
        for index in 0..<5 {
            current.appendPathComponent("d\(index)")
            try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: NSNumber(value: 0o700)])
        }
        try Data("x".utf8).write(to: current.appendingPathComponent("x"))
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                               ofItemAtPath: current.appendingPathComponent("x").path)
        XCTAssertThrowsError(try TransferPackageValidator.validate(directory: deepRoot))

        let manyRoot = uniqueRoot("gofly-count")
        defer { try? FileManager.default.removeItem(at: manyRoot) }
        try makeEmptyPackage(at: manyRoot, device: device)
        for index in 0...512 {
            let file = manyRoot.appendingPathComponent("x\(index)")
            try Data("x".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: file.path)
        }
        XCTAssertThrowsError(try TransferPackageValidator.validate(directory: manyRoot))

        let quotaRoot = uniqueRoot("gofly-claimed-quota")
        defer { try? FileManager.default.removeItem(at: quotaRoot) }
        try makeEmptyPackage(at: quotaRoot, device: device)
        let manifest = try TransferManifest(transferID: UUID(), dataSetID: UUID(), nonce: UUID(),
                                            sourceDeviceUDID: device, destinationDeviceUDID: device,
                                            sourceApp: try testIdentity(), targetApp: try testIdentity(), setupID: UUID(),
                                            categories: [], artifacts: [try TransferArtifact(
                                                id: UUID(), path: "settings/preferences.json",
                                                byteCount: Int64(TransferLimits.aggregateBytes),
                                                sha256: String(repeating: "a", count: 64))])
        let manifestURL = quotaRoot.appendingPathComponent("manifest.json")
        try TransferCodec.encodeManifest(manifest).write(to: manifestURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: manifestURL.path)
        XCTAssertThrowsError(try TransferPackageValidator.validate(directory: quotaRoot))
    }

    func testValidatorRejectsValidImportedArchiveOverIts64MiBPayloadQuota() throws {
        let root = uniqueRoot("gofly-imported-overquota")
        defer { try? FileManager.default.removeItem(at: root) }
        let points = try (0..<GPXLimits.points).map { index in
            try XCTUnwrap(GeoCoordinate(latitude: 25.1234567890123 + Double(index) / 1_000_000,
                                         longitude: 121.1234567890123 + Double(index) / 1_000_000))
        }
        let filename = String(repeating: "x", count: 512)
        let segments = points.map { [$0] }
        let document = try GPXDocument(content: .tracks([GPXTrack(segments: segments)]))
        let artifact = try ImportedRouteArtifact(document: document, filename: filename)
        let base = artifact.payload
        var files: [String: Data] = [
            "routes/favorites/manifest.json": Data("{\"records\":[],\"schemaVersion\":1}".utf8),
            "routes/draft.json": try TransferCodec.encodeDraft(RouteDraft())
        ]
        var records: [[String: Any]] = []
        for _ in 0..<100 {
            let id = UUID()
            let record = try artifact.record(id: id)
            let payload = base
            XCTAssertNoThrow(try GPXCodec.decode(payload))
            files["routes/imported/\(id.uuidString).gpx"] = payload
            records.append([
                "id": id.uuidString,
                "filename": record.filename,
                "kind": record.kind.rawValue,
                "pointCount": record.pointCount,
                "byteCount": record.byteCount,
                "sha256": record.sha256,
                "start": ["latitude": record.start.latitude, "longitude": record.start.longitude],
                "end": ["latitude": record.end.latitude, "longitude": record.end.longitude]
            ])
        }
        files["routes/imported/manifest.json"] = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "records": records
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertGreaterThan(Int64(base.count) * 100, Int64(ImportedRoutesLimits.payloadBytes))
        XCTAssertLessThanOrEqual(Int64(base.count) * 87, Int64(ImportedRoutesLimits.payloadBytes))

        let boundaryRoot = uniqueRoot("gofly-imported-boundary")
        defer { try? FileManager.default.removeItem(at: boundaryRoot) }
        let boundaryRecords = Array(records.prefix(87))
        let boundaryIDs = Set(boundaryRecords.compactMap { $0["id"] as? String })
        var boundaryFiles = files.filter { path, _ in
            guard path.hasPrefix("routes/imported/"), path.hasSuffix(".gpx") else { return true }
            return boundaryIDs.contains(String(path.dropFirst("routes/imported/".count).dropLast(4)))
        }
        boundaryFiles["routes/imported/manifest.json"] = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "records": boundaryRecords
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        try makePackage(at: boundaryRoot, device: device, categories: [.routes], files: boundaryFiles)
        XCTAssertNoThrow(try TransferPackageValidator.validate(directory: boundaryRoot))

        try makePackage(at: root, device: device, categories: [.routes], files: files)
        for path in ["routes", "routes/imported", "routes/favorites"] {
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)],
                                                   ofItemAtPath: root.appendingPathComponent(path).path)
        }
        do {
            _ = try TransferPackageValidator.validate(directory: root)
            XCTFail("the imported payload archive exceeds its 64 MiB quota")
        } catch let failure as TransferFailure {
            XCTAssertEqual(failure, .limitExceeded)
        }
    }

    func testInvalidPackageRootsAreRejectedRepeatedlyWithoutPoisoningTheNextValidRead() throws {
        let rootURL = uniqueRoot("gofly-invalid-root")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o755)])
        let before = openFDCount()
        XCTAssertGreaterThan(before, 0, "the descriptor census must be available")
        for _ in 0..<256 {
            XCTAssertThrowsError(try TransferPackageValidator.validate(directory: rootURL))
            XCTAssertThrowsError(try TransferPackageValidator.validate(directory: URL(fileURLWithPath: "/")))
        }
        let after = openFDCount()
        XCTAssertLessThanOrEqual(after, before + 8,
                                 "invalid roots must not leak descriptors (before \(before), after \(after))")
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: rootURL.path)
        let identity = try testIdentity()
        let manifest = try TransferManifest(transferID: UUID(), dataSetID: UUID(), nonce: UUID(),
                                            sourceDeviceUDID: device, destinationDeviceUDID: device,
                                            sourceApp: identity, targetApp: identity, setupID: UUID(),
                                            categories: [], artifacts: [])
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        try TransferCodec.encodeManifest(manifest).write(to: manifestURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: manifestURL.path)
        XCTAssertNoThrow(try TransferPackageValidator.validate(directory: rootURL))
    }

    func testTransferSnapshotsRejectUnvalidatedFilesystemRoot() async throws {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        do {
            _ = try await FileImportedRoutesPersistence(directory: root).transferSnapshot()
            XCTFail("filesystem root must not become a healthy empty imported archive")
        } catch let failure as ImportedRoutesFailure {
            XCTAssertEqual(failure, .unsafeFile)
        }
        do {
            _ = try await FileFavoriteRoutesPersistence(directory: root).transferSnapshot()
            XCTFail("filesystem root must not become a healthy empty favorite archive")
        } catch let failure as FavoriteRoutesFailure {
            XCTAssertEqual(failure, .unsafeFile)
        }
    }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func uniqueRoot(_ name: String) -> URL {
    let temporaryPath = FileManager.default.temporaryDirectory.path
    let noFollowPath = temporaryPath.hasPrefix("/var/") ? "/private\(temporaryPath)" : temporaryPath
    return URL(fileURLWithPath: noFollowPath).appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func openFDCount() -> Int {
    var limit = rlimit()
    guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return 0 }
    let upperBound = min(Int(limit.rlim_cur), 16_384)
    return (0..<upperBound).reduce(into: 0) { count, value in
        if fcntl(Int32(value), F_GETFD) >= 0 { count += 1 }
    }
}

private func testIdentity() throws -> SetupAppIdentity {
    try SetupAppIdentity(bundleID: SetupAppIdentity.formalBundleID, build: "1",
                         profileSHA256: String(repeating: "b", count: 64),
                         executableSHA256: String(repeating: "c", count: 64))
}

private func makeEmptyPackage(at root: URL, device: String) throws {
    try makePackage(at: root, device: device, categories: [], files: [:])
}

private func makePackage(at root: URL, device: String, categories: [TransferCategory], files: [String: Data]) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: NSNumber(value: 0o700)])
    let artifacts = try files.keys.sorted().map { path in
        try TransferArtifact(id: UUID(), path: path, byteCount: Int64(files[path]!.count), sha256: sha256(files[path]!))
    }
    let manifest = try TransferManifest(transferID: UUID(), dataSetID: UUID(), nonce: UUID(),
                                        sourceDeviceUDID: device, destinationDeviceUDID: device,
                                        sourceApp: try testIdentity(), targetApp: try testIdentity(), setupID: UUID(),
                                        categories: categories, artifacts: artifacts)
    let manifestURL = root.appendingPathComponent("manifest.json")
    try TransferCodec.encodeManifest(manifest).write(to: manifestURL)
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: manifestURL.path)
    for (path, data) in files {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try data.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: file.path)
    }
}
