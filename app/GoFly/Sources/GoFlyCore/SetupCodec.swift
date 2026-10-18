import Foundation

private func _setupUUID(_ value: _SetupJSON) throws -> UUID {
    guard let uuid = UUID(uuidString: try value.string()) else { throw SetupFailure.invalidInput }
    return uuid
}
public enum SetupCodec {
    public static func encodeManifest(_ manifest: SetupManifest) throws -> Data {
        try encode(object: manifestObject(manifest), maximum: SetupManifest.maximumBytes)
    }

    public static func decodeManifest(_ data: Data) throws -> SetupManifest {
        guard data.count <= SetupManifest.maximumBytes else { throw SetupFailure.limitExceeded }
        return try SetupManifest.decode(_SetupJSON.parse(data))
    }

    public static func encodeRequest(_ request: SetupReadbackRequest) throws -> Data {
        try encode(object: requestObject(request), maximum: 64 * 1_024)
    }

    public static func decodeRequest(_ data: Data) throws -> SetupReadbackRequest {
        guard data.count <= 64 * 1_024 else { throw SetupFailure.limitExceeded }
        return try SetupReadbackRequest.decode(_SetupJSON.parse(data))
    }

    public static func encodeReceipt(_ receipt: SetupReadbackReceipt) throws -> Data {
        try encode(object: readbackReceiptObject(receipt), maximum: 64 * 1_024)
    }

    public static func decodeReceipt(_ data: Data) throws -> SetupReadbackReceipt {
        guard data.count <= 64 * 1_024 else { throw SetupFailure.limitExceeded }
        return try SetupReadbackReceipt.decode(_SetupJSON.parse(data))
    }

    static func encodeActivation(_ record: SetupActivationRecord) throws -> Data {
        try encode(object: activationObject(record), maximum: 256 * 1_024)
    }

    static func decodeActivation(_ data: Data) throws -> SetupActivationRecord {
        guard data.count <= 256 * 1_024 else { throw SetupFailure.limitExceeded }
        return try SetupActivationRecord.decode(_SetupJSON.parse(data))
    }

    private static func encode(object: [String: Any], maximum: Int) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else { throw SetupFailure.invalidInput }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            guard data.count <= maximum else { throw SetupFailure.limitExceeded }
            return data
        } catch let failure as SetupFailure { throw failure }
        catch { throw SetupFailure.invalidInput }
    }

    static func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }
    static func appObject(_ value: SetupAppIdentity) -> [String: Any] {
        ["bundleID": value.bundleID, "build": value.build,
         "profileSHA256": value.profileSHA256, "executableSHA256": value.executableSHA256]
    }
    static func artifactObject(_ value: SetupArtifact) -> [String: Any] {
        ["id": uuid(value.id), "filename": value.filename, "byteCount": value.byteCount, "sha256": value.sha256]
    }
    static func manifestObject(_ value: SetupManifest) -> [String: Any] {
        ["version": value.version, "setupID": uuid(value.setupID), "nonce": uuid(value.nonce),
         "expectedDeviceUDID": value.expectedDeviceUDID, "pairingTransactionID": uuid(value.pairingTransactionID),
         "pairingSHA256": value.pairingSHA256, "app": appObject(value.app), "teamID": value.teamID,
         "signingExpiry": value.signingExpiry, "deviceOS": value.deviceOS, "method": value.method.rawValue,
         "artifacts": value.artifacts.map(artifactObject)]
    }
    static func requestObject(_ value: SetupReadbackRequest) -> [String: Any] {
        ["version": value.version, "setupID": uuid(value.setupID), "nonce": uuid(value.nonce),
         "expectedDeviceUDID": value.expectedDeviceUDID, "app": appObject(value.app)]
    }
    static func observationObject(_ value: SetupPairingObservation) -> [String: Any] {
        switch value {
        case .absent: return ["kind": "absent"]
        case .invalid: return ["kind": "invalid"]
        case .verified(let device, let sha256): return ["kind": "verified", "expectedDeviceUDID": device, "sha256": sha256]
        }
    }
    static func readbackReceiptObject(_ value: SetupReadbackReceipt) -> [String: Any] {
        ["version": value.version, "setupID": uuid(value.setupID), "nonce": uuid(value.nonce),
         "expectedDeviceUDID": value.expectedDeviceUDID, "app": appObject(value.app),
         "pairing": observationObject(value.pairing)]
    }
    static func receiptObject(_ value: SetupReceipt) -> [String: Any] {
        ["version": value.version, "setupID": uuid(value.setupID), "nonce": uuid(value.nonce),
         "expectedDeviceUDID": value.expectedDeviceUDID, "rawManifestSHA256": value.rawManifestSHA256,
         "pairingTransactionID": uuid(value.pairingTransactionID), "pairingSHA256": value.pairingSHA256,
         "app": appObject(value.app), "teamID": value.teamID, "signingExpiry": value.signingExpiry,
         "deviceOS": value.deviceOS, "method": value.method.rawValue, "generationID": uuid(value.generationID),
         "artifacts": value.artifacts.map(artifactObject), "status": value.status]
    }
    static func activationObject(_ value: SetupActivationRecord) -> [String: Any] {
        ["version": value.version, "activeSetupID": value.activeSetupID.map(uuid) as Any,
         "receipts": value.receipts.map(receiptObject)]
    }
}

