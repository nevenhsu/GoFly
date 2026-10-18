import CoreFoundation
import Foundation

public enum MacBackupAction: String, Codable, Sendable { case list, maintain, delete }
public enum MacBackupCategory: String, Codable, CaseIterable, Sendable { case favorites, routes, settings }
public enum MacBackupKind: String, Sendable { case completed, incomplete, missing, deleted }

public enum MacBackupFailure: Error, Equatable, Sendable {
    case invalidRequest, invalidResponse, unavailable, cancelled, timeout
    case service(String)

    public var title: String {
        switch self {
        case .cancelled: return "備份操作已取消"
        case .timeout: return "備份操作逾時"
        case .unavailable: return "備份管理尚未就緒"
        case .invalidRequest, .invalidResponse: return "無法驗證備份回覆"
        case .service(let code):
            switch code {
            case "busy": return "目前有未完成的裝置操作"
            case "backup-not-complete": return "這筆備份尚未完成"
            case "backup-changed": return "備份來源已變更"
            case "configuration-invalid": return "備份設定無效"
            default: return "備份操作未完成"
            }
        }
    }

    public var detail: String {
        switch self {
        case .cancelled: return "程序已中止；實際回覆已返回前不會重新開放操作。"
        case .timeout: return "沒有取得完整回覆。請稍後重新整理備份狀態。"
        case .unavailable: return "請確認 Mac App 的本機備份元件與設定檔完整。"
        case .invalidRequest, .invalidResponse: return "回覆未通過固定格式、身分或資料界線檢查。"
        case .service(let code):
            switch code {
            case "busy": return "目前仍有未完成的裝置操作；列表可讀取，維護與刪除會在操作完成後開放。"
            case "backup-not-complete": return "只有已完成且再次核對來源的備份可以刪除。"
            case "backup-changed": return "原始交易或備份內容與記錄不符，已停止後續刪除。"
            case "configuration-invalid": return "請重新建立正式 Mac App bundle 後再試。"
            case "storage-unavailable": return "無法安全讀取或寫入本機備份資料。"
            default: return "本次備份操作已停止，未假設資料已刪除。"
            }
        }
    }
}

public struct MacBackupRequest: Encodable, Sendable {
    public let requestID: UUID
    public let action: MacBackupAction
    public let transferID: UUID?
    public let confirmed: Bool?

    public init(action: MacBackupAction, transferID: UUID? = nil, confirmed: Bool? = nil,
                requestID: UUID = UUID()) throws {
        guard action == .delete
            ? transferID != nil && confirmed == true
            : transferID == nil && confirmed == nil else {
            throw MacBackupFailure.invalidRequest
        }
        self.requestID = requestID
        self.action = action
        self.transferID = transferID
        self.confirmed = confirmed
    }

    private enum CodingKeys: String, CodingKey { case `protocol`, requestID, action, transferID, confirmed }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(4, forKey: .protocol)
        try values.encode(requestID.uuidString.lowercased(), forKey: .requestID)
        try values.encode(action.rawValue, forKey: .action)
        if action == .delete {
            guard let transferID, confirmed == true else { throw MacBackupFailure.invalidRequest }
            try values.encode(transferID.uuidString.lowercased(), forKey: .transferID)
            try values.encode(true, forKey: .confirmed)
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do { data = try encoder.encode(self) }
        catch let error as MacBackupFailure { throw error }
        catch { throw MacBackupFailure.invalidRequest }
        guard data.count <= 32 * 1_024 else { throw MacBackupFailure.invalidRequest }
        return data
    }
}

public struct MacBackupCounts: Equatable, Sendable {
    public let favorites: Int
    public let importedRoutes: Int
    public let favoriteRoutes: Int
    public let draftNodes: Int
    public let gpxPoints: Int
}

public struct MacBackupEntry: Identifiable, Equatable, Sendable {
    public let transferID: UUID
    public let dataSetID: UUID
    public let deviceID: String
    public let categories: [MacBackupCategory]
    public let counts: MacBackupCounts?
    public let kind: MacBackupKind
    public let completedObservedAt: String?
    public let deleteAfter: String?
    public let canDelete: Bool
    public let canContinue: Bool

