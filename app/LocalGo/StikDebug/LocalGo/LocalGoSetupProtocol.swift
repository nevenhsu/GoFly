//
//  LocalGoSetupProtocol.swift
//  LocalGo
//
//  The small, versioned plist protocol used by the macOS setup helper and
//  LocalGo.  This file intentionally has no app or device-framework
//  dependencies so it can be tested on its own.
//

import Foundation
import CryptoKit
import CoreFoundation

/// The on-disk protocol shared by the macOS setup helper and the iOS app.
public enum LocalGoSetupProtocol {
    public static let version = 1
    public static let maximumPairingFileBytes = 1 * 1024 * 1024
    public static let maximumIncomingFileBytes = maximumPairingFileBytes + 64 * 1024
    public static let maximumReceiptCount = 1_000

    public struct IncomingPayload: Equatable, Sendable {
        public let transactionID: UUID
        public let expectedDeviceUDID: String
        public let pairingFile: Data
        public let sha256: Data

        public init(
            transactionID: UUID,
            expectedDeviceUDID: String,
            pairingFile: Data,
            sha256: Data
        ) throws {
            guard let normalized = LocalGoSetupProtocol.normalizeDeviceUDID(expectedDeviceUDID),
                  pairingFile.count <= maximumPairingFileBytes,
                  sha256.count == 32 else {
                throw Error.invalidPayload
            }
            try LocalGoSetupProtocol.validatePairingFile(pairingFile)
            guard Data(SHA256.hash(data: pairingFile)) == sha256 else {
                throw Error.invalidPayload
            }
            self.transactionID = transactionID
            self.expectedDeviceUDID = normalized
            self.pairingFile = pairingFile
            self.sha256 = sha256
        }
    }

    public struct Receipt: Equatable, Sendable {
        public enum Status: String, Equatable, Sendable {
            case success
            case rejected
        }

        public let transactionID: UUID
        public let status: Status

        public init(transactionID: UUID, status: Status) {
            self.transactionID = transactionID
            self.status = status
        }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidPayload
        case invalidReceipt
        case unsupportedVersion
    }

    /// Parses and validates the complete incoming plist. The parser accepts
    /// only the protocol's exact top-level keys and never returns an
    /// unvalidated pairing payload.
    public static func decodeIncoming(_ data: Data) throws -> IncomingPayload {
        guard data.count <= maximumIncomingFileBytes else {
            throw Error.invalidPayload
        }

        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw Error.invalidPayload
        }

        guard let dictionary = object as? [String: Any],
              Set(dictionary.keys) == ["version", "transactionID", "expectedDeviceUDID", "pairingFile", "sha256"],
              let version = dictionary["version"] as? Int,
              let transactionString = dictionary["transactionID"] as? String,
              let transactionID = strictUUID(transactionString),
              let expectedDeviceUDID = dictionary["expectedDeviceUDID"] as? String,
              let pairingFile = dictionary["pairingFile"] as? Data,
              let sha256 = dictionary["sha256"] as? Data else {
            throw Error.invalidPayload
        }
        guard transactionString == transactionString.lowercased(),
              expectedDeviceUDID == expectedDeviceUDID.lowercased() else {
            throw Error.invalidPayload
        }

        // Property-list NSNumber can bridge to Int, so explicitly reject a
        // Boolean version as well as every value other than protocol version 1.
        if let number = dictionary["version"] as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            throw Error.invalidPayload
        }
        guard version == Self.version else {
            throw Error.unsupportedVersion
        }

        return try IncomingPayload(
            transactionID: transactionID,
            expectedDeviceUDID: expectedDeviceUDID,
            pairingFile: pairingFile,
            sha256: sha256
        )
    }

    public static func encodeIncoming(_ payload: IncomingPayload) throws -> Data {
        let object: [String: Any] = [
            "version": version,
            "transactionID": payload.transactionID.uuidString.lowercased(),
            "expectedDeviceUDID": payload.expectedDeviceUDID,
            "pairingFile": payload.pairingFile,
            "sha256": payload.sha256
        ]
        do {
            return try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        } catch {
            throw Error.invalidPayload
        }
    }

    public static func decodeReceipt(_ data: Data) throws -> Receipt {
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw Error.invalidReceipt
        }
        guard let dictionary = object as? [String: Any],
              Set(dictionary.keys) == ["version", "transactionID", "status"],
              let version = dictionary["version"] as? Int,
              let transactionString = dictionary["transactionID"] as? String,
              let transactionID = strictUUID(transactionString),
              let statusString = dictionary["status"] as? String,
              let status = Receipt.Status(rawValue: statusString) else {
            throw Error.invalidReceipt
        }
        if let number = dictionary["version"] as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            throw Error.invalidReceipt
        }
        guard version == Self.version else {
            throw Error.unsupportedVersion
        }
        return Receipt(transactionID: transactionID, status: status)
    }

    public static func encodeReceipt(_ receipt: Receipt) throws -> Data {
        let object: [String: Any] = [
            "version": version,
            "transactionID": receipt.transactionID.uuidString.lowercased(),
            "status": receipt.status.rawValue
        ]
        do {
            return try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        } catch {
            throw Error.invalidReceipt
        }
    }

    /// Validates the remote-pairing plist independently of the native reader.
    /// The app's import closure still performs the authoritative native parse.
    public static func validatePairingFile(_ data: Data) throws {
        guard data.count <= maximumPairingFileBytes else {
            throw Error.invalidPayload
        }

        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw Error.invalidPayload
        }
        guard let dictionary = object as? [String: Any],
              let publicKey = dictionary["public_key"] as? Data,
              let privateKey = dictionary["private_key"] as? Data,
              publicKey.count == 32,
              privateKey.count == 32,
              let identifier = dictionary["identifier"] as? String,
              strictUUID(identifier) != nil else {
            throw Error.invalidPayload
        }

        if let altIRK = dictionary["alt_irk"] as? Data {
            guard altIRK.count == 16 else { throw Error.invalidPayload }
        } else if dictionary["alt_irk"] != nil {
            throw Error.invalidPayload
        }

        do {
            let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
            guard signingKey.publicKey.rawRepresentation == publicKey else {
                throw Error.invalidPayload
            }
        } catch {
            throw Error.invalidPayload
        }
    }

    public static func normalizeDeviceUDID(_ value: String) -> String? {
        let normalized = value.lowercased()
        let scalars = Array(normalized.unicodeScalars)

        func isHex(_ scalar: UnicodeScalar) -> Bool {
            switch scalar.value {
            case 48...57, 97...102: return true
            default: return false
            }
        }

        // Modern device identifiers are 24 hex characters separated after
        // the first 8 characters (25 UTF-8 bytes including the dash).
        if scalars.count == 25,
           scalars[8] == "-",
           scalars.enumerated().allSatisfy({ index, scalar in index == 8 || isHex(scalar) }) {
            return normalized
        }

        if scalars.count == 40, scalars.allSatisfy(isHex) {
            return normalized
        }
        return nil
    }

    private static func strictUUID(_ value: String) -> UUID? {
        guard value.utf8.count == 36,
              value.unicodeScalars.enumerated().allSatisfy({ index, scalar in
                  let isDash = index == 8 || index == 13 || index == 18 || index == 23
                  if isDash { return scalar == "-" }
                  switch scalar.value {
                  case 48...57, 65...70, 97...102: return true
                  default: return false
                  }
              }),
              let uuid = UUID(uuidString: value) else {
            return nil
        }
        return uuid.uuidString.lowercased() == value ? uuid : nil
    }
}
