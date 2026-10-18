import CryptoKit
import Darwin
import Foundation

// MARK: - Transfer control values

/// The request written by the producer before it addresses the live App.
public struct TransferExportRequest: Sendable, Equatable {
    public static let schemaVersion = 1
    public let version: Int
    public let transferID: UUID
    public let dataSetID: UUID
    public let nonce: UUID
    public let sourceDeviceUDID: String
    public let destinationDeviceUDID: String
    public let sourceBundleID: String
    public let sourceBuild: String
    public let targetApp: SetupAppIdentity
    public let setupID: UUID
    public let categories: [TransferCategory]

    public init(version: Int = Self.schemaVersion, transferID: UUID, dataSetID: UUID,
                nonce: UUID, sourceDeviceUDID: String, destinationDeviceUDID: String,
                sourceBundleID: String = SetupAppIdentity.formalBundleID,
                sourceBuild: String, targetApp: SetupAppIdentity, setupID: UUID,
                categories: [TransferCategory]) throws {
        guard version == Self.schemaVersion,
              SetupValidation.validUDID(sourceDeviceUDID),
              SetupValidation.validUDID(destinationDeviceUDID),
              sourceDeviceUDID == destinationDeviceUDID,
              sourceBundleID == SetupAppIdentity.formalBundleID,
              !sourceBuild.isEmpty, sourceBuild.utf8.count <= 128,
              sourceBuild.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              categories == TransferCategory.allCases.filter({ categories.contains($0) }),
              Set(categories).count == categories.count else { throw TransferFailure.invalidInput }
        self.version = version; self.transferID = transferID; self.dataSetID = dataSetID
        self.nonce = nonce; self.sourceDeviceUDID = sourceDeviceUDID
        self.destinationDeviceUDID = destinationDeviceUDID; self.sourceBundleID = sourceBundleID
        self.sourceBuild = sourceBuild; self.targetApp = targetApp; self.setupID = setupID
        self.categories = categories
    }
}

/// A raw request and its original bytes.  The original digest is never
/// obtained by encoding the typed request again.
public struct TransferExportInput: Sendable, Equatable {
    public let request: TransferExportRequest
    public let rawData: Data
    public let rawSHA256: String

    public init(data: Data) throws {
        guard !data.isEmpty, data.count <= TransferLimits.requestBytes else { throw TransferFailure.limitExceeded }
        self.request = try TransferControlCodec.decodeExportRequest(data)
        self.rawData = data
        self.rawSHA256 = SetupValidation.sha256(data)
    }
    public var requestSHA256: String { rawSHA256 }
}

public enum TransferAction: String, Sendable, Equatable { case export, seal, release }

public struct TransferControlRequest: Sendable, Equatable {
    public static let schemaVersion = 1
    public let version: Int
    public let action: TransferAction
    public let commandID: UUID
    public let transferID: UUID
    public let nonce: UUID
    public let requestSHA256: String
    public let manifestSHA256: String?
    public let sourceApp: SetupAppIdentity?

    public init(version: Int = Self.schemaVersion, action: TransferAction, commandID: UUID,
                transferID: UUID, nonce: UUID, requestSHA256: String,
                manifestSHA256: String?, sourceApp: SetupAppIdentity?) throws {
        guard version == Self.schemaVersion,
              SetupValidation.isLowerHex(requestSHA256, count: 64) else { throw TransferFailure.invalidInput }
        switch action {
        case .export:
            guard manifestSHA256 == nil, sourceApp == nil else { throw TransferFailure.invalidInput }
        case .seal:
            guard let manifestSHA256, SetupValidation.isLowerHex(manifestSHA256, count: 64), sourceApp != nil else { throw TransferFailure.invalidInput }
        case .release:
            guard (manifestSHA256 == nil && sourceApp == nil) ||
                    (manifestSHA256.flatMap { SetupValidation.isLowerHex($0, count: 64) } == true && sourceApp != nil) else { throw TransferFailure.invalidInput }
        }
        self.version = version; self.action = action; self.commandID = commandID
        self.transferID = transferID; self.nonce = nonce; self.requestSHA256 = requestSHA256
        self.manifestSHA256 = manifestSHA256; self.sourceApp = sourceApp
    }
}

public struct TransferRestoreIntent: Sendable, Equatable {
    public static let schemaVersion = 1
    public let version: Int
    public let transferID: UUID
    public let dataSetID: UUID
    public let nonce: UUID
    public let rawManifestSHA256: String
    public let sourceDeviceUDID: String
    public let destinationDeviceUDID: String
    public let sourceApp: SetupAppIdentity
    public let targetApp: SetupAppIdentity
    public let setupID: UUID
    public let categories: [TransferCategory]

    public init(version: Int = Self.schemaVersion, transferID: UUID, dataSetID: UUID,
                nonce: UUID, rawManifestSHA256: String, sourceDeviceUDID: String,
                destinationDeviceUDID: String, sourceApp: SetupAppIdentity,
                targetApp: SetupAppIdentity, setupID: UUID,
                categories: [TransferCategory]) throws {
        guard version == Self.schemaVersion,
              SetupValidation.isLowerHex(rawManifestSHA256, count: 64),
              SetupValidation.validUDID(sourceDeviceUDID),
              SetupValidation.validUDID(destinationDeviceUDID),
              sourceDeviceUDID == destinationDeviceUDID,
              categories == TransferCategory.allCases.filter({ categories.contains($0) }),
              Set(categories).count == categories.count else { throw TransferFailure.invalidInput }
        self.version = version; self.transferID = transferID; self.dataSetID = dataSetID
        self.nonce = nonce; self.rawManifestSHA256 = rawManifestSHA256
        self.sourceDeviceUDID = sourceDeviceUDID; self.destinationDeviceUDID = destinationDeviceUDID
        self.sourceApp = sourceApp; self.targetApp = targetApp; self.setupID = setupID
        self.categories = categories
    }
}

public enum TransferControlURLFailure: Error, Equatable, Sendable { case invalidInput }

public struct TransferControlURL: Sendable, Equatable {
    public let action: TransferAction
    public let transferID: UUID
    public let nonce: UUID

    public init(url: URL) throws {
        guard url.scheme == "gofly", url.host == "transfer", url.user == nil,
              url.password == nil, url.port == nil, url.fragment == nil,
              let components = url.pathComponents.dropFirst().first,
              let action = TransferAction(rawValue: components),
              url.pathComponents.count == 2,
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              query.count == 2,
              Set(query.map(\.name)) == ["id", "nonce"],
              query.allSatisfy({ $0.value != nil && $0.value == $0.value!.lowercased() }),
              let idText = query.first(where: { $0.name == "id" })?.value,
              let nonceText = query.first(where: { $0.name == "nonce" })?.value,
              let transferID = UUID(uuidString: idText), let nonce = UUID(uuidString: nonceText),
              transferID.uuidString.lowercased() == idText, nonce.uuidString.lowercased() == nonceText,
              !url.absoluteString.contains("%") else { throw TransferControlURLFailure.invalidInput }
        self.action = action; self.transferID = transferID; self.nonce = nonce
    }
}

public enum TransferExportPhase: String, Sendable, Equatable { case preparing, ready, removalSealed, released, releasedNoSnapshot }
public enum TransferReadbackPhase: String, Sendable, Equatable { case waiting, preparing, ready, removalSealed, released, releasedNoSnapshot, failed }

public final class TransferRuntimeProjection: @unchecked Sendable, Equatable {
    public let transferID: UUID?
    public let favoritesDirectory: URL
    public let importedRoutesDirectory: URL
    public let favoriteRoutesDirectory: URL
    public let sessionDirectory: URL

    static func ordinary(applicationSupport: URL) -> TransferRuntimeProjection {
        TransferRuntimeProjection(transferID: nil,
            favoritesDirectory: applicationSupport.appendingPathComponent("FavoritePlaces", isDirectory: true),
            importedRoutesDirectory: applicationSupport.appendingPathComponent("ImportedRoutes", isDirectory: true),
            favoriteRoutesDirectory: applicationSupport.appendingPathComponent("FavoriteRoutes", isDirectory: true),
            sessionDirectory: applicationSupport.appendingPathComponent("SessionRecovery", isDirectory: true))
    }

    init(transferID: UUID?, favoritesDirectory: URL, importedRoutesDirectory: URL,
         favoriteRoutesDirectory: URL, sessionDirectory: URL) {
        self.transferID = transferID; self.favoritesDirectory = favoritesDirectory
        self.importedRoutesDirectory = importedRoutesDirectory; self.favoriteRoutesDirectory = favoriteRoutesDirectory
        self.sessionDirectory = sessionDirectory
    }

    public static func == (lhs: TransferRuntimeProjection, rhs: TransferRuntimeProjection) -> Bool {
        lhs.transferID == rhs.transferID && lhs.favoritesDirectory.standardizedFileURL == rhs.favoritesDirectory.standardizedFileURL &&
            lhs.importedRoutesDirectory.standardizedFileURL == rhs.importedRoutesDirectory.standardizedFileURL &&
            lhs.favoriteRoutesDirectory.standardizedFileURL == rhs.favoriteRoutesDirectory.standardizedFileURL &&
            lhs.sessionDirectory.standardizedFileURL == rhs.sessionDirectory.standardizedFileURL
    }
}

public struct TransferExportCutline: Sendable, Equatable {
    public let draft: RouteDraft
    public let settings: TransferSettings
    public let projection: TransferRuntimeProjection

    public init(draft: RouteDraft, settings: TransferSettings, projection: TransferRuntimeProjection) {
        self.draft = draft; self.settings = settings; self.projection = projection
    }
}

public final class TransferPreparation: @unchecked Sendable {
    let request: TransferExportRequest
    let requestData: Data
    let transferID: UUID; let dataSetID: UUID; let nonce: UUID; let requestSHA256: String
    let sourceApp: SetupAppIdentity; let cutline: TransferExportCutline; let cutlineSHA256: String
    let packageDirectory: URL
    init(request: TransferExportRequest, requestData: Data, transferID: UUID, dataSetID: UUID, nonce: UUID, requestSHA256: String,
         sourceApp: SetupAppIdentity, cutline: TransferExportCutline, cutlineSHA256: String,
         packageDirectory: URL) {
        self.request = request
        self.requestData = requestData
        self.transferID = transferID; self.dataSetID = dataSetID; self.nonce = nonce
        self.requestSHA256 = requestSHA256; self.sourceApp = sourceApp; self.cutline = cutline
        self.cutlineSHA256 = cutlineSHA256; self.packageDirectory = packageDirectory
    }
}

public final class TransferPreparedExport: @unchecked Sendable {
    let preparation: TransferPreparation
    init(preparation: TransferPreparation) { self.preparation = preparation }
}

public final class TransferExportReceipt: @unchecked Sendable, Equatable {
    public let version: Int
    public let phase: TransferExportPhase
    public let request: TransferExportRequest
    public let requestSHA256: String
    public let sourceApp: SetupAppIdentity
    public let manifestSHA256: String?
    public let cutlineSHA256: String?
    public let receiptSHA256: String

    init(phase: TransferExportPhase, request: TransferExportRequest, requestSHA256: String,
         sourceApp: SetupAppIdentity, manifestSHA256: String?, cutlineSHA256: String?) throws {
        guard SetupValidation.isLowerHex(requestSHA256, count: 64),
              manifestSHA256.map({ SetupValidation.isLowerHex($0, count: 64) }) ?? true,
              cutlineSHA256.map({ SetupValidation.isLowerHex($0, count: 64) }) ?? true else { throw TransferFailure.invalidInput }
        if phase == .preparing { guard manifestSHA256 == nil, cutlineSHA256 != nil else { throw TransferFailure.invalidInput } }
        if phase == .releasedNoSnapshot { guard manifestSHA256 == nil else { throw TransferFailure.invalidInput } }
        if phase != .releasedNoSnapshot && phase != .preparing { guard manifestSHA256 != nil, cutlineSHA256 != nil else { throw TransferFailure.invalidInput } }
        self.version = 1; self.phase = phase; self.request = request; self.requestSHA256 = requestSHA256
        self.sourceApp = sourceApp; self.manifestSHA256 = manifestSHA256; self.cutlineSHA256 = cutlineSHA256
        let object: [String: Any] = ["version": 1, "phase": phase.rawValue,
            "request": try JSONSerialization.jsonObject(with: TransferControlCodec.encodeExportRequest(request)),
            "requestSHA256": requestSHA256, "sourceApp": SetupCodec.appObject(sourceApp),
            "manifestSHA256": manifestSHA256 as Any, "cutlineSHA256": cutlineSHA256 as Any,
            "transferID": request.transferID.uuidString.lowercased()]
        self.receiptSHA256 = try TransferStorageJSON.hash(object, maximum: 1_048_576)
    }

    public static func == (lhs: TransferExportReceipt, rhs: TransferExportReceipt) -> Bool {
        lhs.receiptSHA256 == rhs.receiptSHA256
    }
}

public struct TransferReadback: Sendable, Equatable {
    public let version: Int; public let commandID: UUID; public let action: TransferAction
    public let transferID: UUID; public let nonce: UUID; public let requestSHA256: String
    public let manifestSHA256: String?; public let sourceApp: SetupAppIdentity
    public let pid: Int32; public let phase: TransferReadbackPhase
    public let receiptSHA256: String?; public let errorCode: String?
    init(version: Int, commandID: UUID, action: TransferAction, transferID: UUID, nonce: UUID,
         requestSHA256: String, manifestSHA256: String?, sourceApp: SetupAppIdentity,
         pid: Int32, phase: TransferReadbackPhase, receiptSHA256: String?, errorCode: String?) {
        self.version = version; self.commandID = commandID; self.action = action; self.transferID = transferID
        self.nonce = nonce; self.requestSHA256 = requestSHA256; self.manifestSHA256 = manifestSHA256
        self.sourceApp = sourceApp; self.pid = pid; self.phase = phase; self.receiptSHA256 = receiptSHA256; self.errorCode = errorCode
    }
}

public enum TransferCategoryState: String, Sendable, Equatable { case waiting, validating, committed, failed }
public struct TransferCategoryStatus: Sendable, Equatable {
    public let category: TransferCategory; public let state: TransferCategoryState; public let receiptSHA256: String?
}
public enum TransferRestorePhase: String, Sendable, Equatable { case waiting, validating, committed, failed }

