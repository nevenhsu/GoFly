import CryptoKit
import Foundation

public enum MacManagementKind: String, Codable, Equatable, Sendable { case renew, repair }
public enum MacManagementTransport: String, Codable, Equatable, Sendable {
    case usb = "USB"
    case network = "Network"
}
public enum MacManagementAction: String, Codable, Equatable, Sendable {
    case preflight, apply, query, resume, release
}
public enum MacManagementStage: String, Codable, Equatable, Sendable {
    case preflight, artifact, source, seal, update, pairing, support, adoption, complete, release
}
public enum MacManagementOutcome: String, Codable, Equatable, Sendable {
    case ready, inProgress, confirmed, unknown, failed
}
public enum MacManagementSourceAdmission: String, Codable, Equatable, Sendable { case live, cold }
public typealias MacManagementSource = MacSetupSource

public enum MacManagementFailure: Error, Equatable, Sendable {
    case invalidRequest
    case invalidResponse
    case unavailable, cancelled, timeout
    case service(String)

    public var title: String {
        switch self {
        case .unavailable: return "管理工具尚未就緒"
        case .cancelled: return "已停止等待這次操作"
        case .timeout: return "等待裝置回覆逾時"
        case .invalidRequest: return "請確認本次管理選項"
        case .invalidResponse: return "無法核對管理結果"
        case .service(let code):
            switch code {
            case "receipt-capacity": return "App 準備紀錄已滿"
            case "identity-unverified", "identity-mismatch": return "App 身分尚未確認"
            case "source-busy": return "請先完成手機上的操作"
            case "app-running": return "請先關閉 iPhone 上的 GoFly"
            case "update-unknown": return "App 更新結果待確認"
            case "adoption-unknown": return "資料接續結果待確認"
            case "revision-conflict": return "需要重新核對連線"
            case "signing-required", "signature-invalid": return "需要完成簽名設定"
            default: return "本次操作尚未完成"
            }
        }
    }
    public var detail: String {
        switch self {
        case .unavailable: return "請確認 Mac 執行環境可用，再接續原操作。"
        case .cancelled: return "裝置操作可能尚未確認。原進度會保留，重新核對後才能繼續。"
        case .timeout: return "請保持原 iPhone 連線並解鎖，再手動接續；不會自動重送未知的裝置操作。"
        case .invalidRequest: return "請確認原 iPhone、開發團隊與簽名來源，再進行唯讀檢查。"
        case .invalidResponse: return "回覆未通過身分與進度核對，已保留操作紀錄。請先查詢原操作；仍無法讀取時請重新開啟 Mac App。"
        case .service(let code):
            switch code {
            case "receipt-capacity": return "本次沒有開始新的更新。取消本次操作後，可明確選擇「保留資料與重裝」；不會自動刪除準備紀錄。"
            case "identity-unverified", "identity-mismatch": return "請確認連接的是原 iPhone，且 App 與開發團隊相符，再查詢原操作。"
            case "source-busy": return "請在 iPhone 停止移動並完成清除、結束編輯，再停留於 GoFly 地圖，手動接續。"
            case "update-required": return "原 App 尚未支援此資料交接流程。請使用相容版本或明確選擇保留資料的重裝流程。"
            case "update-unknown": return "更新可能已提交。請在原 iPhone 開啟 GoFly 取得本次版本回報，再回 Mac 手動接續；不會盲目重送更新。"
            case "app-running": return "尚未取得可管理的原程序資訊。請關閉 GoFly、保持原 iPhone 解鎖與連線，再手動接續；不會強制關閉其他程序。"
            case "adoption-unknown": return "尚未取得完整 App 與資料接續回報。保持 GoFly 開啟，手動查詢原操作。"
            case "revision-conflict": return "請連接同一部 iPhone，明確選擇接續使用的連線。未確認的舊操作會先保留。"
            case "signing-required", "signature-invalid": return "請在 Xcode 完成開發團隊與簽署設定，再接續原操作。本次選項與已完成的進度會保留。"
            case "device-disconnected": return "請重新連接原 iPhone 並解鎖，再手動接續原操作。"
            case "trust-required": return "請解鎖 iPhone，確認信任這部 Mac，再手動接續。"
            case "developer-mode-required": return "請在 iPhone「設定 → 隱私權與安全性」開啟開發者模式，再手動接續。"
            default: return "本次操作尚未完整確認，請查詢原操作並依目前狀態接續。"
            }
        }
    }
}

public struct MacManagementOptions: Equatable, Sendable {
    public let source: MacManagementSource
    public let artifactPath: String?
    public let teamID: String
    public let allowProvisioningUpdates: Bool

    public init(source: MacManagementSource, artifactPath: String? = nil, teamID: String,
                allowProvisioningUpdates: Bool = false) throws {
        guard MacManagementWire.validTeamID(teamID) else { throw MacManagementFailure.invalidRequest }
        switch source {
        case .project:
            guard artifactPath == nil else { throw MacManagementFailure.invalidRequest }
        case .signedApp:
            guard let artifactPath, MacManagementWire.validArtifactPath(artifactPath),
                  !allowProvisioningUpdates else { throw MacManagementFailure.invalidRequest }
        }
        self.source = source
        self.artifactPath = artifactPath
        self.teamID = teamID
        self.allowProvisioningUpdates = allowProvisioningUpdates
    }
}

public struct MacManagementSelection: Equatable, Sendable {
    public let selectionID: UUID
    public let transport: MacManagementTransport
    public init(selectionID: UUID, transport: MacManagementTransport) {
        self.selectionID = selectionID
        self.transport = transport
    }
}

