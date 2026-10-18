import Foundation

private func transferUUID(_ value: _SetupJSON) throws -> UUID {
    let text: String
    do { text = try value.string() } catch { throw TransferFailure.invalidInput }
    guard text == text.lowercased(), let uuid = UUID(uuidString: text),
          uuid.uuidString.lowercased() == text else { throw TransferFailure.invalidInput }
    return uuid
}

private func transferString(_ value: _SetupJSON) throws -> String {
    do { return try value.string() } catch { throw TransferFailure.invalidInput }
}

private func transferInt(_ value: _SetupJSON) throws -> Int {
    do { return try value.int() } catch { throw TransferFailure.invalidInput }
}

private func transferBool(_ value: _SetupJSON) throws -> Bool {
    do { return try value.bool() } catch { throw TransferFailure.invalidInput }
}

private func transferApp(_ value: _SetupJSON) throws -> SetupAppIdentity {
    do {
        return try SetupAppIdentity.decode(value)
    } catch {
        throw TransferFailure.identityMismatch
    }
}

public enum TransferCodec {
    public static func encodeManifest(_ manifest: TransferManifest) throws -> Data {
        let artifacts = manifest.artifacts.sorted { $0.path < $1.path }.map { artifact in
            ["id": artifact.id.uuidString.lowercased(), "path": artifact.path,
             "byteCount": artifact.byteCount, "sha256": artifact.sha256] as [String: Any]
        }
        let schemas = Dictionary(uniqueKeysWithValues: manifest.categories.map { ($0.rawValue, 1) })
        let object: [String: Any] = [
            "version": manifest.version,
            "transferID": manifest.transferID.uuidString.lowercased(),
            "dataSetID": manifest.dataSetID.uuidString.lowercased(),
            "nonce": manifest.nonce.uuidString.lowercased(),
            "sourceDeviceUDID": manifest.sourceDeviceUDID,
            "destinationDeviceUDID": manifest.destinationDeviceUDID,
            "sourceApp": SetupCodec.appObject(manifest.sourceApp),
            "targetApp": SetupCodec.appObject(manifest.targetApp),
            "setupID": manifest.setupID.uuidString.lowercased(),
            "categories": manifest.categories.map(\.rawValue),
            "schemas": schemas,
            "artifacts": artifacts
        ]
        return try transferEncode(object, maximum: TransferLimits.manifestBytes)
    }

    public static func decodeManifest(_ data: Data) throws -> TransferManifest {
        guard data.count <= TransferLimits.manifestBytes else { throw TransferFailure.limitExceeded }
        let value: _SetupJSON
        do { value = try _SetupJSON.parse(data) }
        catch let failure as SetupFailure { throw transferFailure(failure) }
        catch { throw TransferFailure.invalidInput }
        do {
            try value.requireObjectKeys(["version", "transferID", "dataSetID", "nonce",
                                         "sourceDeviceUDID", "destinationDeviceUDID", "sourceApp",
                                         "targetApp", "setupID", "categories", "schemas", "artifacts"])
            let version = try transferInt(value.object("version"))
            guard version == TransferManifest.schemaVersion else { throw TransferFailure.unsupportedVersion }
            let categoryValues = try value.object("categories").array().map(transferString)
            let categories = categoryValues.compactMap { TransferCategory(rawValue: $0) }
            guard categories.count == categoryValues.count,
                  Set(categories).count == categories.count,
                  categories == TransferCategory.allCases.filter({ categories.contains($0) }) else {
                throw TransferFailure.invalidInput
            }
            var schemaValues: [String: Int] = [:]
            guard case .object(let schemaPairs) = try value.object("schemas") else { throw TransferFailure.invalidInput }
            let schemaKeys = schemaPairs.map { $0.0 }
            guard Set(schemaKeys).count == schemaKeys.count,
                  Set(schemaKeys) == Set(categories.map { $0.rawValue }) else {
                throw TransferFailure.invalidInput
            }
            for (key, item) in schemaPairs {
                schemaValues[key] = try transferInt(item)
            }
            guard schemaValues == Dictionary(uniqueKeysWithValues: categories.map { ($0.rawValue, 1) }) else {
                throw TransferFailure.unsupportedVersion
            }
            let artifacts = try value.object("artifacts").array().map { item -> TransferArtifact in
                try item.requireObjectKeys(["id", "path", "byteCount", "sha256"])
                do {
                    return try TransferArtifact(id: transferUUID(item.object("id")),
                                                path: transferString(item.object("path")),
                                                byteCount: item.object("byteCount").int64(),
                                                sha256: transferString(item.object("sha256")))
                } catch let failure as TransferFailure { throw failure }
                catch { throw TransferFailure.invalidInput }
            }
            return try TransferManifest(transferID: transferUUID(value.object("transferID")),
                                        dataSetID: transferUUID(value.object("dataSetID")),
                                        nonce: transferUUID(value.object("nonce")),
                                        sourceDeviceUDID: transferString(value.object("sourceDeviceUDID")),
                                        destinationDeviceUDID: transferString(value.object("destinationDeviceUDID")),
                                        sourceApp: transferApp(value.object("sourceApp")),
                                        targetApp: transferApp(value.object("targetApp")),
                                        setupID: transferUUID(value.object("setupID")),
                                        categories: categories, artifacts: artifacts)
        } catch let failure as TransferFailure {
            throw failure
        } catch {
            throw TransferFailure.invalidInput
        }
    }

