import Foundation
import CryptoKit
import XCTest
import GoFlyCore

final class TransferStorageTests: XCTestCase {
    private final class CheckpointCounter: @unchecked Sendable {
        var value = 0
    }
    private let device = String(repeating: "a", count: 40)

    private func identity() throws -> SetupAppIdentity {
        try SetupAppIdentity(bundleID: SetupAppIdentity.formalBundleID, build: "20",
                              profileSHA256: String(repeating: "b", count: 64),
                              executableSHA256: String(repeating: "c", count: 64))
    }

    func testExportAndControlCodecsPreserveOriginalRequestBinding() throws {
        let app = try identity()
        let request = try TransferExportRequest(transferID: UUID(), dataSetID: UUID(), nonce: UUID(),
                                                sourceDeviceUDID: device, destinationDeviceUDID: device,
                                                sourceBuild: "20", targetApp: app, setupID: UUID(),
                                                categories: [.favorites, .routes, .settings])
        let raw = try TransferControlCodec.encodeExportRequest(request)
        let input = try TransferExportInput(data: raw)
        XCTAssertEqual(input.request, request)
        XCTAssertEqual(input.rawData, raw)
        let digest = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(input.rawSHA256, digest)

        let control = try TransferControlRequest(action: .export, commandID: UUID(), transferID: request.transferID,
                                                  nonce: request.nonce, requestSHA256: input.rawSHA256,
                                                  manifestSHA256: nil, sourceApp: nil)
        XCTAssertEqual(try TransferControlCodec.decodeControlRequest(TransferControlCodec.encodeControlRequest(control)), control)
    }

    func testControlCodecRejectsMixedReleaseAuthorityAndDuplicateKeys() throws {
        let app = try identity()
        let request = try TransferExportRequest(transferID: UUID(), dataSetID: UUID(), nonce: UUID(),
                                                sourceDeviceUDID: device, destinationDeviceUDID: device,
                                                sourceBuild: "20", targetApp: app, setupID: UUID(), categories: [])
        let requestData = try TransferControlCodec.encodeExportRequest(request)
        let digest = SHA256.hash(data: requestData).map { String(format: "%02x", $0) }.joined()
        XCTAssertThrowsError(try TransferControlRequest(action: .release, commandID: UUID(), transferID: request.transferID,
                                                         nonce: request.nonce, requestSHA256: digest,
                                                         manifestSHA256: String(repeating: "d", count: 64), sourceApp: nil))
        XCTAssertThrowsError(try TransferControlCodec.decodeExportRequest(Data("{\"version\":1,\"version\":1}".utf8)))
    }

    func testPreferencesActivationKeepsTheCanonicalPairAndRestoreMarker() throws {
        let defaults = UserDefaults(suiteName: "gofly-transfer-storage-\(UUID().uuidString)")!
        defaults.set(["otherPreference": "retained"], forKey: "gofly.preferences.v1")
        let store = TransferPreferencesStore(defaults: defaults)
        let settings = try TransferSettings(language: "zh-Hant", appearance: "dark", mode: .joystick,
                                             roundTripEnabled: true, joystickSpeed: .standard)
        let transferID = UUID()
        try store.activate(settings: settings, transferID: transferID)
        let values = try store.currentValues()
        XCTAssertEqual(values.language, "zh-Hant")
        XCTAssertEqual(values.appearance, "dark")
        XCTAssertEqual(values.marker, transferID)
        XCTAssertEqual(defaults.dictionary(forKey: "gofly.preferences.v1")?["otherPreference"] as? String, "retained")
    }

    func testNoRestoreUsesOrdinaryProjectionAndIncompleteRootNeverFabricatesStatus() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gofly-ordinary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TransferRestoreStore(applicationSupport: root)
        let ordinary = try store.currentProjection()
        XCTAssertNil(ordinary.transferID)
        XCTAssertTrue(ordinary.sessionDirectory.path.hasSuffix("SessionRecovery"))
        XCTAssertNil(try store.status())

