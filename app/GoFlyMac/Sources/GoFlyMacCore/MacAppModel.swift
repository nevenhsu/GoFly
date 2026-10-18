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
    private var verifiedSetupID: UUID?
    public private(set) var isCancellingCheck = false
    public var isChecking: Bool { checkingBusy }
    public let setup: MacSetupModel?
    public let reinstall: MacReinstallModel?
    public let backups: MacBackupModel?
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
    @ObservationIgnored private var activeCheckID: UUID?
    private enum PendingCheckAction { case mode(Bool), scenario }
    @ObservationIgnored private var pendingCheckAction: PendingCheckAction?
    @ObservationIgnored private var backupMaintenanceStarted = false
    @ObservationIgnored private var backupMaintenanceReinstallID: UUID?

    public init(live: any MacChecking, setup: MacSetupModel? = nil, reinstall: MacReinstallModel? = nil,
                backups: MacBackupModel? = nil) {
        self.live = live
        self.setup = setup
        self.reinstall = reinstall
        self.backups = backups
    }
    public var busy: Bool {
        checkingBusy || backups?.isBusy == true || (!isPreview && (setup?.isBusy == true || reinstall?.isBusy == true))
    }
    public var setupLocksDevice: Bool {
        !isPreview && (setup?.locksDevice == true || reinstall?.locksDevice == true)
    }
    private var activeOperationPage: MacPage {
        reinstall?.locksDevice == true ? .reinstall : .install
    }

    public func restoreSetup() async {
        await reinstall?.restore()
        if let identity = reinstall?.continuation {
            selectedID = identity.deviceID
            firstInstall = false
            page = .reinstall
            return
        } else if reinstall?.failure != nil {
            firstInstall = false
            page = .reinstall
            return
        }
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

    public func finishReinstall() async {
        guard !busy, reinstall?.snapshot?.isComplete == true || reinstall?.snapshot?.isAbandoned == true else { return }
        let completedID = reinstall?.snapshot?.isComplete == true ? reinstall?.continuation?.transferID : nil
        reinstall?.resetSelection()
        // When M2 was restored first, M1 has not reopened the predecessor
        // which M2 may archive. Read its actual current journal only now.
        await setup?.restore()
        if setup?.locksDevice == true {
            firstInstall = true
            selectedID = setup?.continuation?.deviceID
            page = .install
        } else {
            selectedID = nil
            inspection = nil
            page = .home
        }
        maintainBackupsIfIdle(completedReinstallID: completedID)
    }
    public var ready: Bool { environment?.ready == true && !busy }
    public var selected: ConnectedDevice? {
        if let inspection, inspection.device.id.lowercased() == selectedID?.lowercased() { return inspection.device }
        return devices.first { $0.id.lowercased() == selectedID?.lowercased() }
    }
    public var visibleDevices: [ConnectedDevice] { ConnectedDevice.unique(devices, usbOnly: firstInstall) }
    public var mayInspect: Bool { ready && selected != nil }
    public var setupVPNConfirmed: Bool {
        guard setup?.snapshot?.isComplete == true, let identity = setup?.continuation,
              verifiedSetupID == identity.setupID,
              inspection?.device.id.lowercased() == identity.deviceID.lowercased() else { return false }
        return inspection?.vpnInstalled == true
    }

    public func verifySetupDevice() {
        guard !busy, setup?.snapshot?.isComplete == true,
              let identity = setup?.continuation else { return }
        verifiedSetupID = nil
        inspection = nil
        perform(.inspect, deviceID: identity.deviceID) { data, request in
            let result = try ResponseDecoder.decode(data, for: request, as: DeviceInspection.self)
            guard result.device.id.lowercased() == identity.deviceID.lowercased(),
                  result.device.transport == .usb, result.installed == true else { throw CheckFailure.invalidResponse }
            self.selectedID = identity.deviceID
            self.inspection = result
            self.verifiedSetupID = identity.setupID
        }
    }
    public var installStatus: String {
        guard let inspection else { return "尚未檢查" }
        switch inspection.installed { case true: return "已偵測到 App"; case false: return "未偵測到 App"; default: return "安裝狀態待確認" }
    }

    public func navigate(_ destination: MacPage) {
        guard !busy else { return }
        if setupLocksDevice && destination != .home && destination != activeOperationPage && destination != .environment && destination != .backups {
            page = activeOperationPage; return
        }
        if !isPreview && destination != .home && destination != .environment && destination != .backups &&
            !(destination == activeOperationPage && setupLocksDevice) &&
            !(destination == .install && setup?.hasRecordedTransaction == true) &&
            !(destination == .reinstall && reinstall?.hasRecordedTransaction == true) && environment?.ready != true {
            page = .environment; return
        }
        page = destination; failure = nil; previewMessage = nil
    }

    public func switchMode(preview: Bool) {
        guard !setupLocksDevice, backups?.isBusy != true else { return }
        if checkingBusy {
            pendingCheckAction = .mode(preview)
            cancel()
            return
        }
        setup?.resetSelection()
        reinstall?.resetSelection()
        cancel()
        isPreview = preview; environment = nil; devices = []; inspection = nil
        selectedID = nil; page = .home; previewStage = 0; previewMessage = nil; failure = nil
        checkEnvironment()
    }

    public func select(_ id: String) {
        guard !busy, !setupLocksDevice, visibleDevices.contains(where: { $0.id == id }) else { return }
        if selectedID?.lowercased() != id.lowercased() {
            setup?.resetSelection()
            reinstall?.resetSelection()
        }
        selectedID = id; inspection = nil; failure = nil
    }

    public func openDevices(firstInstall: Bool) {
        guard ready, !setupLocksDevice else { return }
        setup?.resetSelection()
        reinstall?.resetSelection()
        self.firstInstall = firstInstall; selectedID = nil; inspection = nil
        page = .devices; refreshDevices()
    }

    public func checkEnvironment() {
        guard !busy else { return }
        environment = nil
        perform(.environment) { data, request in
            self.environment = try ResponseDecoder.decode(data, for: request, as: MacEnvironment.self)
        }
    }

    public func refreshDevices() {
        guard !busy, !setupLocksDevice else { return }
        setup?.resetSelection()
        reinstall?.resetSelection()
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
        generation = UUID()
        if checkingBusy { isCancellingCheck = true }
        task?.cancel()
        // A cancelled refresh cannot leave apparently current device evidence.
        inspection = nil
    }

    public func applyScenario() {
        guard isPreview else { return }
        if checkingBusy {
            pendingCheckAction = .scenario
            cancel()
            return
        }
        cancel(); failure = nil; inspection = nil; selectedID = nil; devices = []
        page = .home; checkEnvironment()
    }

    public func maintainBackupsIfIdle() {
        let completedID = reinstall?.snapshot?.isComplete == true ? reinstall?.continuation?.transferID : nil
        maintainBackupsIfIdle(completedReinstallID: completedID)
    }

    private func maintainBackupsIfIdle(completedReinstallID: UUID?) {
        guard !isPreview, !busy, !setupLocksDevice, let backups else { return }
        guard !backupMaintenanceStarted ||
            (completedReinstallID != nil && completedReinstallID != backupMaintenanceReinstallID) else { return }
        backupMaintenanceStarted = true
        if let completedReinstallID { backupMaintenanceReinstallID = completedReinstallID }
        backups.maintain()
    }

    public func openBackup(_ entry: MacBackupEntry) {
        guard !isPreview, !busy, entry.canContinue,
              let identity = reinstall?.continuation,
              identity.transferID == entry.transferID,
              identity.deviceID.lowercased() == entry.deviceID.lowercased() else { return }
        selectedID = identity.deviceID
        firstInstall = false
        page = .reinstall
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
        isCancellingCheck = false
        let token = UUID(); generation = token; activeCheckID = token
        let request = CheckRequest(action: action, deviceID: deviceID)
        let checker: any MacChecking = isPreview ? PreviewChecker(scenario: previewScenario) : live
        task = Task {
            defer { self.finishCheck(token) }
            do {
                let result = try await checker.check(request)
                guard !Task.isCancelled, self.generation == token else { return }
                try apply(result, request)
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.inspection = nil
                self.failure = error as? CheckFailure ?? .invalidResponse
            }
        }
    }

    private func finishCheck(_ token: UUID) {
        guard activeCheckID == token else { return }
        activeCheckID = nil
        checkingBusy = false
        isCancellingCheck = false
        task = nil
        let pending = pendingCheckAction
        pendingCheckAction = nil
        switch pending {
        case .mode(let preview): switchMode(preview: preview)
        case .scenario: applyScenario()
        case nil: break
        }
    }
}

public struct UnavailableChecker: MacChecking {
    public init() {}
    public func check(_ request: CheckRequest) async throws -> Data { throw CheckFailure.unavailable }
}