public struct MacManagementRequest: Equatable, Sendable {
    public static let protocolVersion = 5
    public static let maximumBytes = 32 * 1_024
    public let `protocol`: Int
    public let operation: String
    public let requestID: UUID
    public let managementID: UUID
    public let deviceID: String
    public let selectionID: UUID
    public let kind: MacManagementKind
    public let transport: MacManagementTransport
    public let connectionRevision: Int
    public let action: MacManagementAction
    public let options: MacManagementOptions?
    public let resumeSelection: MacManagementSelection?

    public init(action: MacManagementAction, managementID: UUID, deviceID: String,
                selectionID: UUID, kind: MacManagementKind, transport: MacManagementTransport,
                connectionRevision: Int, options: MacManagementOptions? = nil,
                resumeSelection: MacManagementSelection? = nil, requestID: UUID = UUID()) throws {
        let normalizedDevice = deviceID.lowercased()
        guard MacManagementWire.validDeviceID(normalizedDevice), (0...31).contains(connectionRevision) else {
            throw MacManagementFailure.invalidRequest
        }
        switch action {
        case .preflight, .apply:
            guard connectionRevision == 0, resumeSelection == nil else { throw MacManagementFailure.invalidRequest }
            switch kind {
            case .renew: guard options != nil else { throw MacManagementFailure.invalidRequest }
            case .repair: guard options == nil else { throw MacManagementFailure.invalidRequest }
            }
        case .query, .release:
            guard options == nil, resumeSelection == nil else { throw MacManagementFailure.invalidRequest }
        case .resume:
            guard options == nil else { throw MacManagementFailure.invalidRequest }
        }
        self.`protocol` = Self.protocolVersion
        self.operation = "management"
        self.requestID = requestID
        self.managementID = managementID
        self.deviceID = normalizedDevice
        self.selectionID = selectionID
        self.kind = kind
        self.transport = transport
        self.connectionRevision = connectionRevision
        self.action = action
        self.options = options
        self.resumeSelection = resumeSelection
    }

    public func encoded() throws -> Data {
        try MacManagementWire.encode(object, maximum: Self.maximumBytes)
    }
    private var object: [String: Any] {
        var result: [String: Any] = [
            "protocol": Self.protocolVersion, "operation": "management",
            "requestID": requestID.uuidString.lowercased(), "managementID": managementID.uuidString.lowercased(),
            "deviceID": deviceID, "selectionID": selectionID.uuidString.lowercased(),
            "kind": kind.rawValue, "transport": transport.rawValue,
            "connectionRevision": connectionRevision, "action": action.rawValue
        ]
        switch action {
        case .preflight, .apply: result["options"] = options.map(MacManagementWire.optionsObject) ?? NSNull()
        case .resume: result["resumeSelection"] = resumeSelection.map(MacManagementWire.selectionObject) ?? NSNull()
        case .query, .release: break
        }
        return result
    }
}

public struct MacManagementAppIdentity: Equatable, Sendable {
    public static let formalBundleID = "com.neven.gofly"
    public let bundleID: String
    public let build: String
    public let profileSHA256: String
    public let executableSHA256: String

    public init(bundleID: String, build: String, profileSHA256: String,
                executableSHA256: String) throws {
        guard Self.valid(bundleID: bundleID, build: build, profileSHA256: profileSHA256,
                         executableSHA256: executableSHA256) else { throw MacManagementFailure.invalidRequest }
        self.bundleID = bundleID
        self.build = build
        self.profileSHA256 = profileSHA256
        self.executableSHA256 = executableSHA256
    }
    public static func valid(bundleID: String, build: String, profileSHA256: String,
                             executableSHA256: String) -> Bool {
        bundleID == formalBundleID && !build.isEmpty && build.utf8.count <= 128 &&
            !MacManagementWire.hasControlCharacters(build) &&
            MacManagementWire.validHash(profileSHA256) && MacManagementWire.validHash(executableSHA256)
    }
}

public struct MacManagementProof: Equatable, Sendable {
    public let sourceBound: Bool
    public let sourceQuiescent: Bool
    public let mutationSealed: Bool
    public let updateConfirmed: Bool
    public let pairingImported: Bool
    public let supportObserved: Bool
    public let adoptionCommitted: Bool
    public init(sourceBound: Bool, sourceQuiescent: Bool, mutationSealed: Bool,
                updateConfirmed: Bool, pairingImported: Bool, supportObserved: Bool,
                adoptionCommitted: Bool) {
        self.sourceBound = sourceBound
        self.sourceQuiescent = sourceQuiescent
        self.mutationSealed = mutationSealed
        self.updateConfirmed = updateConfirmed
        self.pairingImported = pairingImported
        self.supportObserved = supportObserved
        self.adoptionCommitted = adoptionCommitted
    }
    fileprivate var allFalse: Bool {
        !sourceBound && !sourceQuiescent && !mutationSealed && !updateConfirmed &&
            !pairingImported && !supportObserved && !adoptionCommitted
    }
}

public struct MacManagementAdoptionReceipt: Equatable, Sendable {
    public static let schemaVersion = 1
    public let version: Int
    public let managementID: UUID
    public let nonce: UUID
    public let requestSHA256: String
    public let sourceSetupID: UUID
    public let targetSetupID: UUID
    public let sourceApp: MacManagementAppIdentity
    public let targetApp: MacManagementAppIdentity
    public let expectedDeviceUDID: String
    public let teamID: String
    public let sourceActivationSHA256: String
    public let sourceRestoreRootSHA256: String?
    public let targetActivationSHA256: String
    public let receiptSHA256: String