public final class TransferRestoreStatus: @unchecked Sendable, Equatable {
    public let transferID: UUID; public let dataSetID: UUID; public let rawManifestSHA256: String
    public let categories: [TransferCategoryStatus]; public let counts: TransferCounts?
    public let phase: TransferRestorePhase; public let receiptSHA256: String?
    public let projection: TransferRuntimeProjection?
    // Internal root evidence; the public contract intentionally exposes only
    // the opaque receipt digest while storage retains the seed digest for
    // replay/readback validation.
    let sessionSeedSHA256: String?
    // Every authoritative active/history record also keeps the complete
    // immutable intent. This remains internal so callers cannot manufacture
    // a status with a different transaction binding.
    let originalIntent: TransferRestoreIntent?
    init(transferID: UUID, dataSetID: UUID, rawManifestSHA256: String,
         categories: [TransferCategoryStatus], counts: TransferCounts?, phase: TransferRestorePhase,
         receiptSHA256: String?, projection: TransferRuntimeProjection?, sessionSeedSHA256: String? = nil,
         originalIntent: TransferRestoreIntent? = nil) {
        self.transferID = transferID; self.dataSetID = dataSetID; self.rawManifestSHA256 = rawManifestSHA256
        self.categories = categories; self.counts = counts; self.phase = phase
        self.receiptSHA256 = receiptSHA256; self.projection = projection
        self.sessionSeedSHA256 = sessionSeedSHA256
        self.originalIntent = originalIntent
    }
    public static func == (lhs: TransferRestoreStatus, rhs: TransferRestoreStatus) -> Bool {
        lhs.receiptSHA256 == rhs.receiptSHA256 && lhs.phase == rhs.phase && lhs.transferID == rhs.transferID
    }
}

// MARK: - Strict control codecs

public enum TransferControlCodec {
    public static func encodeExportRequest(_ request: TransferExportRequest) throws -> Data {
        try TransferStorageJSON.encode(["version": request.version,
            "transferID": request.transferID.uuidString.lowercased(), "dataSetID": request.dataSetID.uuidString.lowercased(),
            "nonce": request.nonce.uuidString.lowercased(), "sourceDeviceUDID": request.sourceDeviceUDID,
            "destinationDeviceUDID": request.destinationDeviceUDID, "sourceBundleID": request.sourceBundleID,
            "sourceBuild": request.sourceBuild, "targetApp": SetupCodec.appObject(request.targetApp),
            "setupID": request.setupID.uuidString.lowercased(), "categories": request.categories.map(\.rawValue)], maximum: TransferLimits.requestBytes)
    }

    public static func decodeExportRequest(_ data: Data) throws -> TransferExportRequest {
        let value = try TransferStorageJSON.parse(data, maximum: TransferLimits.requestBytes)
        do {
            try value.requireObjectKeys(["version", "transferID", "dataSetID", "nonce", "sourceDeviceUDID", "destinationDeviceUDID", "sourceBundleID", "sourceBuild", "targetApp", "setupID", "categories"])
            let categories = try value.object("categories").array().map { try TransferStorageJSON.string($0) }.compactMap(TransferCategory.init(rawValue:))
            guard categories.count == (try value.object("categories").array().count) else { throw TransferFailure.invalidInput }
            return try TransferExportRequest(version: TransferStorageJSON.int(value.object("version")),
                transferID: TransferStorageJSON.uuid(value.object("transferID")), dataSetID: TransferStorageJSON.uuid(value.object("dataSetID")),
                nonce: TransferStorageJSON.uuid(value.object("nonce")), sourceDeviceUDID: TransferStorageJSON.string(value.object("sourceDeviceUDID")),
                destinationDeviceUDID: TransferStorageJSON.string(value.object("destinationDeviceUDID")), sourceBundleID: TransferStorageJSON.string(value.object("sourceBundleID")),
                sourceBuild: TransferStorageJSON.string(value.object("sourceBuild")), targetApp: try SetupAppIdentity.decode(value.object("targetApp")),
                setupID: TransferStorageJSON.uuid(value.object("setupID")), categories: categories)
        } catch let failure as TransferFailure { throw failure }
        catch { throw TransferFailure.invalidInput }
    }

    public static func encodeControlRequest(_ request: TransferControlRequest) throws -> Data {
        try TransferStorageJSON.encode(["version": request.version, "action": request.action.rawValue,
            "commandID": request.commandID.uuidString.lowercased(), "transferID": request.transferID.uuidString.lowercased(),
            "nonce": request.nonce.uuidString.lowercased(), "requestSHA256": request.requestSHA256,
            "manifestSHA256": request.manifestSHA256 as Any,
            "sourceApp": request.sourceApp.map(SetupCodec.appObject) as Any], maximum: TransferLimits.requestBytes)
    }

    public static func decodeControlRequest(_ data: Data) throws -> TransferControlRequest {
        let value = try TransferStorageJSON.parse(data, maximum: TransferLimits.requestBytes)
        do {
            try value.requireObjectKeys(["version", "action", "commandID", "transferID", "nonce", "requestSHA256", "manifestSHA256", "sourceApp"])
            let manifestValue = try value.object("manifestSHA256")
            let manifest: String? = manifestValue.isNull ? nil : try TransferStorageJSON.string(manifestValue)
            let sourceValue = try value.object("sourceApp")
            let source: SetupAppIdentity? = sourceValue.isNull ? nil : try SetupAppIdentity.decode(sourceValue)
            guard let action = TransferAction(rawValue: try TransferStorageJSON.string(value.object("action"))) else { throw TransferFailure.invalidInput }
            return try TransferControlRequest(version: TransferStorageJSON.int(value.object("version")), action: action,
                commandID: TransferStorageJSON.uuid(value.object("commandID")), transferID: TransferStorageJSON.uuid(value.object("transferID")),
                nonce: TransferStorageJSON.uuid(value.object("nonce")), requestSHA256: TransferStorageJSON.string(value.object("requestSHA256")),
                manifestSHA256: manifest, sourceApp: source)
        } catch let failure as TransferFailure { throw failure }
        catch { throw TransferFailure.invalidInput }
    }

    public static func encodeRestoreIntent(_ intent: TransferRestoreIntent) throws -> Data {
        try TransferStorageJSON.encode(["version": intent.version, "transferID": intent.transferID.uuidString.lowercased(),
            "dataSetID": intent.dataSetID.uuidString.lowercased(), "nonce": intent.nonce.uuidString.lowercased(),
            "rawManifestSHA256": intent.rawManifestSHA256, "sourceDeviceUDID": intent.sourceDeviceUDID,
            "destinationDeviceUDID": intent.destinationDeviceUDID, "sourceApp": SetupCodec.appObject(intent.sourceApp),
            "targetApp": SetupCodec.appObject(intent.targetApp), "setupID": intent.setupID.uuidString.lowercased(),
            "categories": intent.categories.map(\.rawValue)], maximum: TransferLimits.requestBytes)
    }

    public static func decodeRestoreIntent(_ data: Data) throws -> TransferRestoreIntent {
        let value = try TransferStorageJSON.parse(data, maximum: TransferLimits.requestBytes)
        do {
            try value.requireObjectKeys(["version", "transferID", "dataSetID", "nonce", "rawManifestSHA256", "sourceDeviceUDID", "destinationDeviceUDID", "sourceApp", "targetApp", "setupID", "categories"])
            let rawCategories = try value.object("categories").array().map { try TransferStorageJSON.string($0) }
            let categories = rawCategories.compactMap(TransferCategory.init(rawValue:))
            guard categories.count == rawCategories.count else { throw TransferFailure.invalidInput }
            return try TransferRestoreIntent(version: TransferStorageJSON.int(value.object("version")), transferID: TransferStorageJSON.uuid(value.object("transferID")),
                dataSetID: TransferStorageJSON.uuid(value.object("dataSetID")), nonce: TransferStorageJSON.uuid(value.object("nonce")),
                rawManifestSHA256: TransferStorageJSON.string(value.object("rawManifestSHA256")), sourceDeviceUDID: TransferStorageJSON.string(value.object("sourceDeviceUDID")),
                destinationDeviceUDID: TransferStorageJSON.string(value.object("destinationDeviceUDID")), sourceApp: try SetupAppIdentity.decode(value.object("sourceApp")),
                targetApp: try SetupAppIdentity.decode(value.object("targetApp")), setupID: TransferStorageJSON.uuid(value.object("setupID")), categories: categories)
        } catch let failure as TransferFailure { throw failure }
        catch { throw TransferFailure.invalidInput }
    }

    public static func encodeReadback(_ readback: TransferReadback) throws -> Data {
        try TransferStorageJSON.readbackObject(readback)
    }

    public static func decodeReadback(_ data: Data) throws -> TransferReadback {
        let value = try TransferStorageJSON.parse(data, maximum: TransferLimits.requestBytes)
        do {
            try value.requireObjectKeys(["version", "commandID", "action", "transferID", "nonce", "requestSHA256", "manifestSHA256", "sourceApp", "pid", "phase", "receiptSHA256", "errorCode"])
            let manifestValue = try value.object("manifestSHA256"); let receiptValue = try value.object("receiptSHA256"); let errorValue = try value.object("errorCode")
            guard let action = TransferAction(rawValue: try TransferStorageJSON.string(value.object("action"))),
                  let phase = TransferReadbackPhase(rawValue: try TransferStorageJSON.string(value.object("phase"))) else { throw TransferFailure.invalidInput }
            let source = try SetupAppIdentity.decode(value.object("sourceApp"))
            let pidInt = try TransferStorageJSON.int(value.object("pid")); guard pidInt > 0 && pidInt <= Int(Int32.max) else { throw TransferFailure.invalidInput }
            let requestSHA = try TransferStorageJSON.string(value.object("requestSHA256"))
            guard SetupValidation.isLowerHex(requestSHA, count: 64) else { throw TransferFailure.invalidInput }
            let manifest = manifestValue.isNull ? nil : try TransferStorageJSON.string(manifestValue)
            guard manifest.map({ SetupValidation.isLowerHex($0, count: 64) }) ?? true else { throw TransferFailure.invalidInput }
            let receipt = receiptValue.isNull ? nil : try TransferStorageJSON.string(receiptValue)
            guard receipt.map({ SetupValidation.isLowerHex($0, count: 64) }) ?? true else { throw TransferFailure.invalidInput }
            let errorCode = errorValue.isNull ? nil : try TransferStorageJSON.string(errorValue)
            guard errorCode.map(TransferStorageErrorCode.isValid) ?? true else { throw TransferFailure.invalidInput }
            if phase == .waiting || phase == .failed {
                guard receipt == nil, manifest == nil else { throw TransferFailure.invalidInput }
            }
            return TransferReadback(version: try TransferStorageJSON.int(value.object("version")), commandID: try TransferStorageJSON.uuid(value.object("commandID")), action: action,
                transferID: try TransferStorageJSON.uuid(value.object("transferID")), nonce: try TransferStorageJSON.uuid(value.object("nonce")),
                requestSHA256: requestSHA, manifestSHA256: manifest,
                sourceApp: source, pid: Int32(pidInt), phase: phase, receiptSHA256: receipt,
                errorCode: errorCode)
        } catch let failure as TransferFailure { throw failure }
        catch { throw TransferFailure.invalidInput }
    }
}

// MARK: - Preferences

public final class TransferPreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey: String
    public init(defaults: UserDefaults, storageKey: String = "gofly.preferences.v1") {
        self.defaults = defaults; self.storageKey = storageKey
    }
    public func activate(settings: TransferSettings, transferID: UUID) throws {
        var dictionary = defaults.dictionary(forKey: storageKey) ?? [:]
        dictionary["language"] = settings.language
        dictionary["appearance"] = settings.appearance
        dictionary["transferRestoreID"] = transferID.uuidString.lowercased()
        defaults.set(dictionary, forKey: storageKey)
        let applied = try currentValues()
        guard applied.language == settings.language, applied.appearance == settings.appearance,
              applied.marker == transferID else { throw TransferFailure.storageUnavailable }
    }
    public func currentValues() throws -> (language: String, appearance: String, marker: UUID?) {
        guard let dictionary = defaults.dictionary(forKey: storageKey),
              let language = dictionary["language"] as? String,
              let appearance = dictionary["appearance"] as? String else {
            return ("system", "system", nil)
        }
        let marker = (dictionary["transferRestoreID"] as? String).flatMap(UUID.init(uuidString:))
        return (language, appearance, marker)
    }
}

// MARK: - Export storage

public final class TransferExportStore: @unchecked Sendable {
    private let applicationSupport: URL
    private let transferRoot: URL
    private let checkpoint: (@Sendable (SetupWriteCheckpoint) throws -> Void)?
    private let lock = NSLock()

    public init(applicationSupport: URL, checkpoint: (@Sendable (SetupWriteCheckpoint) throws -> Void)? = nil) {
        // Application Support is the one trusted OS-provided base. Resolve
        // its host volume aliases once; all descendants remain fixed derived
        // names and are opened with no-follow descriptors.
        let trustedBase = TransferStorageDisk.canonicalTrustedBase(applicationSupport)
        self.applicationSupport = trustedBase
        self.transferRoot = trustedBase.appendingPathComponent("GoFlyTransfer", isDirectory: true)
        self.checkpoint = checkpoint
    }

    public func readRequest() throws -> TransferExportInput? {
        try withLock { guard let data = try TransferStorageDisk.read(transferRoot.appendingPathComponent("export-request.json"), maximum: TransferLimits.requestBytes) else { return nil }; return try TransferExportInput(data: data) }
    }
    public func readControl() throws -> TransferControlRequest? {
        try withLock { guard let data = try TransferStorageDisk.read(transferRoot.appendingPathComponent("control-request.json"), maximum: TransferLimits.requestBytes) else { return nil }; return try TransferControlCodec.decodeControlRequest(data) }
    }
    public func readExport() throws -> TransferExportReceipt? {
        try withLock { try readExportUnlocked() }
    }
    public func hasLockedExport() throws -> Bool {
        try withLock { guard let receipt = try readExportUnlocked() else { return false }; return [.preparing, .ready, .removalSealed].contains(receipt.phase) }
    }

    public func prepareIncomingFiles() throws {
        try withLock {
            guard let root = try TransferStorageDisk.openExistingDirectory(transferRoot, requirePrivate: false) else { return }
            try TransferStorageDisk.sealTransferRoot(root, at: transferRoot)
            for name in ["export-request.json", "control-request.json", "restore-intent.json", "incoming.json"] {
                try TransferStorageDisk.sealIngressFile(transferRoot.appendingPathComponent(name), maximum: TransferLimits.requestBytes)
            }
        }
    }

