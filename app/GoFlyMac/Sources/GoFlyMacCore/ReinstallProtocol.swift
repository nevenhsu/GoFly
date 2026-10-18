import CoreFoundation
import Foundation

public enum MacReinstallCategory: String, Codable, CaseIterable, Sendable { case favorites, routes, settings }
public enum MacReinstallAction: String, Codable, Sendable { case preflight, apply, status, resume, abandon }
public enum MacReinstallStage: String, Sendable { case preflight, artifact, source, backup, seal, uninstall, install, support, restore, complete, abandon }
public enum MacReinstallCategoryState: String, Sendable { case waiting, validating, committed, failed }
public enum MacReinstallFailure: Error, Equatable, Sendable {
    case invalidRequest, invalidResponse, unavailable, cancelled, timeout
    case service(String)
}

public struct MacReinstallOptions: Encodable, Equatable, Sendable {
    public let source: MacSetupSource
    public let artifactPath: String?
    public let teamID: String
    public let allowProvisioningUpdates: Bool
    public let categories: [MacReinstallCategory]

    public init(source: MacSetupSource, artifactPath: String? = nil, teamID: String,
                allowProvisioningUpdates: Bool = false, categories: [MacReinstallCategory]) throws {
        guard categories == MacReinstallCategory.allCases.filter(categories.contains) else {
            throw MacReinstallFailure.invalidRequest
        }
        do {
            let base = try MacSetupOptions(source: source, artifactPath: artifactPath, teamID: teamID,
                                           allowProvisioningUpdates: allowProvisioningUpdates)
            self.source = base.source; self.artifactPath = base.artifactPath
            self.teamID = base.teamID; self.allowProvisioningUpdates = base.allowProvisioningUpdates
            self.categories = categories
        } catch { throw MacReinstallFailure.invalidRequest }
    }

    private enum CodingKeys: String, CodingKey { case source, artifactPath, teamID, allowProvisioningUpdates, categories }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(source, forKey: .source)
        if let artifactPath { try values.encode(artifactPath, forKey: .artifactPath) }
        else { try values.encodeNil(forKey: .artifactPath) }
        try values.encode(teamID, forKey: .teamID)
        try values.encode(allowProvisioningUpdates, forKey: .allowProvisioningUpdates)
        try values.encode(categories, forKey: .categories)
    }
}

public struct MacReinstallRequest: Encodable, Sendable {
    public let requestID: UUID
    public let transferID: UUID
    public let deviceID: String
    public let action: MacReinstallAction
    public let options: MacReinstallOptions?

    public init(action: MacReinstallAction, transferID: UUID, deviceID: String,
                options: MacReinstallOptions? = nil, requestID: UUID = UUID()) throws {
        guard setupFullMatch(deviceID, "^(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})$"),
              ((action == .preflight || action == .apply) == (options != nil)) else {
            throw MacReinstallFailure.invalidRequest
        }
        self.requestID = requestID; self.transferID = transferID; self.deviceID = deviceID
        self.action = action; self.options = options
    }

    private enum CodingKeys: String, CodingKey { case `protocol`, operation, requestID, transferID, deviceID, action, options }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(3, forKey: .protocol); try values.encode("reinstall", forKey: .operation)
        try values.encode(requestID.uuidString.lowercased(), forKey: .requestID)
        try values.encode(transferID.uuidString.lowercased(), forKey: .transferID)
        try values.encode(deviceID, forKey: .deviceID); try values.encode(action, forKey: .action)
        if let options { try values.encode(options, forKey: .options) }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(self)
        guard bytes.count <= 32_768 else { throw MacReinstallFailure.invalidRequest }
        return bytes
    }
}