    public init(version: Int = Self.schemaVersion, managementID: UUID, nonce: UUID,
                requestSHA256: String, sourceSetupID: UUID, targetSetupID: UUID,
                sourceApp: MacManagementAppIdentity, targetApp: MacManagementAppIdentity,
                expectedDeviceUDID: String, teamID: String, sourceActivationSHA256: String,
                sourceRestoreRootSHA256: String?, targetActivationSHA256: String,
                receiptSHA256: String? = nil) throws {
        let device = expectedDeviceUDID.lowercased()
        guard expectedDeviceUDID == device, version == Self.schemaVersion, sourceSetupID != targetSetupID,
              MacManagementWire.validHash(requestSHA256), MacManagementWire.validDeviceID(device),
              MacManagementWire.validTeamID(teamID), MacManagementWire.validHash(sourceActivationSHA256),
              sourceRestoreRootSHA256.map(MacManagementWire.validHash) ?? true,
              MacManagementWire.validHash(targetActivationSHA256) else { throw MacManagementFailure.invalidRequest }
        let digest = Self.digest(version: version, managementID: managementID, nonce: nonce,
                                 requestSHA256: requestSHA256, sourceSetupID: sourceSetupID,
                                 targetSetupID: targetSetupID, sourceApp: sourceApp, targetApp: targetApp,
                                 expectedDeviceUDID: device, teamID: teamID,
                                 sourceActivationSHA256: sourceActivationSHA256,
                                 sourceRestoreRootSHA256: sourceRestoreRootSHA256,
                                 targetActivationSHA256: targetActivationSHA256)
        let value = receiptSHA256 ?? digest
        guard MacManagementWire.validHash(value), value == digest else { throw MacManagementFailure.invalidRequest }
        self.version = version; self.managementID = managementID; self.nonce = nonce
        self.requestSHA256 = requestSHA256; self.sourceSetupID = sourceSetupID; self.targetSetupID = targetSetupID
        self.sourceApp = sourceApp; self.targetApp = targetApp; self.expectedDeviceUDID = device
        self.teamID = teamID; self.sourceActivationSHA256 = sourceActivationSHA256
        self.sourceRestoreRootSHA256 = sourceRestoreRootSHA256; self.targetActivationSHA256 = targetActivationSHA256
        self.receiptSHA256 = value
    }
    public var canonicalSHA256: String {
        Self.digest(version: version, managementID: managementID, nonce: nonce,
                    requestSHA256: requestSHA256, sourceSetupID: sourceSetupID, targetSetupID: targetSetupID,
                    sourceApp: sourceApp, targetApp: targetApp, expectedDeviceUDID: expectedDeviceUDID,
                    teamID: teamID, sourceActivationSHA256: sourceActivationSHA256,
                    sourceRestoreRootSHA256: sourceRestoreRootSHA256, targetActivationSHA256: targetActivationSHA256)
    }
    private static func digest(version: Int, managementID: UUID, nonce: UUID, requestSHA256: String,
                               sourceSetupID: UUID, targetSetupID: UUID, sourceApp: MacManagementAppIdentity,
                               targetApp: MacManagementAppIdentity, expectedDeviceUDID: String, teamID: String,
                               sourceActivationSHA256: String, sourceRestoreRootSHA256: String?,
                               targetActivationSHA256: String) -> String {
        let object: [String: Any] = [
            "version": version, "managementID": managementID.uuidString.lowercased(),
            "nonce": nonce.uuidString.lowercased(), "requestSHA256": requestSHA256,
            "sourceSetupID": sourceSetupID.uuidString.lowercased(), "targetSetupID": targetSetupID.uuidString.lowercased(),
            "sourceApp": MacManagementWire.appObject(sourceApp), "targetApp": MacManagementWire.appObject(targetApp),
            "expectedDeviceUDID": expectedDeviceUDID, "teamID": teamID,
            "sourceActivationSHA256": sourceActivationSHA256, "sourceRestoreRootSHA256": sourceRestoreRootSHA256 ?? NSNull(),
            "targetActivationSHA256": targetActivationSHA256
        ]
        return MacManagementWire.sha256(object)
    }
}

public struct MacManagementPayload: Equatable, Sendable {
    private let operationKind: MacManagementKind
    public let stage: MacManagementStage
    public let outcome: MacManagementOutcome
    public let canResume: Bool
    public let canRelease: Bool
    public let sourceAdmission: MacManagementSourceAdmission?
    public let connectionRevision: Int
    public let currentTransport: MacManagementTransport
    public let proof: MacManagementProof
    public let app: MacManagementAppIdentity?
    public let teamID: String?
    public let expiresAt: String?
    public let adoptionReceipt: MacManagementAdoptionReceipt?

    public init(stage: MacManagementStage, outcome: MacManagementOutcome, canResume: Bool,
                canRelease: Bool, sourceAdmission: MacManagementSourceAdmission?,
                connectionRevision: Int, currentTransport: MacManagementTransport,
                proof: MacManagementProof, app: MacManagementAppIdentity?, teamID: String?,
                expiresAt: String?, adoptionReceipt: MacManagementAdoptionReceipt?,
                request: MacManagementRequest) throws {
        self.operationKind = request.kind
        self.stage = stage; self.outcome = outcome; self.canResume = canResume; self.canRelease = canRelease
        self.sourceAdmission = sourceAdmission; self.connectionRevision = connectionRevision
        self.currentTransport = currentTransport; self.proof = proof; self.app = app; self.teamID = teamID
        self.expiresAt = expiresAt; self.adoptionReceipt = adoptionReceipt
        try validate(for: request)
    }

