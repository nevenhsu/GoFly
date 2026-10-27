import CryptoKit
import Foundation

@main
private enum LocalGoSetupHandoffHostTests {
    private static let deviceID = String(repeating: "0", count: 40)

    static func main() throws {
        try testConsumerClaimsAndConsumesOneShotFile()
        try testRecoveredClaimIsConsumed()
        try testWrongTransactionRestoresIncomingFile()
        try testConflictingPathsFailClosed()
        try testBusyEngineDoesNotClaimFile()
        print("LocalGoSetupHandoff host tests passed")
    }

    private static func testConsumerClaimsAndConsumesOneShotFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let transactionID = UUID()
        let payload = try encodedPayload(transactionID: transactionID)
        let incoming = fixture.url(LocalGoSetupHandoff.incomingFileName)
        let claimed = fixture.url(LocalGoSetupHandoff.consumingFileName)
        try payload.write(to: incoming)
        let userData = fixture.url("user-data.json")
        try Data("keep".utf8).write(to: userData)

        var imported: Data?
        let handoff = LocalGoSetupHandoff(directory: fixture.directory) { pairing, device in
            precondition(device == deviceID)
            imported = pairing
        }
        precondition(handoff.consume() == .imported)
        precondition(imported != nil)
        precondition(!FileManager.default.fileExists(atPath: incoming.path))
        precondition(!FileManager.default.fileExists(atPath: claimed.path))
        let retainedUserData = try Data(contentsOf: userData)
        precondition(retainedUserData == Data("keep".utf8))
        let receiptURL = fixture.url("receipts/\(transactionID.uuidString.lowercased()).plist")
        let receipt = try LocalGoSetupProtocol.decodeReceipt(Data(contentsOf: receiptURL))
        precondition(receipt.transactionID == transactionID)
        precondition(receipt.status == .success)
    }

    private static func testRecoveredClaimIsConsumed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let transactionID = UUID()
        let claimed = fixture.url(LocalGoSetupHandoff.consumingFileName)
        try encodedPayload(transactionID: transactionID).write(to: claimed)
        var importCount = 0
        let handoff = LocalGoSetupHandoff(directory: fixture.directory) { _, _ in importCount += 1 }
        precondition(handoff.consume() == .imported)
        precondition(importCount == 1)
        precondition(!FileManager.default.fileExists(atPath: claimed.path))
    }

    private static func testWrongTransactionRestoresIncomingFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let incoming = fixture.url(LocalGoSetupHandoff.incomingFileName)
        let payload = try encodedPayload(transactionID: UUID())
        try payload.write(to: incoming)
        let handoff = LocalGoSetupHandoff(directory: fixture.directory) { _, _ in
            preconditionFailure("wrong-transaction payload must not be imported")
        }
        precondition(handoff.consume(expectedTransactionID: UUID()) == .rejected)
        let restoredPayload = try Data(contentsOf: incoming)
        precondition(restoredPayload == payload)
        precondition(!FileManager.default.fileExists(atPath: fixture.url(
            LocalGoSetupHandoff.consumingFileName
        ).path))
    }

    private static func testConflictingPathsFailClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let payload = try encodedPayload(transactionID: UUID())
        let incoming = fixture.url(LocalGoSetupHandoff.incomingFileName)
        let claimed = fixture.url(LocalGoSetupHandoff.consumingFileName)
        try payload.write(to: incoming)
        try payload.write(to: claimed)
        let handoff = LocalGoSetupHandoff(directory: fixture.directory) { _, _ in
            preconditionFailure("conflicting paths must not be imported")
        }
        precondition(handoff.consume() == .storageFailure)
        precondition(FileManager.default.fileExists(atPath: incoming.path))
        precondition(FileManager.default.fileExists(atPath: claimed.path))
    }

    private static func testBusyEngineDoesNotClaimFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let incoming = fixture.url(LocalGoSetupHandoff.incomingFileName)
        try encodedPayload(transactionID: UUID()).write(to: incoming)
        let handoff = LocalGoSetupHandoff(directory: fixture.directory) { _, _ in
            preconditionFailure("busy engine must not import")
        }
        precondition(handoff.consume(commandsIdle: false) == .storageFailure)
        precondition(FileManager.default.fileExists(atPath: incoming.path))
        precondition(!FileManager.default.fileExists(atPath: fixture.url(
            LocalGoSetupHandoff.consumingFileName
        ).path))
    }

    private static func encodedPayload(transactionID: UUID) throws -> Data {
        let key = Curve25519.Signing.PrivateKey()
        let pairingObject: [String: Any] = [
            "public_key": key.publicKey.rawRepresentation,
            "private_key": key.rawRepresentation,
            "identifier": UUID().uuidString.lowercased()
        ]
        let pairing = try PropertyListSerialization.data(
            fromPropertyList: pairingObject,
            format: .binary,
            options: 0
        )
        let payload = try LocalGoSetupProtocol.IncomingPayload(
            transactionID: transactionID,
            expectedDeviceUDID: deviceID,
            pairingFile: pairing,
            sha256: Data(SHA256.hash(data: pairing))
        )
        return try LocalGoSetupProtocol.encodeIncoming(payload)
    }

    private struct Fixture {
        let directory: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("gofly-handoff-\(UUID().uuidString)", isDirectory: true)
            _ = try LocalGoSetupHandoff.prepare(directory: directory)
        }

        func url(_ path: String) -> URL {
            path.split(separator: "/").reduce(directory) { partial, component in
                partial.appendingPathComponent(String(component), isDirectory: false)
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