public struct MacReinstallCounts: Equatable, Sendable {
    public let favorites: Int
    public let importedRoutes: Int
    public let favoriteRoutes: Int
    public let draftNodes: Int
    public let gpxPoints: Int
}
public struct MacReinstallCategoryProgress: Equatable, Sendable {
    public let category: MacReinstallCategory
    public let state: MacReinstallCategoryState
    public let receiptSHA256: String?
}
public struct MacReinstallProof: Equatable, Sendable {
    public let backupValidated: Bool
    public let sourceSealed: Bool
    public let removalConfirmed: Bool
    public let installationConfirmed: Bool
    public let pairingImported: Bool
    public let supportObserved: Bool
    public let restoreCommitted: Bool
    public var isComplete: Bool {
        backupValidated && sourceSealed && removalConfirmed && installationConfirmed &&
        pairingImported && supportObserved && restoreCommitted
    }
}
public struct MacReinstallPayload: Equatable, Sendable {
    public let stage: MacReinstallStage
    public let outcome: MacSetupOutcome
    public let canResume: Bool
    public let canAbandon: Bool
    public let proof: MacReinstallProof
    public let categories: [MacReinstallCategoryProgress]
    public let counts: MacReinstallCounts?
    public let appBuild: String?
    public let teamID: String?
    public let expiresAt: String?
    public let receiptSHA256: String?
    public let errorCode: String?
    public var isComplete: Bool {
        stage == .complete && outcome == .confirmed && proof.isComplete &&
        categories.allSatisfy { $0.state == .committed } && counts != nil &&
        receiptSHA256 != nil && !canResume && !canAbandon && errorCode == nil
    }
    public var isAbandoned: Bool { stage == .abandon && outcome == .confirmed && errorCode == nil }
}
public protocol MacReinstallRunning: Sendable {
    func run(_ request: MacReinstallRequest) async throws -> Data
}
public enum MacReinstallResponseDecoder {
    public static func decode(_ data: Data, for request: MacReinstallRequest,
                              selectedCategories: [MacReinstallCategory]) throws -> MacReinstallPayload {
        do {
            guard selectedCategories == MacReinstallCategory.allCases.filter(selectedCategories.contains) else { throw MacReinstallFailure.invalidResponse }
            let root = try SetupWireJSON.object(data, integerKey: "protocol", integerValue: "3")
            try ReinstallWireValues.requireIntegerTokens(data)
            guard ReinstallWireValues.keys(root, required: ["protocol","requestID","operation","action","transferID","deviceID","status","payload"], optional: ["code"]),
                  root["operation"] as? String == "reinstall",
                  root["action"] as? String == request.action.rawValue,
                  ReinstallWireValues.uuid(root["requestID"]) == request.requestID,
                  ReinstallWireValues.uuid(root["transferID"]) == request.transferID,
                  root["deviceID"] as? String == request.deviceID,
                  let status = root["status"] as? String, ["ok","error"].contains(status),
                  let payload = root["payload"] as? [String:Any],
                  ReinstallWireValues.keys(payload, required: ["stage","outcome","canResume","canAbandon","proof","categories","counts"], optional: ["app","teamID","expiresAt","receiptSHA256"]),
                  let stage = (payload["stage"] as? String).flatMap(MacReinstallStage.init(rawValue:)),
                  let outcome = (payload["outcome"] as? String).flatMap(MacSetupOutcome.init(rawValue:)),
                  let canResume = ReinstallWireValues.boolean(payload["canResume"]),
                  let canAbandon = ReinstallWireValues.boolean(payload["canAbandon"]),
                  let rawProof = payload["proof"] as? [String:Any],
                  ReinstallWireValues.keys(rawProof, required: ReinstallWireValues.proofKeys),
                  let backup = ReinstallWireValues.boolean(rawProof["backupValidated"]),
                  let sealed = ReinstallWireValues.boolean(rawProof["sourceSealed"]),
                  let removed = ReinstallWireValues.boolean(rawProof["removalConfirmed"]),
                  let installed = ReinstallWireValues.boolean(rawProof["installationConfirmed"]),
                  let paired = ReinstallWireValues.boolean(rawProof["pairingImported"]),
                  let support = ReinstallWireValues.boolean(rawProof["supportObserved"]),
                  let restored = ReinstallWireValues.boolean(rawProof["restoreCommitted"]),
                  let rawCategories = payload["categories"] as? [[String:Any]] else { throw MacReinstallFailure.invalidResponse }
            let code: String?
            if status == "error" {
                guard let value = root["code"] as? String, ReinstallWireValues.safeCodes.contains(value) else { throw MacReinstallFailure.invalidResponse }
                code = value
            } else {
                guard root["code"] == nil else { throw MacReinstallFailure.invalidResponse }
                code = nil
            }
            let proof = MacReinstallProof(backupValidated: backup, sourceSealed: sealed, removalConfirmed: removed,
                installationConfirmed: installed, pairingImported: paired, supportObserved: support, restoreCommitted: restored)
            let categories = try rawCategories.map { raw -> MacReinstallCategoryProgress in
                guard ReinstallWireValues.keys(raw, required: ["category","state","receiptSHA256"]),
                      let category = (raw["category"] as? String).flatMap(MacReinstallCategory.init(rawValue:)),
                      let state = (raw["state"] as? String).flatMap(MacReinstallCategoryState.init(rawValue:)) else { throw MacReinstallFailure.invalidResponse }
                let receipt: String?
                if state == .committed {
                    guard let value = raw["receiptSHA256"] as? String, ReinstallWireValues.hash(value) else { throw MacReinstallFailure.invalidResponse }
                    receipt = value
                } else {
                    guard raw["receiptSHA256"] is NSNull else { throw MacReinstallFailure.invalidResponse }
                    receipt = nil
                }
                return MacReinstallCategoryProgress(category: category, state: state, receiptSHA256: receipt)
            }
            let categoryIDs = categories.map(\.category)
            guard categoryIDs == MacReinstallCategory.allCases.filter(categoryIDs.contains) else { throw MacReinstallFailure.invalidResponse }
            let defaultError = code != nil && stage == .preflight && outcome == .unknown &&
                rawProof.values.allSatisfy { ReinstallWireValues.boolean($0) == false } &&
                rawCategories.isEmpty && payload["counts"] is NSNull
            guard categoryIDs == selectedCategories || defaultError else { throw MacReinstallFailure.invalidResponse }
            let counts: MacReinstallCounts?
            if payload["counts"] is NSNull { counts = nil }
            else {
                guard let raw = payload["counts"] as? [String:Any],
                      ReinstallWireValues.keys(raw, required: ["favorites","importedRoutes","favoriteRoutes","draftNodes","gpxPoints"]),
                      let favorites = ReinstallWireValues.integer(raw["favorites"], maximum: 100),
                      let imported = ReinstallWireValues.integer(raw["importedRoutes"], maximum: 100),
                      let routes = ReinstallWireValues.integer(raw["favoriteRoutes"], maximum: 100),
                      let nodes = ReinstallWireValues.integer(raw["draftNodes"], maximum: 27),
                      let points = ReinstallWireValues.integer(raw["gpxPoints"], maximum: 2_010_000),
                      selectedCategories.contains(.favorites) || favorites == 0,
                      selectedCategories.contains(.routes) || (imported == 0 && routes == 0 && nodes == 0 && points == 0) else { throw MacReinstallFailure.invalidResponse }
                counts = MacReinstallCounts(favorites: favorites, importedRoutes: imported, favoriteRoutes: routes, draftNodes: nodes, gpxPoints: points)
            }
            let team = try ReinstallWireValues.optionalString(payload, "teamID")
            let expiry = try ReinstallWireValues.optionalString(payload, "expiresAt")
            let receipt = try ReinstallWireValues.optionalString(payload, "receiptSHA256")
            if let team, !setupFullMatch(team, "^[A-Z0-9]{10}$") { throw MacReinstallFailure.invalidResponse }
            if let expiry, !ReinstallWireValues.validDate(expiry) { throw MacReinstallFailure.invalidResponse }
            if let receipt, !ReinstallWireValues.hash(receipt) { throw MacReinstallFailure.invalidResponse }
            let build: String?
            if let value = payload["app"] {
                guard let app = value as? [String:Any],
                      ReinstallWireValues.keys(app, required: ["bundleID","build","profileSHA256","executableSHA256"]),
                      app["bundleID"] as? String == "com.neven.gofly",
                      let appBuild = app["build"] as? String, !appBuild.isEmpty, appBuild.utf8.count <= 128,
                      !appBuild.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                      let profile = app["profileSHA256"] as? String, ReinstallWireValues.hash(profile),
                      let executable = app["executableSHA256"] as? String, ReinstallWireValues.hash(executable) else { throw MacReinstallFailure.invalidResponse }
                build = appBuild
            } else { build = nil }
            guard !canAbandon || (!sealed && !removed && !installed) else { throw MacReinstallFailure.invalidResponse }
            if stage == .install, outcome == .unknown, installed { throw MacReinstallFailure.invalidResponse }
            if stage == .preflight, rawProof.values.contains(where: { ReinstallWireValues.boolean($0) == true }) { throw MacReinstallFailure.invalidResponse }
            if request.action == .preflight, stage != .preflight { throw MacReinstallFailure.invalidResponse }
            if stage == .complete, outcome == .confirmed {
                guard code == nil, proof.isComplete, counts != nil, receipt != nil,
                      categories.allSatisfy({ $0.state == .committed }), !canResume, !canAbandon else { throw MacReinstallFailure.invalidResponse }
            }
            if stage == .abandon, outcome == .confirmed {
                guard !canResume, !canAbandon else { throw MacReinstallFailure.invalidResponse }
            }
            return MacReinstallPayload(stage: stage, outcome: outcome, canResume: canResume, canAbandon: canAbandon,
                proof: proof, categories: categories, counts: counts, appBuild: build, teamID: team, expiresAt: expiry,
                receiptSHA256: receipt, errorCode: code)
        } catch { throw MacReinstallFailure.invalidResponse }
    }
}