    public var isComplete: Bool {
        guard stage == .complete, outcome == .confirmed, sourceAdmission != nil,
              !canResume, !canRelease, proof.sourceBound, proof.pairingImported,
              proof.supportObserved, proof.adoptionCommitted, app != nil, teamID != nil,
              expiresAt != nil, adoptionReceipt != nil else { return false }
        if sourceAdmission == .live { guard proof.sourceQuiescent && proof.mutationSealed else { return false } }
        if sourceAdmission == .cold { guard !proof.sourceQuiescent && !proof.mutationSealed else { return false } }
        return operationKind == .renew ? proof.updateConfirmed : !proof.updateConfirmed
    }

    fileprivate func validate(for request: MacManagementRequest) throws {
        guard operationKind == request.kind,
              (0...31).contains(connectionRevision), connectionRevision >= request.connectionRevision else {
            throw MacManagementFailure.invalidRequest
        }
        // The envelope retains the immutable initial selection. A later
        // committed revision may use another transport; the journal/model
        // verifies that revision independently of this data-only codec.
        if connectionRevision == 0, currentTransport != request.transport {
            throw MacManagementFailure.invalidRequest
        }
        if let teamID {
            guard expiresAt != nil, MacManagementWire.validTeamID(teamID), MacManagementWire.validDate(expiresAt!) else {
                throw MacManagementFailure.invalidRequest
            }
        } else { guard expiresAt == nil else { throw MacManagementFailure.invalidRequest } }
        if let receipt = adoptionReceipt {
            guard let app, let teamID, expiresAt != nil, receipt.managementID == request.managementID,
                  receipt.expectedDeviceUDID == request.deviceID, receipt.targetApp == app, receipt.teamID == teamID else {
                throw MacManagementFailure.invalidRequest
            }
            if request.kind == .repair { guard receipt.sourceApp == receipt.targetApp else { throw MacManagementFailure.invalidRequest } }
        }
        if proof.adoptionCommitted { guard adoptionReceipt != nil, app != nil, teamID != nil else { throw MacManagementFailure.invalidRequest } }
        if proof.sourceBound { guard sourceAdmission != nil else { throw MacManagementFailure.invalidRequest } }
        if sourceAdmission == .cold { guard !proof.sourceQuiescent && !proof.mutationSealed else { throw MacManagementFailure.invalidRequest } }
        if request.kind == .repair { guard !proof.updateConfirmed else { throw MacManagementFailure.invalidRequest } }
        if canRelease {
            guard [.artifact, .source].contains(stage), [.inProgress, .failed, .unknown].contains(outcome),
                  !proof.updateConfirmed, !proof.pairingImported, !proof.adoptionCommitted,
                  !proof.mutationSealed, adoptionReceipt == nil else { throw MacManagementFailure.invalidRequest }
        }
        if outcome == .ready {
            guard stage == .preflight, proof.allFalse, !canResume, !canRelease,
                  app == nil, teamID == nil, expiresAt == nil, adoptionReceipt == nil else {
                throw MacManagementFailure.invalidRequest
            }
        }
        if request.action == .preflight {
            guard stage == .preflight, proof.allFalse, !canResume, !canRelease,
                  app == nil, teamID == nil, expiresAt == nil, adoptionReceipt == nil else {
                throw MacManagementFailure.invalidRequest
            }
        }
        if stage == .complete, outcome == .confirmed {
            guard sourceAdmission != nil, proof.sourceBound, proof.pairingImported, proof.supportObserved,
                  proof.adoptionCommitted, !canResume, !canRelease, app != nil, teamID != nil,
                  expiresAt != nil, adoptionReceipt != nil else { throw MacManagementFailure.invalidRequest }
            if sourceAdmission == .live { guard proof.sourceQuiescent && proof.mutationSealed else { throw MacManagementFailure.invalidRequest } }
            if sourceAdmission == .cold { guard !proof.sourceQuiescent && !proof.mutationSealed else { throw MacManagementFailure.invalidRequest } }
            if request.kind == .renew { guard proof.updateConfirmed else { throw MacManagementFailure.invalidRequest } }
            else { guard !proof.updateConfirmed else { throw MacManagementFailure.invalidRequest } }
        }
        if stage == .release, outcome == .confirmed {
            guard !canResume, !canRelease, !proof.adoptionCommitted, !proof.updateConfirmed, adoptionReceipt == nil else {
                throw MacManagementFailure.invalidRequest
            }
        }
        if stage == .complete, outcome == .unknown {
            throw MacManagementFailure.invalidRequest
        }
    }
}

public enum MacManagementResponseDecoder {
    public static let maximumBytes = 256 * 1_024

