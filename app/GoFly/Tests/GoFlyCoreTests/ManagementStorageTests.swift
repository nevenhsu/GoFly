import CryptoKit
import Foundation
import XCTest
import GoFlyCore

final class ManagementStorageTests: XCTestCase {
    private let device = String(repeating: "a", count: 40)
    private let team = "ABCDE12345"
    private let digest = String(repeating: "b", count: 64)

    func testSourceReadySealIsMonotonicAndReleaseIsForbiddenAfterSeal() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let setup = try makeSetup(root: root, build: "18")
        let request = try makeRequest(source: setup.manifest, targetBuild: "19")
        let appSupport = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let management = try makeManagementStore(appSupport: appSupport, request: request)
        let setupStore = SetupActivationStore(directory: setup.directory)
        let restoreStore = TransferRestoreStore(applicationSupport: appSupport)

        let prepared = try management.prepareSource(currentApp: setup.manifest.app, pid: 101,
                                                     setupStore: setupStore, restoreStore: restoreStore)
        let ready = try management.commitSourceReady(prepared, currentApp: setup.manifest.app, pid: 102)
        XCTAssertEqual(ready.phase, .ready)
        XCTAssertEqual(try management.writeSourceReadback(currentApp: setup.manifest.app, pid: 102), ready)
        XCTAssertEqual(try ManagementCodec.decodeSourceReceipt(Data(contentsOf: appSupport
            .appendingPathComponent("GoFlyManagement/response.json"))), ready)
        let target = try makeManifest(setupID: request.targetSetupID, app: request.targetApp,
                                      pairingTransactionID: setup.manifest.pairingTransactionID,
                                      pairingSHA256: setup.manifest.pairingSHA256)
        try materializeSupport(target, in: setup.directory)
        let targetInput = try SetupInput(manifest: target)
        let incoming = setup.directory.appendingPathComponent("incoming.json")
        try targetInput.encoded().write(to: incoming, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                              ofItemAtPath: incoming.path)
        try setupStore.prepareIncomingFiles()
        XCTAssertThrowsError(try management.prepareTarget(currentApp: target.app,
                                                           setupStore: setupStore,
                                                           restoreStore: restoreStore)) { error in
            XCTAssertEqual(error as? ManagementFailure, .conflict)
        }

        let sealed = try management.sealSource(currentApp: setup.manifest.app, pid: 103)
        XCTAssertEqual(sealed.phase, .mutationSealed)
        XCTAssertEqual(try management.replaySourceReadback(currentApp: setup.manifest.app,
                                                            setupStore: setupStore,
                                                            restoreStore: restoreStore)?.pid, 103)
        XCTAssertThrowsError(try management.releaseSource(currentApp: setup.manifest.app, pid: 103,
                                                          setupStore: setupStore, restoreStore: restoreStore)) { error in
            XCTAssertEqual(error as? ManagementFailure, .conflict)
        }
        let releasedManagement = try makeManagementStore(
            appSupport: root.appendingPathComponent("released-support", isDirectory: true), request: request)
        let releasedPrepared = try releasedManagement.prepareSource(currentApp: setup.manifest.app, pid: 104,
                                                                     setupStore: setupStore, restoreStore: restoreStore)
        _ = try releasedManagement.releaseSource(currentApp: setup.manifest.app, pid: 104,
                                                  setupStore: setupStore, restoreStore: restoreStore)
        XCTAssertThrowsError(try releasedManagement.prepareTarget(currentApp: request.targetApp,
                                                                    setupStore: setupStore,
                                                                    restoreStore: restoreStore)) { error in
            XCTAssertEqual(error as? ManagementFailure, .conflict)
        }
        _ = releasedPrepared

        XCTAssertThrowsError(try management.readSourceReceipt(currentApp: setup.manifest.app, pid: 102)) { error in
            XCTAssertEqual(error as? ManagementFailure, .identityMismatch)
        }
        XCTAssertEqual(try management.readSourceReceipt(currentApp: setup.manifest.app, pid: 103), sealed)