extension SetupManifest {
    static func decode(_ value: _SetupJSON) throws -> SetupManifest {
        try value.requireObjectKeys(["version", "setupID", "nonce", "expectedDeviceUDID", "pairingTransactionID", "pairingSHA256", "app", "teamID", "signingExpiry", "deviceOS", "method", "artifacts"])
        let version = try value.object("version").int()
        guard version == schemaVersion else { throw SetupFailure.unsupportedVersion }
        let methodValue = try value.object("method").string()
        guard let method = SetupSupportMethod(rawValue: methodValue) else { throw SetupFailure.invalidInput }
        let artifacts = try value.object("artifacts").array().map { try SetupArtifact.decode($0) }
        return try SetupManifest(version: version,
            setupID: try _setupUUID(value.object("setupID")), nonce: try _setupUUID(value.object("nonce")),
            expectedDeviceUDID: try value.object("expectedDeviceUDID").string(),
            pairingTransactionID: try _setupUUID(value.object("pairingTransactionID")),
            pairingSHA256: try value.object("pairingSHA256").string(),
            app: try SetupAppIdentity.decode(value.object("app")), teamID: try value.object("teamID").string(),
            signingExpiry: try value.object("signingExpiry").string(), deviceOS: try value.object("deviceOS").string(),
            method: method, artifacts: artifacts)
    }
}

extension SetupAppIdentity {
    static func decode(_ value: _SetupJSON) throws -> SetupAppIdentity {
        try value.requireObjectKeys(["bundleID", "build", "profileSHA256", "executableSHA256"])
        return try SetupAppIdentity(bundleID: value.object("bundleID").string(), build: value.object("build").string(),
                                    profileSHA256: value.object("profileSHA256").string(), executableSHA256: value.object("executableSHA256").string())
    }
}

extension SetupArtifact {
    static func decode(_ value: _SetupJSON) throws -> SetupArtifact {
        try value.requireObjectKeys(["id", "filename", "byteCount", "sha256"])
        return try SetupArtifact(id: _setupUUID(value.object("id")), filename: value.object("filename").string(),
                                 byteCount: value.object("byteCount").int64(), sha256: value.object("sha256").string())
    }
}

extension SetupReadbackRequest {
    static func decode(_ value: _SetupJSON) throws -> SetupReadbackRequest {
        try value.requireObjectKeys(["version", "setupID", "nonce", "expectedDeviceUDID", "app"])
        let version = try value.object("version").int()
        guard version == schemaVersion else { throw SetupFailure.unsupportedVersion }
        return try SetupReadbackRequest(version: version, setupID: _setupUUID(value.object("setupID")), nonce: _setupUUID(value.object("nonce")),
                                        expectedDeviceUDID: value.object("expectedDeviceUDID").string(), app: SetupAppIdentity.decode(value.object("app")))
    }
}