    public static func decode(_ data: Data, for request: MacManagementRequest) throws -> MacManagementPayload {
        do {
            let root = try MacManagementWire.object(data, maximum: maximumBytes)
            let common: Set<String> = ["protocol", "operation", "requestID", "managementID", "deviceID",
                                       "selectionID", "kind", "transport", "action", "status"]
            guard MacManagementWire.keys(root, required: common, optional: ["payload", "code"]),
                  MacManagementWire.int(root["protocol"]) == MacManagementRequest.protocolVersion,
                  MacManagementWire.string(root["operation"]) == "management",
                  MacManagementWire.uuid(root["requestID"]) == request.requestID,
                  MacManagementWire.uuid(root["managementID"]) == request.managementID,
                  MacManagementWire.string(root["deviceID"]) == request.deviceID,
                  MacManagementWire.uuid(root["selectionID"]) == request.selectionID,
                  MacManagementKind(rawValue: MacManagementWire.string(root["kind"]) ?? "") == request.kind,
                  MacManagementTransport(rawValue: MacManagementWire.string(root["transport"]) ?? "") == request.transport,
                  MacManagementAction(rawValue: MacManagementWire.string(root["action"]) ?? "") == request.action,
                  let status = MacManagementWire.string(root["status"]) else {
                throw MacManagementFailure.invalidResponse
            }
            if status == "error" {
                guard MacManagementWire.keys(root, required: common.union(["code"])),
                      let code = MacManagementWire.string(root["code"]), MacManagementWire.safeCodes.contains(code),
                      root["payload"] == nil else { throw MacManagementFailure.invalidResponse }
                throw MacManagementFailure.service(code)
            }
            guard status == "ok", root["code"] == nil, let payloadValue = root["payload"],
                  let payloadObject = MacManagementWire.object(payloadValue) else {
                throw MacManagementFailure.invalidResponse
            }
            return try decodePayload(payloadObject, for: request)
        } catch let failure as MacManagementFailure {
            if case .service = failure { throw failure }
            throw MacManagementFailure.invalidResponse
        } catch { throw MacManagementFailure.invalidResponse }
    }

    private static func decodePayload(_ object: [String: MacManagementWire.Value],
                                      for request: MacManagementRequest) throws -> MacManagementPayload {
        let required: Set<String> = ["stage", "outcome", "canResume", "canRelease", "sourceAdmission",
                                     "connectionRevision", "currentTransport", "proof", "app", "teamID",
                                     "expiresAt", "adoptionReceipt"]
        guard MacManagementWire.keys(object, required: required),
              let stage = MacManagementStage(rawValue: MacManagementWire.string(object["stage"]) ?? ""),
              let outcome = MacManagementOutcome(rawValue: MacManagementWire.string(object["outcome"]) ?? ""),
              let canResume = MacManagementWire.bool(object["canResume"]),
              let canRelease = MacManagementWire.bool(object["canRelease"]),
              let revision = MacManagementWire.int(object["connectionRevision"]),
              let transport = MacManagementTransport(rawValue: MacManagementWire.string(object["currentTransport"]) ?? ""),
              let proofValue = MacManagementWire.object(object["proof"]),
              let proof = decodeProof(proofValue) else { throw MacManagementFailure.invalidResponse }
        let admission: MacManagementSourceAdmission?
        if object["sourceAdmission"]?.isNull == true { admission = nil }
        else { admission = MacManagementSourceAdmission(rawValue: MacManagementWire.string(object["sourceAdmission"]) ?? "") }
        guard object["sourceAdmission"] != nil, object["sourceAdmission"]?.isNull == true || admission != nil else {
            throw MacManagementFailure.invalidResponse
        }
        let app: MacManagementAppIdentity?
        if object["app"]?.isNull == true { app = nil }
        else { guard let decoded = decodeApp(object["app"]) else { throw MacManagementFailure.invalidResponse }; app = decoded }
        let team = try decodeOptionalString(object["teamID"])
        let expiry = try decodeOptionalString(object["expiresAt"])
        let receipt: MacManagementAdoptionReceipt?
        if object["adoptionReceipt"]?.isNull == true { receipt = nil }
        else {
            guard let decoded = decodeReceipt(object["adoptionReceipt"], request: request, app: app, team: team) else {
                throw MacManagementFailure.invalidResponse
            }
            receipt = decoded
        }
        return try MacManagementPayload(stage: stage, outcome: outcome, canResume: canResume,
                                        canRelease: canRelease, sourceAdmission: admission,
                                        connectionRevision: revision, currentTransport: transport,
                                        proof: proof, app: app, teamID: team, expiresAt: expiry,
                                        adoptionReceipt: receipt, request: request)
    }

    private static func decodeProof(_ object: [String: MacManagementWire.Value]) -> MacManagementProof? {
        let keys: Set<String> = ["sourceBound", "sourceQuiescent", "mutationSealed", "updateConfirmed",
                                 "pairingImported", "supportObserved", "adoptionCommitted"]
        guard MacManagementWire.keys(object, required: keys),
              let a = MacManagementWire.bool(object["sourceBound"]),
              let b = MacManagementWire.bool(object["sourceQuiescent"]),
              let c = MacManagementWire.bool(object["mutationSealed"]),
              let d = MacManagementWire.bool(object["updateConfirmed"]),
              let e = MacManagementWire.bool(object["pairingImported"]),
              let f = MacManagementWire.bool(object["supportObserved"]),
              let g = MacManagementWire.bool(object["adoptionCommitted"]) else { return nil }
        return MacManagementProof(sourceBound: a, sourceQuiescent: b, mutationSealed: c,
                                  updateConfirmed: d, pairingImported: e, supportObserved: f,
                                  adoptionCommitted: g)
    }

    private static func decodeApp(_ value: MacManagementWire.Value?) -> MacManagementAppIdentity? {
        guard let object = MacManagementWire.object(value),
              MacManagementWire.keys(object, required: ["bundleID", "build", "profileSHA256", "executableSHA256"]),
              let bundle = MacManagementWire.string(object["bundleID"]),
              let build = MacManagementWire.string(object["build"]),
              let profile = MacManagementWire.string(object["profileSHA256"]),
              let executable = MacManagementWire.string(object["executableSHA256"]) else { return nil }
        return try? MacManagementAppIdentity(bundleID: bundle, build: build,
                                             profileSHA256: profile, executableSHA256: executable)
    }

