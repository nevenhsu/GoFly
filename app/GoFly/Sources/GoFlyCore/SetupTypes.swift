import CryptoKit
import Foundation

/// The supported on-device support image families.
public enum SetupSupportMethod: String, Codable, CaseIterable, Sendable {
    case personalized
    case cryptex
}
/// Stable, user-safe setup failure values. Dependency and subprocess errors never cross this boundary.
public enum SetupFailure: Error, Equatable, Sendable {
    case invalidInput
    case unsupportedVersion
    case unsafeFile
    case limitExceeded
    case identityMismatch
    case artifactMismatch
    case pairingUnknown
    case pairingRejected
    case storageUnavailable
    case commitUnknown
    case receiptCapacity
}

public enum SetupWriteCheckpoint: Equatable, Sendable {
    case stagingSecured
    case contentsWritten
    case stagingFlushed
    case beforeRename
    case afterRename
    case parentDirectoryFlushed
}

public enum SetupPairingObservation: Codable, Equatable, Sendable {
    case absent
    case invalid
    case verified(expectedDeviceUDID: String, sha256: String)
}

extension SetupPairingObservation {
    private enum CodingKeys: String, CodingKey { case kind, expectedDeviceUDID, sha256 }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "absent": self = .absent
        case "invalid": self = .invalid
        case "verified": self = .verified(expectedDeviceUDID: try values.decode(String.self, forKey: .expectedDeviceUDID), sha256: try values.decode(String.self, forKey: .sha256))
        default: throw SetupFailure.invalidInput
        }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .absent: try values.encode("absent", forKey: .kind)
        case .invalid: try values.encode("invalid", forKey: .kind)
        case .verified(let expectedDeviceUDID, let sha256):
            try values.encode("verified", forKey: .kind); try values.encode(expectedDeviceUDID, forKey: .expectedDeviceUDID); try values.encode(sha256, forKey: .sha256)
        }
    }
}

public enum SetupV1InputObservation: Equatable, Sendable {
    case absent
    case exact
    case malformedOrMismatched
}

public enum SetupV1ReceiptObservation: Equatable, Sendable {
    case absent
    case success
    case rejectedOrMalformed
}

public struct SetupPairingEvidence: Equatable, Sendable {
    public let stored: SetupPairingObservation
    public let input: SetupV1InputObservation
    public let receipt: SetupV1ReceiptObservation

    public init(stored: SetupPairingObservation,
                input: SetupV1InputObservation,
                receipt: SetupV1ReceiptObservation) {
        self.stored = stored
        self.input = input
        self.receipt = receipt
    }

    public var inputObservation: SetupV1InputObservation { input }
    public var receiptObservation: SetupV1ReceiptObservation { receipt }
}

public protocol SetupPairingAccess: Sendable {
    func prepare() throws
    func observeStoredPairing(expectedDeviceUDID: String) throws -> SetupPairingObservation
    func observe(for input: SetupInput) throws -> SetupPairingEvidence
    func consumeExactPending(for input: SetupInput) throws
}

public enum SetupBootstrapResult: Equatable, Sendable {
    case ordinaryStartup
    case waitingForMac(SetupReadbackRequest)
    case completed(SetupReceipt)
    case blocked(SetupFailure)
}

public struct SetupAppIdentity: Codable, Equatable, Sendable {
    public static let formalBundleID = "com.neven.gofly"
    public let bundleID: String
    public let build: String
    public let profileSHA256: String
    public let executableSHA256: String

    public init(bundleID: String, build: String, profileSHA256: String, executableSHA256: String) throws {
        guard Self.valid(bundleID: bundleID, build: build, profileSHA256: profileSHA256,
                         executableSHA256: executableSHA256) else { throw SetupFailure.identityMismatch }
        self.bundleID = bundleID
        self.build = build
        self.profileSHA256 = profileSHA256
        self.executableSHA256 = executableSHA256
    }

