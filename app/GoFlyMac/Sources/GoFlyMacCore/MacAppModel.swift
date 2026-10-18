import Foundation
import Observation

public enum MacPage: String, CaseIterable, Sendable {
    case home, environment, devices, device, signing, repair, channel, install, handoff, reinstall, backups
}

public enum PreviewScenario: String, CaseIterable, Identifiable, Sendable {
    case ready, missingEnvironment, noDevices, trustRequired, developerMode, expired, disconnected
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ready: "正常連接"
        case .missingEnvironment: "Mac 環境未就緒"
        case .noDevices: "沒有裝置"
        case .trustRequired: "等待信任"
        case .developerMode: "開發者模式關閉"
        case .expired: "簽名已過期"
        case .disconnected: "裝置中斷"
        }
    }
}

@MainActor @Observable
public final class MacAppModel {
    public private(set) var page: MacPage = .home
    public private(set) var isPreview = false
    public private(set) var environment: MacEnvironment?
    public private(set) var devices: [ConnectedDevice] = []
    public private(set) var inspection: DeviceInspection?
    public private(set) var selectedID: String?
    private var checkingBusy = false
    public let setup: MacSetupModel?
    public private(set) var failure: CheckFailure?
    public private(set) var firstInstall = true
    public private(set) var previewStage = 0
    public private(set) var previewMessage: String?
    public var previewScenario: PreviewScenario = .ready
    public var preserveFavorites = true
    public var preserveRoutes = true
    public var preserveSettings = true
    @ObservationIgnored private let live: any MacChecking
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    public init(live: any MacChecking, setup: MacSetupModel? = nil) { self.live = live; self.setup = setup }
    public var busy: Bool { checkingBusy || (!isPreview && setup?.isBusy == true) }
    public var setupLocksDevice: Bool { !isPreview && setup?.locksDevice == true }

    public func restoreSetup() async {
        await setup?.restore()
        if let identity = setup?.continuation {
            selectedID = identity.deviceID
            firstInstall = true
            page = .install
        } else if setup?.failure != nil {
            firstInstall = true
            page = .install
        }
    }
    public var ready: Bool { environment?.ready == true && !busy }
    public var selected: ConnectedDevice? {
        if let inspection, inspection.device.id.lowercased() == selectedID?.lowercased() { return inspection.device }
        return devices.first { $0.id.lowercased() == selectedID?.lowercased() }
    }
    public var visibleDevices: [ConnectedDevice] { ConnectedDevice.unique(devices, usbOnly: firstInstall) }
    public var mayInspect: Bool { ready && selected != nil }
    public var installStatus: String {
        guard let inspection else { return "尚未檢查" }
        switch inspection.installed { case true: return "已偵測到 App"; case false: return "未偵測到 App"; default: return "安裝狀態待確認" }
    }

    public func navigate(_ destination: MacPage) {
        guard !busy else { return }
        if setupLocksDevice && destination != .home && destination != .install && destination != .environment {
            page = .install; return
        }
        if !isPreview && destination != .home && destination != .environment &&
            !(destination == .install && (setup?.hasRecordedTransaction == true || setupLocksDevice)) && environment?.ready != true {
            page = .environment; return
        }
        page = destination; failure = nil; previewMessage = nil
    }

    public func switchMode(preview: Bool) {
        guard !setupLocksDevice else { return }
        setup?.resetSelection()
        cancel()
        isPreview = preview; environment = nil; devices = []; inspection = nil
        selectedID = nil; page = .home; previewStage = 0; previewMessage = nil; failure = nil
        checkEnvironment()
    }

    public func select(_ id: String) {
        guard !busy, !setupLocksDevice, visibleDevices.contains(where: { $0.id == id }) else { return }
        if selectedID?.lowercased() != id.lowercased() { setup?.resetSelection() }
        selectedID = id; inspection = nil; failure = nil
    }

    public func openDevices(firstInstall: Bool) {
        guard ready, !setupLocksDevice else { return }
        setup?.resetSelection()
        self.firstInstall = firstInstall; selectedID = nil; inspection = nil
        page = .devices; refreshDevices()
    }

    public func checkEnvironment() {
        environment = nil
        perform(.environment) { data, request in
            self.environment = try ResponseDecoder.decode(data, for: request, as: MacEnvironment.self)
        }
    }

    public func refreshDevices() {
        guard !setupLocksDevice else { return }
        setup?.resetSelection()
        devices = []; selectedID = nil; inspection = nil
        perform(.devices) { data, request in
            self.devices = ConnectedDevice.unique(try ResponseDecoder.decode(data, for: request, as: DeviceList.self).devices,
                                                   usbOnly: false)
        }
    }

    public func inspectSelected() {
        guard let device = selected, ready, !setupLocksDevice else { return }
        inspection = nil
        perform(.inspect, deviceID: device.id) { data, request in
            let result = try ResponseDecoder.decode(data, for: request, as: DeviceInspection.self)
            guard result.device.id.lowercased() == device.id.lowercased(),
                  result.device.transport == device.transport else { throw CheckFailure.invalidResponse }
            self.inspection = result
            self.page = self.firstInstall ? .install : .device
        }
    }

    public func cancel() {
        generation = UUID(); task?.cancel(); task = nil; checkingBusy = false
        // A cancelled refresh cannot leave apparently current device evidence.
        inspection = nil
    }

    public func applyScenario() {
        guard isPreview else { return }
        cancel(); failure = nil; inspection = nil; selectedID = nil; devices = []
        page = .home; checkEnvironment()
    }

    /// These transitions are presentation only and never call the live checker.
    public func previewAdvance() {
        guard isPreview, !busy else { return }
        failure = nil
        switch page {
        case .install:
            previewStage = 1
            previewMessage = "預覽：App 安裝、本次配對匯入與必要裝置支援均已確認。"
            page = .handoff
        case .signing:
            previewMessage = "預覽：重新簽名完成。資料與手機設定保留。"
        case .repair:
            previewMessage = "預覽：裝置配對已修復。回到手機後手動繼續操作。"
        case .reinstall:
            let selected = [preserveFavorites ? "最愛地點與標籤" : nil,
                            preserveRoutes ? "路線" : nil, preserveSettings ? "設定" : nil].compactMap { $0 }
            previewMessage = selected.isEmpty ? "預覽：已完成全新安裝。" : "預覽：備份 → 重新安裝 → \(selected.joined(separator: "、")) 自動匯入完成。"
        case .backups: previewMessage = "預覽：沒有刪除或匯入任何真實資料。"
        default: break
        }
    }

    private func perform(_ action: CheckAction, deviceID: String? = nil,
                         apply: @escaping @MainActor (Data, CheckRequest) throws -> Void) {
        guard !busy else { return }
        checkingBusy = true; failure = nil
        let token = UUID(); generation = token
        let request = CheckRequest(action: action, deviceID: deviceID)
        let checker: any MacChecking = isPreview ? PreviewChecker(scenario: previewScenario) : live
        task = Task {
            do {
                let result = try await checker.check(request)
                guard !Task.isCancelled, self.generation == token else { return }
                try apply(result, request)
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.inspection = nil
                self.failure = error as? CheckFailure ?? .invalidResponse
            }
            guard self.generation == token else { return }
            self.checkingBusy = false; self.task = nil
        }
    }
}

public struct UnavailableChecker: MacChecking {
    public init() {}
    public func check(_ request: CheckRequest) async throws -> Data { throw CheckFailure.unavailable }
}