    private static func decodeOptionalString(_ value: MacManagementWire.Value?) throws -> String? {
        guard let value else { throw MacManagementFailure.invalidResponse }
        if value.isNull { return nil }
        guard let result = MacManagementWire.string(value) else { throw MacManagementFailure.invalidResponse }
        return result
    }

    private static func decodeReceipt(_ value: MacManagementWire.Value?, request: MacManagementRequest,
                                      app: MacManagementAppIdentity?, team: String?) -> MacManagementAdoptionReceipt? {
        guard let object = MacManagementWire.object(value),
              MacManagementWire.keys(object, required: ["version", "managementID", "nonce", "requestSHA256",
                                                         "sourceSetupID", "targetSetupID", "sourceApp", "targetApp",
                                                         "expectedDeviceUDID", "teamID", "sourceActivationSHA256",
                                                         "sourceRestoreRootSHA256", "targetActivationSHA256", "receiptSHA256"]),
              let version = MacManagementWire.int(object["version"]),
              let managementID = MacManagementWire.uuid(object["managementID"]),
              let nonce = MacManagementWire.uuid(object["nonce"]),
              let requestSHA = MacManagementWire.string(object["requestSHA256"]),
              let sourceSetupID = MacManagementWire.uuid(object["sourceSetupID"]),
              let targetSetupID = MacManagementWire.uuid(object["targetSetupID"]),
              let sourceApp = decodeApp(object["sourceApp"]),
              let targetApp = decodeApp(object["targetApp"]),
              let expectedDevice = MacManagementWire.string(object["expectedDeviceUDID"]),
              let receiptTeam = MacManagementWire.string(object["teamID"]),
              let sourceActivation = MacManagementWire.string(object["sourceActivationSHA256"]),
              let targetActivation = MacManagementWire.string(object["targetActivationSHA256"]),
              let digest = MacManagementWire.string(object["receiptSHA256"]) else { return nil }
        let restore: String?
        if object["sourceRestoreRootSHA256"]?.isNull == true { restore = nil }
        else {
            guard let value = MacManagementWire.string(object["sourceRestoreRootSHA256"]) else { return nil }
            restore = value
        }
        guard let receipt = try? MacManagementAdoptionReceipt(version: version,
                                                               managementID: managementID, nonce: nonce,
                                                               requestSHA256: requestSHA, sourceSetupID: sourceSetupID,
                                                               targetSetupID: targetSetupID, sourceApp: sourceApp,
                                                               targetApp: targetApp, expectedDeviceUDID: expectedDevice,
                                                               teamID: receiptTeam, sourceActivationSHA256: sourceActivation,
                                                               sourceRestoreRootSHA256: restore,
                                                               targetActivationSHA256: targetActivation,
                                                               receiptSHA256: digest),
              receipt.managementID == request.managementID,
              receipt.expectedDeviceUDID == request.deviceID,
              receipt.targetApp == app, receipt.teamID == team else { return nil }
        if request.kind == .repair && receipt.sourceApp != receipt.targetApp { return nil }
        return receipt
    }
}

public enum MacManagementResponseEncoder {
    public static func encodeResponse(_ payload: MacManagementPayload,
                                      for request: MacManagementRequest) throws -> Data {
        try payload.validate(for: request)
        let object: [String: Any] = [
            "protocol": MacManagementRequest.protocolVersion, "operation": "management",
            "requestID": request.requestID.uuidString.lowercased(),
            "managementID": request.managementID.uuidString.lowercased(), "deviceID": request.deviceID,
            "selectionID": request.selectionID.uuidString.lowercased(), "kind": request.kind.rawValue,
            "transport": request.transport.rawValue, "action": request.action.rawValue, "status": "ok",
            "payload": MacManagementWire.payloadObject(payload)
        ]
        return try MacManagementWire.encode(object, maximum: MacManagementResponseDecoder.maximumBytes)
    }

    public static func errorResponse(for request: MacManagementRequest?, code: String) throws -> Data {
        guard MacManagementWire.safeCodes.contains(code) else { throw MacManagementFailure.invalidRequest }
        let null = NSNull()
        let object: [String: Any] = [
            "protocol": MacManagementRequest.protocolVersion, "operation": "management",
            "requestID": request.map { $0.requestID.uuidString.lowercased() } ?? null,
            "managementID": request.map { $0.managementID.uuidString.lowercased() } ?? null,
            "deviceID": request?.deviceID ?? null,
            "selectionID": request.map { $0.selectionID.uuidString.lowercased() } ?? null,
            "kind": request?.kind.rawValue ?? null, "transport": request?.transport.rawValue ?? null,
            "action": request?.action.rawValue ?? null, "status": "error", "code": code
        ]
        return try MacManagementWire.encode(object, maximum: MacManagementResponseDecoder.maximumBytes)
    }
}

public func encodeResponse(_ payload: MacManagementPayload, for request: MacManagementRequest) throws -> Data {
    try MacManagementResponseEncoder.encodeResponse(payload, for: request)
}
public func errorResponse(for request: MacManagementRequest?, code: String) throws -> Data {
    try MacManagementResponseEncoder.errorResponse(for: request, code: code)
}