    public func beginPreparation(input: TransferExportInput, currentApp: SetupAppIdentity,
                                 cutline: TransferExportCutline) throws -> TransferPreparation {
        try withLock {
            guard input.request.sourceBundleID == currentApp.bundleID,
                  input.request.sourceBuild == currentApp.build,
                  input.request.targetApp == currentApp else { throw TransferFailure.identityMismatch }
            if let existing = try readExportUnlocked() {
                if existing.request.transferID == input.request.transferID {
                    switch existing.phase {
                    case .preparing:
                        guard existing.requestSHA256 == input.rawSHA256, existing.sourceApp == currentApp else { throw TransferFailure.identityMismatch }
                        return try loadCutline(input: input, sourceApp: currentApp)
                    case .ready, .removalSealed, .released, .releasedNoSnapshot: throw TransferFailure.busy
                    }
                } else if ![.released, .releasedNoSnapshot].contains(existing.phase) {
                    throw TransferFailure.busy
                }
            }
            if let root = try readExportRootUnlocked(), root.history.contains(where: { $0.request.transferID == input.request.transferID }) {
                // A transaction UUID is a replay key. It may not be reused
                // after the original receipt moved to history.
                throw TransferFailure.busy
            }
            if try TransferStorageDisk.orphanExists(transferRoot, dataSetID: input.request.dataSetID) { throw TransferFailure.busy }
            let cutlineData = try TransferStorageJSON.encode(["version": 1,
                "draft": try JSONSerialization.jsonObject(with: TransferCodec.encodeDraft(cutline.draft)),
                "settings": try JSONSerialization.jsonObject(with: TransferCodec.encodeSettings(cutline.settings)),
                "projectionID": cutline.projection.transferID?.uuidString.lowercased() as Any], maximum: 5 * 1_024 * 1_024)
            let cutlineSHA = SetupValidation.sha256(cutlineData)
            let generation = transferRoot.appendingPathComponent("exports", isDirectory: true)
                .appendingPathComponent(input.request.dataSetID.uuidString.lowercased(), isDirectory: true)
            let package = generation.appendingPathComponent("package", isDirectory: true)
            try TransferStorageDisk.ensureDirectory(package)
            try TransferStorageDisk.atomicWrite(input.rawData, to: generation.appendingPathComponent("request.json"), checkpoint: checkpoint)
            try TransferStorageDisk.atomicWrite(cutlineData, to: generation.appendingPathComponent("cutline.json"), checkpoint: checkpoint)
            let receipt = try TransferExportReceipt(phase: .preparing, request: input.request,
                requestSHA256: input.rawSHA256, sourceApp: currentApp, manifestSHA256: nil, cutlineSHA256: cutlineSHA)
            try writeActive(receipt)
            return TransferPreparation(request: input.request, requestData: input.rawData, transferID: input.request.transferID, dataSetID: input.request.dataSetID,
                nonce: input.request.nonce, requestSHA256: input.rawSHA256, sourceApp: currentApp,
                cutline: cutline, cutlineSHA256: cutlineSHA, packageDirectory: package)
        }
    }

    public func reopenPreparation(input: TransferExportInput, currentApp: SetupAppIdentity) throws -> TransferPreparation {
        try withLock {
            guard let receipt = try readExportUnlocked(), receipt.phase == .preparing,
                  receipt.request == input.request, receipt.requestSHA256 == input.rawSHA256,
                  receipt.sourceApp == currentApp else { throw TransferFailure.busy }
            return try loadCutline(input: input, sourceApp: currentApp)
        }
    }

    public func stage(preparation: TransferPreparation, favorites: Data?, importedRoutes: TransferArchiveSnapshot?,
                      favoriteRoutes: TransferArchiveSnapshot?) throws -> TransferPreparedExport {
        try withLock {
            guard let receipt = try readExportUnlocked(), receipt.phase == .preparing,
                  receipt.request.transferID == preparation.transferID,
                  receipt.request.dataSetID == preparation.dataSetID,
                  receipt.cutlineSHA256 == preparation.cutlineSHA256 else { throw TransferFailure.busy }
            let persisted = try reloadPreparation(preparation, current: receipt)
            let categories = receipt.request.categories
            var files: [String: Data] = [:]
            if categories.contains(.favorites) {
                guard let favorites else { throw TransferFailure.artifactMismatch }
                _ = try TransferArchiveCodec.favoritePlaces(favorites)
                files["favorites/archive.json"] = favorites
            }
            if categories.contains(.routes) {
                guard let importedRoutes, let favoriteRoutes else { throw TransferFailure.artifactMismatch }
                _ = try TransferArchiveCodec.importedRoutes(importedRoutes)
                _ = try TransferArchiveCodec.favoriteRoutes(favoriteRoutes)
                files["routes/imported/manifest.json"] = importedRoutes.manifest
                files["routes/favorites/manifest.json"] = favoriteRoutes.manifest
                files["routes/draft.json"] = try TransferCodec.encodeDraft(persisted.cutline.draft)
                for (name, data) in importedRoutes.payloads { files["routes/imported/\(name)"] = data }
                for (name, data) in favoriteRoutes.payloads { files["routes/favorites/\(name)"] = data }
            }
            if categories.contains(.settings) { files["settings/preferences.json"] = try TransferCodec.encodeSettings(persisted.cutline.settings) }
            let package = persisted.packageDirectory
            for (path, data) in files {
                let target = package.appendingPathComponent(path)
                try TransferStorageDisk.ensureDirectory(target.deletingLastPathComponent())
                try TransferStorageDisk.writeStable(data, to: target)
            }
            let artifacts = try files.keys.sorted().map { path in
                try TransferArtifact(id: TransferStorageCrypto.uuidV5(namespace: preparation.dataSetID, name: path), path: path,
                    byteCount: Int64(files[path]!.count), sha256: SetupValidation.sha256(files[path]!))
            }
            let manifest = try TransferManifest(transferID: receipt.request.transferID, dataSetID: receipt.request.dataSetID,
                nonce: receipt.request.nonce, sourceDeviceUDID: receipt.request.sourceDeviceUDID,
                destinationDeviceUDID: receipt.request.destinationDeviceUDID, sourceApp: receipt.sourceApp,
                targetApp: receipt.request.targetApp, setupID: receipt.request.setupID,
                categories: receipt.request.categories, artifacts: artifacts)
            let manifestData = try TransferCodec.encodeManifest(manifest)
            try TransferStorageDisk.writeStable(manifestData, to: package.appendingPathComponent("manifest.json"))
            let validated = try TransferPackageValidator.validate(directory: package)
            try validatePackageBinding(validated.input.manifest, request: receipt.request, sourceApp: receipt.sourceApp)
            return TransferPreparedExport(preparation: persisted)
        }
    }

    public func commitReady(_ prepared: TransferPreparedExport) throws -> TransferExportReceipt {
        try withLock {
            guard let current = try readExportUnlocked(), current.phase == .preparing,
                  current.request == prepared.preparation.request,
                  current.requestSHA256 == prepared.preparation.requestSHA256,
                  current.sourceApp == prepared.preparation.sourceApp,
                  current.cutlineSHA256 == prepared.preparation.cutlineSHA256 else { throw TransferFailure.artifactMismatch }
            let persisted = try reloadPreparation(prepared.preparation, current: current)
            let package = try TransferPackageValidator.validate(directory: persisted.packageDirectory)
            try validatePackageBinding(package.input.manifest, request: current.request, sourceApp: current.sourceApp)
            let receipt = try TransferExportReceipt(phase: .ready, request: current.request, requestSHA256: current.requestSHA256,
                sourceApp: current.sourceApp, manifestSHA256: package.input.rawManifestSHA256, cutlineSHA256: current.cutlineSHA256)
            try writeActive(receipt)
            return receipt
        }
    }

    /// Re-open every immutable input that was committed before staging. The
    /// in-memory preparation is only a handle; it cannot authorize copying if
    /// the original request, cutline bytes, projection or source identity no
    /// longer agree with the authoritative root.
    private func reloadPreparation(_ preparation: TransferPreparation,
                                   current: TransferExportReceipt) throws -> TransferPreparation {
        let generation = transferRoot.appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent(preparation.dataSetID.uuidString.lowercased(), isDirectory: true)
        guard let generationRequestData = try TransferStorageDisk.read(generation.appendingPathComponent("request.json"), maximum: TransferLimits.requestBytes),
              let ingressData = try TransferStorageDisk.read(transferRoot.appendingPathComponent("export-request.json"), maximum: TransferLimits.requestBytes) else {
            throw TransferFailure.artifactMismatch
        }
        let persistedInput = try TransferExportInput(data: generationRequestData)
        _ = try TransferExportInput(data: ingressData)
        guard generationRequestData == preparation.requestData,
              ingressData == generationRequestData,
              persistedInput.request == preparation.request,
              persistedInput.request == current.request,
              persistedInput.rawSHA256 == preparation.requestSHA256,
              persistedInput.rawSHA256 == current.requestSHA256,
              persistedInput.request.sourceBundleID == current.sourceApp.bundleID,
              persistedInput.request.sourceBuild == current.sourceApp.build else {
            throw TransferFailure.artifactMismatch
        }
        let persisted = try loadCutline(input: persistedInput, sourceApp: current.sourceApp)
        guard persisted.cutlineSHA256 == current.cutlineSHA256,
              persisted.cutlineSHA256 == preparation.cutlineSHA256,
              persisted.cutline == preparation.cutline,
              persisted.cutline.projection == preparation.cutline.projection,
              persisted.sourceApp == preparation.sourceApp,
              persisted.sourceApp == current.sourceApp else { throw TransferFailure.artifactMismatch }
        return persisted
    }

    private func validatePackageBinding(_ manifest: TransferManifest,
                                        request: TransferExportRequest,
                                        sourceApp: SetupAppIdentity) throws {
        guard manifest.transferID == request.transferID,
              manifest.dataSetID == request.dataSetID,
              manifest.nonce == request.nonce,
              manifest.sourceDeviceUDID == request.sourceDeviceUDID,
              manifest.destinationDeviceUDID == request.destinationDeviceUDID,
              manifest.sourceApp == sourceApp,
              manifest.targetApp == request.targetApp,
              manifest.setupID == request.setupID,
              manifest.categories == request.categories else { throw TransferFailure.artifactMismatch }
    }

    public func seal(_ control: TransferControlRequest, currentApp: SetupAppIdentity) throws -> TransferExportReceipt {
        try withLock {
            guard let current = try readExportUnlocked(), current.request.transferID == control.transferID,
                  current.request.nonce == control.nonce,
                  current.phase == .ready || current.phase == .removalSealed,
                  current.sourceApp == currentApp, current.requestSHA256 == control.requestSHA256,
                  current.manifestSHA256 == control.manifestSHA256, current.sourceApp == control.sourceApp else { throw TransferFailure.identityMismatch }
            if current.phase == .removalSealed { return current }
            let sealed = try TransferExportReceipt(phase: .removalSealed, request: current.request, requestSHA256: current.requestSHA256,
                sourceApp: current.sourceApp, manifestSHA256: current.manifestSHA256, cutlineSHA256: current.cutlineSHA256)
            try writeActive(sealed); return sealed
        }
    }

    public func release(_ control: TransferControlRequest, input: TransferExportInput,
                        currentApp: SetupAppIdentity) throws -> TransferExportReceipt {
        try withLock {
            guard control.action == .release, control.transferID == input.request.transferID,
                  control.nonce == input.request.nonce, control.requestSHA256 == input.rawSHA256 else { throw TransferFailure.identityMismatch }
            guard let current = try readExportUnlocked() else {
                let tombstone = try TransferExportReceipt(phase: .releasedNoSnapshot, request: input.request,
                    requestSHA256: input.rawSHA256, sourceApp: currentApp, manifestSHA256: nil, cutlineSHA256: nil)
                try writeActive(tombstone); return tombstone
            }
            guard current.request == input.request else {
                if let historical = try readExportRootUnlocked()?.history.first(where: {
                    $0.request == input.request && $0.requestSHA256 == input.rawSHA256
                }) {
                    return historical
                }
                throw TransferFailure.identityMismatch
            }
            guard current.sourceApp == currentApp else { throw TransferFailure.identityMismatch }
            if current.phase == .released || current.phase == .releasedNoSnapshot { return current }
            if current.phase == .removalSealed { throw TransferFailure.busy }
            if current.phase == .ready {
                guard let manifestSHA = control.manifestSHA256, let source = control.sourceApp,
                      manifestSHA == current.manifestSHA256, source == current.sourceApp else { throw TransferFailure.exportConflict }
            } else {
                guard control.manifestSHA256 == nil, control.sourceApp == nil else { throw TransferFailure.invalidInput }
            }
            let cutline = try loadCutline(input: input, sourceApp: currentApp)
            try TransferStorageDisk.writeSessionSeed(cutline: cutline.cutline, applicationSupport: applicationSupport)
            let phase: TransferExportPhase = current.phase == .ready ? .released : .releasedNoSnapshot
            let released = try TransferExportReceipt(phase: phase, request: current.request, requestSHA256: current.requestSHA256,
                sourceApp: current.sourceApp, manifestSHA256: current.manifestSHA256, cutlineSHA256: current.cutlineSHA256)
            try writeActive(released); return released
        }
    }

    public func writeReadback(control: TransferControlRequest, currentApp: SetupAppIdentity,
                              pid: Int32, failure: TransferFailure? = nil) throws -> TransferReadback {
        try withLock {
            guard pid > 0 else { throw TransferFailure.invalidInput }
            let root = try readExportRootUnlocked()
            let receipt = root?.current?.request.transferID == control.transferID
                ? root?.current
                : root?.history.first(where: { $0.request.transferID == control.transferID })
            let input = try TransferStorageDisk.read(transferRoot.appendingPathComponent("export-request.json"), maximum: TransferLimits.requestBytes).map(TransferExportInput.init(data:))
            let requestSHA = receipt?.requestSHA256 ?? input?.rawSHA256
            guard let requestSHA, requestSHA == control.requestSHA256 else { throw TransferFailure.identityMismatch }
            if let receipt {
                guard receipt.request.nonce == control.nonce,
                      let original = try TransferStorageDisk.read(transferRoot.appendingPathComponent("exports/\(receipt.request.dataSetID.uuidString.lowercased())/request.json"), maximum: TransferLimits.requestBytes),
                      SetupValidation.sha256(original) == receipt.requestSHA256 else { throw TransferFailure.artifactMismatch }
            } else {
                guard input?.request.nonce == control.nonce else { throw TransferFailure.identityMismatch }
            }
            let phase: TransferReadbackPhase
            if let receipt {
                phase = TransferReadbackPhase(rawValue: receipt.phase.rawValue) ?? .failed
            } else { phase = .waiting }
            let readback = TransferReadback(version: 1, commandID: control.commandID, action: control.action,
                transferID: control.transferID, nonce: control.nonce, requestSHA256: requestSHA,
                manifestSHA256: receipt?.manifestSHA256, sourceApp: currentApp,
                pid: pid, phase: phase, receiptSHA256: receipt?.receiptSHA256,
                errorCode: failure.map(TransferStorageErrorCode.code))
            let object = try TransferStorageJSON.readbackObject(readback)
            try TransferStorageDisk.atomicWrite(object, to: transferRoot.appendingPathComponent("control-response.json"), checkpoint: checkpoint)
            return readback
        }
    }