    public static func == (lhs: SetupAppIdentity, rhs: SetupAppIdentity) -> Bool {
        lhs.bundleID == rhs.bundleID && lhs.build == rhs.build &&
            lhs.profileSHA256 == rhs.profileSHA256 && lhs.executableSHA256 == rhs.executableSHA256
    }

    static func valid(bundleID: String, build: String, profileSHA256: String, executableSHA256: String) -> Bool {
        bundleID == formalBundleID && !build.isEmpty && build.utf8.count <= 128 &&
            build.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } &&
            SetupValidation.isLowerHex(profileSHA256, count: 64) &&
            SetupValidation.isLowerHex(executableSHA256, count: 64)
    }
}

public struct SetupArtifact: Codable, Equatable, Sendable {
    public let id: UUID
    public let filename: String
    public let byteCount: Int64
    public let sha256: String

    public init(id: UUID, filename: String, byteCount: Int64, sha256: String) throws {
        guard Self.validFilename(filename), byteCount > 0,
              SetupValidation.isLowerHex(sha256, count: 64) else { throw SetupFailure.artifactMismatch }
        self.id = id
        self.filename = filename
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    static func validFilename(_ value: String) -> Bool {
        ["MountMethod", "BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache",
         "Image.dmg.cryptex_info", "Image.dmg.root_hash"].contains(value) &&
            !value.contains("/") && !value.contains("\\") && !value.contains("..") &&
            !value.hasPrefix("/")
    }
}

public struct SetupManifest: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumBytes = 256 * 1_024
    public static let maximumGenerationBytes: Int64 = 4 * 1_024 * 1_024 * 1_024
    public let version: Int
    public let setupID: UUID
    public let nonce: UUID
    public let expectedDeviceUDID: String
    public let pairingTransactionID: UUID
    public let pairingSHA256: String
    public let app: SetupAppIdentity
    public let teamID: String
    public let signingExpiry: String
    public let deviceOS: String
    public let method: SetupSupportMethod
    public let artifacts: [SetupArtifact]

    public init(version: Int = Self.schemaVersion, setupID: UUID, nonce: UUID,
                expectedDeviceUDID: String, pairingTransactionID: UUID, pairingSHA256: String,
                app: SetupAppIdentity, teamID: String, signingExpiry: String, deviceOS: String,
                method: SetupSupportMethod, artifacts: [SetupArtifact]) throws {
        var totalBytes: Int64 = 0
        for artifact in artifacts {
            guard artifact.byteCount > 0,
                  artifact.byteCount <= Self.maximumGenerationBytes,
                  totalBytes <= Self.maximumGenerationBytes - artifact.byteCount else { throw SetupFailure.limitExceeded }
            totalBytes += artifact.byteCount
        }
        guard version == Self.schemaVersion,
              SetupValidation.validUDID(expectedDeviceUDID),
              SetupValidation.isLowerHex(pairingSHA256, count: 64),
              teamID.count == 10, teamID.unicodeScalars.allSatisfy({
                  ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90)
              }),
              SetupValidation.validISO8601(signingExpiry),
              SetupValidation.validOS(deviceOS),
              SetupValidation.method(method, supports: deviceOS),
              !artifacts.isEmpty,
              Set(artifacts.map(\.id)).count == artifacts.count,
              Set(artifacts.map(\.filename)).count == artifacts.count,
              totalBytes <= Self.maximumGenerationBytes,
              Set(Self.requiredNames(method)).isSubset(of: Set(artifacts.map(\.filename))) else {
            throw SetupFailure.invalidInput
        }
        let allowed = Set(Self.requiredNames(method))
        guard Set(artifacts.map(\.filename)) == allowed else { throw SetupFailure.artifactMismatch }
        let mount = artifacts.first(where: { $0.filename == "MountMethod" })
        guard let mount,
              mount.byteCount == Int64(method.rawValue.utf8.count),
              mount.sha256 == SetupValidation.sha256(Data(method.rawValue.utf8)) else { throw SetupFailure.artifactMismatch }
        self.version = version; self.setupID = setupID; self.nonce = nonce
        self.expectedDeviceUDID = expectedDeviceUDID.lowercased()
        self.pairingTransactionID = pairingTransactionID; self.pairingSHA256 = pairingSHA256
        self.app = app; self.teamID = teamID; self.signingExpiry = signingExpiry
        self.deviceOS = deviceOS; self.method = method; self.artifacts = artifacts
    }

    static func requiredNames(_ method: SetupSupportMethod) -> [String] {
        switch method {
        case .personalized: return ["MountMethod", "BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"]
        case .cryptex: return ["MountMethod", "BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache", "Image.dmg.cryptex_info", "Image.dmg.root_hash"]
        }
    }
}

