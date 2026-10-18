import Foundation

/// Live requests are deliberately a closed, read-only set.
public enum CheckAction: String, Codable, Sendable { case environment, devices, inspect }

public struct CheckRequest: Codable, Sendable {
    public let `protocol`: Int
    public let requestID: String
    public let action: CheckAction
    public let deviceID: String?
    public let transport: ConnectedDevice.Transport?

    public init(action: CheckAction, deviceID: String? = nil, transport: ConnectedDevice.Transport? = nil) {
        self.protocol = 1
        self.requestID = UUID().uuidString
        self.action = action
        self.deviceID = deviceID
        self.transport = action == .inspect ? transport : nil
    }
}

public struct EnvironmentCheck: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let passed: Bool
    public init(id: String, title: String, detail: String, passed: Bool) {
        self.id = id; self.title = title; self.detail = detail; self.passed = passed
    }
}

public struct MacEnvironment: Codable, Equatable, Sendable {
    public let ready: Bool
    public let checks: [EnvironmentCheck]
    public let teamID: String?
    public init(ready: Bool, checks: [EnvironmentCheck], teamID: String? = nil) {
        self.ready = ready; self.checks = checks; self.teamID = teamID
    }
}

public struct ConnectedDevice: Codable, Identifiable, Equatable, Sendable {
    public enum Transport: String, Codable, Sendable { case usb, wifi }
    public let id: String
    public let name: String
    public let transport: Transport
    public let osVersion: String?
    public init(id: String, name: String, transport: Transport, osVersion: String? = nil) {
        self.id = id; self.name = name; self.transport = transport; self.osVersion = osVersion
    }
    public var connectionName: String { transport == .usb ? "USB" : "Wi-Fi" }
    public var displayName: String { name.isEmpty ? "iPhone · …\(id.suffix(6))" : name }
    public var connectionID: String { id.lowercased() + ":" + transport.rawValue }

    /// Management keeps both explicit connection choices for the same phone.
    /// First install continues to use the USB-only list.
    public static func connectionChoices(_ devices: [Self], usbOnly: Bool) -> [Self] {
        var choices: [String: Self] = [:]
        for device in devices where !usbOnly || device.transport == .usb {
            if choices[device.connectionID] == nil { choices[device.connectionID] = device }
        }
        return choices.values.sorted {
            ($0.name, $0.id.lowercased(), $0.transport == .usb ? 0 : 1) <
            ($1.name, $1.id.lowercased(), $1.transport == .usb ? 0 : 1)
        }
    }

    public static func unique(_ devices: [Self], usbOnly: Bool) -> [Self] {
        var byID: [String: Self] = [:]
        for device in devices where !usbOnly || device.transport == .usb {
            let key = device.id.lowercased()
            if byID[key] == nil || device.transport == .usb { byID[key] = device }
        }
        return byID.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
}

public struct DeviceInspection: Codable, Equatable, Sendable {
    public let device: ConnectedDevice
    public let developerMode: Bool?
    public let installed: Bool?
    public let vpnInstalled: Bool?
    public let appVersion: String?
    public let teamID: String?
    public let expiresAt: String?
    public let canInstall: Bool
    public let canRenew: Bool
    public let canRepair: Bool
    public let canReinstall: Bool
    public init(device: ConnectedDevice, developerMode: Bool?, installed: Bool?, vpnInstalled: Bool?,
                appVersion: String? = nil, teamID: String? = nil, expiresAt: String? = nil) {
        self.device = device; self.developerMode = developerMode; self.installed = installed
        self.vpnInstalled = vpnInstalled; self.appVersion = appVersion; self.teamID = teamID
        self.expiresAt = expiresAt
        self.canInstall = false; self.canRenew = false; self.canRepair = false; self.canReinstall = false
    }
}

public struct DeviceList: Codable, Sendable { public let devices: [ConnectedDevice] }

public enum CheckFailure: Error, Equatable, Sendable {
    case unavailable, invalidResponse, timeout, cancelled, service(String)