    public func writePendingReadback(control: TransferControlRequest, input: TransferExportInput,
                                     currentApp: SetupAppIdentity, pid: Int32,
                                     phase: TransferReadbackPhase, errorCode: String?) throws -> TransferReadback {
        guard phase == .waiting || phase == .failed else { throw TransferFailure.invalidInput }
        guard control.transferID == input.request.transferID, control.nonce == input.request.nonce,
              control.requestSHA256 == input.rawSHA256 else { throw TransferFailure.identityMismatch }
        let safeError: String? = errorCode.flatMap { value in
            guard !value.isEmpty, value.utf8.count <= 64,
                  value.unicodeScalars.allSatisfy({ scalar in
                      scalar == "-" || scalar == "_" ||
                      (scalar.value >= 48 && scalar.value <= 57) ||
                      (scalar.value >= 65 && scalar.value <= 90) ||
                      (scalar.value >= 97 && scalar.value <= 122)
                  }) else { return nil }
            return value
        }
        return try withLock {
            let readback = TransferReadback(version: 1, commandID: control.commandID, action: control.action,
                transferID: input.request.transferID, nonce: input.request.nonce, requestSHA256: input.rawSHA256,
                manifestSHA256: nil, sourceApp: currentApp, pid: pid, phase: phase,
                receiptSHA256: nil, errorCode: safeError)
            try TransferStorageDisk.atomicWrite(TransferStorageJSON.readbackObject(readback), to: transferRoot.appendingPathComponent("control-response.json"), checkpoint: checkpoint)
            return readback
        }
    }

    private func loadCutline(input: TransferExportInput, sourceApp: SetupAppIdentity) throws -> TransferPreparation {
        let generation = transferRoot.appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent(input.request.dataSetID.uuidString.lowercased(), isDirectory: true)
        guard let requestData = try TransferStorageDisk.read(generation.appendingPathComponent("request.json"), maximum: TransferLimits.requestBytes),
              requestData == input.rawData else { throw TransferFailure.artifactMismatch }
        guard let raw = try TransferStorageDisk.read(generation.appendingPathComponent("cutline.json"), maximum: 5 * 1_024 * 1_024) else { throw TransferFailure.artifactMismatch }
        let value = try TransferStorageJSON.parse(raw, maximum: 5 * 1_024 * 1_024)
        try value.requireObjectKeys(["version", "draft", "settings", "projectionID"])
        guard try TransferStorageJSON.int(value.object("version")) == 1 else { throw TransferFailure.unsupportedVersion }
        let draftData = try JSONSerialization.data(withJSONObject: try TransferStorageJSON.foundation(value.object("draft")), options: [.sortedKeys, .withoutEscapingSlashes])
        let settingsData = try JSONSerialization.data(withJSONObject: try TransferStorageJSON.foundation(value.object("settings")), options: [.sortedKeys, .withoutEscapingSlashes])
        let draft = try TransferCodec.decodeDraft(draftData); let settings = try TransferCodec.decodeSettings(settingsData)
        let projectionValue = try value.object("projectionID")
        let projectionID = projectionValue.isNull ? nil : try TransferStorageJSON.uuid(projectionValue)
        let projectionBase = projectionID.map { applicationSupport.appendingPathComponent("GoFlyTransfer/active/\($0.uuidString.lowercased())", isDirectory: true) }
        let projection = TransferRuntimeProjection(transferID: projectionID,
            favoritesDirectory: projectionBase?.appendingPathComponent("favorites", isDirectory: true) ?? applicationSupport.appendingPathComponent("FavoritePlaces", isDirectory: true),
            importedRoutesDirectory: projectionBase?.appendingPathComponent("routes/imported", isDirectory: true) ?? applicationSupport.appendingPathComponent("ImportedRoutes", isDirectory: true),
            favoriteRoutesDirectory: projectionBase?.appendingPathComponent("routes/favorites", isDirectory: true) ?? applicationSupport.appendingPathComponent("FavoriteRoutes", isDirectory: true),
            sessionDirectory: projectionBase?.appendingPathComponent("session", isDirectory: true) ?? applicationSupport.appendingPathComponent("SessionRecovery", isDirectory: true))
        let cutlineSHA = SetupValidation.sha256(raw)
        if let current = try readExportUnlocked(), current.request.dataSetID == input.request.dataSetID {
            guard current.cutlineSHA256 == cutlineSHA else { throw TransferFailure.artifactMismatch }
        }
        return TransferPreparation(request: input.request, requestData: input.rawData, transferID: input.request.transferID, dataSetID: input.request.dataSetID,
            nonce: input.request.nonce, requestSHA256: input.rawSHA256, sourceApp: sourceApp,
            cutline: TransferExportCutline(draft: draft, settings: settings, projection: projection),
            cutlineSHA256: cutlineSHA, packageDirectory: generation.appendingPathComponent("package", isDirectory: true))
    }

    private func writeActive(_ receipt: TransferExportReceipt) throws {
        try TransferStorageDisk.ensureDirectory(transferRoot)
        let existing = try TransferStorageDisk.read(transferRoot.appendingPathComponent("active-export.json"), maximum: 1_048_576)
        let prior = try existing.map(TransferStorageJSON.decodeActiveExportRoot)
        var history = prior?.history ?? []
        guard !history.contains(where: { $0.request.transferID == receipt.request.transferID }) else {
            throw TransferFailure.busy
        }
        if let old = prior?.current, old.request.transferID != receipt.request.transferID,
           [.released, .releasedNoSnapshot].contains(old.phase), receipt.phase == .preparing {
            guard history.count < TransferLimits.historyCount else { throw TransferFailure.receiptCapacity }
            history.append(old)
        }
        let object = try TransferStorageJSON.activeExportRootObject(current: receipt, history: history)
        try TransferStorageDisk.atomicWrite(object, to: transferRoot.appendingPathComponent("active-export.json"), checkpoint: checkpoint)
    }
    private func readExportRootUnlocked() throws -> (current: TransferExportReceipt?, history: [TransferExportReceipt])? {
        guard let data = try TransferStorageDisk.read(transferRoot.appendingPathComponent("active-export.json"), maximum: 1_048_576) else { return nil }
        return try TransferStorageJSON.decodeActiveExportRoot(data)
    }
    private func readExportUnlocked() throws -> TransferExportReceipt? {
        return try readExportRootUnlocked()?.current
    }
    private func withLock<T>(_ body: () throws -> T) throws -> T { lock.lock(); defer { lock.unlock() }; return try body() }
}

// MARK: - Restore storage

public final class TransferRestoreStore: @unchecked Sendable {
    private let applicationSupport: URL
    private let transferRoot: URL
    private let checkpoint: (@Sendable (SetupWriteCheckpoint) throws -> Void)?
    private let lock = NSLock()
    public init(applicationSupport: URL, checkpoint: (@Sendable (SetupWriteCheckpoint) throws -> Void)? = nil) {
        let trustedBase = TransferStorageDisk.canonicalTrustedBase(applicationSupport)
        self.applicationSupport = trustedBase
        self.transferRoot = trustedBase.appendingPathComponent("GoFlyTransfer", isDirectory: true)
        self.checkpoint = checkpoint
    }
    public func readIntent() throws -> TransferRestoreIntent? {
        try withLock { guard let data = try TransferStorageDisk.read(transferRoot.appendingPathComponent("restore-intent.json"), maximum: TransferLimits.requestBytes) else { return nil }; return try TransferControlCodec.decodeRestoreIntent(data) }
    }
    public func prepareIncomingFiles() throws {
        try withLock {
            if let root = try TransferStorageDisk.openExistingDirectory(transferRoot, requirePrivate: false) {
                try TransferStorageDisk.sealTransferRoot(root, at: transferRoot)
            }
            try TransferStorageDisk.sealIngressFile(transferRoot.appendingPathComponent("restore-intent.json"), maximum: TransferLimits.requestBytes)
            guard let intent = try readIntentUnlocked() else { return }
            let package = incomingPackage(intent)
            // The fixed ingress may arrive before the package.  Seal and
            // inspect it when present; a missing generation is an honest
            // waiting state and must not be fabricated into a failure root.
            guard TransferStorageDisk.pathExists(package) else { return }
            try TransferStorageDisk.sealIncomingTree(package)
            _ = try TransferPackageValidator.validate(directory: package)
        }
    }
    public func currentProjection() throws -> TransferRuntimeProjection {
        try withLock {
            guard let status = try statusUnlocked() else {
                // No formal intent retains the ordinary Core namespaces.
                // Once an intent exists, an incomplete projection is locked.
                guard try readIntentUnlocked() == nil else { throw TransferFailure.unavailable }
                return TransferRuntimeProjection.ordinary(applicationSupport: applicationSupport)
            }
            guard status.phase == .committed, let projection = status.projection else { throw TransferFailure.unavailable }
            try validateProjection(projection)
            return projection
        }
    }
    public func status() throws -> TransferRestoreStatus? { try withLock { try statusUnlocked() } }