extension SetupPairingObservation {
    static func decode(_ value: _SetupJSON) throws -> SetupPairingObservation {
        guard case .object = value else { throw SetupFailure.invalidInput }
        let kind = try value.object("kind").string()
        switch kind {
        case "absent": try value.requireObjectKeys(["kind"]); return .absent
        case "invalid": try value.requireObjectKeys(["kind"]); return .invalid
        case "verified":
            try value.requireObjectKeys(["kind", "expectedDeviceUDID", "sha256"])
            let device = try value.object("expectedDeviceUDID").string()
            let hash = try value.object("sha256").string()
            guard SetupValidation.validUDID(device) else { throw SetupFailure.invalidInput }
            guard SetupValidation.isLowerHex(hash, count: 64) else { throw SetupFailure.invalidInput }
            return .verified(expectedDeviceUDID: device, sha256: hash)
        default: throw SetupFailure.invalidInput
        }
    }
}

extension SetupReadbackReceipt {
    static func decode(_ value: _SetupJSON) throws -> SetupReadbackReceipt {
        try value.requireObjectKeys(["version", "setupID", "nonce", "expectedDeviceUDID", "app", "pairing"])
        let version = try value.object("version").int()
        guard version == schemaVersion else { throw SetupFailure.unsupportedVersion }
        return try SetupReadbackReceipt(version: version, setupID: _setupUUID(value.object("setupID")), nonce: _setupUUID(value.object("nonce")),
                                         expectedDeviceUDID: value.object("expectedDeviceUDID").string(), app: SetupAppIdentity.decode(value.object("app")), pairing: SetupPairingObservation.decode(value.object("pairing")))
    }
}

extension SetupReceipt {
    static func decode(_ value: _SetupJSON) throws -> SetupReceipt {
        try value.requireObjectKeys(["version", "setupID", "nonce", "expectedDeviceUDID", "rawManifestSHA256", "pairingTransactionID", "pairingSHA256", "app", "teamID", "signingExpiry", "deviceOS", "method", "generationID", "artifacts", "status"])
        let version = try value.object("version").int()
        guard version == schemaVersion else { throw SetupFailure.unsupportedVersion }
        guard try value.object("status").string() == "committed" else { throw SetupFailure.invalidInput }
        let methodValue = try value.object("method").string()
        guard let method = SetupSupportMethod(rawValue: methodValue) else { throw SetupFailure.invalidInput }
        let manifest = try SetupManifest(version: 1, setupID: _setupUUID(value.object("setupID")), nonce: _setupUUID(value.object("nonce")),
            expectedDeviceUDID: value.object("expectedDeviceUDID").string(), pairingTransactionID: _setupUUID(value.object("pairingTransactionID")),
            pairingSHA256: value.object("pairingSHA256").string(), app: SetupAppIdentity.decode(value.object("app")), teamID: value.object("teamID").string(),
            signingExpiry: value.object("signingExpiry").string(), deviceOS: value.object("deviceOS").string(), method: method,
            artifacts: value.object("artifacts").array().map { try SetupArtifact.decode($0) })
        let receipt = try SetupReceipt(manifest: manifest, rawManifestSHA256: value.object("rawManifestSHA256").string())
        guard receipt.generationID == (try _setupUUID(value.object("generationID"))) else { throw SetupFailure.invalidInput }
        return receipt
    }
}

extension SetupActivationRecord {
    static func decode(_ value: _SetupJSON) throws -> SetupActivationRecord {
        try value.requireObjectKeys(["version", "activeSetupID", "receipts"])
        let version = try value.object("version").int()
        guard version == schemaVersion else { throw SetupFailure.unsupportedVersion }
        let activeValue = try value.object("activeSetupID")
        let activeID: UUID?
        if case .null = activeValue { activeID = nil } else { activeID = try _setupUUID(activeValue) }
        return try SetupActivationRecord(version: version, activeSetupID: activeID,
                                         receipts: try value.object("receipts").array().map { try SetupReceipt.decode($0) })
    }
}