private enum ReinstallWireValues {
    static let proofKeys: Set<String> = ["backupValidated","sourceSealed","removalConfirmed","installationConfirmed","pairingImported","supportObserved","restoreCommitted"]
    static let safeCodes: Set<String> = [
        "invalid-request","protocol-mismatch","configuration-invalid","dependency-mismatch","runtime-api-mismatch",
        "environment-not-ready","device-disconnected","trust-required","developer-mode-required","unsupported-os",
        "identity-mismatch","app-already-installed", "app-running","signing-required","signature-invalid","artifact-mismatch",
        "support-unavailable","pairing-unknown","pairing-rejected","handoff-unknown","commit-unknown",
        "transaction-unknown","transaction-conflict","busy","cancelled","timeout","storage-unavailable","operation-failed",
        "update-required","source-busy","backup-invalid","restore-unknown","export-conflict","removal-unknown","operation-abandoned"
    ]
    static func keys(_ object: [String:Any], required: Set<String>, optional: Set<String> = []) -> Bool {
        required.isSubset(of: Set(object.keys)) && Set(object.keys).isSubset(of: required.union(optional))
    }
    static func uuid(_ value: Any?) -> UUID? {
        guard let text = value as? String, text == text.lowercased(), let id = UUID(uuidString: text),
              id.uuidString.lowercased() == text else { return nil }
        return id
    }
    static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
    static func integer(_ value: Any?, maximum: Int) -> Int? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              let integer = Int(value.stringValue), (0...maximum).contains(integer) else { return nil }
        return integer
    }
    static func hash(_ value: String) -> Bool { setupFullMatch(value, "^[0-9a-f]{64}$") }
    static func optionalString(_ object: [String:Any], _ key: String) throws -> String? {
        guard let value = object[key] else { return nil }
        guard let text = value as? String else { throw MacReinstallFailure.invalidResponse }
        return text
    }
    static func validDate(_ text: String) -> Bool {
        guard text.utf8.count <= 40, text.hasSuffix("Z") else { return false }
        let parser = ISO8601DateFormatter()
        if parser.date(from: text) != nil { return true }
        parser.formatOptions.insert(.withFractionalSeconds)
        return parser.date(from: text) != nil
    }
    /// All numeric protocol3 fields are nonnegative integers. Scan original
    /// tokens so Foundation cannot coerce 2.0 or 2e0 into an accepted count.
    static func requireIntegerTokens(_ data: Data) throws {
        let bytes = Array(data); var index = 0
        while index < bytes.count {
            if bytes[index] == 34 {
                index += 1
                while index < bytes.count {
                    let value = bytes[index]; index += 1
                    if value == 92 { index += 1 }
                    else if value == 34 { break }
                }
            } else if bytes[index] == 45 || (48...57).contains(bytes[index]) {
                let start = index
                while index < bytes.count, ![9,10,13,32,44,93,125].contains(bytes[index]) { index += 1 }
                let text = String(decoding: bytes[start..<index], as: UTF8.self)
                guard setupFullMatch(text, "^(?:0|[1-9][0-9]*)$"), Int(text) != nil else { throw MacReinstallFailure.invalidResponse }
            } else { index += 1 }
        }
    }
}
