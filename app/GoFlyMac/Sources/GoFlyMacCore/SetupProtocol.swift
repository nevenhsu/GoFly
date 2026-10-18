import Foundation
import CoreFoundation

func setupFullMatch(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
}

public enum MacSetupAction: String, Codable, Sendable { case preflight, apply, status, resume }
public enum MacSetupSource: String, Codable, Sendable { case signedApp, project }

public enum MacSetupFailure: Error, Equatable, Sendable {
    case invalidRequest, invalidResponse, unavailable, cancelled, timeout
    case service(String)
}

public struct MacSetupOptions: Codable, Equatable, Sendable {
    public let source: MacSetupSource
    public let artifactPath: String?
    public let teamID: String
    public let allowProvisioningUpdates: Bool

    public init(source: MacSetupSource, artifactPath: String? = nil, teamID: String,
                allowProvisioningUpdates: Bool = false) throws {
        guard setupFullMatch(teamID, "^[A-Z0-9]{10}$") else {
            throw MacSetupFailure.invalidRequest
        }
        switch source {
        case .project:
            guard artifactPath == nil else { throw MacSetupFailure.invalidRequest }
        case .signedApp:
            guard let artifactPath, artifactPath.utf8.count <= 4_096,
                  artifactPath.hasPrefix("/"), !artifactPath.contains("\0"),
                  URL(fileURLWithPath: artifactPath).pathExtension == "app",
                  !allowProvisioningUpdates else { throw MacSetupFailure.invalidRequest }
        }
        self.source = source
        self.artifactPath = artifactPath
        self.teamID = teamID
        self.allowProvisioningUpdates = allowProvisioningUpdates
    }

    private enum CodingKeys: String, CodingKey { case source, artifactPath, teamID, allowProvisioningUpdates }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(source: values.decode(MacSetupSource.self, forKey: .source),
                      artifactPath: values.decodeIfPresent(String.self, forKey: .artifactPath),
                      teamID: values.decode(String.self, forKey: .teamID),
                      allowProvisioningUpdates: values.decode(Bool.self, forKey: .allowProvisioningUpdates))
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(source, forKey: .source)
        if let artifactPath { try values.encode(artifactPath, forKey: .artifactPath) }
        else { try values.encodeNil(forKey: .artifactPath) }
        try values.encode(teamID, forKey: .teamID)
        try values.encode(allowProvisioningUpdates, forKey: .allowProvisioningUpdates)
    }
}

public struct MacSetupRequest: Encodable, Sendable {
    public let `protocol` = 2
    public let operation = "setup"
    public let requestID: UUID
    public let setupID: UUID
    public let deviceID: String
    public let action: MacSetupAction
    public let options: MacSetupOptions?

    public init(action: MacSetupAction, setupID: UUID, deviceID: String,
                options: MacSetupOptions? = nil) throws {
        let normalized = deviceID.lowercased()
        guard setupFullMatch(normalized, "^(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})$"),
              ((action == .preflight || action == .apply) == (options != nil)) else {
            throw MacSetupFailure.invalidRequest
        }
        requestID = UUID()
        self.setupID = setupID
        self.deviceID = normalized
        self.action = action
        self.options = options
    }
}

public enum MacSetupStage: String, Decodable, Sendable {
    case preflight, artifact, pairing, install, support, handoff, complete
}
public enum MacSetupOutcome: String, Decodable, Sendable {
    case ready, inProgress, confirmed, unknown, failed
}

public struct MacSetupSnapshot: Equatable, Sendable {
    public let stage: MacSetupStage
    public let outcome: MacSetupOutcome
    public let canResume: Bool
    public let appBuild: String?
    public let teamID: String?
    public let expiresAt: String?
    public let receiptSHA256: String?
    public let installationConfirmed: Bool
    public let pairingImported: Bool
    public let supportObserved: Bool
    public let errorCode: String?

    public var failure: MacSetupFailure? { errorCode.map(MacSetupFailure.service) }

    public var isComplete: Bool {
        stage == .complete && outcome == .confirmed && installationConfirmed &&
            pairingImported && supportObserved && receiptSHA256 != nil && appBuild != nil && errorCode == nil
    }
}

public protocol MacSetupRunning: Sendable {
    func run(_ request: MacSetupRequest) async throws -> Data
}

public enum MacSetupResponseDecoder {
    private static let safeCodes: Set<String> = [
        "invalid-request", "protocol-mismatch", "configuration-invalid", "dependency-mismatch",
        "runtime-api-mismatch", "environment-not-ready", "device-disconnected", "trust-required",
        "developer-mode-required", "unsupported-os", "identity-mismatch", "app-already-installed",
        "signing-required", "signature-invalid", "artifact-mismatch", "support-unavailable",
        "pairing-unknown", "pairing-rejected", "handoff-unknown", "commit-unknown",
        "transaction-unknown", "transaction-conflict", "busy", "cancelled", "timeout",
        "storage-unavailable", "operation-failed"
    ]