    public func restore(currentApp: SetupAppIdentity, setupStore: SetupActivationStore,
                        preferences: TransferPreferencesStore) throws -> TransferRestoreStatus {
        try withLock {
            guard let intent = try readIntentUnlocked() else { throw TransferFailure.unavailable }
            guard intent.targetApp == currentApp else { throw TransferFailure.identityMismatch }
            guard let activation = try setupStore.activation(), activation.activeSetupID == intent.setupID,
                  let receipt = activation.receipts.first(where: { $0.setupID == intent.setupID }), receipt.app == currentApp else { throw TransferFailure.identityMismatch }
            _ = try setupStore.activeSupportDirectory(method: receipt.method)
            if let historical = try historicalStatus(for: intent) {
                guard let rootData = try TransferStorageDisk.read(transferRoot.appendingPathComponent("restore-root.json"), maximum: 1_048_576),
                      let root = try? TransferStorageJSON.decodeRestoreRoot(rootData, applicationSupport: applicationSupport),
                      let currentProjection = root.current?.projection else { throw TransferFailure.busy }
                try validateProjection(currentProjection)
                try rehydratePreferences(for: currentProjection,
                                         transferID: currentProjection.transferID ?? intent.transferID,
                                         preferences: preferences)
                return historical
            }
            if let existing = try statusUnlocked() {
                if existing.transferID == intent.transferID, existing.rawManifestSHA256 == intent.rawManifestSHA256 {
                    guard existing.originalIntent == intent else { throw TransferFailure.identityMismatch }
                    if existing.phase == .committed, let projection = existing.projection {
                        try validateProjection(projection)
                        try rehydratePreferences(for: projection, transferID: projection.transferID ?? intent.transferID,
                                                 preferences: preferences)
                        return TransferRestoreStatus(transferID: existing.transferID, dataSetID: existing.dataSetID,
                            rawManifestSHA256: existing.rawManifestSHA256, categories: existing.categories,
                            counts: existing.counts, phase: existing.phase, receiptSHA256: existing.receiptSHA256,
                            projection: projection, sessionSeedSHA256: existing.sessionSeedSHA256,
                            originalIntent: existing.originalIntent)
                    }
                } else if existing.phase == .committed {
                    guard let historical = try historicalStatus(for: intent),
                          let currentProjection = existing.projection else { throw TransferFailure.identityMismatch }
                    try validateProjection(currentProjection)
                    try rehydratePreferences(for: currentProjection,
                                             transferID: currentProjection.transferID ?? existing.transferID,
                                             preferences: preferences)
                    return historical
                } else if existing.phase != .committed && existing.phase != .failed {
                    throw TransferFailure.busy
                }
            }
            let existingPending = try statusUnlocked()
            var pending = existingPending.flatMap { status in
                status.transferID == intent.transferID && status.rawManifestSHA256 == intent.rawManifestSHA256 && status.phase != .committed ? status : nil
            } ?? TransferRestoreStatus(transferID: intent.transferID, dataSetID: intent.dataSetID,
                rawManifestSHA256: intent.rawManifestSHA256,
                categories: intent.categories.map { TransferCategoryStatus(category: $0, state: .waiting, receiptSHA256: nil) },
                counts: nil, phase: .validating, receiptSHA256: nil, projection: nil,
                originalIntent: intent)
            let package = incomingPackage(intent)
            guard TransferStorageDisk.pathExists(package) else {
                let waiting = TransferRestoreStatus(transferID: pending.transferID, dataSetID: pending.dataSetID,
                    rawManifestSHA256: pending.rawManifestSHA256, categories: pending.categories,
                    counts: pending.counts, phase: .waiting, receiptSHA256: nil, projection: nil,
                    originalIntent: intent)
                try writeRestorePending(waiting, intent: intent)
                throw TransferFailure.unavailable
            }
            // The pending record is authoritative before validation/copy.  A
            // crash at any later point therefore reopens as a locked
            // validating transaction rather than silently returning to normal
            // runtime.
            try writeRestorePending(pending, intent: intent)
            let validated: ValidatedTransferPackage
            do {
                let candidate = try TransferPackageValidator.validate(directory: package)
                guard candidate.input.manifest.transferID == intent.transferID,
                      candidate.input.manifest.dataSetID == intent.dataSetID,
                      candidate.input.manifest.nonce == intent.nonce,
                      candidate.input.rawManifestSHA256 == intent.rawManifestSHA256,
                      candidate.input.manifest.sourceApp == intent.sourceApp,
                      candidate.input.manifest.targetApp == intent.targetApp,
                      candidate.input.manifest.setupID == intent.setupID,
                      candidate.input.manifest.categories == intent.categories else { throw TransferFailure.identityMismatch }
                validated = candidate
            } catch {
                let failed = failedRestoreStatus(from: pending, counts: nil)
                try writeRestorePending(failed, intent: intent)
                throw error
            }
            do {
            let active = transferRoot.appendingPathComponent("active", isDirectory: true)
                .appendingPathComponent(intent.transferID.uuidString.lowercased(), isDirectory: true)
            try TransferStorageDisk.ensureDirectory(active)
            for category in TransferCategory.allCases {
                if pending.categories.first(where: { $0.category == category })?.state == .committed {
                    try validateCommittedCategory(category, active: active)
                    continue
                }
                switch category {
                case .favorites:
                    let directory = active.appendingPathComponent("favorites", isDirectory: true); try TransferStorageDisk.ensureDirectory(directory)
                    let data: Data = intent.categories.contains(.favorites) ? try TransferStorageDisk.read(package.appendingPathComponent("favorites/archive.json"), maximum: FavoritePlacesLimits.fileBytes) ?? Data() : (try TransferArchiveCodec.emptyFavoritePlaces())
                    _ = try TransferArchiveCodec.favoritePlaces(data)
                    try TransferStorageDisk.writeStable(data, to: directory.appendingPathComponent("favorites.json"))
                case .routes:
                    let routeRoot = active.appendingPathComponent("routes", isDirectory: true)
                    let imported = routeRoot.appendingPathComponent("imported", isDirectory: true); let favorites = routeRoot.appendingPathComponent("favorites", isDirectory: true)
                    try TransferStorageDisk.ensureDirectory(imported); try TransferStorageDisk.ensureDirectory(favorites)
                    if intent.categories.contains(.routes) {
                        for (name, target) in [("routes/imported/manifest.json", imported.appendingPathComponent("manifest.json")), ("routes/favorites/manifest.json", favorites.appendingPathComponent("manifest.json")), ("routes/draft.json", active.appendingPathComponent("session/draft.json"))] {
                            guard let data = try TransferStorageDisk.read(package.appendingPathComponent(name), maximum: TransferLimits.draftBytes) else { throw TransferFailure.artifactMismatch }
                            try TransferStorageDisk.writeStable(data, to: target)
                        }
                        let importedRecords = try TransferArchiveCodec.decodeImportedManifest(try TransferStorageDisk.read(package.appendingPathComponent("routes/imported/manifest.json"), maximum: ImportedRoutesLimits.manifestBytes) ?? Data())
                        let favoriteRecords = try TransferArchiveCodec.decodeFavoriteRouteManifest(try TransferStorageDisk.read(package.appendingPathComponent("routes/favorites/manifest.json"), maximum: FavoriteRoutesLimits.manifestBytes) ?? Data())
                        for record in importedRecords { try copyPackage(name: "routes/imported/\(record.id.uuidString).gpx", to: imported.appendingPathComponent("\(record.id.uuidString).gpx"), package: package, maximum: GPXLimits.fileBytes) }
                        for record in favoriteRecords { try copyPackage(name: "routes/favorites/\(record.id.uuidString).route", to: favorites.appendingPathComponent("\(record.id.uuidString).route"), package: package, maximum: FavoriteRoutesLimits.fileBytes) }
                    } else {
                        try TransferStorageDisk.writeStable(try TransferArchiveCodec.encodeImportedManifest([]), to: imported.appendingPathComponent("manifest.json"))
                        try TransferStorageDisk.writeStable(try TransferArchiveCodec.encodeFavoriteRouteManifest([]), to: favorites.appendingPathComponent("manifest.json"))
                    }
                case .settings:
                    let directory = active.appendingPathComponent("settings", isDirectory: true); try TransferStorageDisk.ensureDirectory(directory)
                    let data: Data = intent.categories.contains(.settings) ? try TransferStorageDisk.read(package.appendingPathComponent("settings/preferences.json"), maximum: TransferLimits.settingsBytes) ?? Data() : try TransferCodec.encodeSettings(TransferSettings(language: "system", appearance: "system", mode: .teleport, roundTripEnabled: false, joystickSpeed: .standard))
                    let settings = try TransferCodec.decodeSettings(data)
                    try TransferStorageDisk.writeStable(data, to: directory.appendingPathComponent("preferences.json"))
                    try preferences.activate(settings: settings, transferID: intent.transferID)
                }
                if intent.categories.contains(category) {
                    let categoryReceipt = try categoryReceiptSHA256(category: category, intent: intent, validated: validated)
                    let completed = pending.categories.map { status in
                        status.category == category
                            ? TransferCategoryStatus(category: category, state: .committed, receiptSHA256: categoryReceipt)
                            : status
                    }
                    pending = TransferRestoreStatus(transferID: pending.transferID, dataSetID: pending.dataSetID,
                        rawManifestSHA256: pending.rawManifestSHA256, categories: completed, counts: validated.counts,
                        phase: .validating, receiptSHA256: nil, projection: nil,
                        originalIntent: intent)
                    try writeRestorePending(pending, intent: intent)
                }
            }
            let sessionDirectory = active.appendingPathComponent("session", isDirectory: true); try TransferStorageDisk.ensureDirectory(sessionDirectory)
            let draft: RouteDraft = validated.draft ?? RouteDraft()
            let settings = try validated.settings ?? TransferSettings(language: "system", appearance: "system", mode: .teleport, roundTripEnabled: false, joystickSpeed: .standard)
            let sessionData = try SessionRecoveryCodec.encode(SessionRecoverySnapshot(mode: settings.mode, draft: intent.categories.contains(.routes) ? draft : RouteDraft(), roundTripEnabled: settings.roundTripEnabled, joystickSpeed: settings.joystickSpeed, position: nil, activeMovement: nil, uncertainty: SessionMovementUncertainty(source: .unverifiedPreviousMovement)))
            try TransferStorageDisk.writeStable(sessionData, to: sessionDirectory.appendingPathComponent("session.json"))
            let projection = TransferRuntimeProjection(transferID: intent.transferID,
                favoritesDirectory: active.appendingPathComponent("favorites", isDirectory: true),
                importedRoutesDirectory: active.appendingPathComponent("routes/imported", isDirectory: true),
                favoriteRoutesDirectory: active.appendingPathComponent("routes/favorites", isDirectory: true), sessionDirectory: sessionDirectory)
            try validateProjection(projection)
            let categories = try intent.categories.map { category in
                TransferCategoryStatus(category: category, state: .committed,
                                        receiptSHA256: try categoryReceiptSHA256(category: category, intent: intent, validated: validated))
            }
            let receiptObject = try TransferStorageJSON.restoreFinalReceiptObject(intent: intent,
                categories: categories, sessionSeedSHA256: SetupValidation.sha256(sessionData), counts: validated.counts)
            let receiptSHA = try TransferStorageJSON.hash(receiptObject, maximum: 1_048_576)
            let status = TransferRestoreStatus(transferID: intent.transferID, dataSetID: intent.dataSetID, rawManifestSHA256: intent.rawManifestSHA256, categories: categories, counts: validated.counts, phase: .committed, receiptSHA256: receiptSHA, projection: projection, sessionSeedSHA256: SetupValidation.sha256(sessionData), originalIntent: intent)
            try writeRestoreRoot(status)
            return status
            } catch {
                // Preserve every category pointer/receipt that was committed
                // in an earlier atomic pending-root update.  Only the
                // currently incomplete categories become failed; no runtime
                // projection is exposed from this state.
                let failed = failedRestoreStatus(from: pending, counts: validated.counts)
                try writeRestorePending(failed, intent: intent)
                throw error
            }
        }
    }

    public func writeReadback(currentApp: SetupAppIdentity, pid: Int32) throws {
        try withLock {
            guard let intent = try readIntentUnlocked() else { throw TransferFailure.unavailable }
            let status = try statusUnlocked()
            let responseReceipt: Any
            if let status, status.phase == .committed, let seed = status.sessionSeedSHA256,
               let receiptSHA = status.receiptSHA256, let counts = status.counts {
                let canonical = try TransferStorageJSON.restoreFinalReceiptObject(intent: intent,
                    categories: status.categories, sessionSeedSHA256: seed, counts: counts)
                var final = canonical
                final["receiptSHA256"] = receiptSHA
                responseReceipt = final
            } else {
                responseReceipt = NSNull()
            }
            let object: [String: Any] = ["version": 1, "intent": try JSONSerialization.jsonObject(with: TransferControlCodec.encodeRestoreIntent(intent)), "pid": pid, "app": SetupCodec.appObject(currentApp), "phase": status?.phase.rawValue ?? "waiting", "categories": (status?.categories ?? intent.categories.map { TransferCategoryStatus(category: $0, state: .waiting, receiptSHA256: nil) }).map { ["category": $0.category.rawValue, "state": $0.state.rawValue, "receiptSHA256": $0.receiptSHA256 as Any] }, "counts": status?.counts.map { ["favorites": $0.favorites, "importedRoutes": $0.importedRoutes, "favoriteRoutes": $0.favoriteRoutes, "draftNodes": $0.draftNodes, "gpxPoints": $0.gpxPoints] } as Any, "receipt": responseReceipt]
            try TransferStorageDisk.atomicWrite(try TransferStorageJSON.encode(object, maximum: TransferLimits.requestBytes), to: transferRoot.appendingPathComponent("restore-response.json"), checkpoint: checkpoint)
        }
    }

    private func incomingPackage(_ intent: TransferRestoreIntent) -> URL { transferRoot.appendingPathComponent("incoming", isDirectory: true).appendingPathComponent(intent.dataSetID.uuidString.lowercased(), isDirectory: true).appendingPathComponent("package", isDirectory: true) }
    private func copyPackage(name: String, to target: URL, package: URL, maximum: Int) throws { guard let data = try TransferStorageDisk.read(package.appendingPathComponent(name), maximum: maximum) else { throw TransferFailure.artifactMismatch }; try TransferStorageDisk.writeStable(data, to: target) }
    private func failedRestoreStatus(from status: TransferRestoreStatus, counts: TransferCounts?) -> TransferRestoreStatus {
        let categories = status.categories.map { value in
            value.state == .committed
                ? value
                : TransferCategoryStatus(category: value.category, state: .failed, receiptSHA256: nil)
        }
        return TransferRestoreStatus(transferID: status.transferID, dataSetID: status.dataSetID,
            rawManifestSHA256: status.rawManifestSHA256, categories: categories,
            counts: counts ?? status.counts, phase: .failed, receiptSHA256: nil,
            projection: nil, sessionSeedSHA256: status.sessionSeedSHA256,
            originalIntent: status.originalIntent)
    }
    private func validateCommittedCategory(_ category: TransferCategory, active: URL) throws {
        switch category {
        case .favorites:
            guard let data = try TransferStorageDisk.read(active.appendingPathComponent("favorites/favorites.json"), maximum: FavoritePlacesLimits.fileBytes) else { throw TransferFailure.artifactMismatch }
            _ = try TransferArchiveCodec.favoritePlaces(data)
        case .routes:
            guard let imported = try TransferStorageDisk.read(active.appendingPathComponent("routes/imported/manifest.json"), maximum: ImportedRoutesLimits.manifestBytes),
                  let favorite = try TransferStorageDisk.read(active.appendingPathComponent("routes/favorites/manifest.json"), maximum: FavoriteRoutesLimits.manifestBytes),
                  let draft = try TransferStorageDisk.read(active.appendingPathComponent("session/draft.json"), maximum: TransferLimits.draftBytes) else { throw TransferFailure.artifactMismatch }
            let importedRecords = try TransferArchiveCodec.decodeImportedManifest(imported)
            let favoriteRecords = try TransferArchiveCodec.decodeFavoriteRouteManifest(favorite)
            _ = try TransferCodec.decodeDraft(draft)
            for record in importedRecords {
                guard let data = try TransferStorageDisk.read(active.appendingPathComponent("routes/imported/\(record.id.uuidString).gpx"), maximum: GPXLimits.fileBytes) else { throw TransferFailure.artifactMismatch }
                try TransferArchiveCodec.validateImportedPayload(data, record: record)
            }
            for record in favoriteRecords {
                guard let data = try TransferStorageDisk.read(active.appendingPathComponent("routes/favorites/\(record.id.uuidString).route"), maximum: FavoriteRoutesLimits.fileBytes) else { throw TransferFailure.artifactMismatch }
                try TransferArchiveCodec.validateFavoriteRoutePayload(data, record: record)
            }
        case .settings:
            guard let data = try TransferStorageDisk.read(active.appendingPathComponent("settings/preferences.json"), maximum: TransferLimits.settingsBytes) else { throw TransferFailure.artifactMismatch }
            _ = try TransferCodec.decodeSettings(data)
        }
    }
    private func readIntentUnlocked() throws -> TransferRestoreIntent? { guard let data = try TransferStorageDisk.read(transferRoot.appendingPathComponent("restore-intent.json"), maximum: TransferLimits.requestBytes) else { return nil }; return try TransferControlCodec.decodeRestoreIntent(data) }
    private func statusUnlocked() throws -> TransferRestoreStatus? { guard let data = try TransferStorageDisk.read(transferRoot.appendingPathComponent("restore-root.json"), maximum: 1_048_576) else { return nil }; return try TransferStorageJSON.decodeRestoreStatus(data, applicationSupport: applicationSupport) }
    private func historicalStatus(for intent: TransferRestoreIntent) throws -> TransferRestoreStatus? {
        guard let data = try TransferStorageDisk.read(transferRoot.appendingPathComponent("restore-root.json"), maximum: 1_048_576) else { return nil }
        return try TransferStorageJSON.decodeRestoreHistory(data, matching: intent, applicationSupport: applicationSupport)
    }
    private func rehydratePreferences(for projection: TransferRuntimeProjection,
                                      transferID: UUID,
                                      preferences: TransferPreferencesStore) throws {
        let settingsURL = projection.sessionDirectory.deletingLastPathComponent()
            .appendingPathComponent("settings/preferences.json")
        guard let data = try TransferStorageDisk.read(settingsURL, maximum: TransferLimits.settingsBytes) else {
            throw TransferFailure.artifactMismatch
        }
        let settings = try TransferCodec.decodeSettings(data)
        let current = try preferences.currentValues()
        // A matching marker means the user may have changed the pair after
        // restore; retain that explicit pair. Otherwise repair defaults from
        // the current authoritative active settings namespace.
        if current.marker != transferID {
            try preferences.activate(settings: settings, transferID: transferID)
        }
    }
    private func validateProjection(_ projection: TransferRuntimeProjection) throws {
        guard let favorites = try TransferStorageDisk.read(projection.favoritesDirectory.appendingPathComponent("favorites.json"), maximum: FavoritePlacesLimits.fileBytes),
              let imported = try TransferStorageDisk.read(projection.importedRoutesDirectory.appendingPathComponent("manifest.json"), maximum: ImportedRoutesLimits.manifestBytes),
              let favorite = try TransferStorageDisk.read(projection.favoriteRoutesDirectory.appendingPathComponent("manifest.json"), maximum: FavoriteRoutesLimits.manifestBytes),
              let session = try TransferStorageDisk.read(projection.sessionDirectory.appendingPathComponent("session.json"), maximum: SessionRecoveryLimits.recordBytes) else { throw TransferFailure.artifactMismatch }
        _ = try TransferArchiveCodec.favoritePlaces(favorites)
        _ = try TransferArchiveCodec.decodeImportedManifest(imported)
        _ = try TransferArchiveCodec.decodeFavoriteRouteManifest(favorite)
        _ = try SessionRecoveryCodec.decodeRecord(session)
        if let transferID = projection.transferID {
            let settingsURL = applicationSupport.appendingPathComponent("GoFlyTransfer/active/\(transferID.uuidString.lowercased())/settings/preferences.json")
            guard let settingsData = try TransferStorageDisk.read(settingsURL, maximum: TransferLimits.settingsBytes) else { throw TransferFailure.artifactMismatch }
            _ = try TransferCodec.decodeSettings(settingsData)
        }
    }
    private func categoryReceiptSHA256(category: TransferCategory, intent: TransferRestoreIntent,
                                       validated: ValidatedTransferPackage) throws -> String {
        let paths = validated.input.manifest.artifacts
            .filter { artifact in
                switch category {
                case .favorites: return artifact.path == "favorites/archive.json"
                case .routes: return artifact.path == "routes/draft.json" || artifact.path.hasPrefix("routes/imported/") || artifact.path.hasPrefix("routes/favorites/")
                case .settings: return artifact.path == "settings/preferences.json"
                }
            }
            .sorted { $0.path < $1.path }
            .map { ["path": $0.path, "sha256": $0.sha256] }
        return try TransferStorageJSON.hash([
            "version": 1, "transferID": intent.transferID.uuidString.lowercased(),
            "dataSetID": intent.dataSetID.uuidString.lowercased(), "nonce": intent.nonce.uuidString.lowercased(),
            "rawManifestSHA256": intent.rawManifestSHA256, "category": category.rawValue,
            "artifacts": paths
        ], maximum: 1_048_576)
    }
    private func writeRestorePending(_ status: TransferRestoreStatus, intent: TransferRestoreIntent) throws {
        guard status.originalIntent == intent else { throw TransferFailure.identityMismatch }
        let existing = try TransferStorageDisk.read(transferRoot.appendingPathComponent("restore-root.json"), maximum: 1_048_576)
        let prior: (current: TransferRestoreStatus?, pending: (status: TransferRestoreStatus, intent: TransferRestoreIntent)?, history: [TransferRestoreStatus])?
        prior = try existing.map { try TransferStorageJSON.decodeRestoreRoot($0, applicationSupport: applicationSupport) }
        var history = prior?.history ?? []
        guard !history.contains(where: { $0.transferID == status.transferID }) else { throw TransferFailure.busy }
        if let old = prior?.current, old.transferID != status.transferID {
            guard history.count < TransferLimits.historyCount else { throw TransferFailure.receiptCapacity }
            history.append(old)
        }
        try TransferStorageDisk.atomicWrite(try TransferStorageJSON.restoreRootObject(active: nil,
            pending: (status, intent), history: history), to: transferRoot.appendingPathComponent("restore-root.json"), checkpoint: checkpoint)
    }
    private func writeRestoreRoot(_ status: TransferRestoreStatus) throws {
        guard status.originalIntent != nil else { throw TransferFailure.identityMismatch }
        let existing = try TransferStorageDisk.read(transferRoot.appendingPathComponent("restore-root.json"), maximum: 1_048_576)
        let prior = try existing.map { try TransferStorageJSON.decodeRestoreRoot($0, applicationSupport: applicationSupport) }
        var history = prior?.history ?? []
        guard !history.contains(where: { $0.transferID == status.transferID }) else { throw TransferFailure.busy }
        if let old = prior?.current, old.transferID != status.transferID {
            guard history.count < TransferLimits.historyCount else { throw TransferFailure.receiptCapacity }
            history.append(old)
        }
        try TransferStorageDisk.atomicWrite(try TransferStorageJSON.restoreRootObject(active: status,
            pending: nil, history: history), to: transferRoot.appendingPathComponent("restore-root.json"), checkpoint: checkpoint)
    }
    private func withLock<T>(_ body: () throws -> T) throws -> T { lock.lock(); defer { lock.unlock() }; return try body() }
}