    public var title: String {
        switch self {
        case .cancelled: "檢查已取消"
        case .timeout: "檢查逾時"
        case .unavailable: "檢查工具尚未就緒"
        case .invalidResponse: "無法確認檢查結果"
        case .service(let code):
            switch code {
            case "trust-required", "usb-lockdown-failed": "請在 iPhone 完成信任"
            case "developer-mode-required": "請啟用 iPhone 開發者模式"
            case "device-disconnected", "usb-device-not-found": "iPhone 連線已中斷"
            case "identity-mismatch", "device-identity-mismatch": "目前連接的 iPhone 不符"
            case "unsupported-os", "unsupported-os-version": "目前 iOS 版本不在檢查範圍"
            case "environment-not-ready": "Mac 環境尚未就緒"
            default: "尚未確認檢查成功"
            }
        }
    }
    public var detail: String {
        switch self {
        case .unavailable: "請使用 build-app.sh 建立本機開發版，確認專案的 Python 檢查環境可用。"
        case .timeout: "沒有取得完整回覆。請確認連線與手機解鎖狀態，再手動重新檢查。"
        case .cancelled: "這次唯讀檢查已結束，可重新選擇裝置或再檢查。"
        case .invalidResponse: "回覆未通過格式或裝置身分核對，先前狀態已作廢。請重新檢查。"
        case .service(let code):
            switch code {
            case "trust-required", "usb-lockdown-failed": "解鎖 iPhone，確認已信任這部 Mac，再按重新檢查。本版不會自動建立配對。"
            case "developer-mode-required": "在 iPhone「設定 → 隱私權與安全性 → 開發者模式」手動完成設定後，再重新檢查。"
            case "device-disconnected", "usb-device-not-found": "請重新連接原 iPhone，再回到裝置清單。檢查不會自動切換到其他手機。"
            case "unsupported-os", "unsupported-os-version": "現有檢查介面以 iOS 26 以上為目標；這不代表各版本已通過實機驗收。"
            default: "請確認 Xcode、裝置連接與信任狀態，再重新檢查。這次沒有安裝 App 或寫入裝置。"
            }
        }
    }
}

public protocol MacChecking: Sendable {
    func check(_ request: CheckRequest) async throws -> Data
}

public enum ResponseDecoder {
    private struct Envelope: Decodable {
        let `protocol`: Int
        let requestID: String
        let status: String
        let code: String?
    }
    private struct Result<T: Decodable>: Decodable { let payload: T }

    public static func decode<T: Decodable>(_ data: Data, for request: CheckRequest, as type: T.Type) throws -> T {
        guard !data.isEmpty, data.count <= 262_144 else { throw CheckFailure.invalidResponse }
        let decoder = JSONDecoder()
        do {
            let envelope = try decoder.decode(Envelope.self, from: data)
            guard envelope.protocol == 1, envelope.requestID == request.requestID,
                  ["ok", "error"].contains(envelope.status) else { throw CheckFailure.invalidResponse }
            if envelope.status == "error" {
                let safeCodes: Set<String> = ["invalid-request", "protocol-mismatch", "read-only-mode", "environment-not-ready",
                    "device-disconnected", "trust-required", "developer-mode-required", "unsupported-os", "identity-mismatch",
                    "signing-required", "operation-failed", "busy", "usb-lockdown-failed", "usb-device-not-found",
                    "device-identity-mismatch", "unsupported-os-version", "runtime-unavailable", "dependency-mismatch",
                    "device-values-unavailable", "runtime-api-mismatch", "timeout", "configuration-invalid",
                    "invalid-config", "runtime-import-unavailable"]
                guard let code = envelope.code, safeCodes.contains(code) else { throw CheckFailure.invalidResponse }
                throw CheckFailure.service(code)
            }
            return try decoder.decode(Result<T>.self, from: data).payload
        } catch let error as CheckFailure { throw error }
        catch { throw CheckFailure.invalidResponse }
    }
}
