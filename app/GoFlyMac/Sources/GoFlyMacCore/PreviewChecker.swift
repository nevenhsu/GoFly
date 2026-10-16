import Foundation

/// Sample data is isolated from USB and never reads a saved live receipt.
public struct PreviewChecker: MacChecking {
    public let scenario: PreviewScenario
    public init(scenario: PreviewScenario) { self.scenario = scenario }

    public func check(_ request: CheckRequest) async throws -> Data {
        try await Task.sleep(for: .milliseconds(220))
        let primary = ConnectedDevice(id: "PREVIEW-IPHONE-01", name: "我的 iPhone", transport: .usb, osVersion: "27.0.1（預覽）")
        let secondary = ConnectedDevice(id: "PREVIEW-IPHONE-02", name: "測試 iPhone", transport: .wifi, osVersion: "26.0（預覽）")
        switch request.action {
        case .environment:
            let ready = scenario != .missingEnvironment
            return try envelope(MacEnvironment(ready: ready, checks: [
                .init(id: "xcode", title: "Xcode", detail: ready ? "Xcode 與必要元件已就緒（預覽）" : "尚未完成 Xcode 元件設定（預覽）", passed: ready),
                .init(id: "runtime", title: "裝置檢查工具", detail: "檢查環境可用（預覽）", passed: true)
            ], teamID: "PREVIEW"), request)
        case .devices:
            let devices = scenario == .noDevices || scenario == .disconnected ? [] : [primary, secondary]
            return try envelope(["devices": devices], request)
        case .inspect:
            if scenario == .trustRequired { throw CheckFailure.service("trust-required") }
            if scenario == .disconnected { throw CheckFailure.service("device-disconnected") }
            let device = request.deviceID == secondary.id ? secondary : primary
            return try envelope(DeviceInspection(device: device, developerMode: scenario != .developerMode,
                installed: true, vpnInstalled: true, appVersion: "1.0（預覽）", teamID: "Personal Team（預覽）",
                expiresAt: scenario == .expired ? "2026-10-15T15:00:00Z" : "2026-10-23T15:00:00Z"), request)
        }
    }

    private struct Envelope<T: Encodable>: Encodable {
        let `protocol` = 1
        let requestID: String
        let status = "ok"
        let payload: T
    }
    private func envelope<T: Encodable>(_ payload: T, _ request: CheckRequest) throws -> Data {
        try JSONEncoder().encode(Envelope(requestID: request.requestID, payload: payload))
    }
}
