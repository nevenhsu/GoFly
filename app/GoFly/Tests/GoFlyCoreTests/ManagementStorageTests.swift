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
        let sealed = try management.sealSource(currentApp: setup.manifest.app, pid: 103)
        XCTAssertEqual(sealed.phase, .mutationSealed)
        XCTAssertThrowsError(try management.releaseSource(currentApp: setup.manifest.app, pid: 103,
                                                          setupStore: setupStore, restoreStore: restoreStore)) { error in
            XCTAssertEqual(error as? ManagementFailure, .conflict)
        }
        XCTAssertThrowsError(try management.readSourceReceipt(currentApp: setup.manifest.app, pid: 102)) { error in
            XCTAssertEqual(error as? ManagementFailure, .identityMismatch)
        }
        XCTAssertEqual(try management.readSourceReceipt(currentApp: setup.manifest.app, pid: 103), sealed)
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
        let appSupport = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let request = try makeRequest(source: source.manifest, target: target)
        let management = try makeManagementStore(appSupport: appSupport, request: request)
        let setupStore = SetupActivationStore(directory: source.directory)
        let restoreStore = TransferRestoreStore(applicationSupport: appSupport)
        let preferences = TransferPreferencesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)

        let prepared = try management.prepareSource(currentApp: source.manifest.app, pid: 201,
                                                     setupStore: setupStore, restoreStore: restoreStore)
        _ = try management.commitSourceReady(prepared, currentApp: source.manifest.app, pid: 201)
        _ = try management.releaseSource(currentApp: source.manifest.app, pid: 201,
                                         setupStore: setupStore, restoreStore: restoreStore)
        let targetPrepared = try management.prepareTarget(currentApp: target.app,
                                                           setupStore: setupStore, restoreStore: restoreStore)
        _ = try setupStore.commit(targetInput)
        let adopted = try management.adoptTarget(targetPrepared, currentApp: target.app,
                                                  setupStore: setupStore, restoreStore: restoreStore,
                                                  preferences: preferences)
        XCTAssertEqual(adopted.receipt.sourceSetupID, source.manifest.setupID)
        XCTAssertEqual(adopted.receipt.targetSetupID, target.setupID)
        XCTAssertEqual(adopted.projection.transferID, nil)
        XCTAssertEqual(try management.status()?.phase, .adopted)

        let replay = try management.adoptTarget(targetPrepared, currentApp: target.app,
                                                 setupStore: setupStore, restoreStore: restoreStore,
                                                 preferences: preferences)
        XCTAssertEqual(replay, adopted)
        XCTAssertEqual(try management.reopenAdoptedProjection(currentApp: target.app,
                                                               setupStore: setupStore,
                                                               restoreStore: restoreStore,
                                                               preferences: preferences), adopted)
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
    }

    func testReceiptCapacityRejectsNewManagementGenerationBeforePublishingRoot() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let setup = try makeSetup(root: root, build: "18", fillReceiptCapacity: true)
        let appSupport = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let request = try makeRequest(source: setup.manifest, targetBuild: "19")
        let management = try makeManagementStore(appSupport: appSupport, request: request)
        let setupStore = SetupActivationStore(directory: setup.directory)
        let restoreStore = TransferRestoreStore(applicationSupport: appSupport)

        XCTAssertThrowsError(try management.prepareSource(currentApp: setup.manifest.app, pid: 401,
                                                          setupStore: setupStore, restoreStore: restoreStore)) { error in
            XCTAssertEqual(error as? ManagementFailure, .receiptCapacity)
        }
        XCTAssertNil(try management.status())
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: appSupport.appendingPathComponent("GoFlyManagement/root.json").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: appSupport.appendingPathComponent("GoFlyManagement/generations").path))
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
        try ManagementRequest(managementID: UUID(), nonce: UUID(), kind: .renew,
                              expectedDeviceUDID: device, sourceSetupID: source.setupID,
                              sourceApp: source.app, sourceActivationSHA256: try activationSHA(source),
                              sourceRestoreRootSHA256: nil, teamID: team,
                              targetSetupID: target.setupID, targetApp: target.app)
    }

    private func activationSHA(_ manifest: SetupManifest) throws -> String {
        let root = try XCTUnwrap(manifestDirectory[manifest.setupID])
        return try SetupValidationProxy.sha256(Data(contentsOf: root.appendingPathComponent("activation.json")))
    }

    private var manifestDirectory: [UUID: URL] = [:]

    private func makeSetup(root: URL, build: String, fillReceiptCapacity: Bool = false) throws -> SetupFixture {
        let directory = root.appendingPathComponent("setup-\(build)", isDirectory: true)
        let app = try makeApp(build: build)
        let manifest = try makeManifest(setupID: UUID(), app: app,
                                        pairingTransactionID: UUID(), pairingSHA256: digest)
        let store = SetupActivationStore(directory: directory)
        if fillReceiptCapacity {
            for _ in 0..<(SetupActivationRecord.maximumReceipts - 1) {
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