    public var id: UUID { transferID }
}

public struct MacBackupPayload: Equatable, Sendable {
    public let entries: [MacBackupEntry]
    public let pendingDeletion: Bool
}

public protocol MacBackupRunning: Sendable {
    func run(_ request: MacBackupRequest) async throws -> Data
}

public enum MacBackupResponseDecoder {
    private static let safeCodes: Set<String> = [
        "invalid-request", "configuration-invalid", "storage-unavailable", "busy",
        "backup-not-complete", "backup-changed", "operation-failed"
    ]

    public static func decode(_ data: Data, for request: MacBackupRequest) throws -> MacBackupPayload {
        do {
            let root = try BackupWireValues.object(data, maximumBytes: 256 * 1_024)
            guard BackupWireValues.keys(root, required: ["protocol", "requestID", "status"], optional: ["payload", "code"]),
                  BackupWireValues.integer(root["protocol"], maximum: 4) == 4,
                  BackupWireValues.uuid(root["requestID"]) == request.requestID,
                  let status = root["status"] as? String, status == "ok" || status == "error" else {
                throw MacBackupFailure.invalidResponse
            }
            if status == "error" {
                guard BackupWireValues.keys(root, required: ["protocol", "requestID", "status", "code"]),
                      let code = root["code"] as? String, safeCodes.contains(code) else {
                    throw MacBackupFailure.invalidResponse
                }
                throw MacBackupFailure.service(code)
            }

            guard BackupWireValues.keys(root, required: ["protocol", "requestID", "status", "payload"]),
                  let payload = root["payload"] as? [String: Any],
                  BackupWireValues.keys(payload, required: ["entries", "pendingDeletion"]),
                  let pendingDeletion = BackupWireValues.boolean(payload["pendingDeletion"]),
                  let rawEntries = payload["entries"] as? [[String: Any]], rawEntries.count <= 129 else {
                throw MacBackupFailure.invalidResponse
            }
            let entries = try rawEntries.map { try decodeEntry($0, pendingDeletion: pendingDeletion) }
            return MacBackupPayload(entries: entries, pendingDeletion: pendingDeletion)
        } catch let error as MacBackupFailure { throw error }
        catch { throw MacBackupFailure.invalidResponse }
    }

    private static func decodeEntry(_ value: [String: Any], pendingDeletion: Bool) throws -> MacBackupEntry {
        let required = ["transferID", "dataSetID", "deviceID", "categories", "counts", "kind",
                        "completedObservedAt", "deleteAfter", "canDelete", "canContinue"]
        guard BackupWireValues.keys(value, required: Set(required)),
              let transferID = BackupWireValues.uuid(value["transferID"]),
              let dataSetID = BackupWireValues.uuid(value["dataSetID"]),
              let deviceID = BackupWireValues.deviceID(value["deviceID"]),
              let categories = BackupWireValues.categories(value["categories"]),
              let kindValue = value["kind"] as? String,
              let kind = MacBackupKind(rawValue: kindValue),
              let canDelete = BackupWireValues.boolean(value["canDelete"]),
              let canContinue = BackupWireValues.boolean(value["canContinue"]) else {
            throw MacBackupFailure.invalidResponse
        }
        let completedAt = try BackupWireValues.optionalDate(value["completedObservedAt"])
        let deleteAfter = try BackupWireValues.optionalDate(value["deleteAfter"])
        guard (completedAt == nil) == (deleteAfter == nil) else { throw MacBackupFailure.invalidResponse }

        let counts = try BackupWireValues.counts(value["counts"], categories: categories)
        if kind == .incomplete { guard counts == nil else { throw MacBackupFailure.invalidResponse } }
        guard !canDelete || (kind == .completed && !pendingDeletion),
              !canContinue || kind == .incomplete,
              kind != .deleted || (!canDelete && !canContinue),
              kind != .missing || (!canDelete && !canContinue) else {
            throw MacBackupFailure.invalidResponse
        }
        return MacBackupEntry(transferID: transferID, dataSetID: dataSetID, deviceID: deviceID,
                              categories: categories, counts: counts, kind: kind,
                              completedObservedAt: completedAt, deleteAfter: deleteAfter,
                              canDelete: canDelete, canContinue: canContinue)
    }
}