public struct SetupInput: Equatable, Sendable {
    public let manifest: SetupManifest
    public let rawManifestSHA256: String
    public let rawData: Data

    public init(data: Data) throws {
        guard !data.isEmpty, data.count <= SetupManifest.maximumBytes else { throw SetupFailure.limitExceeded }
        let value = try _SetupJSON.parse(data)
        let manifest = try SetupManifest.decode(value)
        self.manifest = manifest
        self.rawManifestSHA256 = SetupValidation.sha256(data)
        self.rawData = data
    }

    public init(manifest: SetupManifest) throws {
        let data = try SetupCodec.encodeManifest(manifest)
        try self.init(data: data)
    }

    public func encoded() throws -> Data { rawData }
    public var data: Data { rawData }
}

public struct SetupReadbackRequest: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public let version: Int
    public let setupID: UUID
    public let nonce: UUID
    public let expectedDeviceUDID: String
    public let app: SetupAppIdentity

    public init(version: Int = Self.schemaVersion, setupID: UUID, nonce: UUID,
                expectedDeviceUDID: String, app: SetupAppIdentity) throws {
        guard version == Self.schemaVersion, SetupValidation.validUDID(expectedDeviceUDID) else { throw SetupFailure.invalidInput }
        self.version = version; self.setupID = setupID; self.nonce = nonce
        self.expectedDeviceUDID = expectedDeviceUDID.lowercased(); self.app = app
    }

    public func encoded() throws -> Data { try SetupCodec.encodeRequest(self) }
}

public struct SetupReadbackReceipt: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public let version: Int
    public let setupID: UUID
    public let nonce: UUID
    public let expectedDeviceUDID: String
    public let app: SetupAppIdentity
    public let pairing: SetupPairingObservation

    public init(version: Int = Self.schemaVersion, setupID: UUID, nonce: UUID,
                expectedDeviceUDID: String, app: SetupAppIdentity,
                pairing: SetupPairingObservation) throws {
        guard version == Self.schemaVersion, SetupValidation.validUDID(expectedDeviceUDID) else { throw SetupFailure.invalidInput }
        if case .verified(let observed, let hash) = pairing {
            guard observed.lowercased() == expectedDeviceUDID.lowercased(),
                  SetupValidation.validUDID(observed),
                  SetupValidation.isLowerHex(hash, count: 64) else {
                throw SetupFailure.pairingUnknown
            }
        }
        self.version = version; self.setupID = setupID; self.nonce = nonce
        self.expectedDeviceUDID = expectedDeviceUDID.lowercased(); self.app = app; self.pairing = pairing
    }

    public func encoded() throws -> Data { try SetupCodec.encodeReceipt(self) }
}