enum MacManagementWire {
    static let safeCodes: Set<String> = [
        "invalid-request", "protocol-mismatch", "configuration-invalid", "dependency-mismatch",
        "runtime-api-mismatch", "environment-not-ready", "device-disconnected", "trust-required",
        "developer-mode-required", "unsupported-os", "identity-mismatch", "app-already-installed",
        "app-running", "signing-required", "signature-invalid", "artifact-mismatch", "support-unavailable",
        "pairing-unknown", "pairing-rejected", "handoff-unknown", "commit-unknown", "transaction-unknown",
        "transaction-conflict", "busy", "cancelled", "timeout", "storage-unavailable", "operation-failed",
        "update-required", "source-busy", "backup-invalid", "restore-unknown", "export-conflict",
        "removal-unknown", "operation-abandoned", "identity-unverified", "update-unknown", "adoption-unknown",
        "operation-released", "revision-conflict", "receipt-capacity"
    ]

    // Protocol 5 validates lexical integer tokens at every nested boundary.
    // SetupWireJSON only preserves one outer version token before Foundation
    // decoding; reusing it would lose the distinction between 2 and 2.0 here.
    // Keep this scanner local so existing M1/M2 acceptance remains unchanged.
    indirect enum Value: Equatable, Sendable {
        case object([String: Value]), array([Value]), string(String), number(String), bool(Bool), null
        var isNull: Bool { if case .null = self { return true }; return false }
    }

    static func object(_ data: Data, maximum: Int) throws -> [String: Value] {
        guard !data.isEmpty, data.count <= maximum, String(data: data, encoding: .utf8) != nil else {
            throw MacManagementFailure.invalidResponse
        }
        var parser = Parser(bytes: Array(data))
        let value = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count, case .object(let result) = value else {
            throw MacManagementFailure.invalidResponse
        }
        return result
    }

    static func object(_ value: Value?) -> [String: Value]? {
        guard let value, case .object(let object) = value else { return nil }
        return object
    }

    static func keys(_ object: [String: Value], required: Set<String>, optional: Set<String> = []) -> Bool {
        let actual = Set(object.keys)
        return required.isSubset(of: actual) && actual.isSubset(of: required.union(optional))
    }

    static func string(_ value: Value?) -> String? {
        guard let value, case .string(let result) = value else { return nil }
        return result
    }

    static func int(_ value: Value?) -> Int? {
        guard let value, case .number(let raw) = value, !raw.hasPrefix("-"), !raw.contains("."),
              !raw.contains("e"), !raw.contains("E"), let result = Int(raw), result >= 0 else { return nil }
        return result
    }

    static func bool(_ value: Value?) -> Bool? {
        guard let value, case .bool(let result) = value else { return nil }
        return result
    }