private enum BackupWireValues {
    private static let categoryOrder = MacBackupCategory.allCases
    private static let countKeys: Set<String> = ["favorites", "importedRoutes", "favoriteRoutes", "draftNodes", "gpxPoints"]

    static func object(_ data: Data, maximumBytes: Int) throws -> [String: Any] {
        guard data.count <= maximumBytes else { throw MacBackupFailure.invalidResponse }
        try requireIntegerTokens(data)
        do { return try SetupWireJSON.object(data, maximumBytes: maximumBytes) }
        catch { throw MacBackupFailure.invalidResponse }
    }

    static func keys(_ value: [String: Any], required: Set<String>, optional: Set<String> = []) -> Bool {
        required.isSubset(of: Set(value.keys)) && Set(value.keys).isSubset(of: required.union(optional))
    }

    static func integer(_ value: Any?, maximum: Int) -> Int? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              let integer = Int(value.stringValue), (0...maximum).contains(integer) else { return nil }
        return integer
    }

    static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }

    static func uuid(_ value: Any?) -> UUID? {
        guard let text = value as? String, text == text.lowercased(),
              let uuid = UUID(uuidString: text), uuid.uuidString.lowercased() == text else { return nil }
        return uuid
    }

    static func deviceID(_ value: Any?) -> String? {
        guard let text = value as? String, text == text.lowercased(),
              setupFullMatch(text, "^(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})$") else { return nil }
        return text
    }

    static func categories(_ value: Any?) -> [MacBackupCategory]? {
        guard let raw = value as? [String], raw.count <= categoryOrder.count,
              let categories = Optional(raw.compactMap(MacBackupCategory.init(rawValue:))),
              categories.count == raw.count, categories == categoryOrder.filter(categories.contains) else { return nil }
        return categories
    }

    static func optionalDate(_ value: Any?) throws -> String? {
        guard let value else { throw MacBackupFailure.invalidResponse }
        if value is NSNull { return nil }
        guard let date = value as? String,
              setupFullMatch(date, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") else {
            throw MacBackupFailure.invalidResponse
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.isLenient = false
        guard formatter.date(from: date) != nil else { throw MacBackupFailure.invalidResponse }
        return date
    }

    static func counts(_ value: Any?, categories: [MacBackupCategory]) throws -> MacBackupCounts? {
        if value is NSNull { return nil }
        guard let value = value as? [String: Any], keys(value, required: countKeys),
              let favorites = integer(value["favorites"], maximum: 100),
              let imported = integer(value["importedRoutes"], maximum: 100),
              let favoriteRoutes = integer(value["favoriteRoutes"], maximum: 100),
              let draftNodes = integer(value["draftNodes"], maximum: 27),
              let gpxPoints = integer(value["gpxPoints"], maximum: 2_010_000),
              categories.contains(.favorites) || favorites == 0,
              categories.contains(.routes) || (imported == 0 && favoriteRoutes == 0 && draftNodes == 0 && gpxPoints == 0) else {
            throw MacBackupFailure.invalidResponse
        }
        return MacBackupCounts(favorites: favorites, importedRoutes: imported, favoriteRoutes: favoriteRoutes,
                               draftNodes: draftNodes, gpxPoints: gpxPoints)
    }

    /// Foundation's JSON parser otherwise accepts 2.0 and 2e0 as NSNumber.
    static func requireIntegerTokens(_ data: Data) throws {
        let bytes = Array(data)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 34 {
                index += 1
                while index < bytes.count {
                    let byte = bytes[index]; index += 1
                    if byte == 92 { index += 1 }
                    else if byte == 34 { break }
                }
            } else if bytes[index] == 45 || (48...57).contains(bytes[index]) {
                let start = index
                while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                let token = String(decoding: bytes[start..<index], as: UTF8.self)
                guard setupFullMatch(token, "^(?:0|[1-9][0-9]*)$") else { throw MacBackupFailure.invalidResponse }
            } else { index += 1 }
        }
    }
}
