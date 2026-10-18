import Foundation

private let managementRequestKeys: Set<String> = [
    "version", "managementID", "nonce", "kind", "expectedDeviceUDID", "sourceSetupID",
    "sourceApp", "sourceActivationSHA256", "sourceRestoreRootSHA256", "teamID",
    "targetSetupID", "targetApp"
]

private let managementSourceReceiptKeys: Set<String> = [
    "version", "managementID", "nonce", "requestSHA256", "phase", "pid", "app",
    "sourceSetupID", "activationSHA256", "restoreRootSHA256"
]

private func managementUUID(_ value: _SetupJSON) throws -> UUID {
    let text = try value.string()
    guard text == text.lowercased(),
          let uuid = UUID(uuidString: text),
          uuid.uuidString.lowercased() == text else {
        throw ManagementFailure.invalidInput
    }
    return uuid
}

private func managementString(_ value: _SetupJSON) throws -> String {
    do { return try value.string() }
    catch { throw ManagementFailure.invalidInput }
}

private func managementInt(_ value: _SetupJSON) throws -> Int {
    do { return try value.int() }
    catch { throw ManagementFailure.invalidInput }
}

private func managementHash(_ value: _SetupJSON) throws -> String {
    let hash = try managementString(value)
    guard SetupValidation.isLowerHex(hash, count: 64) else {
        throw ManagementFailure.invalidInput
    }
    return hash
}

private func managementOptionalHash(_ value: _SetupJSON) throws -> String? {
    if case .null = value { return nil }
    return try managementHash(value)
}

private func managementApp(_ value: _SetupJSON) throws -> SetupAppIdentity {
    do { return try SetupAppIdentity.decode(value) }
    catch let failure as SetupFailure { throw managementFailure(failure) }
    catch { throw ManagementFailure.invalidInput }
}

private func managementFailure(_ failure: SetupFailure) -> ManagementFailure {
    switch failure {
    case .unsupportedVersion: return .unsupportedVersion
    case .limitExceeded: return .limitExceeded
    case .unsafeFile: return .unsafeFile
    case .storageUnavailable: return .storageUnavailable
    case .identityMismatch: return .identityMismatch
    default: return .invalidInput
    }
}

private func managementParse(_ data: Data, maximum: Int) throws -> _SetupJSON {
    guard data.count <= maximum else { throw ManagementFailure.limitExceeded }
    do { return try _SetupJSON.parse(data) }
    catch let failure as SetupFailure { throw managementFailure(failure) }
    catch { throw ManagementFailure.invalidInput }
}

public enum ManagementCodec {
    public static func encodeRequest(_ request: ManagementRequest) throws -> Data {
        let object: [String: Any] = [
            "version": request.version,
            "managementID": request.managementID.uuidString.lowercased(),
            "nonce": request.nonce.uuidString.lowercased(),
            "kind": request.kind.rawValue,
            "expectedDeviceUDID": request.expectedDeviceUDID,
            "sourceSetupID": request.sourceSetupID.uuidString.lowercased(),
            "sourceApp": SetupCodec.appObject(request.sourceApp),
            "sourceActivationSHA256": request.sourceActivationSHA256,
            "sourceRestoreRootSHA256": request.sourceRestoreRootSHA256 ?? NSNull(),
            "teamID": request.teamID,
            "targetSetupID": request.targetSetupID.uuidString.lowercased(),
            "targetApp": SetupCodec.appObject(request.targetApp)
        ]
        return try encode(object: object, maximum: ManagementRequest.maximumBytes)
    }

