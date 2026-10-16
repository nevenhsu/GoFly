//
//  LocalGoPairingIdentity.swift
//  StikDebug
//

import Foundation
import idevice

enum LocalGoPairingIdentity {
    private static let context = JITEnableContext.makeIsolatedContext()
    private static let verificationLock = NSLock()

    enum VerificationError: Error, LocalizedError {
        case noExpectedDevice
        case pairingRecordUnavailable
        case tunnelUnavailable
        case deviceInfoUnavailable
        case invalidDeviceInfo
        case deviceMismatch

        var errorDescription: String? {
            switch self {
            case .noExpectedDevice:
                return "No expected device identity is configured."
            case .pairingRecordUnavailable:
                return "The stored pairing record is unavailable."
            case .tunnelUnavailable:
                return "The paired device tunnel is unavailable."
            case .deviceInfoUnavailable:
                return "The paired device identity is unavailable."
            case .invalidDeviceInfo:
                return "The paired device identity could not be validated."
            case .deviceMismatch:
                return "The connected device does not match the paired device."
            }
        }
    }

    /// Reuses an exclusively owned identity tunnel, rebuilding it once after
    /// a transport failure. No client escapes the verification lock.
    /// The actual remote UniqueDeviceID is deliberately never returned or
    /// logged.
    static func verifyCurrentDevice() throws {
        verificationLock.lock()
        defer { verificationLock.unlock() }
        // prepareURL() repairs a raw file after a crash only from the private,
        // authenticated envelope. The record is then checked before opening a
        // device connection.
        _ = PairingFileStore.prepareURL()
        guard let expected = PairingFileStore.expectedDeviceUDID,
              !expected.isEmpty else {
            throw VerificationError.noExpectedDevice
        }
        guard PairingFileStore.verifyStoredRecord(expectedDeviceUDID: expected) else {
            throw VerificationError.pairingRecordUnavailable
        }

        do {
            try context.ensureTunnel()
            try verifyOnCurrentTunnel(expected: expected)
            return
        } catch let error as VerificationError {
            switch error {
            case .tunnelUnavailable, .deviceInfoUnavailable: break
            default: throw error
            }
        } catch {
            // Opening/reading an expired transport may fail before the typed
            // identity checks. Retry once on this privately owned context.
        }

        do {
            try context.startTunnel()
        } catch {
            throw VerificationError.tunnelUnavailable
        }
        try verifyOnCurrentTunnel(expected: expected)
    }

    private static func verifyOnCurrentTunnel(expected: String) throws {
        guard let adapter = context.adapterHandle, let handshake = context.handshakeHandle else {
            throw VerificationError.tunnelUnavailable
        }
        var client: OpaquePointer?
        defer {
            if let client { lockdownd_client_free(client) }
        }
        if let error = lockdownd_connect_rsd(adapter, handshake, &client) {
            idevice_error_free(error)
            throw VerificationError.deviceInfoUnavailable
        }
        guard let client else { throw VerificationError.deviceInfoUnavailable }
        try verifyIdentity(with: client, expected: expected)
    }

    private static func verifyIdentity(with lockdownClient: OpaquePointer, expected: String) throws {
        let xml: UnsafeMutablePointer<CChar>
        do {
            guard let value = try context.ideviceInfoGetXML(
                withLockdownClient: lockdownClient
            ) else {
                throw VerificationError.deviceInfoUnavailable
            }
            xml = value
        } catch let error as VerificationError {
            throw error
        } catch {
            throw VerificationError.deviceInfoUnavailable
        }
        defer { plist_mem_free(xml) }

        guard let xmlString = String(validatingUTF8: xml) else {
            throw VerificationError.invalidDeviceInfo
        }

        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(
                from: Data(xmlString.utf8),
                options: [],
                format: nil
            )
        } catch {
            throw VerificationError.invalidDeviceInfo
        }

        guard let dictionary = object as? [String: Any],
              let actual = dictionary["UniqueDeviceID"] as? String else {
            throw VerificationError.invalidDeviceInfo
        }

        let normalizedExpected = normalize(expected)
        let normalizedActual = normalize(actual)
        guard !normalizedExpected.isEmpty,
              !normalizedActual.isEmpty else {
            throw VerificationError.invalidDeviceInfo
        }
        guard normalizedExpected.caseInsensitiveCompare(normalizedActual) == .orderedSame else {
            throw VerificationError.deviceMismatch
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