        let transferRoot = root.appendingPathComponent("GoFlyTransfer", isDirectory: true)
        try FileManager.default.createDirectory(at: transferRoot, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let emptyRoot: [String: Any] = ["version": 1, "active": NSNull(), "pending": NSNull(), "history": []]
        let rootData = try JSONSerialization.data(withJSONObject: emptyRoot, options: [.sortedKeys])
        try rootData.write(to: transferRoot.appendingPathComponent("restore-root.json"))
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: transferRoot.appendingPathComponent("restore-root.json").path)
        XCTAssertNil(try store.status())
        XCTAssertNil(try store.currentProjection().transferID)
    }

    func testPendingRestoreRootIsDurableStatusWithoutCompletedProjection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gofly-pending-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try identity(); let transferID = UUID(); let dataSetID = UUID(); let nonce = UUID()
        let intent = try TransferRestoreIntent(transferID: transferID, dataSetID: dataSetID, nonce: nonce,
                                                rawManifestSHA256: String(repeating: "a", count: 64), sourceDeviceUDID: device,
                                                destinationDeviceUDID: device, sourceApp: app, targetApp: app, setupID: UUID(), categories: [.favorites, .settings])
        let pendingCategories: [[String: Any]] = [
            ["category": "favorites", "state": "committed", "receiptSHA256": String(repeating: "b", count: 64)],
            ["category": "settings", "state": "waiting", "receiptSHA256": NSNull()]
        ]
        let status: [String: Any] = ["transferID": transferID.uuidString.lowercased(), "dataSetID": dataSetID.uuidString.lowercased(),
                                      "rawManifestSHA256": intent.rawManifestSHA256, "phase": "validating", "receiptSHA256": NSNull(),
                                      "sessionSeedSHA256": NSNull(), "categories": pendingCategories, "counts": NSNull()]
        let rootObject: [String: Any] = ["version": 1, "active": NSNull(),
                                         "pending": ["intent": try JSONSerialization.jsonObject(with: TransferControlCodec.encodeRestoreIntent(intent)), "status": status],
                                         "history": []]
        let transferRoot = root.appendingPathComponent("GoFlyTransfer", isDirectory: true)
        try FileManager.default.createDirectory(at: transferRoot, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let rootData = try JSONSerialization.data(withJSONObject: rootObject, options: [.sortedKeys])
        try rootData.write(to: transferRoot.appendingPathComponent("restore-root.json"))
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: transferRoot.appendingPathComponent("restore-root.json").path)
        let observed = try TransferRestoreStore(applicationSupport: root).status()
        XCTAssertEqual(observed?.phase, .validating)
        XCTAssertEqual(observed?.categories.first?.state, .committed)
        XCTAssertThrowsError(try TransferRestoreStore(applicationSupport: root).currentProjection())
    }

    func testAllEightRestoreSelectionsUseActualActivationAndSupportBinding() throws {
        let temporaryBase = FileManager.default.temporaryDirectory
        let trustedTemporaryBase = temporaryBase.path.hasPrefix("/var/") ? URL(fileURLWithPath: "/private" + temporaryBase.path, isDirectory: true) : temporaryBase
        let setupRoot = trustedTemporaryBase.appendingPathComponent("gofly-setup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: setupRoot) }
        let app = try identity()
        let setupID = UUID(); let setupDevice = device; let pairingID = UUID()
        let mount = Data(SetupSupportMethod.personalized.rawValue.utf8)
        let bytes: [String: Data] = ["MountMethod": mount, "BuildManifest.plist": Data("build".utf8), "Image.dmg": Data("image".utf8), "Image.dmg.trustcache": Data("trust".utf8)]
        let artifacts = try bytes.map { name, data in try SetupArtifact(id: UUID(), filename: name, byteCount: Int64(data.count), sha256: sha256(data)) }
        let manifest = try SetupManifest(setupID: setupID, nonce: UUID(), expectedDeviceUDID: setupDevice,
                                         pairingTransactionID: pairingID, pairingSHA256: String(repeating: "a", count: 64), app: app,
                                         teamID: "ABCDE12345", signingExpiry: "2027-01-01T00:00:00Z", deviceOS: "26.3",
                                         method: .personalized, artifacts: artifacts)
        let setupStore = SetupActivationStore(directory: setupRoot)
        try FileManager.default.createDirectory(at: setupRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let generations = setupRoot.appendingPathComponent("generations", isDirectory: true)
        try FileManager.default.createDirectory(at: generations, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let generation = generations.appendingPathComponent("\(setupID.uuidString.lowercased())/DDI", isDirectory: true)
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: setupRoot.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: generations.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: generation.deletingLastPathComponent().path)
        for (name, data) in bytes {
            let file = generation.appendingPathComponent(name); try data.write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: file.path)
        }
        let setupInput = try SetupInput(manifest: manifest)
        _ = try setupStore.commit(setupInput)
        XCTAssertNotNil(try setupStore.activeSupportDirectory(method: .personalized))

        for mask in 0..<8 {
            let root = trustedTemporaryBase.appendingPathComponent("gofly-restore-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let selected: [TransferCategory] = TransferCategory.allCases.enumerated().compactMap { index, category in (mask & (1 << index)) != 0 ? category : nil }
            let dataSetID = UUID(); let transferID = UUID(); let nonce = UUID()
            var packageFiles: [String: Data] = [:]
            if selected.contains(.favorites) { packageFiles["favorites/archive.json"] = try TransferArchiveCodec.emptyFavoritePlaces() }
            if selected.contains(.routes) {
                packageFiles["routes/imported/manifest.json"] = Data("{\"records\":[],\"schemaVersion\":1}".utf8)
                packageFiles["routes/favorites/manifest.json"] = Data("{\"records\":[],\"schemaVersion\":1}".utf8)
                packageFiles["routes/draft.json"] = try TransferCodec.encodeDraft(RouteDraft())
            }
            if selected.contains(.settings) { packageFiles["settings/preferences.json"] = try TransferCodec.encodeSettings(settings()) }
            let artifactValues = try packageFiles.keys.sorted().map { path in
                try TransferArtifact(id: UUID(), path: path, byteCount: Int64(packageFiles[path]!.count), sha256: sha256(packageFiles[path]!))
            }
            let transferManifest = try TransferManifest(transferID: transferID, dataSetID: dataSetID, nonce: nonce,
                                                         sourceDeviceUDID: device, destinationDeviceUDID: device, sourceApp: app,
                                                         targetApp: app, setupID: setupID, categories: selected, artifacts: artifactValues)
            let manifestData = try TransferCodec.encodeManifest(transferManifest)
            let intent = try TransferRestoreIntent(transferID: transferID, dataSetID: dataSetID, nonce: nonce,
                                                   rawManifestSHA256: sha256(manifestData), sourceDeviceUDID: device,
                                                   destinationDeviceUDID: device, sourceApp: app, targetApp: app, setupID: setupID, categories: selected)
            let package = root.appendingPathComponent("GoFlyTransfer/incoming/\(dataSetID.uuidString.lowercased())/package", isDirectory: true)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
            try manifestData.write(to: package.appendingPathComponent("manifest.json"))
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: package.appendingPathComponent("manifest.json").path)
            for (path, data) in packageFiles {
                let file = package.appendingPathComponent(path); try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
                try data.write(to: file); try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: file.path)
            }
            let transferRoot = root.appendingPathComponent("GoFlyTransfer", isDirectory: true)
            let intentData = try TransferControlCodec.encodeRestoreIntent(intent)
            try intentData.write(to: transferRoot.appendingPathComponent("restore-intent.json"))
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: transferRoot.appendingPathComponent("restore-intent.json").path)
            let prefs = TransferPreferencesStore(defaults: UserDefaults(suiteName: "gofly-restore-\(UUID().uuidString)")!)
            let restoreStore = TransferRestoreStore(applicationSupport: root)
            let status = try restoreStore.restore(currentApp: app, setupStore: setupStore, preferences: prefs)
            XCTAssertEqual(status.phase, .committed, "mask=\(mask)")
            XCTAssertEqual(status.categories.map(\.category), selected, "mask=\(mask)")
            XCTAssertNoThrow(try restoreStore.currentProjection())
            let projection = try restoreStore.currentProjection()
            let recoverySeed = try SessionRecoveryCodec.decode(Data(contentsOf: projection.sessionDirectory.appendingPathComponent("session.json")))
            XCTAssertEqual(recoverySeed.uncertainty?.source, .unverifiedPreviousMovement)
            XCTAssertNil(recoverySeed.activeMovement)
            XCTAssertNil(recoverySeed.position)
            try restoreStore.writeReadback(currentApp: app, pid: Int32(getpid()))
            XCTAssertNoThrow(try restoreStore.prepareIncomingFiles(), "cold restore startup mask=\(mask)")
            let responseURL = root.appendingPathComponent("GoFlyTransfer/restore-response.json")
            let response = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: responseURL)) as? [String: Any])
            let finalReceipt = try XCTUnwrap(response["receipt"] as? [String: Any], "mask=\(mask)")
            XCTAssertNotNil(finalReceipt["intent"], "mask=\(mask)")
            XCTAssertNotNil(finalReceipt["categoryReceipts"], "mask=\(mask)")
            let seed = try XCTUnwrap(finalReceipt["sessionSeedSHA256"] as? String, "mask=\(mask)")
            XCTAssertTrue(seed.count == 64 && seed == seed.lowercased(), "mask=\(mask)")
            XCTAssertEqual(finalReceipt["receiptSHA256"] as? String, status.receiptSHA256, "mask=\(mask)")
        }

        // A validation failure after the durable pending commit leaves an
        // actual failed status and keeps projection locked for retry/recovery.
        let failedRoot = trustedTemporaryBase.appendingPathComponent("gofly-restore-failed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: failedRoot) }
        let failedDataSetID = UUID(); let failedTransferID = UUID(); let failedNonce = UUID()
        let malformedSettings = Data("not-a-settings-record".utf8)
        let failedArtifact = try TransferArtifact(id: UUID(), path: "settings/preferences.json",
                                                  byteCount: Int64(malformedSettings.count), sha256: sha256(malformedSettings))
        let failedManifest = try TransferManifest(transferID: failedTransferID, dataSetID: failedDataSetID,
                                                   nonce: failedNonce, sourceDeviceUDID: device,
                                                   destinationDeviceUDID: device, sourceApp: app, targetApp: app,
                                                   setupID: setupID, categories: [.settings], artifacts: [failedArtifact])
        let failedManifestData = try TransferCodec.encodeManifest(failedManifest)
        let failedIntent = try TransferRestoreIntent(transferID: failedTransferID, dataSetID: failedDataSetID,
                                                     nonce: failedNonce, rawManifestSHA256: sha256(failedManifestData),
                                                     sourceDeviceUDID: device, destinationDeviceUDID: device,
                                                     sourceApp: app, targetApp: app, setupID: setupID,
                                                     categories: [.settings])
        let failedPackage = failedRoot.appendingPathComponent("GoFlyTransfer/incoming/\(failedDataSetID.uuidString.lowercased())/package", isDirectory: true)
        try FileManager.default.createDirectory(at: failedPackage, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let failedManifestFile = failedPackage.appendingPathComponent("manifest.json")
        try failedManifestData.write(to: failedManifestFile)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: failedManifestFile.path)
        let failedSettingsFile = failedPackage.appendingPathComponent("settings/preferences.json")
        try FileManager.default.createDirectory(at: failedSettingsFile.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try malformedSettings.write(to: failedSettingsFile)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: failedSettingsFile.path)
        let failedIntentFile = failedRoot.appendingPathComponent("GoFlyTransfer/restore-intent.json")
        try TransferControlCodec.encodeRestoreIntent(failedIntent).write(to: failedIntentFile)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: failedIntentFile.path)
        let failedStore = TransferRestoreStore(applicationSupport: failedRoot)
        let failedPrefs = TransferPreferencesStore(defaults: UserDefaults(suiteName: "gofly-restore-failed-\(UUID().uuidString)")!)
        XCTAssertThrowsError(try failedStore.restore(currentApp: app, setupStore: setupStore, preferences: failedPrefs))
        let failedStatus = try XCTUnwrap(try failedStore.status())
        XCTAssertEqual(failedStatus.phase, .failed)
        XCTAssertEqual(failedStatus.categories.map(\.state), [.failed])
        XCTAssertThrowsError(try failedStore.currentProjection())
    }

    func testPreparingStageFailureKeepsLockAndReplayDoesNotOverwriteLaterSessionBytes() throws {
        let root = try makeProjectionRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try identity()
        let input = try writeExportRequest(root: root, identity: identity, categories: [.favorites])
        let projection = try TransferRestoreStore(applicationSupport: root).currentProjection()
        let cutline = TransferExportCutline(draft: RouteDraft(), settings: try settings(), projection: projection)
        let store = TransferExportStore(applicationSupport: root)
        let preparation = try store.beginPreparation(input: input, currentApp: identity, cutline: cutline)
        XCTAssertThrowsError(try store.stage(preparation: preparation, favorites: nil, importedRoutes: nil, favoriteRoutes: nil))
        XCTAssertTrue(try store.hasLockedExport())
        let release = try TransferControlRequest(action: .release, commandID: UUID(), transferID: input.request.transferID,
                                                  nonce: input.request.nonce, requestSHA256: input.rawSHA256,
                                                  manifestSHA256: nil, sourceApp: nil)
        _ = try store.release(release, input: input, currentApp: identity)
        let newer = try SessionRecoveryCodec.encode(SessionRecoverySnapshot(draft: RouteDraft()))
        let session = root.appendingPathComponent("GoFlyTransfer/active/\(projection.transferID!.uuidString.lowercased())/session/session.json")
        try newer.write(to: session); try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: session.path)
        _ = try store.release(release, input: input, currentApp: identity)
        XCTAssertEqual(try Data(contentsOf: session), newer)
    }

    func testOrphanBeforePreparingRootNeverSeedsANewerSessionCheckpoint() throws {
        let root = try makeProjectionRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try identity()
        let input = try writeExportRequest(root: root, identity: identity, categories: [])
        let projection = try TransferRestoreStore(applicationSupport: root).currentProjection()
        let cutline = TransferExportCutline(draft: RouteDraft(), settings: try settings(), projection: projection)
        let beforeRenameCounter = CheckpointCounter()
        let store = TransferExportStore(applicationSupport: root) { point in
            if point == .beforeRename { beforeRenameCounter.value += 1; if beforeRenameCounter.value == 3 { throw TransferFailure.storageUnavailable } }
        }
        XCTAssertThrowsError(try store.beginPreparation(input: input, currentApp: identity, cutline: cutline))
        let session = root.appendingPathComponent("GoFlyTransfer/active/\(projection.transferID!.uuidString.lowercased())/session/session.json")
        let newer = try SessionRecoveryCodec.encode(SessionRecoverySnapshot(draft: RouteDraft()))
        try newer.write(to: session); try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: session.path)
        let release = try TransferControlRequest(action: .release, commandID: UUID(), transferID: input.request.transferID,
                                                  nonce: input.request.nonce, requestSHA256: input.rawSHA256,
                                                  manifestSHA256: nil, sourceApp: nil)
        _ = try TransferExportStore(applicationSupport: root).release(release, input: input, currentApp: identity)
        XCTAssertEqual(try Data(contentsOf: session), newer)
    }

    func testReadyWinsNullReleaseAndRequiresFullReleaseBinding() throws {
        let root = try makeProjectionRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try identity(); let input = try writeExportRequest(root: root, identity: identity, categories: [])
        let projection = try TransferRestoreStore(applicationSupport: root).currentProjection()
        let store = TransferExportStore(applicationSupport: root)
        let preparation = try store.beginPreparation(input: input, currentApp: identity,
                                                      cutline: TransferExportCutline(draft: RouteDraft(), settings: try settings(), projection: projection))
        let ready = try store.commitReady(store.stage(preparation: preparation, favorites: nil, importedRoutes: nil, favoriteRoutes: nil))
        let nullRelease = try TransferControlRequest(action: .release, commandID: UUID(), transferID: input.request.transferID,
                                                      nonce: input.request.nonce, requestSHA256: input.rawSHA256,
                                                      manifestSHA256: nil, sourceApp: nil)
        XCTAssertThrowsError(try store.release(nullRelease, input: input, currentApp: identity)) { error in XCTAssertEqual(error as? TransferFailure, .exportConflict) }
        XCTAssertEqual(try store.readExport()?.phase, .ready)
        let full = try TransferControlRequest(action: .release, commandID: UUID(), transferID: input.request.transferID,
                                               nonce: input.request.nonce, requestSHA256: input.rawSHA256,
                                               manifestSHA256: ready.manifestSHA256, sourceApp: identity)
        XCTAssertEqual(try store.release(full, input: input, currentApp: identity).phase, .released)
    }

    func testHistoricalReleaseReplayReturnsOldReceiptAndPreservesLaterSessionBytes() throws {
        let root = try makeProjectionRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try identity(); let first = try writeExportRequest(root: root, identity: app, categories: [])
        let projection = try TransferRestoreStore(applicationSupport: root).currentProjection()
        let store = TransferExportStore(applicationSupport: root)
        let cutline = TransferExportCutline(draft: RouteDraft(), settings: try settings(), projection: projection)
        let p1 = try store.beginPreparation(input: first, currentApp: app, cutline: cutline)
        let old = try store.release(try TransferControlRequest(action: .release, commandID: UUID(), transferID: first.request.transferID, nonce: first.request.nonce, requestSHA256: first.rawSHA256, manifestSHA256: nil, sourceApp: nil), input: first, currentApp: app)
        let sessionURL = root.appendingPathComponent("GoFlyTransfer/active/\(projection.transferID!.uuidString.lowercased())/session/session.json")
        let second = try writeExportRequest(root: root, identity: app, categories: [])
        let p2 = try store.beginPreparation(input: second, currentApp: app, cutline: cutline)
        _ = try store.release(try TransferControlRequest(action: .release, commandID: UUID(), transferID: second.request.transferID, nonce: second.request.nonce, requestSHA256: second.rawSHA256, manifestSHA256: nil, sourceApp: nil), input: second, currentApp: app)
        let newer = try SessionRecoveryCodec.encode(SessionRecoverySnapshot(draft: RouteDraft()))
        try newer.write(to: sessionURL); try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: sessionURL.path)
        let replay = try store.release(try TransferControlRequest(action: .release, commandID: UUID(), transferID: first.request.transferID, nonce: first.request.nonce, requestSHA256: first.rawSHA256, manifestSHA256: nil, sourceApp: nil), input: first, currentApp: app)
        XCTAssertEqual(replay.receiptSHA256, old.receiptSHA256)
        XCTAssertEqual(try Data(contentsOf: sessionURL), newer)
        _ = p1; _ = p2
    }

    func testAfterRenameUnknownReopensTheActualPreparingRootAsLocked() throws {
        let root = try makeProjectionRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try identity(); let input = try writeExportRequest(root: root, identity: app, categories: [])
        let projection = try TransferRestoreStore(applicationSupport: root).currentProjection()
        let afterRenameCounter = CheckpointCounter()
        let store = TransferExportStore(applicationSupport: root) { point in
            if point == .afterRename { afterRenameCounter.value += 1; if afterRenameCounter.value == 3 { throw TransferFailure.storageUnavailable } }
        }
        XCTAssertThrowsError(try store.beginPreparation(input: input, currentApp: app,
                                                         cutline: TransferExportCutline(draft: RouteDraft(), settings: try settings(), projection: projection))) { error in
            XCTAssertEqual(error as? TransferFailure, .commitUnknown)
        }
        XCTAssertEqual(try store.readExport()?.phase, .preparing)
        XCTAssertTrue(try store.hasLockedExport())
    }

    func testReleaseAfterRenameUnknownReconcilesTerminalRootWithoutReseeding() throws {
        let root = try makeProjectionRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try identity(); let input = try writeExportRequest(root: root, identity: app, categories: [])
        let projection = try TransferRestoreStore(applicationSupport: root).currentProjection()
        let base = TransferExportStore(applicationSupport: root)
        _ = try base.beginPreparation(input: input, currentApp: app,
                                      cutline: TransferExportCutline(draft: RouteDraft(), settings: try settings(), projection: projection))
        let counter = CheckpointCounter()
        let uncertain = TransferExportStore(applicationSupport: root) { point in
            if point == .afterRename { counter.value += 1; if counter.value == 1 { throw TransferFailure.storageUnavailable } }
        }
        let release = try TransferControlRequest(action: .release, commandID: UUID(), transferID: input.request.transferID,
                                                  nonce: input.request.nonce, requestSHA256: input.rawSHA256, manifestSHA256: nil, sourceApp: nil)
        XCTAssertThrowsError(try uncertain.release(release, input: input, currentApp: app)) { error in XCTAssertEqual(error as? TransferFailure, .commitUnknown) }
        let sessionURL = root.appendingPathComponent("GoFlyTransfer/active/\(projection.transferID!.uuidString.lowercased())/session/session.json")
        let newer = try SessionRecoveryCodec.encode(SessionRecoverySnapshot(draft: RouteDraft()))
        try newer.write(to: sessionURL); try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: sessionURL.path)
        XCTAssertEqual(try base.release(release, input: input, currentApp: app).phase, .releasedNoSnapshot)
        XCTAssertEqual(try Data(contentsOf: sessionURL), newer)
    }

    private func settings() throws -> TransferSettings {
        try TransferSettings(language: "system", appearance: "system", mode: .teleport,
                             roundTripEnabled: false, joystickSpeed: .standard)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeProjectionRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gofly-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let transfer = root.appendingPathComponent("GoFlyTransfer", isDirectory: true)
        try FileManager.default.createDirectory(at: transfer, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let id = UUID(); let active = transfer.appendingPathComponent("active/\(id.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: active.appendingPathComponent("favorites", isDirectory: true), withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try FileManager.default.createDirectory(at: active.appendingPathComponent("routes/imported", isDirectory: true), withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try FileManager.default.createDirectory(at: active.appendingPathComponent("routes/favorites", isDirectory: true), withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try FileManager.default.createDirectory(at: active.appendingPathComponent("session", isDirectory: true), withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try FileManager.default.createDirectory(at: active.appendingPathComponent("settings", isDirectory: true), withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let files: [(URL, Data)] = [
            (active.appendingPathComponent("favorites/favorites.json"), try TransferArchiveCodec.emptyFavoritePlaces()),
            (active.appendingPathComponent("routes/imported/manifest.json"), Data("{\"records\":[],\"schemaVersion\":1}".utf8)),
            (active.appendingPathComponent("routes/favorites/manifest.json"), Data("{\"records\":[],\"schemaVersion\":1}".utf8)),
            (active.appendingPathComponent("session/session.json"), try SessionRecoveryCodec.encode(SessionRecoverySnapshot())),
            (active.appendingPathComponent("settings/preferences.json"), try TransferCodec.encodeSettings(try settings()))
        ]
        for (url, data) in files { try data.write(to: url); try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path) }
        let rootObject: [String: Any] = ["version": 1, "active": ["transferID": id.uuidString.lowercased(), "dataSetID": UUID().uuidString.lowercased(), "rawManifestSHA256": String(repeating: "a", count: 64), "phase": "committed", "receiptSHA256": String(repeating: "b", count: 64), "sessionSeedSHA256": NSNull(), "categories": [], "counts": NSNull()], "pending": NSNull(), "history": []]
        let rootData = try JSONSerialization.data(withJSONObject: rootObject, options: [.sortedKeys])
        let rootFile = transfer.appendingPathComponent("restore-root.json"); try rootData.write(to: rootFile); try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: rootFile.path)
        return root
    }

    private func writeExportRequest(root: URL, identity: SetupAppIdentity, categories: [TransferCategory]) throws -> TransferExportInput {
        let request = try TransferExportRequest(transferID: UUID(), dataSetID: UUID(), nonce: UUID(), sourceDeviceUDID: device,
                                                destinationDeviceUDID: device, sourceBuild: identity.build, targetApp: identity,
                                                setupID: UUID(), categories: categories)
        let data = try TransferControlCodec.encodeExportRequest(request)
        let url = root.appendingPathComponent("GoFlyTransfer/export-request.json"); try data.write(to: url); try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
        return try TransferExportInput(data: data)
    }
}