    static func validTeamID(_ value: String) -> Bool {
        value.utf8.count == 10 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90)
        }
    }

    static func validDeviceID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        let validHex: (UInt8) -> Bool = { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
        if bytes.count == 40 { return bytes.allSatisfy(validHex) }
        guard bytes.count == 25, bytes[8] == 45 else { return false }
        return bytes.enumerated().allSatisfy { $0.offset == 8 || validHex($0.element) }
    }

    static func validArtifactPath(_ value: String) -> Bool {
        guard value.utf8.count <= 4_096, value.hasPrefix("/"),
              URL(fileURLWithPath: value).pathExtension == "app",
              !hasControlCharacters(value) else { return false }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.dropFirst().contains { $0.isEmpty || $0 == ".." }
    }

    static func hasControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    static func validHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    static func validDate(_ value: String) -> Bool {
        guard value.utf8.count <= 40,
              value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$",
                          options: .regularExpression) != nil,
              !value.hasPrefix("0000-") else { return false }
        let seconds = String(value.prefix(19)) + "Z"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: seconds) else { return false }
        // Foundation may normalize an invalid calendar day. Require the exact
        // whole-second value back; fractions cannot change calendar validity.
        return formatter.string(from: date) == seconds
    }

    static func uuid(_ value: Value?) -> UUID? {
        guard let text = string(value), text == text.lowercased(),
              let uuid = UUID(uuidString: text), uuid.uuidString.lowercased() == text else { return nil }
        return uuid
    }

    static func appObject(_ app: MacManagementAppIdentity) -> [String: Any] {
        ["bundleID": app.bundleID, "build": app.build,
         "profileSHA256": app.profileSHA256, "executableSHA256": app.executableSHA256]
    }

    static func optionsObject(_ options: MacManagementOptions) -> [String: Any] {
        ["source": options.source.rawValue, "artifactPath": options.artifactPath ?? NSNull(),
         "teamID": options.teamID, "allowProvisioningUpdates": options.allowProvisioningUpdates]
    }

    static func selectionObject(_ selection: MacManagementSelection) -> [String: Any] {
        ["selectionID": selection.selectionID.uuidString.lowercased(), "transport": selection.transport.rawValue]
    }

    static func payloadObject(_ payload: MacManagementPayload) -> [String: Any] {
        ["stage": payload.stage.rawValue, "outcome": payload.outcome.rawValue,
         "canResume": payload.canResume, "canRelease": payload.canRelease,
         "sourceAdmission": payload.sourceAdmission?.rawValue ?? NSNull(),
         "connectionRevision": payload.connectionRevision, "currentTransport": payload.currentTransport.rawValue,
         "proof": ["sourceBound": payload.proof.sourceBound, "sourceQuiescent": payload.proof.sourceQuiescent,
                   "mutationSealed": payload.proof.mutationSealed, "updateConfirmed": payload.proof.updateConfirmed,
                   "pairingImported": payload.proof.pairingImported, "supportObserved": payload.proof.supportObserved,
                   "adoptionCommitted": payload.proof.adoptionCommitted],
         "app": payload.app.map(appObject) ?? NSNull(), "teamID": payload.teamID ?? NSNull(),
         "expiresAt": payload.expiresAt ?? NSNull(),
         "adoptionReceipt": payload.adoptionReceipt.map(receiptObject) ?? NSNull()]
    }

    static func receiptObject(_ receipt: MacManagementAdoptionReceipt) -> [String: Any] {
        ["version": receipt.version, "managementID": receipt.managementID.uuidString.lowercased(),
         "nonce": receipt.nonce.uuidString.lowercased(), "requestSHA256": receipt.requestSHA256,
         "sourceSetupID": receipt.sourceSetupID.uuidString.lowercased(),
         "targetSetupID": receipt.targetSetupID.uuidString.lowercased(),
         "sourceApp": appObject(receipt.sourceApp), "targetApp": appObject(receipt.targetApp),
         "expectedDeviceUDID": receipt.expectedDeviceUDID, "teamID": receipt.teamID,
         "sourceActivationSHA256": receipt.sourceActivationSHA256,
         "sourceRestoreRootSHA256": receipt.sourceRestoreRootSHA256 ?? NSNull(),
         "targetActivationSHA256": receipt.targetActivationSHA256, "receiptSHA256": receipt.receiptSHA256]
    }

    static func sha256(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object,
                                                  options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encode(_ object: [String: Any], maximum: Int) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else { throw MacManagementFailure.invalidRequest }
        do {
            let data = try JSONSerialization.data(withJSONObject: object,
                                                   options: [.sortedKeys, .withoutEscapingSlashes])
            guard data.count <= maximum else { throw MacManagementFailure.invalidRequest }
            return data
        } catch let failure as MacManagementFailure { throw failure }
        catch { throw MacManagementFailure.invalidRequest }
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func whitespace() {
            while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }

        mutating func value(depth: Int) throws -> Value {
            guard depth <= 32 else { throw MacManagementFailure.invalidResponse }
            whitespace()
            guard index < bytes.count else { throw MacManagementFailure.invalidResponse }
            switch bytes[index] {
            case 123:
                index += 1
                var object: [String: Value] = [:]
                whitespace()
                if take(125) { return .object(object) }
                while true {
                    let key = try string()
                    guard object[key] == nil, take(58) else { throw MacManagementFailure.invalidResponse }
                    object[key] = try value(depth: depth + 1)
                    if take(125) { return .object(object) }
                    guard take(44) else { throw MacManagementFailure.invalidResponse }
                }
            case 91:
                index += 1
                var array: [Value] = []
                whitespace()
                if take(93) { return .array(array) }
                while true {
                    array.append(try value(depth: depth + 1))
                    if take(93) { return .array(array) }
                    guard take(44) else { throw MacManagementFailure.invalidResponse }
                }
            case 34: return .string(try string())
            case 116: try literal("true"); return .bool(true)
            case 102: try literal("false"); return .bool(false)
            case 110: try literal("null"); return .null
            default: return .number(try number())
            }
        }

        mutating func string() throws -> String {
            whitespace()
            let start = index
            guard takeRaw(34) else { throw MacManagementFailure.invalidResponse }
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 34 {
                    let data = Data(bytes[start..<index])
                    guard let value = try? JSONSerialization.jsonObject(with: data,
                                                                          options: [.fragmentsAllowed]) as? String else {
                        throw MacManagementFailure.invalidResponse
                    }
                    return value
                }
                if byte == 92 {
                    guard index < bytes.count else { throw MacManagementFailure.invalidResponse }
                    if bytes[index] == 117 {
                        guard index + 4 < bytes.count else { throw MacManagementFailure.invalidResponse }
                        index += 5
                    } else {
                        guard [34, 92, 47, 98, 102, 110, 114, 116].contains(bytes[index]) else {
                            throw MacManagementFailure.invalidResponse
                        }
                        index += 1
                    }
                } else if byte < 0x20 { throw MacManagementFailure.invalidResponse }
            }
            throw MacManagementFailure.invalidResponse
        }

        mutating func number() throws -> String {
            whitespace()
            let start = index
            if index < bytes.count, bytes[index] == 45 { index += 1 }
            guard index < bytes.count else { throw MacManagementFailure.invalidResponse }
            if bytes[index] == 48 {
                index += 1
                if index < bytes.count, bytes[index] >= 48 && bytes[index] <= 57 {
                    throw MacManagementFailure.invalidResponse
                }
            } else {
                guard bytes[index] >= 49 && bytes[index] <= 57 else { throw MacManagementFailure.invalidResponse }
                while index < bytes.count, bytes[index] >= 48 && bytes[index] <= 57 { index += 1 }
            }
            if index < bytes.count, bytes[index] == 46 {
                index += 1
                guard index < bytes.count, bytes[index] >= 48 && bytes[index] <= 57 else { throw MacManagementFailure.invalidResponse }
                while index < bytes.count, bytes[index] >= 48 && bytes[index] <= 57 { index += 1 }
            }
            if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
                index += 1
                if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
                guard index < bytes.count, bytes[index] >= 48 && bytes[index] <= 57 else { throw MacManagementFailure.invalidResponse }
                while index < bytes.count, bytes[index] >= 48 && bytes[index] <= 57 { index += 1 }
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        mutating func literal(_ literal: String) throws {
            let values = Array(literal.utf8)
            guard index + values.count <= bytes.count,
                  Array(bytes[index..<(index + values.count)]) == values else {
                throw MacManagementFailure.invalidResponse
            }
            index += values.count
        }

        mutating func take(_ byte: UInt8) -> Bool {
            whitespace()
            return takeRaw(byte)
        }
        mutating func takeRaw(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }
    }
}