public struct SetupReceipt: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public let version: Int
    public let setupID: UUID
    public let nonce: UUID
    public let expectedDeviceUDID: String
    public let rawManifestSHA256: String
    public let pairingTransactionID: UUID
    public let pairingSHA256: String
    public let app: SetupAppIdentity
    public let teamID: String
    public let signingExpiry: String
    public let deviceOS: String
    public let method: SetupSupportMethod
    public let generationID: UUID
    public let artifacts: [SetupArtifact]
    public let status: String

    init(manifest: SetupManifest, rawManifestSHA256: String) throws {
        guard SetupValidation.isLowerHex(rawManifestSHA256, count: 64) else { throw SetupFailure.invalidInput }
        version = Self.schemaVersion; setupID = manifest.setupID; nonce = manifest.nonce
        expectedDeviceUDID = manifest.expectedDeviceUDID; self.rawManifestSHA256 = rawManifestSHA256
        pairingTransactionID = manifest.pairingTransactionID; pairingSHA256 = manifest.pairingSHA256
        app = manifest.app; teamID = manifest.teamID; signingExpiry = manifest.signingExpiry
        deviceOS = manifest.deviceOS; method = manifest.method; generationID = manifest.setupID
        artifacts = manifest.artifacts; status = "committed"
    }
}

public struct SetupActivationRecord: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumReceipts = 128
    public let version: Int
    public let activeSetupID: UUID?
    public let receipts: [SetupReceipt]

    public init(version: Int = Self.schemaVersion, activeSetupID: UUID?, receipts: [SetupReceipt]) throws {
        guard version == Self.schemaVersion, receipts.count <= Self.maximumReceipts,
              receipts.allSatisfy({ $0.status == "committed" }),
              Set(receipts.map(\.setupID)).count == receipts.count else { throw SetupFailure.invalidInput }
        if let activeSetupID { guard receipts.contains(where: { $0.setupID == activeSetupID }) else { throw SetupFailure.invalidInput } }
        self.version = version; self.activeSetupID = activeSetupID; self.receipts = receipts
    }
}