// MARK: - Private JSON and filesystem helpers

private enum TransferStorageErrorCode {
    static func isValid(_ value: String) -> Bool {
        ["invalid-input", "unsupported-version", "unsafe-file", "limit-exceeded", "identity-mismatch",
         "artifact-mismatch", "unavailable", "storage-unavailable", "commit-unknown", "receipt-capacity",
         "busy", "source-busy", "export-conflict", "update-required"].contains(value)
    }
    static func code(_ failure: TransferFailure) -> String {
        switch failure { case .invalidInput: return "invalid-input"; case .unsupportedVersion: return "unsupported-version"; case .unsafeFile: return "unsafe-file"; case .limitExceeded: return "limit-exceeded"; case .identityMismatch: return "identity-mismatch"; case .artifactMismatch: return "artifact-mismatch"; case .unavailable: return "unavailable"; case .storageUnavailable: return "storage-unavailable"; case .commitUnknown: return "commit-unknown"; case .receiptCapacity: return "receipt-capacity"; case .busy: return "busy"; case .sourceBusy: return "source-busy"; case .exportConflict: return "export-conflict"; case .updateRequired: return "update-required" }
    }
}

private enum TransferStorageJSON {
    static func encode(_ object: [String: Any], maximum: Int) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else { throw TransferFailure.invalidInput }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= maximum else { throw TransferFailure.limitExceeded }; return data
    }
    static func hash(_ object: [String: Any], maximum: Int) throws -> String { SetupValidation.sha256(try encode(object, maximum: maximum)) }
    static func parse(_ data: Data, maximum: Int) throws -> _SetupJSON { guard data.count <= maximum else { throw TransferFailure.limitExceeded }; do { return try _SetupJSON.parse(data) } catch { throw TransferFailure.invalidInput } }
    static func string(_ value: _SetupJSON) throws -> String { do { return try value.string() } catch { throw TransferFailure.invalidInput } }
    static func int(_ value: _SetupJSON) throws -> Int { do { return try value.int() } catch { throw TransferFailure.invalidInput } }
    static func uuid(_ value: _SetupJSON) throws -> UUID { let s = try string(value); guard s == s.lowercased(), let id = UUID(uuidString: s), id.uuidString.lowercased() == s else { throw TransferFailure.invalidInput }; return id }
    static func foundation(_ value: _SetupJSON) throws -> Any {
        switch value {
        case .object(let pairs): return try Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, try foundation($0.1)) })
        case .array(let values): return try values.map(foundation)
        case .string(let string): return string
        case .number(let number):
            if let integer = Int(number) { return integer }
            if let double = Double(number) { return double }
            return number
        case .bool(let value): return value
        case .null: return NSNull()
        }
    }
    static func receiptObject(_ receipt: TransferExportReceipt) throws -> Data {
        try encode(["version": 1, "phase": receipt.phase.rawValue, "request": try JSONSerialization.jsonObject(with: TransferControlCodec.encodeExportRequest(receipt.request)), "requestSHA256": receipt.requestSHA256, "sourceApp": SetupCodec.appObject(receipt.sourceApp), "manifestSHA256": receipt.manifestSHA256 as Any, "cutlineSHA256": receipt.cutlineSHA256 as Any, "receiptSHA256": receipt.receiptSHA256], maximum: 1_048_576)
    }
    static func decodeReceipt(_ data: Data) throws -> TransferExportReceipt {
        let value = try parse(data, maximum: 1_048_576); try value.requireObjectKeys(["version", "phase", "request", "requestSHA256", "sourceApp", "manifestSHA256", "cutlineSHA256", "receiptSHA256"])
        guard try int(value.object("version")) == 1 else { throw TransferFailure.unsupportedVersion }
        let request = try TransferControlCodec.decodeExportRequest(try JSONSerialization.data(withJSONObject: try foundation(value.object("request"))))
        let phase = try TransferExportPhase(rawValue: string(value.object("phase"))).unwrap(or: TransferFailure.invalidInput)
        let manifestValue = try value.object("manifestSHA256"); let cutlineValue = try value.object("cutlineSHA256")
        let manifest = manifestValue.isNull ? nil : try string(manifestValue); let cutline = cutlineValue.isNull ? nil : try string(cutlineValue)
        let receipt = try TransferExportReceipt(phase: phase, request: request, requestSHA256: string(value.object("requestSHA256")), sourceApp: try SetupAppIdentity.decode(value.object("sourceApp")), manifestSHA256: manifest, cutlineSHA256: cutline)
        let storedDigest = try string(value.object("receiptSHA256"))
        guard receipt.receiptSHA256 == storedDigest else { throw TransferFailure.artifactMismatch }
        return receipt
    }
    static func activeExportRootObject(current: TransferExportReceipt?, history: [TransferExportReceipt]) throws -> Data {
        let currentObject: Any
        if let current { currentObject = try JSONSerialization.jsonObject(with: receiptObject(current)) }
        else { currentObject = NSNull() }
        let historyObjects = try history.map { try JSONSerialization.jsonObject(with: receiptObject($0)) }
        return try encode(["version": 1, "current": currentObject, "history": historyObjects], maximum: 1_048_576)
    }
    static func decodeActiveExportRoot(_ data: Data) throws -> (current: TransferExportReceipt?, history: [TransferExportReceipt]) {
        let value = try parse(data, maximum: 1_048_576)
        try value.requireObjectKeys(["version", "current", "history"])
        guard try int(value.object("version")) == 1 else { throw TransferFailure.unsupportedVersion }
        let currentValue = try value.object("current")
        let current: TransferExportReceipt?
        if currentValue.isNull { current = nil }
        else { current = try decodeReceipt(try JSONSerialization.data(withJSONObject: try foundation(currentValue))) }
        let historyValues = try value.object("history").array()
        guard historyValues.count <= TransferLimits.historyCount else { throw TransferFailure.receiptCapacity }
        let history = try historyValues.map { try decodeReceipt(try JSONSerialization.data(withJSONObject: try foundation($0))) }
        guard history.allSatisfy({ $0.phase == .released || $0.phase == .releasedNoSnapshot }) else { throw TransferFailure.artifactMismatch }
        guard Set(history.map { $0.request.transferID }).count == history.count else { throw TransferFailure.artifactMismatch }
        if let current, history.allSatisfy({ $0.request.transferID != current.request.transferID }) == false { throw TransferFailure.artifactMismatch }
        return (current, history)
    }
    static func readbackObject(_ readback: TransferReadback) throws -> Data {
        try encode(["version": 1, "commandID": readback.commandID.uuidString.lowercased(), "action": readback.action.rawValue, "transferID": readback.transferID.uuidString.lowercased(), "nonce": readback.nonce.uuidString.lowercased(), "requestSHA256": readback.requestSHA256, "manifestSHA256": readback.manifestSHA256 as Any, "sourceApp": SetupCodec.appObject(readback.sourceApp), "pid": readback.pid, "phase": readback.phase.rawValue, "receiptSHA256": readback.receiptSHA256 as Any, "errorCode": readback.errorCode as Any], maximum: TransferLimits.requestBytes)
    }
    static func restoreFinalReceiptObject(intent: TransferRestoreIntent,
                                          categories: [TransferCategoryStatus],
                                          sessionSeedSHA256: String,
                                          counts: TransferCounts) throws -> [String: Any] {
        guard SetupValidation.isLowerHex(sessionSeedSHA256, count: 64) else { throw TransferFailure.artifactMismatch }
        let categoryReceipts: [[String: Any]] = try categories.map { value in
            guard value.state == .committed, let receipt = value.receiptSHA256,
                  SetupValidation.isLowerHex(receipt, count: 64) else { throw TransferFailure.artifactMismatch }
            return ["category": value.category.rawValue, "receiptSHA256": receipt]
        }
        return ["version": 1,
                "intent": try JSONSerialization.jsonObject(with: TransferControlCodec.encodeRestoreIntent(intent)),
                "categoryReceipts": categoryReceipts,
                "sessionSeedSHA256": sessionSeedSHA256,
                "counts": ["favorites": counts.favorites, "importedRoutes": counts.importedRoutes,
                           "favoriteRoutes": counts.favoriteRoutes, "draftNodes": counts.draftNodes,
                           "gpxPoints": counts.gpxPoints]]
    }
    static func restoreRootObject(active: TransferRestoreStatus?, pending: (status: TransferRestoreStatus, intent: TransferRestoreIntent)?, history: [TransferRestoreStatus]) throws -> Data {
        func object(_ value: TransferRestoreStatus) throws -> [String: Any] {
            ["transferID": value.transferID.uuidString.lowercased(), "dataSetID": value.dataSetID.uuidString.lowercased(), "rawManifestSHA256": value.rawManifestSHA256, "phase": value.phase.rawValue, "receiptSHA256": value.receiptSHA256 as Any, "sessionSeedSHA256": value.sessionSeedSHA256 as Any, "intent": try value.originalIntent.map { try JSONSerialization.jsonObject(with: TransferControlCodec.encodeRestoreIntent($0)) } as Any, "categories": value.categories.map { ["category": $0.category.rawValue, "state": $0.state.rawValue, "receiptSHA256": $0.receiptSHA256 as Any] }, "counts": value.counts.map { ["favorites": $0.favorites, "importedRoutes": $0.importedRoutes, "favoriteRoutes": $0.favoriteRoutes, "draftNodes": $0.draftNodes, "gpxPoints": $0.gpxPoints] } as Any]
        }
        let activeObject: Any = try active.map(object) ?? NSNull()
        let pendingObject: Any
        if let pending {
            let pointers: [[String: Any]] = pending.status.categories.map { category in
                ["category": category.category.rawValue,
                 "state": category.state.rawValue,
                 // The pointer is intentionally a closed value.  It names a
                 // derived namespace, never a serialized path supplied by an
                 // ingress file.
                 "pointer": ["transferID": pending.status.transferID.uuidString.lowercased(),
                             "category": category.category.rawValue],
                 "receiptSHA256": category.receiptSHA256 as Any]
            }
            let seed: [String: Any] = ["state": pending.status.sessionSeedSHA256 == nil ? "waiting" : "committed",
                                        "sessionSeedSHA256": pending.status.sessionSeedSHA256 as Any]
            pendingObject = ["intent": try JSONSerialization.jsonObject(with: TransferControlCodec.encodeRestoreIntent(pending.intent)), "status": try object(pending.status), "pointers": pointers, "seed": seed]
        } else {
            pendingObject = NSNull()
        }
        return try encode(["version": 1, "active": activeObject, "pending": pendingObject, "history": try history.map { try object($0) }], maximum: 1_048_576)
    }
    static func decodeRestoreRoot(_ data: Data, applicationSupport: URL) throws -> (current: TransferRestoreStatus?, pending: (status: TransferRestoreStatus, intent: TransferRestoreIntent)?, history: [TransferRestoreStatus]) {
        let value = try parse(data, maximum: 1_048_576)
        try value.requireObjectKeys(["version", "active", "pending", "history"])
        guard try int(value.object("version")) == 1 else { throw TransferFailure.unsupportedVersion }
        let active = try value.object("active")
        let current = active.isNull ? nil : try decodeRestoreStatusObject(active, applicationSupport: applicationSupport)
        let pendingValue = try value.object("pending")
        let pending: (status: TransferRestoreStatus, intent: TransferRestoreIntent)?
        if pendingValue.isNull {
            pending = nil
        } else {
            if (try? pendingValue.requireObjectKeys(["intent", "status"])) == nil {
                try pendingValue.requireObjectKeys(["intent", "status", "pointers", "seed"])
            }
            let intent = try TransferControlCodec.decodeRestoreIntent(JSONSerialization.data(withJSONObject: try foundation(pendingValue.object("intent"))))
            let status = try decodeRestoreStatusObject(pendingValue.object("status"), applicationSupport: applicationSupport)
            guard status.transferID == intent.transferID, status.dataSetID == intent.dataSetID,
                  status.rawManifestSHA256 == intent.rawManifestSHA256 else { throw TransferFailure.artifactMismatch }
            // New roots carry the complete category pointer/receipt journal
            // in the same object as the pending status.  Older roots remain
            // readable for a cold migration; their pointers are deterministic
            // from the typed status and are therefore not adopted from disk.
            if let pointers = try? pendingValue.object("pointers").array() {
                guard pointers.count == status.categories.count else { throw TransferFailure.artifactMismatch }
                for item in pointers {
                    try item.requireObjectKeys(["category", "state", "pointer", "receiptSHA256"])
                    guard let category = TransferCategory(rawValue: try string(item.object("category"))),
                          let statusCategory = status.categories.first(where: { $0.category == category }),
                          statusCategory.state.rawValue == (try string(item.object("state"))) else { throw TransferFailure.artifactMismatch }
                    let pointer = try item.object("pointer")
                    try pointer.requireObjectKeys(["transferID", "category"])
                    guard try uuid(pointer.object("transferID")) == status.transferID,
                          try string(pointer.object("category")) == category.rawValue else { throw TransferFailure.artifactMismatch }
                    let receiptValue = try item.object("receiptSHA256")
                    let receipt = receiptValue.isNull ? nil : try string(receiptValue)
                    guard receipt == statusCategory.receiptSHA256 else { throw TransferFailure.artifactMismatch }
                }
            }
            if let seed = try? pendingValue.object("seed") {
                try seed.requireObjectKeys(["state", "sessionSeedSHA256"])
                let seedValue = try seed.object("sessionSeedSHA256")
                let seedDigest = seedValue.isNull ? nil : try string(seedValue)
                guard seedDigest == status.sessionSeedSHA256 else { throw TransferFailure.artifactMismatch }
                let seedState = try string(seed.object("state"))
                guard seedState == (seedDigest == nil ? "waiting" : "committed") else { throw TransferFailure.artifactMismatch }
            }
            pending = (status, intent)
        }
        let values = try value.object("history").array()
        guard values.count <= TransferLimits.historyCount else { throw TransferFailure.receiptCapacity }
        let history = try values.map { try decodeRestoreStatusObject($0, applicationSupport: applicationSupport) }
        guard Set(history.map(\.transferID)).count == history.count else { throw TransferFailure.artifactMismatch }
        if let current, history.allSatisfy({ $0.transferID != current.transferID }) == false {
            throw TransferFailure.artifactMismatch
        }
        return (current, pending, history)
    }
    static func decodeRestoreHistory(_ data: Data, matching intent: TransferRestoreIntent, applicationSupport: URL) throws -> TransferRestoreStatus? {
        let root = try decodeRestoreRoot(data, applicationSupport: applicationSupport)
        guard let historical = root.history.first(where: { $0.transferID == intent.transferID && $0.dataSetID == intent.dataSetID && $0.rawManifestSHA256 == intent.rawManifestSHA256 }) else { return nil }
        guard historical.originalIntent == intent else { throw TransferFailure.identityMismatch }
        return TransferRestoreStatus(transferID: historical.transferID, dataSetID: historical.dataSetID, rawManifestSHA256: historical.rawManifestSHA256, categories: historical.categories, counts: historical.counts, phase: historical.phase, receiptSHA256: historical.receiptSHA256, projection: root.current?.projection, sessionSeedSHA256: historical.sessionSeedSHA256, originalIntent: historical.originalIntent)
    }
    static func decodeRestoreStatus(_ data: Data, applicationSupport: URL) throws -> TransferRestoreStatus? {
        let root = try decodeRestoreRoot(data, applicationSupport: applicationSupport)
        return root.current ?? root.pending?.status
    }
    private static func decodeRestoreStatusObject(_ active: _SetupJSON, applicationSupport: URL) throws -> TransferRestoreStatus {
        var requiredKeys: Set<String> = ["transferID", "dataSetID", "rawManifestSHA256", "phase", "receiptSHA256", "sessionSeedSHA256", "categories", "counts"]
        if case .object(let pairs) = active, pairs.contains(where: { $0.0 == "intent" }) {
            requiredKeys.insert("intent")
        }
        try active.requireObjectKeys(requiredKeys)
        let transferID = try uuid(active.object("transferID")); let dataSetID = try uuid(active.object("dataSetID")); guard let phase = TransferRestorePhase(rawValue: try string(active.object("phase"))) else { throw TransferFailure.invalidInput }
        let rawManifestSHA256 = try string(active.object("rawManifestSHA256"))
        guard SetupValidation.isLowerHex(rawManifestSHA256, count: 64) else { throw TransferFailure.artifactMismatch }
        let receiptValue = try active.object("receiptSHA256")
        let receipt = receiptValue.isNull ? nil : try string(receiptValue)
        let seedValue = try active.object("sessionSeedSHA256")
        let seed = seedValue.isNull ? nil : try string(seedValue)
        guard receipt.map({ SetupValidation.isLowerHex($0, count: 64) }) ?? true,
              seed.map({ SetupValidation.isLowerHex($0, count: 64) }) ?? true else { throw TransferFailure.artifactMismatch }
        let categoryObjects = try active.object("categories").array()
        let categories = try categoryObjects.map { item -> TransferCategoryStatus in
            try item.requireObjectKeys(["category", "state", "receiptSHA256"])
            guard let category = TransferCategory(rawValue: try string(item.object("category"))),
                  let state = TransferCategoryState(rawValue: try string(item.object("state"))) else { throw TransferFailure.invalidInput }
            let receiptValue = try item.object("receiptSHA256")
            let receipt = receiptValue.isNull ? nil : try string(receiptValue)
            guard receipt.map({ SetupValidation.isLowerHex($0, count: 64) }) ?? true else { throw TransferFailure.artifactMismatch }
            guard (state == .committed) == (receipt != nil) else { throw TransferFailure.artifactMismatch }
            return TransferCategoryStatus(category: category, state: state, receiptSHA256: receipt)
        }
        let categoryValues = categories.map { $0.category }
        guard categoryValues == TransferCategory.allCases.filter({ categoryValues.contains($0) }) else {
            throw TransferFailure.artifactMismatch
        }
        guard Set(categoryValues).count == categories.count else { throw TransferFailure.artifactMismatch }
        let countsValue = try active.object("counts")
        let counts: TransferCounts?
        if countsValue.isNull { counts = nil }
        else {
            try countsValue.requireObjectKeys(["favorites", "importedRoutes", "favoriteRoutes", "draftNodes", "gpxPoints"])
            counts = TransferCounts(favorites: try int(countsValue.object("favorites")),
                                    importedRoutes: try int(countsValue.object("importedRoutes")),
                                    favoriteRoutes: try int(countsValue.object("favoriteRoutes")),
                                    draftNodes: try int(countsValue.object("draftNodes")),
                                    gpxPoints: try int(countsValue.object("gpxPoints")))
            guard counts!.favorites >= 0, counts!.importedRoutes >= 0, counts!.favoriteRoutes >= 0,
                  counts!.draftNodes >= 0, counts!.gpxPoints >= 0 else { throw TransferFailure.artifactMismatch }
        }
        let root = applicationSupport.appendingPathComponent("GoFlyTransfer/active/\(transferID.uuidString.lowercased())", isDirectory: true)
        let projection = phase == .committed ? TransferRuntimeProjection(transferID: transferID, favoritesDirectory: root.appendingPathComponent("favorites", isDirectory: true), importedRoutesDirectory: root.appendingPathComponent("routes/imported", isDirectory: true), favoriteRoutesDirectory: root.appendingPathComponent("routes/favorites", isDirectory: true), sessionDirectory: root.appendingPathComponent("session", isDirectory: true)) : nil
        let originalIntent: TransferRestoreIntent?
        if let intentValue = try? active.object("intent") {
            if intentValue.isNull {
                originalIntent = nil
            } else {
                let intent = try TransferControlCodec.decodeRestoreIntent(JSONSerialization.data(withJSONObject: try foundation(intentValue)))
                guard intent.transferID == transferID, intent.dataSetID == dataSetID,
                      intent.rawManifestSHA256 == rawManifestSHA256,
                      intent.categories == categoryValues else { throw TransferFailure.artifactMismatch }
                originalIntent = intent
            }
        } else {
            originalIntent = nil
        }
        return TransferRestoreStatus(transferID: transferID, dataSetID: dataSetID, rawManifestSHA256: rawManifestSHA256, categories: categories, counts: counts, phase: phase, receiptSHA256: receipt, projection: projection, sessionSeedSHA256: seed, originalIntent: originalIntent)
    }
}