    public static func decode(_ data: Data, for request: MacSetupRequest) throws -> MacSetupSnapshot {
        do {
            let root = try SetupWireJSON.object(data, integerKey: "protocol", integerValue: "2")
            guard keys(root, required: ["protocol", "operation", "action", "requestID", "setupID", "deviceID", "status", "payload"], optional: ["code"]),
                  let version = root["protocol"] as? NSNumber,
                  CFGetTypeID(version) != CFBooleanGetTypeID(), version == 2,
                  root["operation"] as? String == "setup",
                  root["action"] as? String == request.action.rawValue,
                  uuid(root["requestID"]) == request.requestID,
                  uuid(root["setupID"]) == request.setupID,
                  root["deviceID"] as? String == request.deviceID,
                  let status = root["status"] as? String, ["ok", "error"].contains(status),
                  let payload = root["payload"] as? [String: Any],
                  keys(payload, required: ["stage", "outcome", "canResume", "proof"],
                       optional: ["app", "teamID", "expiresAt", "receiptSHA256"]),
                  let stage = (payload["stage"] as? String).flatMap(MacSetupStage.init(rawValue:)),
                  let outcome = (payload["outcome"] as? String).flatMap(MacSetupOutcome.init(rawValue:)),
                  let canResume = boolean(payload["canResume"]),
                  let proof = payload["proof"] as? [String: Any],
                  keys(proof, required: ["installationConfirmed", "pairingImported", "supportObserved"]),
                  let installed = boolean(proof["installationConfirmed"]),
                  let paired = boolean(proof["pairingImported"]),
                  let support = boolean(proof["supportObserved"]) else { throw MacSetupFailure.invalidResponse }
            let code: String?
            if status == "error" {
                guard let value = root["code"] as? String, safeCodes.contains(value) else {
                    throw MacSetupFailure.invalidResponse
                }
                code = value
            } else {
                guard root["code"] == nil else { throw MacSetupFailure.invalidResponse }
                code = nil
            }
            let team = try optionalString(payload["teamID"])
            let expiry = try optionalString(payload["expiresAt"])
            let receipt = try optionalString(payload["receiptSHA256"])
            if let team, !setupFullMatch(team, "^[A-Z0-9]{10}$") {
                throw MacSetupFailure.invalidResponse
            }
            if let expiry, !validDate(expiry) { throw MacSetupFailure.invalidResponse }
            if let receipt, !hash(receipt) { throw MacSetupFailure.invalidResponse }
            let build: String?
            if let raw = payload["app"], !(raw is NSNull) {
                guard let app = raw as? [String: Any],
                      keys(app, required: ["bundleID", "build", "profileSHA256", "executableSHA256"]),
                      app["bundleID"] as? String == "com.neven.gofly",
                      let value = app["build"] as? String, !value.isEmpty, value.utf8.count <= 128,
                      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                      let profile = app["profileSHA256"] as? String, hash(profile),
                      let executable = app["executableSHA256"] as? String, hash(executable) else {
                    throw MacSetupFailure.invalidResponse
                }
                build = value
            } else { build = nil }
            if stage == .preflight, installed || paired || support { throw MacSetupFailure.invalidResponse }
            if request.action == .preflight, stage != .preflight { throw MacSetupFailure.invalidResponse }
            if stage == .complete, outcome == .confirmed {
                guard !canResume, installed, paired, support,
                      receipt != nil, build != nil, team != nil, expiry != nil else {
                    throw MacSetupFailure.invalidResponse
                }
            }
            return MacSetupSnapshot(stage: stage, outcome: outcome, canResume: canResume, appBuild: build,
                                    teamID: team, expiresAt: expiry, receiptSHA256: receipt,
                                    installationConfirmed: installed, pairingImported: paired,
                                    supportObserved: support, errorCode: code)
        } catch { throw MacSetupFailure.invalidResponse }
    }

    private static func keys(_ object: [String: Any], required: Set<String>, optional: Set<String> = []) -> Bool {
        required.isSubset(of: Set(object.keys)) && Set(object.keys).isSubset(of: required.union(optional))
    }
    private static func uuid(_ value: Any?) -> UUID? {
        guard let string = value as? String, string.utf8.count == 36 else { return nil }
        return UUID(uuidString: string)
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    private static func hash(_ value: String) -> Bool {
        setupFullMatch(value, "^[0-9a-f]{64}$")
    }
    private static func optionalString(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String else { throw MacSetupFailure.invalidResponse }
        return string
    }
    private static func validDate(_ value: String) -> Bool {
        guard value.utf8.count <= 40, value.hasSuffix("Z") else { return false }
        let parser = ISO8601DateFormatter()
        if parser.date(from: value) != nil { return true }
        parser.formatOptions.insert(.withFractionalSeconds)
        return parser.date(from: value) != nil
    }
}