    public static func decodeRequest(_ data: Data) throws -> ManagementRequest {
        do {
            let value = try managementParse(data, maximum: ManagementRequest.maximumBytes)
            try value.requireObjectKeys(managementRequestKeys)
            let version = try managementInt(value.object("version"))
            guard version == ManagementRequest.schemaVersion else { throw ManagementFailure.unsupportedVersion }
            guard let kind = ManagementKind(rawValue: try managementString(value.object("kind"))) else {
                throw ManagementFailure.invalidInput
            }
            return try ManagementRequest(
                version: version,
                managementID: try managementUUID(value.object("managementID")),
                nonce: try managementUUID(value.object("nonce")),
                kind: kind,
                expectedDeviceUDID: try managementString(value.object("expectedDeviceUDID")),
                sourceSetupID: try managementUUID(value.object("sourceSetupID")),
                sourceApp: try managementApp(value.object("sourceApp")),
                sourceActivationSHA256: try managementHash(value.object("sourceActivationSHA256")),
                sourceRestoreRootSHA256: try managementOptionalHash(value.object("sourceRestoreRootSHA256")),
                teamID: try managementString(value.object("teamID")),
                targetSetupID: try managementUUID(value.object("targetSetupID")),
                targetApp: try managementApp(value.object("targetApp")))
        } catch let failure as ManagementFailure {
            throw failure
        } catch let failure as SetupFailure {
            throw managementFailure(failure)
        } catch {
            throw ManagementFailure.invalidInput
        }
    }

    public static func encodeSourceReceipt(_ receipt: ManagementSourceReceipt) throws -> Data {
        let object: [String: Any] = [
            "version": receipt.version,
            "managementID": receipt.managementID.uuidString.lowercased(),
            "nonce": receipt.nonce.uuidString.lowercased(),
            "requestSHA256": receipt.requestSHA256,
            "phase": receipt.phase.rawValue,
            "pid": receipt.pid,
            "app": SetupCodec.appObject(receipt.app),
            "sourceSetupID": receipt.sourceSetupID.uuidString.lowercased(),
            "activationSHA256": receipt.activationSHA256,
            "restoreRootSHA256": receipt.restoreRootSHA256 ?? NSNull()
        ]
        return try encode(object: object, maximum: ManagementSourceReceipt.maximumBytes)
    }

    public static func decodeSourceReceipt(_ data: Data) throws -> ManagementSourceReceipt {
        do {
            let value = try managementParse(data, maximum: ManagementSourceReceipt.maximumBytes)
            try value.requireObjectKeys(managementSourceReceiptKeys)
            let version = try managementInt(value.object("version"))
            guard version == ManagementSourceReceipt.schemaVersion else { throw ManagementFailure.unsupportedVersion }
            guard let phase = ManagementSourcePhase(rawValue: try managementString(value.object("phase"))) else {
                throw ManagementFailure.invalidInput
            }
            let pid = try managementInt(value.object("pid"))
            guard pid > 0, pid <= Int(Int32.max) else { throw ManagementFailure.invalidInput }
            return try ManagementSourceReceipt(
                version: version,
                managementID: try managementUUID(value.object("managementID")),
                nonce: try managementUUID(value.object("nonce")),
                requestSHA256: try managementHash(value.object("requestSHA256")),
                phase: phase,
                pid: Int32(pid),
                app: try managementApp(value.object("app")),
                sourceSetupID: try managementUUID(value.object("sourceSetupID")),
                activationSHA256: try managementHash(value.object("activationSHA256")),
                restoreRootSHA256: try managementOptionalHash(value.object("restoreRootSHA256")))
        } catch let failure as ManagementFailure {
            throw failure
        } catch let failure as SetupFailure {
            throw managementFailure(failure)
        } catch {
            throw ManagementFailure.invalidInput
        }
    }

    private static func encode(object: [String: Any], maximum: Int) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else { throw ManagementFailure.invalidInput }
        do {
            let data = try JSONSerialization.data(withJSONObject: object,
                                                   options: [.sortedKeys, .withoutEscapingSlashes])
            guard data.count <= maximum else { throw ManagementFailure.limitExceeded }
            return data
        } catch let failure as ManagementFailure {
            throw failure
        } catch {
            throw ManagementFailure.invalidInput
        }
    }
}