private enum TransferStorageCrypto {
    static func uuidV5(namespace: UUID, name: String) -> UUID {
        var bytes = Data(); var uuid = namespace.uuid; withUnsafeBytes(of: &uuid) { bytes.append(contentsOf: $0) }; bytes.append(contentsOf: name.utf8)
        var digest = Array(Insecure.SHA1.hash(data: bytes)); digest[6] = (digest[6] & 0x0f) | 0x50; digest[8] = (digest[8] & 0x3f) | 0x80
        let tuple: uuid_t = (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7], digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]); return UUID(uuid: tuple)
    }
}

private enum TransferStorageDisk {
    static func canonicalTrustedBase(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        // Foundation can preserve the /var compatibility alias while the
        // descriptor walker correctly refuses that symlink.  Application
        // Support is trusted input, so collapse this host alias once here;
        // all derived transfer components continue to use no-follow opens.
        if standardized.path.hasPrefix("/var/"),
           FileManager.default.fileExists(atPath: "/private/var") {
            return URL(fileURLWithPath: "/private" + standardized.path, isDirectory: true)
        }
        return standardized
    }
    static func ensureDirectory(_ url: URL) throws {
        // The initializer canonicalizes the trusted Application Support base
        // once. Preserve that spelling here; `standardizedFileURL` may turn
        // `/private/var` back into the `/var` compatibility symlink before
        // the descriptor walk reaches it.
        let path = url.absoluteURL.path
        guard path.hasPrefix("/") else { throw TransferFailure.unsafeFile }
        let components = path.split(separator: "/").map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw TransferFailure.unsafeFile
        }
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard current >= 0 else { throw TransferFailure.storageUnavailable }
        defer { Darwin.close(current) }
        guard !components.isEmpty else { return }

