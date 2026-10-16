import XCTest
import CryptoKit
@testable import LocalGoCore

final class SetupHandoffTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalGoSetupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func testProtocolValidatesBoundsHashSchemaAndRPKeys() throws {
        let pairing = try makePairingFile()
        let transactionID = UUID()
        let payload = try LocalGoSetupProtocol.IncomingPayload(
            transactionID: transactionID,
            expectedDeviceUDID: "00008110-001c2d1234567890",
            pairingFile: pairing,
            sha256: Data(SHA256.hash(data: pairing))
        )
        let encoded = try LocalGoSetupProtocol.encodeIncoming(payload)
        let decoded = try LocalGoSetupProtocol.decodeIncoming(encoded)
        XCTAssertEqual(decoded, payload)

        var object = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: encoded, options: [], format: nil)
                as? [String: Any]
        )
        object["sha256"] = Data(repeating: 0, count: 32)
        let badHash = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        XCTAssertThrowsError(try LocalGoSetupProtocol.decodeIncoming(badHash))

        let privateKey = Curve25519.Signing.PrivateKey()
        object["pairingFile"] = try PropertyListSerialization.data(
            fromPropertyList: [
                "private_key": privateKey.rawRepresentation,
                "public_key": Data(repeating: 0, count: 32),
                "identifier": UUID().uuidString.lowercased()
            ],
            format: .binary,
            options: 0
        )
        object["sha256"] = Data(SHA256.hash(data: object["pairingFile"] as! Data))
        let badKeys = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        XCTAssertThrowsError(try LocalGoSetupProtocol.decodeIncoming(badKeys))

        let oversized = Data(repeating: 0, count: LocalGoSetupProtocol.maximumIncomingFileBytes + 1)
        XCTAssertThrowsError(try LocalGoSetupProtocol.decodeIncoming(oversized))
    }

    func testNoPayloadAndBusyState() throws {
        let handoff = makeHandoff { _, _ in XCTFail("no payload must not import") }
        try handoff.prepare()
        XCTAssertEqual(handoff.consume(), .noPayload)
        XCTAssertEqual(handoff.consume(commandsIdle: false), .storageFailure)
        XCTAssertEqual(handoff.consume(isPreparing: true), .storageFailure)
    }

    func testImportFailurePreservesPriorStateAndWritesRejectedReceipt() throws {
        let state = Data("old".utf8)
        let handoff = makeHandoff { _, _ in
            throw TestError.importFailed
        }
        try handoff.prepare()
        let payload = try makePayload()
        try writeIncoming(payload)
        XCTAssertEqual(handoff.consume(), .rejected)
        XCTAssertEqual(state, Data("old".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: incomingURL.path))

        let receipt = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: receiptURL(for: payload.transactionID)),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        XCTAssertEqual(receipt["status"] as? String, "rejected")
    }

    func testReplayReplacesSuccessReceiptAndDoesNotReimport() throws {
        var imports = 0
        let handoff = makeHandoff { _, _ in imports += 1 }
        try handoff.prepare()
        let payload = try makePayload()

        try writeIncoming(payload)
        XCTAssertEqual(handoff.consume(), .imported)
        XCTAssertEqual(imports, 1)

        try writeIncoming(payload)
        XCTAssertEqual(handoff.consume(), .rejected)
        XCTAssertEqual(imports, 1)
        let receipt = try LocalGoSetupProtocol.decodeReceipt(
            Data(contentsOf: receiptURL(for: payload.transactionID))
        )
        XCTAssertEqual(receipt.status, .rejected)
    }

    func testInterruptedReceiptTempIsRecoveredBeforeStrictReceiptScan() throws {
        var imports = 0
        let handoff = makeHandoff { _, _ in imports += 1 }
        try handoff.prepare()
        let receipts = root.appendingPathComponent(LocalGoSetupHandoff.receiptsDirectoryName, isDirectory: true)
        let staleTemp = receipts.appendingPathComponent(".metadata-\(UUID().uuidString).tmp")
        try Data("interrupted write".utf8).write(to: staleTemp)

        let payload = try makePayload()
        try writeIncoming(payload)
        XCTAssertEqual(handoff.consume(), .imported)
        XCTAssertEqual(imports, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleTemp.path))
    }

    func testReceiptCapRejectsWithoutImportOrPruning() throws {
        var imports = 0
        let handoff = makeHandoff { _, _ in imports += 1 }
        try handoff.prepare()
        let receipts = root.appendingPathComponent(LocalGoSetupHandoff.receiptsDirectoryName, isDirectory: true)
        for _ in 0..<LocalGoSetupProtocol.maximumReceiptCount {
            let id = UUID()
            let data = try LocalGoSetupProtocol.encodeReceipt(
                .init(transactionID: id, status: .success)
            )
            try data.write(to: receipts.appendingPathComponent(id.uuidString.lowercased() + ".plist"))
        }

        let payload = try makePayload()
        try writeIncoming(payload)
        XCTAssertEqual(handoff.consume(), .storageFailure)
        XCTAssertEqual(imports, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: receipts, includingPropertiesForKeys: nil).count, 1_000)
    }

    private enum TestError: Error { case importFailed }

    private func makeHandoff(
        importer: @escaping LocalGoSetupHandoff.Importer
    ) -> LocalGoSetupHandoff {
        LocalGoSetupHandoff(directory: root, importSetupData: importer)
    }

    private func makePayload() throws -> LocalGoSetupProtocol.IncomingPayload {
        let pairing = try makePairingFile()
        return try .init(
            transactionID: UUID(),
            expectedDeviceUDID: "00008110-001c2d1234567890",
            pairingFile: pairing,
            sha256: Data(SHA256.hash(data: pairing))
        )
    }

    private func makePairingFile() throws -> Data {
        let privateKey = Curve25519.Signing.PrivateKey()
        return try PropertyListSerialization.data(
            fromPropertyList: [
                "public_key": privateKey.publicKey.rawRepresentation,
                "private_key": privateKey.rawRepresentation,
                "identifier": UUID().uuidString.lowercased()
            ],
            format: .binary,
            options: 0
        )
    }

    private func writeIncoming(_ payload: LocalGoSetupProtocol.IncomingPayload) throws {
        try LocalGoSetupProtocol.encodeIncoming(payload).write(to: incomingURL)
    }

    private var incomingURL: URL {
        root.appendingPathComponent(LocalGoSetupHandoff.incomingFileName)
    }

    private func receiptURL(for id: UUID) -> URL {
        root
            .appendingPathComponent(LocalGoSetupHandoff.receiptsDirectoryName, isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased() + ".plist")
    }
}
