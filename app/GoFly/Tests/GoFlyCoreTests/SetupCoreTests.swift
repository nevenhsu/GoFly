import CryptoKit
import Darwin
import Foundation
import XCTest
import GoFlyCore

final class SetupCoreTests: XCTestCase {
    private let device = String(repeating: "a", count: 40)

    func testOrdinaryStartupDoesNotInvokeLazyIdentityReader() throws {
        let directory = try temporaryDirectory()
        let store = SetupActivationStore(directory: directory)
        let pairing = TestPairing()
        let coordinator = SetupBootstrapCoordinator(store: store, pairing: pairing)
        let called = SetupFlag()
        let result = try coordinator.prepare {
            called.value = true
            throw SetupFailure.identityMismatch
        }
        XCTAssertEqual(result, .ordinaryStartup)
        XCTAssertFalse(called.value)
    }

    func testStrictManifestRejectsUnknownAndDuplicateKeys() throws {
        let manifest = try makeManifest()
        let valid = try SetupCodec.encodeManifest(manifest)
        XCTAssertNoThrow(try SetupInput(data: valid))

        var unknown = valid
        unknown.removeLast()
        unknown.append(contentsOf: Array(",\"extra\":true}".utf8))
        XCTAssertThrowsError(try SetupInput(data: unknown))

        var duplicate = valid
        duplicate.removeLast()
        duplicate.append(contentsOf: Data(",\"version\":1}".utf8))
        XCTAssertThrowsError(try SetupInput(data: duplicate))

        let text = String(decoding: valid, as: UTF8.self)
        let control = Data(text.replacingOccurrences(of: "\"build\":\"18\"", with: "\"build\":\"18\\n\"").utf8)
        XCTAssertThrowsError(try SetupInput(data: control))
    }

    func testSetupInputRejectsControlSuffixesOnBoundedIdentifiers() throws {
        let manifest = try makeManifest()
        let valid = String(decoding: try SetupCodec.encodeManifest(manifest), as: UTF8.self)
        let mutations = [
            ("\"setupID\":\"\(manifest.setupID.uuidString.lowercased())\"", "\"setupID\":\"\(manifest.setupID.uuidString.lowercased())\\n\""),
            ("\"expectedDeviceUDID\":\"\(device)\"", "\"expectedDeviceUDID\":\"\(device)\\n\""),
            ("\"teamID\":\"ABCDE12345\"", "\"teamID\":\"ABCDE12345\\n\""),
            ("\"pairingSHA256\":\"\(String(repeating: "3", count: 64))\"", "\"pairingSHA256\":\"\(String(repeating: "3", count: 64))\\n\"")
        ]
        for (original, replacement) in mutations {
            XCTAssertThrowsError(try SetupInput(data: Data(valid.replacingOccurrences(of: original, with: replacement).utf8)), "field (original) accepted a control suffix")
        }
    }

    func testPublicCodecsRejectNestedArraysAndObjectsBeyondDepth64() throws {
        let arrays = Data(("{\"nested\":" + String(repeating: "[", count: 65) + "null" + String(repeating: "]", count: 65) + "}").utf8)
        let objects = Data(("{\"nested\":" + String(repeating: "{\"nested\":", count: 65) + "null" + String(repeating: "}", count: 65) + "}").utf8)
        for bytes in [arrays, objects] {
            XCTAssertLessThan(bytes.count, SetupManifest.maximumBytes)
            XCTAssertThrowsError(try SetupInput(data: bytes)) { error in
                XCTAssertEqual(error as? SetupFailure, .limitExceeded)
            }
            XCTAssertThrowsError(try SetupCodec.decodeManifest(bytes)) { error in
                XCTAssertEqual(error as? SetupFailure, .limitExceeded)
            }
        }
    }

    func testSharedPersonalizedAndCryptexFixturesDecode() throws {
        let fixtureDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Setup", isDirectory: true)
        let personalized = try SetupInput(data: Data(contentsOf: fixtureDirectory.appendingPathComponent("personalized-manifest.json")))
        let cryptex = try SetupInput(data: Data(contentsOf: fixtureDirectory.appendingPathComponent("cryptex-manifest.json")))
        XCTAssertEqual(personalized.manifest.method, .personalized)
        XCTAssertEqual(cryptex.manifest.method, .cryptex)
        let request = try SetupCodec.decodeRequest(Data(contentsOf: fixtureDirectory.appendingPathComponent("readback-request.json")))
        let receipt = try SetupCodec.decodeReceipt(Data(contentsOf: fixtureDirectory.appendingPathComponent("readback-receipt.json")))
        XCTAssertEqual(request.setupID, receipt.setupID)
        XCTAssertEqual(request.nonce, receipt.nonce)
        // Raw outputs of the actual Python producer builder, generated from
        // real private support fixtures. This verifies the transport boundary;
        // these data fixtures carry no device or native success evidence.
        for (name, method, os) in [
            ("producer-personalized-manifest.json", SetupSupportMethod.personalized, "26.0"),
            ("producer-cryptex-manifest.json", SetupSupportMethod.cryptex, "27.0")
        ] {
            let raw = try Data(contentsOf: fixtureDirectory.appendingPathComponent(name))
            let decoded = try SetupInput(data: raw)
            XCTAssertEqual(decoded.manifest.method, method)
            XCTAssertEqual(decoded.manifest.deviceOS, os)
            XCTAssertEqual(decoded.rawData, raw)
            XCTAssertEqual(decoded.rawManifestSHA256, SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined())
        }
    }