    public static func encodeSettings(_ settings: TransferSettings) throws -> Data {
        let object: [String: Any] = [
            "version": settings.version,
            "language": settings.language,
            "appearance": settings.appearance,
            "mode": settings.mode.rawValue,
            "roundTripEnabled": settings.roundTripEnabled,
            "joystickSpeed": settings.joystickSpeed.kilometersPerHour
        ]
        return try transferEncode(object, maximum: TransferLimits.settingsBytes)
    }

    public static func decodeSettings(_ data: Data) throws -> TransferSettings {
        guard data.count <= TransferLimits.settingsBytes else { throw TransferFailure.limitExceeded }
        do {
            let value = try _SetupJSON.parse(data)
            try value.requireObjectKeys(["version", "language", "appearance", "mode", "roundTripEnabled", "joystickSpeed"])
            guard try transferInt(value.object("version")) == TransferSettings.schemaVersion,
                  let mode = SessionMapMode(rawValue: try transferString(value.object("mode"))),
                  let speed = RouteSpeed(kilometersPerHour: try transferInt(value.object("joystickSpeed"))) else {
                throw TransferFailure.unsupportedVersion
            }
            return try TransferSettings(language: transferString(value.object("language")),
                                        appearance: transferString(value.object("appearance")), mode: mode,
                                        roundTripEnabled: transferBool(value.object("roundTripEnabled")),
                                        joystickSpeed: speed)
        } catch let failure as TransferFailure { throw failure }
        catch let failure as SetupFailure { throw transferFailure(failure) }
        catch { throw TransferFailure.invalidInput }
    }

    public static func encodeDraft(_ draft: RouteDraft) throws -> Data {
        do {
            return try SessionRecoveryCodec.encode(SessionRecoverySnapshot(draft: draft))
        } catch let failure as SessionRecoveryFailure {
            switch failure {
            case .limitExceeded: throw TransferFailure.limitExceeded
            default: throw TransferFailure.invalidInput
            }
        } catch { throw TransferFailure.invalidInput }
    }

    public static func decodeDraft(_ data: Data) throws -> RouteDraft {
        guard data.count <= TransferLimits.draftBytes else { throw TransferFailure.limitExceeded }
        do {
            let decoded = try SessionRecoveryCodec.decodeRecord(data)
            guard decoded.revision == 0,
                  decoded.snapshot.mode == .teleport,
                  decoded.snapshot.roundTripEnabled == false,
                  decoded.snapshot.joystickSpeed == .standard,
                  decoded.snapshot.position == nil,
                  decoded.snapshot.activeMovement == nil,
                  decoded.snapshot.uncertainty == nil else {
                throw TransferFailure.invalidInput
            }
            return decoded.snapshot.draft
        } catch let failure as TransferFailure { throw failure }
        catch let failure as SessionRecoveryFailure {
            switch failure {
            case .limitExceeded: throw TransferFailure.limitExceeded
            case .unsupportedSchema: throw TransferFailure.unsupportedVersion
            default: throw TransferFailure.invalidInput
            }
        } catch { throw TransferFailure.invalidInput }
    }

    private static func transferEncode(_ object: [String: Any], maximum: Int) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else { throw TransferFailure.invalidInput }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            guard data.count <= maximum else { throw TransferFailure.limitExceeded }
            return data
        } catch let failure as TransferFailure { throw failure }
        catch { throw TransferFailure.invalidInput }
    }

    private static func transferFailure(_ failure: SetupFailure) -> TransferFailure {
        switch failure {
        case .unsupportedVersion: return .unsupportedVersion
        case .limitExceeded: return .limitExceeded
        default: return .invalidInput
        }
    }
}