enum SetupValidation {
    static func isLowerHex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) })
    }
    static func validUDID(_ value: String) -> Bool {
        let v = value.lowercased()
        let forty = v.count == 40 && v.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) })
        let compact = v.count == 25 && v.prefix(8).utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }) &&
            v.dropFirst(8).first == "-" && v.dropFirst(9).utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) })
        return v == value && (forty || compact)
    }
    static func validOS(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return (2...3).contains(parts.count) && parts.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
        }
    }
    static func method(_ method: SetupSupportMethod, supports os: String) -> Bool {
        let parts = os.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2, parts[0] >= 26 else { return false }
        if parts[0] > 26 { return method == .cryptex }
        return parts[1] < 4 ? method == .personalized : method == .cryptex
    }
    static func validISO8601(_ value: String) -> Bool {
        guard value.hasSuffix("Z") else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

// MARK: - Strict JSON value reader

enum _SetupJSON {
    case object([(String, _SetupJSON)])
    case array([_SetupJSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    static func parse(_ data: Data) throws -> _SetupJSON {
        var parser = _SetupJSONParser(data)
        let value = try parser.value()
        try parser.finish()
        return value
    }
    func object(_ name: String) throws -> _SetupJSON {
        guard case .object(let pairs) = self else { throw SetupFailure.invalidInput }
        let matches = pairs.filter { $0.0 == name }
        guard matches.count == 1 else { throw SetupFailure.invalidInput }
        return matches[0].1
    }
    func requireObjectKeys(_ names: Set<String>) throws {
        guard case .object(let pairs) = self else { throw SetupFailure.invalidInput }
        let actual = Set(pairs.map(\.0))
        guard actual == names, actual.count == pairs.count else { throw SetupFailure.invalidInput }
    }
    func string() throws -> String { guard case .string(let value) = self else { throw SetupFailure.invalidInput }; return value }
    func bool() throws -> Bool { guard case .bool(let value) = self else { throw SetupFailure.invalidInput }; return value }
    func int() throws -> Int { guard case .number(let value) = self, let result = Int(value), !value.contains(".") && !value.contains("e") && !value.contains("E") else { throw SetupFailure.invalidInput }; return result }
    func int64() throws -> Int64 { guard case .number(let value) = self, let result = Int64(value), !value.contains(".") && !value.contains("e") && !value.contains("E") else { throw SetupFailure.invalidInput }; return result }
    func array() throws -> [_SetupJSON] { guard case .array(let value) = self else { throw SetupFailure.invalidInput }; return value }
}

private struct _SetupJSONParser {
    private static let maximumDepth = 64
    let bytes: [UInt8]
    var index = 0
    init(_ data: Data) { bytes = Array(data) }
    mutating func finish() throws { skipWhitespace(); guard index == bytes.count else { throw SetupFailure.invalidInput } }
    mutating func value() throws -> _SetupJSON {
        try value(depth: 0)
    }
    mutating func value(depth: Int) throws -> _SetupJSON {
        guard depth <= Self.maximumDepth else { throw SetupFailure.limitExceeded }
        skipWhitespace(); guard index < bytes.count else { throw SetupFailure.invalidInput }
        switch bytes[index] {
        case 123: return try object(depth: depth)
        case 91: return try array(depth: depth)
        case 34: return .string(try string())
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        case 45, 48...57: return .number(try number())
        default: throw SetupFailure.invalidInput
        }
    }
    mutating func object(depth: Int) throws -> _SetupJSON {
        index += 1; skipWhitespace(); var pairs: [(String, _SetupJSON)] = []
        if index < bytes.count, bytes[index] == 125 { index += 1; return .object(pairs) }
        while true {
            skipWhitespace(); guard index < bytes.count, bytes[index] == 34 else { throw SetupFailure.invalidInput }
            let key = try string(); skipWhitespace(); guard consume(58) else { throw SetupFailure.invalidInput }
            pairs.append((key, try value(depth: depth + 1))); skipWhitespace()
            if consume(125) { return .object(pairs) }
            guard consume(44) else { throw SetupFailure.invalidInput }
        }
    }
    mutating func array(depth: Int) throws -> _SetupJSON {
        index += 1; skipWhitespace(); var values: [_SetupJSON] = []
        if index < bytes.count, bytes[index] == 93 { index += 1; return .array(values) }
        while true {
            values.append(try value(depth: depth + 1)); skipWhitespace()
            if consume(93) { return .array(values) }
            guard consume(44) else { throw SetupFailure.invalidInput }
        }
    }
    mutating func string() throws -> String {
        guard consume(34) else { throw SetupFailure.invalidInput }
        let start = index - 1; var escaped = false
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte < 0x20 && !escaped { throw SetupFailure.invalidInput }
            if byte == 34 && !escaped {
                let data = Data(self.bytes[start..<index])
                guard let result = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else { throw SetupFailure.invalidInput }
                return result
            }
            if byte == 92 { escaped.toggle() } else { escaped = false }
        }
        throw SetupFailure.invalidInput
    }
    mutating func number() throws -> String {
        let start = index
        if bytes[index] == 45 { index += 1 }
        guard index < bytes.count else { throw SetupFailure.invalidInput }
        if bytes[index] == 48 { index += 1 } else {
            guard bytes[index] >= 49, bytes[index] <= 57 else { throw SetupFailure.invalidInput }
            while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 { index += 1 }
        }
        if index < bytes.count, bytes[index] == 46 {
            index += 1; guard index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 else { throw SetupFailure.invalidInput }
            while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 { index += 1 }
        }
        if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
            index += 1; if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            guard index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 else { throw SetupFailure.invalidInput }
            while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 { index += 1 }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }
    mutating func literal(_ value: String) throws { guard bytes[index..<min(bytes.count, index + value.utf8.count)].elementsEqual(value.utf8) else { throw SetupFailure.invalidInput }; index += value.utf8.count }
    mutating func consume(_ byte: UInt8) -> Bool { guard index < bytes.count, bytes[index] == byte else { return false }; index += 1; return true }
    mutating func skipWhitespace() { while index < bytes.count && (bytes[index] == 32 || bytes[index] == 9 || bytes[index] == 10 || bytes[index] == 13) { index += 1 } }
}