    func testRawDigestDiffersWhenOnlyRawManifestBytesDiffer() throws {
        let manifest = try makeManifest()
        let valid = try SetupCodec.encodeManifest(manifest)
        var spaced = Data([0x20])
        spaced.append(valid)
        let first = try SetupInput(data: valid)
        // The codec retains the exact bytes supplied by the producer. A
        // semantically identical object with different bytes must bind a new
        // transaction digest; this test's explicit byte mutation exercises the
        // receiver boundary without relying on JSON re-encoding.
        let second = try SetupInput(data: spaced)
        XCTAssertEqual(first.manifest, second.manifest)
        XCTAssertNotEqual(first.rawManifestSHA256, second.rawManifestSHA256)
    }

    func testRequestProducesActualPairingReadbackAndWaits() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        let request = try SetupReadbackRequest(setupID: manifest.setupID, nonce: manifest.nonce,
                                               expectedDeviceUDID: device, app: manifest.app)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let requestURL = directory.appendingPathComponent("readback-request.json")
        try request.encoded().write(to: requestURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
        let pairing = TestPairing(observation: .verified(expectedDeviceUDID: device, sha256: manifest.pairingSHA256))
        let coordinator = SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing)
        let result = try coordinator.prepare { manifest.app }
        guard case .waitingForMac(let actual) = result else { return XCTFail("expected waitingForMac") }
        XCTAssertEqual(actual, request)
        let response = try XCTUnwrap(try SetupActivationStore(directory: directory).readReadbackReceipt())
        XCTAssertEqual(response.pairing, pairing.observation)
        XCTAssertEqual(response.app, manifest.app)
    }

    func testCommitReplayKeepsNewerActiveGeneration() throws {
        let directory = try temporaryDirectory()
        let first = try makeManifest()
        let second = try makeManifest()
        try materializeSupport(first, in: directory)
        try materializeSupport(second, in: directory)
        let store = SetupActivationStore(directory: directory)
        let firstInput = try SetupInput(manifest: first)
        let secondInput = try SetupInput(manifest: second)
        let firstReceipt = try store.commit(firstInput)
        _ = try store.commit(secondInput)
        XCTAssertEqual(try store.commit(firstInput), firstReceipt)
        var spaced = Data([0x20]); spaced.append(firstInput.data)
        XCTAssertThrowsError(try store.commit(SetupInput(data: spaced))) { error in
            XCTAssertEqual(error as? SetupFailure, .invalidInput)
        }
        XCTAssertEqual(try XCTUnwrap(try store.activation()).activeSetupID, second.setupID)
        XCTAssertNotNil(try store.activeSupportDirectory(method: .personalized))
    }

    func testAfterRenameCheckpointIsCommitUnknownButRecordIsReadable() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        struct Fault: Error {}
        let store = SetupActivationStore(directory: directory) { point in
            if point == .afterRename { throw Fault() }
        }
        XCTAssertThrowsError(try store.commit(SetupInput(manifest: manifest))) { error in
            XCTAssertEqual(error as? SetupFailure, .commitUnknown)
        }
        let reopened = SetupActivationStore(directory: directory)
        XCTAssertEqual(try XCTUnwrap(try reopened.activation()).activeSetupID, manifest.setupID)
    }

    func testSupportGenerationSymlinkIsRejected() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        let generations = directory.appendingPathComponent("generations")
        try FileManager.default.createDirectory(at: generations, withIntermediateDirectories: true)
        let outside = try temporaryDirectory().appendingPathComponent("DDI", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: generations.appendingPathComponent(manifest.setupID.uuidString.lowercased()), withDestinationURL: outside.deletingLastPathComponent())
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).validateSupport(for: SetupInput(manifest: manifest))) { error in
            XCTAssertEqual(error as? SetupFailure, .unsafeFile)
        }
    }

    func testRequestWithAbsentStoredPairingStillWritesActualReadback() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        let request = try SetupReadbackRequest(setupID: manifest.setupID, nonce: manifest.nonce,
                                               expectedDeviceUDID: device, app: manifest.app)
        let requestURL = directory.appendingPathComponent("readback-request.json")
        try request.encoded().write(to: requestURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
        let pairing = TestPairing(observation: .absent)
        let result = try SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing)
            .prepare { manifest.app }
        XCTAssertEqual(result, .waitingForMac(request))
        XCTAssertEqual(pairing.events, ["prepare", "observeStoredPairing"])
        XCTAssertEqual(try XCTUnwrap(try SetupActivationStore(directory: directory).readReadbackReceipt()).pairing, .absent)
    }

    func testRequestWithInvalidStoredPairingStillWritesActualReadback() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        let request = try SetupReadbackRequest(setupID: manifest.setupID, nonce: manifest.nonce,
                                               expectedDeviceUDID: device, app: manifest.app)
        let requestURL = directory.appendingPathComponent("readback-request.json")
        try request.encoded().write(to: requestURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
        let pairing = TestPairing(observation: .invalid)
        let result = try SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing)
            .prepare { manifest.app }
        XCTAssertEqual(result, .waitingForMac(request))
        XCTAssertEqual(pairing.events, ["prepare", "observeStoredPairing"])
        XCTAssertEqual(try XCTUnwrap(try SetupActivationStore(directory: directory).readReadbackReceipt()).pairing, .invalid)
    }

    func testExactPendingPairingIsConsumedAfterStoredObservation() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let pairing = TestPairing(observation: .verified(expectedDeviceUDID: device, sha256: manifest.pairingSHA256), evidence: SetupPairingEvidence(stored: .verified(expectedDeviceUDID: device, sha256: manifest.pairingSHA256), input: .exact, receipt: .absent))
        let result = try SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing).prepare { manifest.app }
        guard case .completed = result else { return XCTFail("expected completed") }
        XCTAssertEqual(pairing.events, ["prepare", "observe", "consume", "observeStoredPairing"])
    }

    func testFreshExactPendingPairingConsumesAfterAbsentFirstObservation() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let pairing = TestPairing(
            observation: .verified(expectedDeviceUDID: device, sha256: manifest.pairingSHA256),
            evidence: SetupPairingEvidence(stored: .absent, input: .exact, receipt: .absent))
        let result = try SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing)
            .prepare { manifest.app }
        guard case .completed = result else { return XCTFail("expected completed") }
        XCTAssertEqual(pairing.events, ["prepare", "observe", "consume", "observeStoredPairing"])
    }

    func testRejectedV1EvidenceWinsOverVerifiedStoredPairing() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let pairing = TestPairing(evidence: SetupPairingEvidence(stored: .verified(expectedDeviceUDID: device, sha256: manifest.pairingSHA256), input: .absent, receipt: .rejectedOrMalformed))
        let result = try SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing).prepare { manifest.app }
        XCTAssertEqual(result, .blocked(.pairingRejected))
        XCTAssertFalse(pairing.events.contains("consume"))
    }

    func testMalformedPendingEvidenceRejectsBeforeConsumption() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let pairing = TestPairing(evidence: SetupPairingEvidence(
            stored: .verified(expectedDeviceUDID: device, sha256: manifest.pairingSHA256),
            input: .malformedOrMismatched, receipt: .absent))
        let result = try SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing)
            .prepare { manifest.app }
        XCTAssertEqual(result, .blocked(.pairingRejected))
        XCTAssertEqual(pairing.events, ["prepare", "observe"])
    }

    func testExactPendingAndSuccessReceiptConflictRejectsBeforeConsumption() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let pairing = TestPairing(evidence: SetupPairingEvidence(
            stored: .verified(expectedDeviceUDID: device, sha256: manifest.pairingSHA256),
            input: .exact, receipt: .success))
        let result = try SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing)
            .prepare { manifest.app }
        XCTAssertEqual(result, .blocked(.pairingRejected))
        XCTAssertEqual(pairing.events, ["prepare", "observe"])
    }

    func testStoredPairingAndSuccessReceiptCommitWithoutPendingConsume() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let pairing = TestPairing(evidence: SetupPairingEvidence(
            stored: .verified(expectedDeviceUDID: device, sha256: manifest.pairingSHA256),
            input: .absent, receipt: .success))
        let result = try SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing)
            .prepare { manifest.app }
        guard case .completed = result else { return XCTFail("expected completed") }
        XCTAssertEqual(pairing.events, ["prepare", "observe"])
    }

    func testStoredPairingWithoutPendingReceiptCommitsWithoutConsumption() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let pairing = TestPairing(evidence: SetupPairingEvidence(
            stored: .verified(expectedDeviceUDID: device, sha256: manifest.pairingSHA256),
            input: .absent, receipt: .absent))
        let result = try SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing)
            .prepare { manifest.app }
        guard case .completed = result else { return XCTFail("expected completed") }
        XCTAssertEqual(pairing.events, ["prepare", "observe"])
    }

    func testSuccessReceiptWithoutStoredPairingRemainsUnknown() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let pairing = TestPairing(evidence: SetupPairingEvidence(stored: .absent, input: .absent, receipt: .success))
        let result = try SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing)
            .prepare { manifest.app }
        XCTAssertEqual(result, .blocked(.pairingUnknown))
        XCTAssertEqual(pairing.events, ["prepare", "observe"])
    }

    func testCorruptSupportStopsBeforePairingConsume() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let pairing = TestPairing(evidence: SetupPairingEvidence(stored: .absent, input: .exact, receipt: .absent))
        let result = try SetupBootstrapCoordinator(store: SetupActivationStore(directory: directory), pairing: pairing).prepare { manifest.app }
        XCTAssertEqual(result, .blocked(.artifactMismatch))
        XCTAssertEqual(pairing.events, [])
    }

    func testOldReplayValidatesCurrentNewerActiveGeneration() throws {
        let directory = try temporaryDirectory()
        let old = try makeManifest()
        let newer = try makeManifest(method: .cryptex)
        try materializeSupport(old, in: directory)
        try materializeSupport(newer, in: directory)
        let store = SetupActivationStore(directory: directory)
        let oldInput = try SetupInput(manifest: old)
        _ = try store.commit(oldInput)
        _ = try store.commit(SetupInput(manifest: newer))
        try writeInput(oldInput, to: directory)
        let pairing = TestPairing(evidence: SetupPairingEvidence(stored: .verified(expectedDeviceUDID: device, sha256: old.pairingSHA256), input: .absent, receipt: .success))
        let result = try SetupBootstrapCoordinator(store: store, pairing: pairing).prepare { old.app }
        guard case .completed(let receipt) = result else { return XCTFail("expected old receipt replay") }
        XCTAssertEqual(receipt.setupID, old.setupID)
        XCTAssertEqual(try XCTUnwrap(try store.activation()).activeSetupID, newer.setupID)
        XCTAssertEqual(pairing.events, [])
    }

    func testOldReplayRejectsForeignCurrentActiveAppIdentity() throws {
        let directory = try temporaryDirectory()
        let old = try makeManifest()
        let foreignApp = try SetupAppIdentity(
            bundleID: SetupAppIdentity.formalBundleID,
            build: "19",
            profileSHA256: String(repeating: "4", count: 64),
            executableSHA256: String(repeating: "5", count: 64))
        let newer = try makeManifest(method: .cryptex, app: foreignApp)
        try materializeSupport(old, in: directory)
        try materializeSupport(newer, in: directory)
        let store = SetupActivationStore(directory: directory)
        let oldInput = try SetupInput(manifest: old)
        _ = try store.commit(oldInput)
        _ = try store.commit(SetupInput(manifest: newer))
        try writeInput(oldInput, to: directory)
        let pairing = TestPairing(evidence: SetupPairingEvidence(
            stored: .verified(expectedDeviceUDID: device, sha256: old.pairingSHA256),
            input: .absent, receipt: .success))
        let result = try SetupBootstrapCoordinator(store: store, pairing: pairing).prepare { old.app }
        XCTAssertEqual(result, .blocked(.identityMismatch))
        XCTAssertEqual(pairing.events, [])
        XCTAssertEqual(try XCTUnwrap(try store.activation()).activeSetupID, newer.setupID)
    }

    func testActiveOnlyStartupValidatesSelectedSupport() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        let store = SetupActivationStore(directory: directory)
        _ = try store.commit(SetupInput(manifest: manifest))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("generations/\(manifest.setupID.uuidString.lowercased())/DDI/Image.dmg"))
        let result = try SetupBootstrapCoordinator(store: store, pairing: TestPairing()).prepare { manifest.app }
        XCTAssertEqual(result, .blocked(.artifactMismatch))
    }

    func testGenericAfterRenameFaultIsCommitUnknown() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        struct Fault: Error {}
        let store = SetupActivationStore(directory: directory) { point in
            if point == .afterRename { throw Fault() }
        }
        XCTAssertThrowsError(try store.commit(SetupInput(manifest: manifest))) { error in
            XCTAssertEqual(error as? SetupFailure, .commitUnknown)
        }
        XCTAssertEqual(try XCTUnwrap(try SetupActivationStore(directory: directory).activation()).activeSetupID, manifest.setupID)
    }

    func testGenericBeforeRenameFaultPreservesPriorActivation() throws {
        let directory = try temporaryDirectory()
        let prior = try makeManifest()
        let next = try makeManifest()
        try materializeSupport(prior, in: directory)
        try materializeSupport(next, in: directory)
        let base = SetupActivationStore(directory: directory)
        _ = try base.commit(SetupInput(manifest: prior))
        struct Fault: Error {}
        let failing = SetupActivationStore(directory: directory) { point in
            if point == .beforeRename { throw Fault() }
        }
        XCTAssertThrowsError(try failing.commit(SetupInput(manifest: next))) { error in
            XCTAssertEqual(error as? SetupFailure, .storageUnavailable)
        }
        let record = try XCTUnwrap(try base.activation())
        XCTAssertEqual(record.activeSetupID, prior.setupID)
        XCTAssertEqual(record.receipts.count, 1)
    }

    func testGenericAfterParentFsyncFaultCommitsUnknownAndRecordIsReadable() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        struct Fault: Error {}
        let failing = SetupActivationStore(directory: directory) { point in
            if point == .parentDirectoryFlushed { throw Fault() }
        }
        XCTAssertThrowsError(try failing.commit(SetupInput(manifest: manifest))) { error in
            XCTAssertEqual(error as? SetupFailure, .commitUnknown)
        }
        XCTAssertEqual(try XCTUnwrap(try SetupActivationStore(directory: directory).activation()).activeSetupID, manifest.setupID)
    }

    func testReadbackRequestNonceCollisionBlocksBeforePairingObservation() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        let request = try SetupReadbackRequest(setupID: manifest.setupID, nonce: manifest.nonce,
                                               expectedDeviceUDID: device, app: manifest.app)
        let prior = try SetupReadbackReceipt(setupID: request.setupID, nonce: UUID(),
                                             expectedDeviceUDID: device, app: manifest.app, pairing: .absent)
        let requestURL = directory.appendingPathComponent("readback-request.json")
        try request.encoded().write(to: requestURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
        let store = SetupActivationStore(directory: directory)
        try store.writeReadbackReceipt(prior)
        let pairing = TestPairing(observation: .verified(expectedDeviceUDID: device, sha256: manifest.pairingSHA256))
        let result = try SetupBootstrapCoordinator(store: store, pairing: pairing).prepare { manifest.app }
        XCTAssertEqual(result, .blocked(.identityMismatch))
        XCTAssertEqual(pairing.events, [])
    }

    func testReadbackResponseDeviceCollisionBlocksWithoutOverwrite() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        let firstRequest = try SetupReadbackRequest(setupID: manifest.setupID, nonce: manifest.nonce,
                                                    expectedDeviceUDID: device, app: manifest.app)
        let secondDevice = String(repeating: "b", count: 40)
        let secondRequest = try SetupReadbackRequest(setupID: firstRequest.setupID, nonce: firstRequest.nonce,
                                                     expectedDeviceUDID: secondDevice, app: manifest.app)
        let prior = try SetupReadbackReceipt(setupID: firstRequest.setupID, nonce: firstRequest.nonce,
                                             expectedDeviceUDID: device, app: manifest.app, pairing: .absent)
        let requestURL = directory.appendingPathComponent("readback-request.json")
        try secondRequest.encoded().write(to: requestURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
        let store = SetupActivationStore(directory: directory)
        try store.writeReadbackReceipt(prior)
        let pairing = TestPairing(observation: .verified(expectedDeviceUDID: secondDevice, sha256: manifest.pairingSHA256))
        let result = try SetupBootstrapCoordinator(store: store, pairing: pairing).prepare { manifest.app }
        XCTAssertEqual(result, .blocked(.identityMismatch))
        XCTAssertEqual(pairing.events, [])
        XCTAssertEqual(try XCTUnwrap(try store.readReadbackReceipt()).expectedDeviceUDID, device)
    }

    func testCoordinatorRejectsSameSetupIDDifferentRawDigest() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        let store = SetupActivationStore(directory: directory)
        _ = try store.commit(SetupInput(manifest: manifest))
        let original = try SetupInput(manifest: manifest)
        var spaced = Data([0x20]); spaced.append(original.data)
        try spaced.write(to: directory.appendingPathComponent("incoming.json"), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent("incoming.json").path)
        let pairing = TestPairing()
        let result = try SetupBootstrapCoordinator(store: store, pairing: pairing).prepare { manifest.app }
        XCTAssertEqual(result, .blocked(.invalidInput))
        XCTAssertEqual(pairing.events, [])
    }

    func testManifestQuotaRejectsOversizedArtifactWithoutOverflow() throws {
        let manifest = try makeManifest()
        let oversized = try SetupArtifact(id: UUID(), filename: "Image.dmg",
                                          byteCount: SetupManifest.maximumGenerationBytes + 1,
                                          sha256: String(repeating: "f", count: 64))
        var artifacts = manifest.artifacts
        artifacts[2] = oversized
        XCTAssertThrowsError(try SetupManifest(setupID: manifest.setupID, nonce: manifest.nonce,
                                               expectedDeviceUDID: manifest.expectedDeviceUDID,
                                               pairingTransactionID: manifest.pairingTransactionID,
                                               pairingSHA256: manifest.pairingSHA256, app: manifest.app,
                                               teamID: manifest.teamID, signingExpiry: manifest.signingExpiry,
                                               deviceOS: manifest.deviceOS, method: manifest.method,
                                               artifacts: artifacts)) { error in
            XCTAssertEqual(error as? SetupFailure, .limitExceeded)
        }
    }

    func testActivationHistoryStopsAt128Receipts() throws {
        let directory = try temporaryDirectory()
        let store = SetupActivationStore(directory: directory)
        for _ in 0..<SetupActivationRecord.maximumReceipts {
            let manifest = try makeManifest()
            try materializeSupport(manifest, in: directory)
            _ = try store.commit(SetupInput(manifest: manifest))
        }
        let extra = try makeManifest()
        try materializeSupport(extra, in: directory)
        let extraInput = try SetupInput(manifest: extra)
        try writeInput(extraInput, to: directory)
        let pairing = TestPairing(evidence: SetupPairingEvidence(
            stored: .verified(expectedDeviceUDID: device, sha256: extra.pairingSHA256),
            input: .exact, receipt: .absent))
        let result = try SetupBootstrapCoordinator(store: store, pairing: pairing).prepare { extra.app }
        XCTAssertEqual(result, .blocked(.receiptCapacity))
        XCTAssertEqual(pairing.events, [])
        XCTAssertEqual(try XCTUnwrap(try store.activation()).receipts.count, SetupActivationRecord.maximumReceipts)
    }

    func testFIFOInputIsRejectedWithoutBlocking() throws {
        let directory = try temporaryDirectory()
        let fifo = directory.appendingPathComponent("incoming.json")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let start = Date()
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).readInput()) { error in
            XCTAssertEqual(error as? SetupFailure, .unsafeFile)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    func testIndividualArtifactSymlinkIsRejected() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        let image = directory.appendingPathComponent("generations/\(manifest.setupID.uuidString.lowercased())/DDI/Image.dmg")
        let outside = try temporaryDirectory().appendingPathComponent("outside")
        try Data("fixture".utf8).write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outside.path)
        try FileManager.default.removeItem(at: image)
        try FileManager.default.createSymbolicLink(at: image, withDestinationURL: outside)
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).validateSupport(for: SetupInput(manifest: manifest))) { error in
            XCTAssertEqual(error as? SetupFailure, .unsafeFile)
        }
    }

    func testHardLinkedArtifactIsRejected() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        let image = directory.appendingPathComponent("generations/\(manifest.setupID.uuidString.lowercased())/DDI/Image.dmg")
        let outside = try temporaryDirectory().appendingPathComponent("outside")
        try Data("fixture".utf8).write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outside.path)
        try FileManager.default.removeItem(at: image)
        try FileManager.default.linkItem(at: outside, to: image)
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).validateSupport(for: SetupInput(manifest: manifest))) { error in
            XCTAssertEqual(error as? SetupFailure, .unsafeFile)
        }
    }

    func testWorldReadableArtifactIsRejected() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        let image = directory.appendingPathComponent("generations/\(manifest.setupID.uuidString.lowercased())/DDI/Image.dmg")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: image.path)
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).validateSupport(for: SetupInput(manifest: manifest))) { error in
            XCTAssertEqual(error as? SetupFailure, .unsafeFile)
        }
    }

    func testPrivateReaderRejectsNonExactDirectoryModeWithoutRepair() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        let ddi = directory.appendingPathComponent("generations/\(manifest.setupID.uuidString.lowercased())/DDI")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ddi.path)
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).validateSupport(for: SetupInput(manifest: manifest))) { error in
            XCTAssertEqual(error as? SetupFailure, .unsafeFile)
        }
        XCTAssertEqual(try permissions(of: ddi), 0o500)
    }

    func testPrivateReaderRejectsNonExactFileModeWithoutRepair() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        let image = directory.appendingPathComponent("generations/\(manifest.setupID.uuidString.lowercased())/DDI/Image.dmg")
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: image.path)
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).validateSupport(for: SetupInput(manifest: manifest))) { error in
            XCTAssertEqual(error as? SetupFailure, .unsafeFile)
        }
        XCTAssertEqual(try permissions(of: image), 0o400)
    }

    func testPrepareIncomingFilesDoesNotCreateMissingRoot() throws {
        let parent = try temporaryDirectory()
        let root = parent.appendingPathComponent("missing-root", isDirectory: true)
        try SetupActivationStore(directory: root).prepareIncomingFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testPrepareIncomingFilesSealsTransportModesWithoutRewritingBytes() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        let input = try SetupInput(manifest: manifest)
        let request = try SetupReadbackRequest(setupID: manifest.setupID, nonce: manifest.nonce,
                                               expectedDeviceUDID: device, app: manifest.app)
        try materializeSupport(manifest, in: directory)
        let requestURL = directory.appendingPathComponent("readback-request.json")
        try request.encoded().write(to: requestURL, options: .atomic)
        let requestBytes = try Data(contentsOf: requestURL)
        try writeInput(input, to: directory)
        let incomingURL = directory.appendingPathComponent("incoming.json")
        let incomingBytes = try Data(contentsOf: incomingURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: requestURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: incomingURL.path)
        let generations = directory.appendingPathComponent("generations")
        let generation = generations.appendingPathComponent(manifest.setupID.uuidString.lowercased())
        let ddi = generation.appendingPathComponent("DDI")
        for path in [generations, generation, ddi] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }
        for artifact in manifest.artifacts {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: ddi.appendingPathComponent(artifact.filename).path)
        }
        try SetupActivationStore(directory: directory).prepareIncomingFiles()
        XCTAssertEqual(try permissions(of: directory), 0o700)
        XCTAssertEqual(try permissions(of: requestURL), 0o600)
        XCTAssertEqual(try permissions(of: incomingURL), 0o600)
        for path in [generations, generation, ddi] {
            XCTAssertEqual(try permissions(of: path), 0o700)
        }
        for artifact in manifest.artifacts {
            XCTAssertEqual(try permissions(of: ddi.appendingPathComponent(artifact.filename)), 0o600)
        }
        XCTAssertEqual(try Data(contentsOf: requestURL), requestBytes)
        XCTAssertEqual(try Data(contentsOf: incomingURL), incomingBytes)
        XCTAssertEqual(try SetupActivationStore(directory: directory).readInput(), input)
    }

    func testPrepareIncomingFilesAcceptsHealthyPrivateGeneration() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        let input = try SetupInput(manifest: manifest)
        try materializeSupport(manifest, in: directory)
        try writeInput(input, to: directory)
        try SetupActivationStore(directory: directory).prepareIncomingFiles()
        XCTAssertEqual(try SetupActivationStore(directory: directory).readInput(), input)
    }

    func testPrepareIncomingFilesSkipsMissingOldInactiveGenerationOnCommittedReplay() throws {
        let directory = try temporaryDirectory()
        let old = try makeManifest()
        let newer = try makeManifest(method: .cryptex)
        try materializeSupport(old, in: directory)
        try materializeSupport(newer, in: directory)
        let store = SetupActivationStore(directory: directory)
        let oldInput = try SetupInput(manifest: old)
        _ = try store.commit(oldInput)
        _ = try store.commit(SetupInput(manifest: newer))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("generations/\(old.setupID.uuidString.lowercased())"))
        try writeInput(oldInput, to: directory)

        try store.prepareIncomingFiles()
        let pairing = TestPairing(evidence: SetupPairingEvidence(
            stored: .verified(expectedDeviceUDID: device, sha256: old.pairingSHA256),
            input: .absent, receipt: .success))
        let result = try SetupBootstrapCoordinator(store: store, pairing: pairing).prepare { old.app }
        guard case .completed(let receipt) = result else { return XCTFail("expected committed replay") }
        XCTAssertEqual(receipt.setupID, old.setupID)
        XCTAssertEqual(try XCTUnwrap(try store.activation()).activeSetupID, newer.setupID)
        XCTAssertEqual(pairing.events, [])
        XCTAssertNotNil(try store.activeSupportDirectory(method: .cryptex))
    }

    func testPrepareIncomingFilesRejectsReplayDigestConflictBeforeGenerationNormalization() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        let store = SetupActivationStore(directory: directory)
        let original = try SetupInput(manifest: manifest)
        _ = try store.commit(original)
        var spacedBytes = Data([0x20])
        spacedBytes.append(original.data)
        let conflicting = try SetupInput(data: spacedBytes)
        try writeInput(conflicting, to: directory)
        let generations = directory.appendingPathComponent("generations")
        let generation = generations.appendingPathComponent(manifest.setupID.uuidString.lowercased())
        let ddi = generation.appendingPathComponent("DDI")
        for path in [generations, generation, ddi] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }
        for artifact in manifest.artifacts {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: ddi.appendingPathComponent(artifact.filename).path)
        }

        XCTAssertThrowsError(try store.prepareIncomingFiles()) { error in
            XCTAssertEqual(error as? SetupFailure, .invalidInput)
        }
        for path in [generations, generation, ddi] {
            XCTAssertEqual(try permissions(of: path), 0o755)
        }
        for artifact in manifest.artifacts {
            XCTAssertEqual(try permissions(of: ddi.appendingPathComponent(artifact.filename)), 0o644)
        }
    }

    func testPrepareIncomingFilesRejectsCorruptAppOwnedActivationWithoutRepair() throws {
        let directory = try temporaryDirectory()
        let activation = directory.appendingPathComponent("activation.json")
        let corrupt = Data("{\"version\":1,\"activeSetupID\":\"not-a-uuid\"}".utf8)
        try corrupt.write(to: activation, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: activation.path)

        XCTAssertThrowsError(try SetupActivationStore(directory: directory).prepareIncomingFiles()) { error in
            XCTAssertEqual(error as? SetupFailure, .invalidInput)
        }
        XCTAssertEqual(try Data(contentsOf: activation), corrupt)
        XCTAssertEqual(try permissions(of: activation), 0o600)
    }

    func testPrepareIncomingFilesRejectsNonTransportControlModesUntouched() throws {
        for mode in [0o400, 0o700] {
            let directory = try temporaryDirectory()
            let manifest = try makeManifest()
            let input = try SetupInput(manifest: manifest)
            try writeInput(input, to: directory)
            let incomingURL = directory.appendingPathComponent("incoming.json")
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: incomingURL.path)
            XCTAssertThrowsError(try SetupActivationStore(directory: directory).prepareIncomingFiles()) { error in
                XCTAssertEqual(error as? SetupFailure, .unsafeFile)
            }
            XCTAssertEqual(try permissions(of: incomingURL), mode)
        }
    }

    func testPrepareIncomingFilesRejectsNonTransportGenerationModeUntouched() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let generations = directory.appendingPathComponent("generations")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: generations.path)
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).prepareIncomingFiles()) { error in
            XCTAssertEqual(error as? SetupFailure, .unsafeFile)
        }
        XCTAssertEqual(try permissions(of: generations), 0o500)
    }

    func testPrepareIncomingFilesRejectsSymlinkArtifact() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let image = directory.appendingPathComponent("generations/\(manifest.setupID.uuidString.lowercased())/DDI/Image.dmg")
        let outside = try temporaryDirectory().appendingPathComponent("outside")
        try Data("fixture".utf8).write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outside.path)
        try FileManager.default.removeItem(at: image)
        try FileManager.default.createSymbolicLink(at: image, withDestinationURL: outside)
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).prepareIncomingFiles()) { error in
            XCTAssertEqual(error as? SetupFailure, .unsafeFile)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
    }

    func testPrepareIncomingFilesRejectsHardLinkedArtifact() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        try writeInput(try SetupInput(manifest: manifest), to: directory)
        let image = directory.appendingPathComponent("generations/\(manifest.setupID.uuidString.lowercased())/DDI/Image.dmg")
        let outside = try temporaryDirectory().appendingPathComponent("outside")
        try Data("fixture".utf8).write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outside.path)
        try FileManager.default.removeItem(at: image)
        try FileManager.default.linkItem(at: outside, to: image)
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).prepareIncomingFiles()) { error in
            XCTAssertEqual(error as? SetupFailure, .unsafeFile)
        }
        XCTAssertEqual(try permissions(of: image), 0o600)
    }

    func testPrepareIncomingFilesLeavesPartialGenerationBlockedAndBytesIntact() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        let input = try SetupInput(manifest: manifest)
        try writeInput(input, to: directory)
        let bytesBefore = try Data(contentsOf: directory.appendingPathComponent("incoming.json"))
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).prepareIncomingFiles()) { error in
            XCTAssertEqual(error as? SetupFailure, .artifactMismatch)
        }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("incoming.json")), bytesBefore)
    }

    func testPrepareIncomingFilesRejectsMalformedInputBeforeGenerationWalk() throws {
        let directory = try temporaryDirectory()
        let incoming = directory.appendingPathComponent("incoming.json")
        let malformed = Data("{\"unknown\":true}".utf8)
        try malformed.write(to: incoming, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: incoming.path)
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).prepareIncomingFiles()) { error in
            XCTAssertEqual(error as? SetupFailure, .invalidInput)
        }
        XCTAssertEqual(try permissions(of: incoming), 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("generations").path))
    }

    func testPrepareIncomingFilesDoesNotRepairAppOwnedActivation() throws {
        let directory = try temporaryDirectory()
        let activation = directory.appendingPathComponent("activation.json")
        try Data("{}".utf8).write(to: activation, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: activation.path)
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).prepareIncomingFiles()) { error in
            XCTAssertEqual(error as? SetupFailure, .unsafeFile)
        }
        XCTAssertEqual(try permissions(of: activation), 0o644)
    }

    func testContentHashMismatchIsRejected() throws {
        let directory = try temporaryDirectory()
        let manifest = try makeManifest()
        try materializeSupport(manifest, in: directory)
        let image = directory.appendingPathComponent("generations/\(manifest.setupID.uuidString.lowercased())/DDI/Image.dmg")
        try Data("changed".utf8).write(to: image, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: image.path)
        XCTAssertThrowsError(try SetupActivationStore(directory: directory).validateSupport(for: SetupInput(manifest: manifest))) { error in
            XCTAssertEqual(error as? SetupFailure, .artifactMismatch)
        }
    }

    private func makeManifest() throws -> SetupManifest {
        try makeManifest(method: .personalized)
    }

    private func makeManifest(method: SetupSupportMethod, setupID: UUID = UUID(), nonce: UUID = UUID(), app: SetupAppIdentity? = nil) throws -> SetupManifest {
        let bytes = Data("fixture".utf8)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let appIdentity: SetupAppIdentity
        if let app { appIdentity = app }
        else {
            appIdentity = try SetupAppIdentity(bundleID: "com.neven.gofly", build: "18", profileSHA256: String(repeating: "1", count: 64), executableSHA256: String(repeating: "2", count: 64))
        }
        let methodBytes = Data(method.rawValue.utf8)
        var artifacts = try [
            SetupArtifact(id: UUID(), filename: "MountMethod", byteCount: Int64(methodBytes.count), sha256: SHA256.hash(data: methodBytes).map { String(format: "%02x", $0) }.joined()),
            SetupArtifact(id: UUID(), filename: "BuildManifest.plist", byteCount: Int64(bytes.count), sha256: hash),
            SetupArtifact(id: UUID(), filename: "Image.dmg", byteCount: Int64(bytes.count), sha256: hash),
            SetupArtifact(id: UUID(), filename: "Image.dmg.trustcache", byteCount: Int64(bytes.count), sha256: hash)
        ]
        if method == .cryptex {
            artifacts.append(contentsOf: try [
                SetupArtifact(id: UUID(), filename: "Image.dmg.cryptex_info", byteCount: Int64(bytes.count), sha256: hash),
                SetupArtifact(id: UUID(), filename: "Image.dmg.root_hash", byteCount: Int64(bytes.count), sha256: hash)
            ])
        }
        return try SetupManifest(setupID: setupID, nonce: nonce, expectedDeviceUDID: device,
                                 pairingTransactionID: UUID(), pairingSHA256: String(repeating: "3", count: 64), app: appIdentity,
                                 teamID: "ABCDE12345", signingExpiry: "2030-01-01T00:00:00Z", deviceOS: method == .personalized ? "26.3.0" : "26.4.0",
                                 method: method, artifacts: artifacts)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gofly-setup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }

    private func materializeSupport(_ manifest: SetupManifest, in root: URL) throws {
        let ddi = root.appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(manifest.setupID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("DDI", isDirectory: true)
        let generations = ddi.deletingLastPathComponent().deletingLastPathComponent()
        let generation = ddi.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: generations, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: ddi, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for artifact in manifest.artifacts {
            let bytes = artifact.filename == "MountMethod" ? Data(manifest.method.rawValue.utf8) : Data("fixture".utf8)
            try bytes.write(to: ddi.appendingPathComponent(artifact.filename), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ddi.appendingPathComponent(artifact.filename).path)
        }
    }

    private func writeInput(_ input: SetupInput, to directory: URL) throws {
        try input.data.write(to: directory.appendingPathComponent("incoming.json"), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent("incoming.json").path)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

private final class TestPairing: SetupPairingAccess, @unchecked Sendable {
    let observation: SetupPairingObservation
    let evidence: SetupPairingEvidence
    var events: [String] = []
    init(observation: SetupPairingObservation = .absent, evidence: SetupPairingEvidence? = nil) {
        self.observation = observation
        self.evidence = evidence ?? SetupPairingEvidence(stored: observation, input: .absent, receipt: .absent)
    }
    func prepare() throws { events.append("prepare") }
    func observeStoredPairing(expectedDeviceUDID: String) throws -> SetupPairingObservation { events.append("observeStoredPairing"); return observation }
    func observe(for input: SetupInput) throws -> SetupPairingEvidence { events.append("observe"); return evidence }
    func consumeExactPending(for input: SetupInput) throws { events.append("consume") }
}

private final class SetupFlag: @unchecked Sendable {
    var value = false
}

private enum SetupValidationHash {
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