        for (index, component) in components.enumerated() {
            let nextFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            var next = openat(current, component, nextFlags, 0)
            if next < 0 {
                let openError = errno
                guard openError == ENOENT else {
                    if openError == ELOOP || openError == ENOTDIR { throw TransferFailure.unsafeFile }
                    throw TransferFailure.storageUnavailable
                }
                guard mkdirat(current, component, 0o700) == 0 || errno == EEXIST else {
                    throw TransferFailure.storageUnavailable
                }
                next = openat(current, component, nextFlags, 0)
                guard next >= 0 else {
                    if errno == ELOOP || errno == ENOTDIR { throw TransferFailure.unsafeFile }
                    throw TransferFailure.storageUnavailable
                }
                guard fsync(next) == 0 else {
                    Darwin.close(next)
                    throw TransferFailure.storageUnavailable
                }
            }

            var info = stat()
            guard fstat(next, &info) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
                Darwin.close(next)
                throw TransferFailure.unsafeFile
            }
            if index == components.count - 1 {
                guard info.st_uid == getuid(), info.st_mode & 0o7777 == 0o700 else {
                    Darwin.close(next)
                    throw TransferFailure.unsafeFile
                }
            }
            Darwin.close(current)
            current = next
        }
    }
    static func isDirectory(_ url: URL) throws -> Bool { var value = stat(); guard lstat(url.path, &value) == 0 else { throw TransferFailure.storageUnavailable }; return value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) && value.st_uid == getuid() && value.st_mode & 0o7777 == 0o700 }
    static func openExistingDirectory(_ url: URL, requirePrivate: Bool) throws -> Int32? { var value = stat(); guard lstat(url.path, &value) == 0 else { if errno == ENOENT { return nil }; throw TransferFailure.unsafeFile }; guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), value.st_uid == getuid(), !requirePrivate || value.st_mode & 0o7777 == 0o700 else { throw TransferFailure.unsafeFile }; let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC); guard fd >= 0 else { throw TransferFailure.unavailable }; return fd }
    static func sealTransferRoot(_ fd: Int32, at url: URL) throws {
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw TransferFailure.storageUnavailable }
        let mode = info.st_mode & 0o7777
        let initialIngress = mode == 0o755
        guard mode == 0o700 || initialIngress else { throw TransferFailure.unsafeFile }
        let allowed = Set(["export-request.json", "control-request.json", "control-response.json", "restore-response.json", "restore-intent.json", "incoming.json", "active-export.json", "restore-root.json", "exports", "incoming", "active"])
        // Inventory every existing component while the descriptor chain is
        // retained.  No chmod occurs until this complete closed inventory has
        // succeeded, so a malformed ingress cannot be partially sealed.
        var entries = 0
        try inventoryRoot(fd, allowed: allowed, initialIngress: initialIngress, prefix: "", depth: 0, entries: &entries)
        let hasAppRoot = try rootContainsAppOwnedEntry(fd)
        if initialIngress {
            guard !hasAppRoot else { throw TransferFailure.unsafeFile }
            guard fchmod(fd, 0o700) == 0, fsync(fd) == 0 else { throw TransferFailure.storageUnavailable }
        }
    }

    private static func rootContainsAppOwnedEntry(_ fd: Int32) throws -> Bool {
        // `incoming` is producer ingress and may legitimately be the only
        // content in an AFC-created 0755 root.  It becomes App-owned only
        // after the closed ingress inventory has been validated and sealed.
        for name in ["active-export.json", "restore-root.json", "control-response.json", "restore-response.json", "active", "exports"] {
            var value = stat()
            if fstatat(fd, name, &value, AT_SYMLINK_NOFOLLOW) == 0 { return true }
            if errno != ENOENT { throw TransferFailure.unsafeFile }
        }
        return false
    }

    private static func inventoryRoot(_ fd: Int32, allowed: Set<String>, initialIngress: Bool,
                                      prefix: String,
                                      depth: Int, entries: inout Int) throws {
        guard depth <= 8 else { throw TransferFailure.limitExceeded }
        let duplicate = Darwin.dup(fd); guard duplicate >= 0 else { throw TransferFailure.unavailable }
        guard let stream = fdopendir(duplicate) else { Darwin.close(duplicate); throw TransferFailure.unavailable }
        defer { closedir(stream) }
        while let entry = readdir(stream) {
            let name = TransferFileIO.directoryEntryName(entry)
            if name == "." || name == ".." { continue }
            guard depth != 0 || allowed.contains(name) else { throw TransferFailure.unsafeFile }
            entries += 1; guard entries <= 4_096 else { throw TransferFailure.limitExceeded }
            var value = stat()
            guard fstatat(fd, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
                  value.st_uid == getuid() else { throw TransferFailure.unsafeFile }
            let type = value.st_mode & mode_t(S_IFMT)
            let childPath = prefix.isEmpty ? name : prefix + "/" + name
            let incomingIngress = childPath == "incoming" || childPath.hasPrefix("incoming/")
            if type == mode_t(S_IFDIR) {
                let childMode = value.st_mode & 0o7777
                guard childMode == 0o700 || (incomingIngress && childMode == 0o755) || (initialIngress && depth == 0 && childMode == 0o755) else { throw TransferFailure.unsafeFile }
                let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC, 0)
                guard child >= 0 else { throw TransferFailure.unsafeFile }
                defer { Darwin.close(child) }
                try inventoryRoot(child, allowed: allowed, initialIngress: initialIngress, prefix: childPath, depth: depth + 1, entries: &entries)
            } else if type == mode_t(S_IFREG) {
                guard value.st_nlink == 1 else { throw TransferFailure.unsafeFile }
                let fileMode = value.st_mode & 0o7777
                guard fileMode == 0o600 || (incomingIngress && fileMode == 0o644) || (initialIngress && depth == 0 && fileMode == 0o644),
                      value.st_size >= 0, value.st_size <= off_t(TransferLimits.aggregateBytes) else { throw TransferFailure.unsafeFile }
            } else {
                throw TransferFailure.unsafeFile
            }
        }
    }
    static func sealIngressFile(_ url: URL, maximum: Int) throws {
        guard let parent = try TransferFileIO.openDirectory(url.deletingLastPathComponent(), allowMissing: true, requirePrivate: true) else { return }
        var info = stat()
        guard fstatat(parent.fd, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return }
            throw TransferFailure.unsafeFile
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_uid == getuid(), info.st_nlink == 1 else { throw TransferFailure.unsafeFile }
        let fd = openat(parent.fd, url.lastPathComponent, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw TransferFailure.unsafeFile }
        defer { Darwin.close(fd) }
        let mode = info.st_mode & 0o7777
        guard mode == 0o600 || mode == 0o644 else { throw TransferFailure.unsafeFile }
        if mode == 0o644 {
            guard fchmod(fd, 0o600) == 0, fsync(fd) == 0 else { throw TransferFailure.storageUnavailable }
        }
        guard info.st_size >= 0, info.st_size <= off_t(maximum) else { throw TransferFailure.limitExceeded }
    }
    static func sealIncomingTree(_ root: URL) throws {
        guard let handle = try TransferFileIO.openDirectory(root, requirePrivate: false) else { throw TransferFailure.unavailable }
        var entries = 0
        var nodes: [(fd: Int32, directory: Bool, mode: mode_t)] = []
        defer { for node in nodes { Darwin.close(node.fd) } }
        try inventoryIncomingDirectory(handle.fd, depth: 0, entries: &entries, nodes: &nodes)
        // Only after the complete descriptor inventory succeeds may ingress
        // permissions be transitioned.  The open descriptors also close the
        // validation-to-chmod race on every component.
        for node in nodes {
            if node.directory {
                if node.mode == 0o755 { guard fchmod(node.fd, 0o700) == 0 else { throw TransferFailure.storageUnavailable } }
                guard fsync(node.fd) == 0 else { throw TransferFailure.storageUnavailable }
            } else if node.mode == 0o644 {
                guard fchmod(node.fd, 0o600) == 0, fsync(node.fd) == 0 else { throw TransferFailure.storageUnavailable }
            }
        }
    }

    private static func inventoryIncomingDirectory(_ fd: Int32, depth: Int, entries: inout Int,
                                                   nodes: inout [(fd: Int32, directory: Bool, mode: mode_t)]) throws {
        guard depth <= 4 else { throw TransferFailure.limitExceeded }
        var rootInfo = stat(); guard fstat(fd, &rootInfo) == 0 else { throw TransferFailure.unavailable }
        let rootMode = rootInfo.st_mode & 0o7777
        guard rootInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), rootInfo.st_uid == getuid(),
              rootMode == 0o700 || rootMode == 0o755 else { throw TransferFailure.unsafeFile }
        let retained = Darwin.dup(fd); guard retained >= 0 else { throw TransferFailure.unavailable }
        nodes.append((fd: retained, directory: true, mode: rootMode))
        let duplicate = Darwin.dup(fd); guard duplicate >= 0 else { throw TransferFailure.unavailable }
        guard let stream = fdopendir(duplicate) else { Darwin.close(duplicate); throw TransferFailure.unavailable }
        defer { closedir(stream) }
        while let entry = readdir(stream) {
            let name = TransferFileIO.directoryEntryName(entry)
            if name == "." || name == ".." { continue }
            entries += 1; guard entries <= 512 else { throw TransferFailure.limitExceeded }
            var value = stat(); guard fstatat(fd, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
                value.st_uid == getuid() else { throw TransferFailure.unsafeFile }
            let type = value.st_mode & mode_t(S_IFMT); let mode = value.st_mode & 0o7777
            if type == mode_t(S_IFDIR) {
                guard mode == 0o700 || mode == 0o755 else { throw TransferFailure.unsafeFile }
                let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC, 0)
                guard child >= 0 else { throw TransferFailure.unsafeFile }
                defer { Darwin.close(child) }
                try inventoryIncomingDirectory(child, depth: depth + 1, entries: &entries, nodes: &nodes)
            } else if type == mode_t(S_IFREG) {
                guard value.st_nlink == 1 else { throw TransferFailure.unsafeFile }
                guard mode == 0o600 || mode == 0o644 else { throw TransferFailure.unsafeFile }
                let child = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC, 0)
                guard child >= 0 else { throw TransferFailure.unsafeFile }
                nodes.append((fd: child, directory: false, mode: mode))
            } else {
                throw TransferFailure.unsafeFile
            }
        }
    }
    static func read(_ url: URL, maximum: Int) throws -> Data? {
        guard let parent = try TransferFileIO.openDirectory(url.deletingLastPathComponent(), allowMissing: true, requirePrivate: true) else { return nil }
        return try parent.read(url.lastPathComponent, maximum: maximum)
    }
    static func atomicWrite(_ data: Data, to url: URL, checkpoint: (@Sendable (SetupWriteCheckpoint) throws -> Void)?) throws {
        let targetDirectoryURL = url.deletingLastPathComponent()
        try ensureDirectory(targetDirectoryURL)
        // Retain the complete fixed descriptor chain.  Re-opening only the
        // final parent by path would permit a symlink swap in an intermediate
        // transfer component between validation and rename.
        guard let targetHandle = try TransferFileIO.openDirectory(targetDirectoryURL) else { throw TransferFailure.storageUnavailable }
        let targetDirectory = targetHandle.fd
        var existing = stat()
        if fstatat(targetDirectory, url.lastPathComponent, &existing, AT_SYMLINK_NOFOLLOW) == 0 {
            try TransferFileIO.validateFileForStorage(existing)
        } else if errno != ENOENT {
            throw TransferFailure.unsafeFile
        }

        // Immutable package generations never receive temporary children. A
        // crash can therefore leave a stale staging file outside `package`
        // without changing its closed inventory or requiring repair.
        let stagingDirectoryURL: URL = {
            var ancestor = targetDirectoryURL
            while ancestor.lastPathComponent != "package" && ancestor.path != ancestor.deletingLastPathComponent().path {
                ancestor.deleteLastPathComponent()
            }
            return ancestor.lastPathComponent == "package" ? ancestor.deletingLastPathComponent() : targetDirectoryURL
        }()
        let stagingDirectory: Int32
        var stagingHandle: _TransferDirectoryHandle?
        if stagingDirectoryURL.standardizedFileURL == targetDirectoryURL.standardizedFileURL {
            stagingDirectory = targetDirectory
        } else {
            guard let handle = try TransferFileIO.openDirectory(stagingDirectoryURL) else { throw TransferFailure.storageUnavailable }
            stagingHandle = handle
            stagingDirectory = handle.fd
        }
        // Keep the secondary parent descriptor alive through both rename and
        // fsync; the explicit read also documents that this is intentional.
        _ = stagingHandle
        let staging = ".gofly-\(UUID().uuidString.lowercased()).staging"
        let fd = openat(stagingDirectory, staging, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            throw TransferFailure.storageUnavailable
        }
        var renamed = false
        defer {
            Darwin.close(fd)
            if !renamed { unlinkat(stagingDirectory, staging, 0) }
            // targetHandle/stagingHandle retain every parent descriptor until
            // the rename and both directory fsyncs have completed.
        }
        guard fchmod(fd, 0o600) == 0 else { throw TransferFailure.storageUnavailable }
        try checkpoint?(.stagingSecured)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw TransferFailure.storageUnavailable }
                offset += n
            }
        }
        try checkpoint?(.contentsWritten)
        guard fsync(fd) == 0 else { throw TransferFailure.storageUnavailable }
        try checkpoint?(.stagingFlushed)
        try checkpoint?(.beforeRename)
        guard renameat(stagingDirectory, staging, targetDirectory, url.lastPathComponent) == 0 else { throw TransferFailure.storageUnavailable }
        renamed = true
        do {
            try checkpoint?(.afterRename)
            guard fsync(targetDirectory) == 0 else { throw TransferFailure.storageUnavailable }
            if stagingDirectory != targetDirectory { guard fsync(stagingDirectory) == 0 else { throw TransferFailure.storageUnavailable } }
            try checkpoint?(.parentDirectoryFlushed)
        } catch {
            throw TransferFailure.commitUnknown
        }
    }
    static func writePackageFile(_ data: Data, path: String, under root: URL) throws { let target = root.appendingPathComponent(path); try ensureDirectory(target.deletingLastPathComponent()); try atomicWrite(data, to: target, checkpoint: nil) }
    static func writeStable(_ data: Data, to target: URL) throws {
        if let existing = try read(target, maximum: max(data.count, 1)) {
            guard existing == data else { throw TransferFailure.artifactMismatch }
            return
        }
        try atomicWrite(data, to: target, checkpoint: nil)
    }
    static func pathExists(_ url: URL) -> Bool {
        var value = stat()
        return lstat(url.path, &value) == 0
    }
    static func orphanExists(_ root: URL, dataSetID: UUID) throws -> Bool {
        let generation = root.appendingPathComponent("exports/\(dataSetID.uuidString.lowercased())", isDirectory: true)
        // A dataset generation is immutable even when a prior terminal root
        // exists. Reusing it would permit changed input bytes to masquerade as
        // a replay; callers must choose a fresh dataset ID.
        return pathExists(generation)
    }
    static func openFile(_ url: URL, create: Bool) throws -> Int32? { guard !url.path.contains("/../") else { throw TransferFailure.unsafeFile }; let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC); if fd < 0 { if errno == ENOENT && !create { return nil }; if errno == ELOOP || errno == ENOTDIR { throw TransferFailure.unsafeFile }; throw TransferFailure.unavailable }; return fd }
    static func writeSessionSeed(cutline: TransferExportCutline, applicationSupport: URL) throws { let data = try SessionRecoveryCodec.encode(SessionRecoverySnapshot(mode: cutline.settings.mode, draft: cutline.draft, roundTripEnabled: cutline.settings.roundTripEnabled, joystickSpeed: cutline.settings.joystickSpeed, position: nil, activeMovement: nil, uncertainty: SessionMovementUncertainty(source: .unverifiedPreviousMovement))); let directory = cutline.projection.sessionDirectory; try ensureDirectory(directory); try atomicWrite(data, to: directory.appendingPathComponent("session.json"), checkpoint: nil) }
}

private extension TransferFileIO {
    static func validateFileForStorage(_ value: stat) throws { guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), value.st_uid == getuid(), value.st_nlink == 1, value.st_mode & 0o7777 == 0o600 else { throw TransferFailure.unsafeFile } }
}

private extension Optional {
    func unwrap(or error: Error) throws -> Wrapped { guard let self else { throw error }; return self }
}

private extension _SetupJSON {
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}
