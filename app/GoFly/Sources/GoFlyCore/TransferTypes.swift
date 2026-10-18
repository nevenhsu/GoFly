import Foundation

/// The user-data namespaces that may travel during a same-device reinstall.
public enum TransferCategory: String, Codable, CaseIterable, Sendable, Equatable {
    case favorites
    case routes
    case settings
}

/// Stable, user-safe failures for transfer data.  The values intentionally do
/// not include paths or untrusted file contents.
public enum TransferFailure: Error, Equatable, Sendable {
    case invalidInput
    case unsupportedVersion
    case unsafeFile
    case limitExceeded
    case identityMismatch
    case artifactMismatch
    case unavailable
    case storageUnavailable
    case commitUnknown
    case receiptCapacity
    case busy
    case sourceBusy
    case exportConflict
    case updateRequired
}

public enum TransferLimits {
    public static let manifestBytes = 262_144
    public static let requestBytes = 262_144
    public static let aggregateBytes = 167_772_160
    public static let artifactCount = 210
    public static let settingsBytes = 16_384
    public static let draftBytes = 4_194_304
    public static let historyCount = 128
}

public struct TransferArtifact: Sendable, Equatable {
    public let id: UUID
    public let path: String
    public let byteCount: Int64
    public let sha256: String

    public init(id: UUID, path: String, byteCount: Int64, sha256: String) throws {
        guard byteCount > 0,
              Self.isClosedPath(path),
              SetupValidation.isLowerHex(sha256, count: 64) else {
            throw TransferFailure.artifactMismatch
        }
        self.id = id
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    static func isClosedPath(_ path: String) -> Bool {
        let allowed = Set([
            "favorites/archive.json",
            "routes/imported/manifest.json",
            "routes/favorites/manifest.json",
            "routes/draft.json",
            "settings/preferences.json"
        ])
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let importedPayload = components.count == 3 && components[0] == "routes" && components[1] == "imported" && components[2].hasSuffix(".gpx")
        let favoritePayload = components.count == 3 && components[0] == "routes" && components[1] == "favorites" && components[2].hasSuffix(".route")
        let payload = importedPayload || favoritePayload
        guard (allowed.contains(path) || payload), !path.contains("\\"), !path.contains("%") else { return false }
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return false }
        if importedPayload {
            let stem = String(components.last!.dropLast(4))
            return UUID(uuidString: stem)?.uuidString == stem
        }
        if favoritePayload {
            let stem = String(components.last!.dropLast(6))
            return UUID(uuidString: stem)?.uuidString == stem
        }
        return true
    }
}

public struct TransferSettings: Sendable, Equatable {
    public static let schemaVersion = 1
    public let version: Int
    public let language: String
    public let appearance: String
    public let mode: SessionMapMode
    public let roundTripEnabled: Bool
    public let joystickSpeed: RouteSpeed

    public init(language: String, appearance: String, mode: SessionMapMode,
                roundTripEnabled: Bool, joystickSpeed: RouteSpeed) throws {
        guard ["system", "en", "zh-Hant", "zh-Hans"].contains(language),
              ["system", "light", "dark"].contains(appearance),
              joystickSpeed.kilometersPerHour >= 2,
              joystickSpeed.kilometersPerHour <= 100 else {
            throw TransferFailure.invalidInput
        }
        self.version = Self.schemaVersion
        self.language = language
        self.appearance = appearance
        self.mode = mode
        self.roundTripEnabled = roundTripEnabled
        self.joystickSpeed = joystickSpeed
    }
}

public struct TransferManifest: Sendable, Equatable {
    public static let schemaVersion = 1
    public let version: Int
    public let transferID: UUID
    public let dataSetID: UUID
    public let nonce: UUID
    public let sourceDeviceUDID: String
    public let destinationDeviceUDID: String
    public let sourceApp: SetupAppIdentity
    public let targetApp: SetupAppIdentity
    public let setupID: UUID
    public let categories: [TransferCategory]
    public let schemas: [String: Int]
    public let artifacts: [TransferArtifact]

    public init(transferID: UUID, dataSetID: UUID, nonce: UUID,
                sourceDeviceUDID: String, destinationDeviceUDID: String,
                sourceApp: SetupAppIdentity, targetApp: SetupAppIdentity,
                setupID: UUID, categories: [TransferCategory],
                artifacts: [TransferArtifact]) throws {
        guard SetupValidation.validUDID(sourceDeviceUDID),
              SetupValidation.validUDID(destinationDeviceUDID),
              sourceDeviceUDID == destinationDeviceUDID else {
            throw TransferFailure.identityMismatch
        }
        let canonical = TransferCategory.allCases
        guard categories == canonical.filter({ categories.contains($0) }),
              Set(categories).count == categories.count,
              Set(artifacts.map(\.id)).count == artifacts.count,
              Set(artifacts.map(\.path)).count == artifacts.count else {
            throw TransferFailure.invalidInput
        }
        guard artifacts.count <= TransferLimits.artifactCount else { throw TransferFailure.limitExceeded }
        guard artifacts.allSatisfy({ TransferArtifact.isClosedPath($0.path) }) else {
            throw TransferFailure.artifactMismatch
        }
        self.version = Self.schemaVersion
        self.transferID = transferID
        self.dataSetID = dataSetID
        self.nonce = nonce
        self.sourceDeviceUDID = sourceDeviceUDID
        self.destinationDeviceUDID = destinationDeviceUDID
        self.sourceApp = sourceApp
        self.targetApp = targetApp
        self.setupID = setupID
        self.categories = categories
        self.schemas = Dictionary(uniqueKeysWithValues: categories.map { ($0.rawValue, 1) })
        self.artifacts = artifacts
    }
}

public struct TransferInput: Sendable, Equatable {
    public let manifest: TransferManifest
    public let rawManifest: Data
    public let rawManifestSHA256: String

    public init(data: Data) throws {
        guard !data.isEmpty, data.count <= TransferLimits.manifestBytes else {
            throw TransferFailure.limitExceeded
        }
        let manifest = try TransferCodec.decodeManifest(data)
        self.manifest = manifest
        self.rawManifest = data
        self.rawManifestSHA256 = SetupValidation.sha256(data)
    }
}

public struct TransferCounts: Sendable, Equatable {
    public let favorites: Int
    public let importedRoutes: Int
    public let favoriteRoutes: Int
    public let draftNodes: Int
    public let gpxPoints: Int

    init(favorites: Int = 0, importedRoutes: Int = 0, favoriteRoutes: Int = 0,
         draftNodes: Int = 0, gpxPoints: Int = 0) {
        self.favorites = favorites
        self.importedRoutes = importedRoutes
        self.favoriteRoutes = favoriteRoutes
        self.draftNodes = draftNodes
        self.gpxPoints = gpxPoints
    }
}

public struct TransferArchiveSnapshot: Sendable, Equatable {
    public let manifest: Data
    public let payloads: [String: Data]

    public init(manifest: Data, payloads: [String: Data]) {
        self.manifest = manifest
        self.payloads = payloads
    }
}

public struct ValidatedTransferPackage: Sendable, Equatable {
    public let input: TransferInput
    public let counts: TransferCounts
    public let settings: TransferSettings?
    public let draft: RouteDraft?

    init(input: TransferInput, counts: TransferCounts,
         settings: TransferSettings?, draft: RouteDraft?) {
        self.input = input
        self.counts = counts
        self.settings = settings
        self.draft = draft
    }
}