        let targetPrepared = try management.prepareTarget(currentApp: target.app,
                                                          setupStore: setupStore,
                                                          restoreStore: restoreStore)
        let coordinator = SetupBootstrapCoordinator(store: setupStore,
                                                    pairing: ManagementGatePairing())
        XCTAssertEqual(try coordinator.prepare(identity: { target.app }, management: targetPrepared),
                       .blocked(.pairingUnknown))
        _ = try setupStore.commit(targetInput)
        let preferences = TransferPreferencesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        _ = try management.adoptTarget(targetPrepared, currentApp: target.app,
                                       setupStore: setupStore, restoreStore: restoreStore,
                                       preferences: preferences)
        XCTAssertNoThrow(try management.prepareTarget(currentApp: target.app,
                                                       setupStore: setupStore, restoreStore: restoreStore))
        XCTAssertEqual(try management.writeAdoptionReadback(
            currentApp: target.app, setupStore: setupStore, restoreStore: restoreStore,
            preferences: preferences)?.receipt.targetSetupID, target.setupID)

    }

    func testColdTargetCapturesSourceThenAdoptsAfterTargetSetupCommitAndReplays() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSetup(root: root, build: "18")
        let targetApp = try makeApp(build: "19")
        let target = try makeManifest(setupID: UUID(), app: targetApp,
                                      pairingTransactionID: source.manifest.pairingTransactionID,
                                      pairingSHA256: source.manifest.pairingSHA256)
        try materializeSupport(target, in: source.directory)
        let targetInput = try SetupInput(manifest: target)
        let setupIncoming = source.directory.appendingPathComponent("incoming.json")
        try targetInput.encoded().write(to: setupIncoming, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                              ofItemAtPath: setupIncoming.path)
        let appSupport = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let request = try makeRequest(source: source.manifest, target: target)
        let management = try makeManagementStore(appSupport: appSupport, request: request)
        let setupStore = SetupActivationStore(directory: source.directory)
        let restoreStore = TransferRestoreStore(applicationSupport: appSupport)
        let preferences = TransferPreferencesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)

        try setupStore.prepareIncomingFiles()
        _ = try management.prepareTarget(currentApp: target.app,
                                          setupStore: setupStore, restoreStore: restoreStore)
        _ = try setupStore.commit(targetInput)
        let replayPrepared = try management.prepareTarget(currentApp: target.app,
                                                           setupStore: setupStore, restoreStore: restoreStore)
        let adopted = try management.adoptTarget(replayPrepared, currentApp: target.app,
                                                  setupStore: setupStore, restoreStore: restoreStore,
                                                  preferences: preferences)
        XCTAssertEqual(adopted.receipt.sourceSetupID, source.manifest.setupID)
        XCTAssertEqual(adopted.receipt.targetSetupID, target.setupID)
        XCTAssertEqual(adopted.projection.transferID, nil)
        XCTAssertEqual(try management.status()?.phase, .adopted)

        let activationURL = source.directory.appendingPathComponent("activation.json")
        let activationBytes = try Data(contentsOf: activationURL)
        var mutatedActivation = activationBytes
        mutatedActivation.append(0x20)
        try mutatedActivation.write(to: activationURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                              ofItemAtPath: activationURL.path)
        XCTAssertThrowsError(try management.adoptTarget(replayPrepared, currentApp: target.app,
                                                         setupStore: setupStore, restoreStore: restoreStore,
                                                         preferences: preferences)) { error in
            XCTAssertEqual(error as? ManagementFailure, .identityMismatch)
        }
        XCTAssertThrowsError(try management.reopenAdoptedProjection(currentApp: target.app,
                                                                      setupStore: setupStore,
                                                                      restoreStore: restoreStore,
                                                                      preferences: preferences)) { error in
            XCTAssertEqual(error as? ManagementFailure, .identityMismatch)
        }
        try activationBytes.write(to: activationURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                              ofItemAtPath: activationURL.path)

        let replay = try management.adoptTarget(replayPrepared, currentApp: target.app,
                                                 setupStore: setupStore, restoreStore: restoreStore,
                                                 preferences: preferences)
        XCTAssertEqual(replay, adopted)
        XCTAssertEqual(try management.reopenAdoptedProjection(currentApp: target.app,
                                                               setupStore: setupStore,
                                                               restoreStore: restoreStore,
                                                               preferences: preferences), adopted)
        XCTAssertEqual(try management.writeAdoptionReadback(currentApp: target.app,
                                                             setupStore: setupStore,
                                                             restoreStore: restoreStore,
                                                             preferences: preferences), adopted)
        XCTAssertEqual(try ManagementCodec.decodeAdoptionReceipt(Data(contentsOf: appSupport
            .appendingPathComponent("GoFlyManagement/response.json"))), adopted.receipt)
    }

    func testMismatchedRequestCannotReplacePreparingRelation() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let setup = try makeSetup(root: root, build: "18")
        let appSupport = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let first = try makeManagementStore(appSupport: appSupport,
                                            request: makeRequest(source: setup.manifest, targetBuild: "19"))
        let firstInput = try XCTUnwrap(first.readInput())
        let setupStore = SetupActivationStore(directory: setup.directory)
        let restoreStore = TransferRestoreStore(applicationSupport: appSupport)
        _ = try first.prepareSource(currentApp: setup.manifest.app, pid: 301,
                                    setupStore: setupStore, restoreStore: restoreStore)

        let secondRequest = try makeRequest(source: setup.manifest, targetBuild: "20")
        try writeRequest(secondRequest, to: appSupport)
        XCTAssertThrowsError(try first.prepareSource(currentApp: setup.manifest.app, pid: 302,
                                                     setupStore: setupStore, restoreStore: restoreStore)) { error in
            XCTAssertEqual(error as? ManagementFailure, .conflict)
        }

        // A preparing relation cannot be replayed after its immutable
        // generation evidence is removed, even when the original request is
        // restored byte-for-byte.
        try writeRequest(firstInput.request, to: appSupport)
        let generation = appSupport.appendingPathComponent(
            "GoFlyManagement/generations/\(firstInput.request.managementID.uuidString.lowercased())/source-activation.json")
        try FileManager.default.removeItem(at: generation)
        XCTAssertThrowsError(try first.prepareSource(currentApp: setup.manifest.app, pid: 303,
                                                     setupStore: setupStore, restoreStore: restoreStore)) { error in
            XCTAssertEqual(error as? ManagementFailure, .identityMismatch)
        }
    }

    func testReceiptCapacityRejectsNewManagementGenerationBeforePublishingRoot() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Leave one slot for an exact target replay, then fill it by
        // committing that target. A new generation from the now-full active
        // target must still be rejected before management root publication.
        let setup = try makeSetup(root: root, build: "18",
                                  fillReceiptCount: SetupActivationRecord.maximumReceipts - 2)
        let target = try makeManifest(setupID: UUID(), app: try makeApp(build: "19"),
                                      pairingTransactionID: setup.manifest.pairingTransactionID,
                                      pairingSHA256: setup.manifest.pairingSHA256)
        try materializeSupport(target, in: setup.directory)
        let targetInput = try SetupInput(manifest: target)
        let incoming = setup.directory.appendingPathComponent("incoming.json")
        try targetInput.encoded().write(to: incoming, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                              ofItemAtPath: incoming.path)
        let appSupport = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let request = try makeRequest(source: setup.manifest, target: target)
        let management = try makeManagementStore(appSupport: appSupport, request: request)
        let setupStore = SetupActivationStore(directory: setup.directory)
        let restoreStore = TransferRestoreStore(applicationSupport: appSupport)
        let preferences = TransferPreferencesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)

        try setupStore.prepareIncomingFiles()
        _ = try management.prepareTarget(currentApp: target.app,
                                          setupStore: setupStore, restoreStore: restoreStore)
        _ = try setupStore.commit(targetInput)
        let replayPrepared = try management.prepareTarget(currentApp: target.app,
                                                           setupStore: setupStore,
                                                           restoreStore: restoreStore)
        _ = try management.adoptTarget(replayPrepared, currentApp: target.app,
                                       setupStore: setupStore, restoreStore: restoreStore,
                                       preferences: preferences)

        let nextTarget = try makeManifest(setupID: UUID(), app: try makeApp(build: "20"),
                                          pairingTransactionID: target.pairingTransactionID,
                                          pairingSHA256: target.pairingSHA256)
        let nextRequest = try makeRequest(source: target, target: nextTarget,
                                          sourceActivationSHA256: try activationSHA(in: setup.directory),
                                          sourceRestoreRootSHA256: nil)
        try writeRequest(nextRequest, to: appSupport)
        XCTAssertThrowsError(try management.prepareTarget(currentApp: nextTarget.app,
                                                           setupStore: setupStore,
                                                           restoreStore: restoreStore)) { error in
            XCTAssertEqual(error as? ManagementFailure, .receiptCapacity)
        }
        XCTAssertEqual(try management.status()?.phase, .adopted)
    }

    func testCompletedM2ProjectionSurvivesRepeatedRenewalAndNewM2UsesOrdinaryPath() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSetup(root: root, build: "18")
        let targetApp = try makeApp(build: "19")
        let target = try makeManifest(setupID: UUID(), app: targetApp,
                                      pairingTransactionID: source.manifest.pairingTransactionID,
                                      pairingSHA256: source.manifest.pairingSHA256)
        try materializeSupport(target, in: source.directory)
        let secondApp = try makeApp(build: "20")
        let secondTarget = try makeManifest(setupID: UUID(), app: secondApp,
                                            pairingTransactionID: source.manifest.pairingTransactionID,
                                            pairingSHA256: source.manifest.pairingSHA256)
        try materializeSupport(secondTarget, in: source.directory)

        let appSupport = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let setupStore = SetupActivationStore(directory: source.directory)
        let restoreStore = TransferRestoreStore(applicationSupport: appSupport)
        let preferences = TransferPreferencesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let completed = try makeCompletedM2Restore(appSupport: appSupport, source: source,
                                                   setupStore: setupStore, restoreStore: restoreStore,
                                                   preferences: preferences)

        let editedSettings = try TransferSettings(language: "zh-Hant", appearance: "dark",
                                                   mode: .joystick, roundTripEnabled: true,
                                                   joystickSpeed: .standard)
        try preferences.activate(settings: editedSettings, transferID: completed.status.transferID)
        let editedSession = try SessionRecoveryCodec.encode(
            SessionRecoverySnapshot(mode: .joystick, roundTripEnabled: true,
                                    uncertainty: SessionMovementUncertainty(source: .point)))
        let sessionURL = completed.projection.sessionDirectory.appendingPathComponent("session.json")
        try editedSession.write(to: sessionURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                              ofItemAtPath: sessionURL.path)

        let firstRequest = try makeRequest(source: source.manifest, target: target,
                                           sourceRestoreRootSHA256: completed.rootSHA256)
        let management = try makeManagementStore(appSupport: appSupport, request: firstRequest)
        let firstPrepared = try management.prepareTarget(currentApp: target.app,
                                                          setupStore: setupStore,
                                                          restoreStore: restoreStore)
        _ = try setupStore.commit(SetupInput(manifest: target))
        let firstAdoption = try management.adoptTarget(firstPrepared, currentApp: target.app,
                                                       setupStore: setupStore, restoreStore: restoreStore,
                                                       preferences: preferences)
        XCTAssertEqual(try Data(contentsOf: sessionURL), editedSession)
        XCTAssertEqual(try preferences.currentValues().language, editedSettings.language)
        XCTAssertEqual(try preferences.currentValues().appearance, editedSettings.appearance)
        XCTAssertEqual(firstAdoption.projection, completed.projection)

        let secondRequest = try makeRequest(source: target, target: secondTarget,
                                            sourceActivationSHA256: try activationSHA(in: source.directory),
                                            sourceRestoreRootSHA256: completed.rootSHA256)
        try writeRequest(secondRequest, to: appSupport)
        let secondPrepared = try management.prepareTarget(currentApp: secondTarget.app,
                                                           setupStore: setupStore,
                                                           restoreStore: restoreStore)
        _ = try setupStore.commit(SetupInput(manifest: secondTarget))
        let secondAdoption = try management.adoptTarget(secondPrepared, currentApp: secondTarget.app,
                                                        setupStore: setupStore, restoreStore: restoreStore,
                                                        preferences: preferences)
        XCTAssertEqual(secondAdoption.projection, completed.projection)
        XCTAssertEqual(try Data(contentsOf: sessionURL), editedSession)
        XCTAssertEqual(try preferences.currentValues().language, editedSettings.language)
        XCTAssertEqual(try preferences.currentValues().appearance, editedSettings.appearance)
        XCTAssertEqual(try management.reopenAdoptedProjection(currentApp: secondTarget.app,
                                                               setupStore: setupStore,
                                                               restoreStore: restoreStore,
                                                               preferences: preferences), secondAdoption)

        // A later source-side operation may be released before its target is
        // committed. Reopen must retain the current projection through that
        // released relation while keeping the prior adopted receipt sealed.
        let thirdApp = try makeApp(build: "21")
        let thirdTarget = try makeManifest(setupID: UUID(), app: thirdApp,
                                           pairingTransactionID: source.manifest.pairingTransactionID,
                                           pairingSHA256: source.manifest.pairingSHA256)
        let releaseRequest = try makeRequest(source: secondTarget, target: thirdTarget,
                                             sourceActivationSHA256: try activationSHA(in: source.directory),
                                             sourceRestoreRootSHA256: completed.rootSHA256)
        try writeRequest(releaseRequest, to: appSupport)
        _ = try management.prepareSource(currentApp: secondTarget.app, pid: 501,
                                          setupStore: setupStore, restoreStore: restoreStore)
        _ = try management.releaseSource(currentApp: secondTarget.app, pid: 501,
                                          setupStore: setupStore, restoreStore: restoreStore)
        XCTAssertEqual(try management.releasedSourceProjection(currentApp: secondTarget.app,
                                                                setupStore: setupStore,
                                                                restoreStore: restoreStore,
                                                                preferences: preferences), completed.projection)
        XCTAssertNil(try management.reopenAdoptedProjection(currentApp: secondTarget.app,
                                                             setupStore: setupStore,
                                                             restoreStore: restoreStore,
                                                             preferences: preferences))

        // A later ordinary M2 setup must leave the old successor relation
        // ineligible; the caller can route this current App to strict M2
        // restore instead of reopening the obsolete management projection.
        let ordinary = try makeManifest(setupID: UUID(), app: source.manifest.app,
                                        pairingTransactionID: source.manifest.pairingTransactionID,
                                        pairingSHA256: source.manifest.pairingSHA256)
        try materializeSupport(ordinary, in: source.directory)
        _ = try setupStore.commit(SetupInput(manifest: ordinary))
        XCTAssertNil(try management.reopenAdoptedProjection(currentApp: ordinary.app,
                                                             setupStore: setupStore,
                                                             restoreStore: restoreStore,
                                                             preferences: preferences))
        XCTAssertEqual(try restoreStore.currentProjection(), completed.projection)
    }

    private struct SetupFixture {
        let directory: URL
        let manifest: SetupManifest
    }

    private func makeManagementStore(appSupport: URL, request: ManagementRequest) throws -> ManagementStore {
        let managementRoot = appSupport.appendingPathComponent("GoFlyManagement", isDirectory: true)
        try FileManager.default.createDirectory(at: managementRoot, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try writeRequest(request, to: appSupport)
        let store = ManagementStore(applicationSupport: appSupport)
        try store.prepareIncomingFiles()
        return store
    }

    private func writeRequest(_ request: ManagementRequest, to appSupport: URL) throws {
        let root = appSupport.appendingPathComponent("GoFlyManagement", isDirectory: true)
        try ManagementCodec.encodeRequest(request).write(to: root.appendingPathComponent("request.json"),
                                                         options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                              ofItemAtPath: root.appendingPathComponent("request.json").path)
    }

    private func makeRequest(source: SetupManifest, targetBuild: String) throws -> ManagementRequest {
        try makeRequest(source: source,
                        target: try makeManifest(setupID: UUID(), app: try makeApp(build: targetBuild),
                                                  pairingTransactionID: source.pairingTransactionID,
                                                  pairingSHA256: source.pairingSHA256))
    }

    private func makeRequest(source: SetupManifest, target: SetupManifest) throws -> ManagementRequest {
        try makeRequest(source: source, target: target,
                        sourceActivationSHA256: try activationSHA(source),
                        sourceRestoreRootSHA256: nil)
    }

    private func makeRequest(source: SetupManifest, target: SetupManifest,
                             sourceRestoreRootSHA256: String?) throws -> ManagementRequest {
        try makeRequest(source: source, target: target,
                        sourceActivationSHA256: try activationSHA(source),
                        sourceRestoreRootSHA256: sourceRestoreRootSHA256)
    }

    private func makeRequest(source: SetupManifest, target: SetupManifest,
                             sourceActivationSHA256: String,
                             sourceRestoreRootSHA256: String?) throws -> ManagementRequest {
        try ManagementRequest(managementID: UUID(), nonce: UUID(), kind: .renew,
                              expectedDeviceUDID: device, sourceSetupID: source.setupID,
                              sourceApp: source.app, sourceActivationSHA256: sourceActivationSHA256,
                              sourceRestoreRootSHA256: sourceRestoreRootSHA256, teamID: team,
                              targetSetupID: target.setupID, targetApp: target.app)
    }

    private func activationSHA(_ manifest: SetupManifest) throws -> String {
        let root = try XCTUnwrap(manifestDirectory[manifest.setupID])
        return try activationSHA(in: root)
    }

    private func activationSHA(in directory: URL) throws -> String {
        try SetupValidationProxy.sha256(Data(contentsOf: directory.appendingPathComponent("activation.json")))
    }

    private func makeCompletedM2Restore(appSupport: URL, source: SetupFixture,
                                        setupStore: SetupActivationStore,
                                        restoreStore: TransferRestoreStore,
                                        preferences: TransferPreferencesStore) throws ->
        (status: TransferRestoreStatus, projection: TransferRuntimeProjection, rootSHA256: String) {
        let transferID = UUID()
        let dataSetID = UUID()
        let nonce = UUID()
        let settings = try TransferSettings(language: "system", appearance: "light", mode: .teleport,
                                            roundTripEnabled: false, joystickSpeed: .standard)
        let packageFiles: [String: Data] = [
            "favorites/archive.json": try TransferArchiveCodec.emptyFavoritePlaces(),
            "routes/imported/manifest.json": Data("{\"records\":[],\"schemaVersion\":1}".utf8),
            "routes/favorites/manifest.json": Data("{\"records\":[],\"schemaVersion\":1}".utf8),
            "routes/draft.json": try TransferCodec.encodeDraft(RouteDraft()),
            "settings/preferences.json": try TransferCodec.encodeSettings(settings)
        ]
        let artifacts = try packageFiles.keys.sorted().map { path in
            try TransferArtifact(id: UUID(), path: path, byteCount: Int64(packageFiles[path]!.count),
                                 sha256: SetupValidationProxy.sha256(packageFiles[path]!))
        }
        let manifest = try TransferManifest(transferID: transferID, dataSetID: dataSetID, nonce: nonce,
                                            sourceDeviceUDID: device, destinationDeviceUDID: device,
                                            sourceApp: source.manifest.app, targetApp: source.manifest.app,
                                            setupID: source.manifest.setupID, categories: TransferCategory.allCases,
                                            artifacts: artifacts)
        let manifestData = try TransferCodec.encodeManifest(manifest)
        let intent = try TransferRestoreIntent(transferID: transferID, dataSetID: dataSetID, nonce: nonce,
                                               rawManifestSHA256: SetupValidationProxy.sha256(manifestData),
                                               sourceDeviceUDID: device, destinationDeviceUDID: device,
                                               sourceApp: source.manifest.app, targetApp: source.manifest.app,
                                               setupID: source.manifest.setupID, categories: TransferCategory.allCases)

        let transferRoot = appSupport.appendingPathComponent("GoFlyTransfer", isDirectory: true)
        let package = transferRoot.appendingPathComponent("incoming", isDirectory: true)
            .appendingPathComponent(dataSetID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try manifestData.write(to: package.appendingPathComponent("manifest.json"), options: .atomic)
        for (path, data) in packageFiles {
            let file = package.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: NSNumber(value: 0o700)])
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                                  ofItemAtPath: file.path)
        }
        let intentURL = transferRoot.appendingPathComponent("restore-intent.json")
        try TransferControlCodec.encodeRestoreIntent(intent).write(to: intentURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                              ofItemAtPath: intentURL.path)
        try restoreStore.prepareIncomingFiles()
        let status = try restoreStore.restore(currentApp: source.manifest.app,
                                              setupStore: setupStore, preferences: preferences)
        let projection = try XCTUnwrap(status.projection)
        let rootURL = transferRoot.appendingPathComponent("restore-root.json")
        return (status, projection, SetupValidationProxy.sha256(try Data(contentsOf: rootURL)))
    }

    private var manifestDirectory: [UUID: URL] = [:]

    private func makeSetup(root: URL, build: String, fillReceiptCapacity: Bool = false,
                           fillReceiptCount: Int? = nil) throws -> SetupFixture {
        let directory = root.appendingPathComponent("setup-\(build)", isDirectory: true)
        let app = try makeApp(build: build)
        let manifest = try makeManifest(setupID: UUID(), app: app,
                                        pairingTransactionID: UUID(), pairingSHA256: digest)
        let store = SetupActivationStore(directory: directory)
        let fillerCount = fillReceiptCount ?? (fillReceiptCapacity ? SetupActivationRecord.maximumReceipts - 1 : 0)
        if fillerCount > 0 {
            for _ in 0..<fillerCount {
                let filler = try makeManifest(setupID: UUID(), app: app,
                                              pairingTransactionID: UUID(), pairingSHA256: digest)
                try materializeSupport(filler, in: directory)
                _ = try store.commit(SetupInput(manifest: filler))
            }
        }
        try materializeSupport(manifest, in: directory)
        _ = try store.commit(SetupInput(manifest: manifest))
        manifestDirectory[manifest.setupID] = directory
        return SetupFixture(directory: directory, manifest: manifest)
    }

    private func makeApp(build: String) throws -> SetupAppIdentity {
        try SetupAppIdentity(bundleID: SetupAppIdentity.formalBundleID, build: build,
                             profileSHA256: digest, executableSHA256: digest)
    }

    private func makeManifest(setupID: UUID, app: SetupAppIdentity,
                              pairingTransactionID: UUID, pairingSHA256: String) throws -> SetupManifest {
        let values: [(String, Data)] = [
            ("MountMethod", Data("personalized".utf8)),
            ("BuildManifest.plist", Data("manifest".utf8)),
            ("Image.dmg", Data("image".utf8)),
            ("Image.dmg.trustcache", Data("trust".utf8))
        ]
        let artifacts = try values.map { name, data in
            try SetupArtifact(id: UUID(), filename: name, byteCount: Int64(data.count),
                              sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }
        return try SetupManifest(setupID: setupID, nonce: UUID(), expectedDeviceUDID: device,
                                 pairingTransactionID: pairingTransactionID, pairingSHA256: pairingSHA256,
                                 app: app, teamID: team, signingExpiry: "2030-01-01T00:00:00Z",
                                 deviceOS: "26.0", method: .personalized, artifacts: artifacts)
    }

    private func materializeSupport(_ manifest: SetupManifest, in directory: URL) throws {
        let ddi = directory.appendingPathComponent("generations/\(manifest.setupID.uuidString.lowercased())/DDI",
                                                    isDirectory: true)
        try FileManager.default.createDirectory(at: ddi, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let values: [String: Data] = [
            "MountMethod": Data("personalized".utf8),
            "BuildManifest.plist": Data("manifest".utf8),
            "Image.dmg": Data("image".utf8),
            "Image.dmg.trustcache": Data("trust".utf8)
        ]
        for (name, data) in values {
            let file = ddi.appendingPathComponent(name)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                                  ofItemAtPath: file.path)
        }
        for path in [directory, directory.appendingPathComponent("generations"),
                     ddi.deletingLastPathComponent(), ddi] {
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)],
                                                  ofItemAtPath: path.path)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gofly-management-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        return root
    }
}

private enum SetupValidationProxy {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class ManagementGatePairing: SetupPairingAccess, @unchecked Sendable {
    func prepare() throws { throw SetupFailure.pairingUnknown }
    func observeStoredPairing(expectedDeviceUDID: String) throws -> SetupPairingObservation { .absent }
    func observe(for input: SetupInput) throws -> SetupPairingEvidence {
        SetupPairingEvidence(stored: .absent, input: .absent, receipt: .absent)
    }
    func consumeExactPending(for input: SetupInput) throws {}
}
