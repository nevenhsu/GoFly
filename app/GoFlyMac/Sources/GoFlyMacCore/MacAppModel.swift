import Foundation
import Observation

public enum MacPage: String, CaseIterable, Sendable {
    case home, environment, devices, device, signing, repair, channel, install, handoff, reinstall
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
    public private(set) var selectedTransport: ConnectedDevice.Transport?
    public private(set) var managementSelection: MacManagementSelection?
    private var checkingBusy = false
    private var verifiedSetupID: UUID?
    public private(set) var isCancellingCheck = false
    public var isChecking: Bool { checkingBusy }
    public let setup: MacSetupModel?
    public let reinstall: MacReinstallModel?
    public let management: MacManagementModel?
    private var automaticManagementBusy = false
    private var restoringOperations = false
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
    @ObservationIgnored private var automaticManagementTask: Task<Void, Never>?
    @ObservationIgnored private var dispatchedManagementSelection: UUID?

    public init(live: any MacChecking, setup: MacSetupModel? = nil, reinstall: MacReinstallModel? = nil,
                management: MacManagementModel? = nil) {
        self.live = live
        self.setup = setup
        self.reinstall = reinstall
        self.management = management
    }
    public var busy: Bool {
        checkingBusy || automaticManagementBusy || restoringOperations ||
            (!isPreview && (setup?.isBusy == true || reinstall?.isBusy == true || management?.isBusy == true))
    }
    public var setupLocksDevice: Bool {
        restoringOperations || (!isPreview && (automaticManagementBusy || setup?.locksDevice == true || reinstall?.locksDevice == true || management?.locksDevice == true))
    }
    private var activeOperationPage: MacPage {
        if management?.locksDevice == true || automaticManagementBusy {
            return management?.continuation?.kind == .repair ? .repair : .signing
        }
        return reinstall?.locksDevice == true ? .reinstall : .install
    }

    public func restoreSetup() async {
        await management?.restore()
        if let identity = management?.continuation {
            selectedID = identity.deviceID
            selectedTransport = identity.currentTransport == .usb ? .usb : .wifi
            firstInstall = false
            page = identity.kind == .renew ? .signing : .repair
            return
        } else if management?.failure != nil {
            firstInstall = false
            page = .signing
            return
        }
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

    public func finishManagement() async {
        guard !busy, let management,
              management.snapshot?.isComplete == true ||
                (management.snapshot?.stage == .release && management.snapshot?.outcome == .confirmed) else { return }
        let identity = management.continuation
        let result = management.snapshot
        let priorDevice = selected
        let priorDeveloperMode = inspection?.developerMode
        management.resetSelection()
        await reinstall?.restore()
        await setup?.restore()
        inspection = nil
        selectedID = identity?.deviceID
        selectedTransport = identity.map { $0.currentTransport == .usb ? .usb : .wifi }
        managementSelection = nil
        if reinstall?.locksDevice == true {
            selectedID = reinstall?.continuation?.deviceID
            page = .reinstall
        } else if setup?.locksDevice == true {
            selectedID = setup?.continuation?.deviceID
            page = .install
        } else {
            if let identity, let result, result.isComplete {
                let device = ConnectedDevice(id: identity.deviceID, name: priorDevice?.name ?? "",
                    transport: identity.currentTransport == .usb ? .usb : .wifi, osVersion: priorDevice?.osVersion)
                inspection = DeviceInspection(device: device, developerMode: priorDeveloperMode,
                    installed: true, vpnInstalled: nil, appVersion: result.app?.build,
                    teamID: result.teamID, expiresAt: result.expiresAt)
                firstInstall = false
                page = .device
            } else { page = selectedID == nil ? .home : .device }
        }
    }

    public func finishReinstall() async {
        guard !busy, reinstall?.snapshot?.isComplete == true || reinstall?.snapshot?.isAbandoned == true else { return }
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
    }
    public var ready: Bool { environment?.ready == true && !busy }
    public var selected: ConnectedDevice? {
        if let inspection, inspection.device.id.lowercased() == selectedID?.lowercased(),
           selectedTransport == nil || inspection.device.transport == selectedTransport { return inspection.device }
        return devices.first {
            $0.id.lowercased() == selectedID?.lowercased() && (selectedTransport == nil || $0.transport == selectedTransport)
        }
    }
    public var visibleDevices: [ConnectedDevice] { ConnectedDevice.unique(devices, usbOnly: firstInstall) }
    public var availableConnections: [ConnectedDevice] { ConnectedDevice.connectionChoices(devices, usbOnly: firstInstall) }
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
        if setupLocksDevice && destination != .home && destination != activeOperationPage && destination != .environment {
            page = activeOperationPage; return
        }
        if !isPreview && destination != .home && destination != .environment &&
            !(destination == activeOperationPage && setupLocksDevice) &&
            !(destination == .install && setup?.hasRecordedTransaction == true) &&
            !(destination == .reinstall && reinstall?.hasRecordedTransaction == true) &&
            !((destination == .signing || destination == .repair) && management?.hasRecordedTransaction == true) &&
            environment?.ready != true {
            page = .environment; return
        }
        if (destination == .signing && management?.continuation?.kind == .repair) ||
            (destination == .repair && management?.continuation?.kind == .renew) {
            management?.resetSelection()
        }
        page = destination; failure = nil; previewMessage = nil
    }

    public func openRecordedOperation() {
        if management?.hasRecordedTransaction == true || management?.locksDevice == true {
            navigate(management?.continuation?.kind == .repair ? .repair : .signing)
        } else if reinstall?.hasRecordedTransaction == true || reinstall?.locksDevice == true {
            navigate(.reinstall)
        } else { navigate(.install) }
    }

    public func switchMode(preview: Bool) {
        guard !setupLocksDevice else { return }
        if checkingBusy {
            pendingCheckAction = .mode(preview)
            cancel()
            return
        }
        setup?.resetSelection()
        reinstall?.resetSelection()
        management?.resetSelection()
        cancel()
        isPreview = preview; environment = nil; devices = []; inspection = nil
        selectedID = nil; selectedTransport = nil; managementSelection = nil
        page = .home; previewStage = 0; previewMessage = nil; failure = nil
        if !preview && (setup?.isRestored == false || reinstall?.isRestored == false || management?.isRestored == false) {
            // A preview-only launch has intentionally not opened live records.
            // Explicitly switching back restores them before any live action.
            restoringOperations = true
            Task {
                await restoreSetup()
                restoringOperations = false
                checkEnvironment()
            }
        } else { checkEnvironment() }
    }

    public func select(_ id: String, transport: ConnectedDevice.Transport? = nil) {
        guard !busy, !setupLocksDevice,
              let choice = availableConnections.first(where: { $0.id == id && (transport == nil || $0.transport == transport) }) else { return }
        if selectedID?.lowercased() != id.lowercased() || selectedTransport != choice.transport {
            setup?.resetSelection()
            reinstall?.resetSelection()
        }
        management?.resetSelection()
        selectedID = id; selectedTransport = choice.transport
        managementSelection = MacManagementSelection(selectionID: UUID(), transport: choice.transport == .usb ? .usb : .network)
        inspection = nil; failure = nil
    }

    public func openDevices(firstInstall: Bool) {
        guard ready, !setupLocksDevice else { return }
        setup?.resetSelection()
        reinstall?.resetSelection()
        management?.resetSelection()
        self.firstInstall = firstInstall; selectedID = nil; selectedTransport = nil; managementSelection = nil; inspection = nil
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
        management?.resetSelection()
        devices = []; selectedID = nil; selectedTransport = nil; managementSelection = nil; inspection = nil
        perform(.devices) { data, request in
            self.devices = ConnectedDevice.connectionChoices(try ResponseDecoder.decode(data, for: request, as: DeviceList.self).devices,
                                                   usbOnly: false)
        }
    }

    public func inspectSelected() {
        guard let device = selected, ready, !setupLocksDevice else { return }
        inspection = nil
        perform(.inspect, deviceID: device.id, transport: device.transport) { data, request in
            let result = try ResponseDecoder.decode(data, for: request, as: DeviceInspection.self)
            guard result.device.id.lowercased() == device.id.lowercased(),
                  result.device.transport == device.transport else { throw CheckFailure.invalidResponse }
            self.inspection = result
            self.page = self.firstInstall ? .install : .device
            self.beginAutomaticManagement(after: result)
        }
    }

    private func beginAutomaticManagement(after inspection: DeviceInspection) {
        guard !isPreview, !firstInstall, let management, !management.locksDevice,
              inspection.installed == true, inspection.developerMode == true,
              let selection = managementSelection,
              selection.selectionID != dispatchedManagementSelection,
              selection.transport == (inspection.device.transport == .usb ? .usb : .network),
              let team = environment?.teamID,
              let options = try? MacManagementOptions(source: .project, teamID: team) else { return }
        // This dispatch only follows an explicit selection and its exact
        // authenticated inspection, never discovery, navigation or refresh.
        dispatchedManagementSelection = selection.selectionID
        automaticManagementBusy = true
        page = .signing
        automaticManagementTask = Task {
            await management.automaticRenew(deviceID: inspection.device.id, selection: selection, options: options)
            automaticManagementBusy = false
            automaticManagementTask = nil
        }
    }

    public func cancel() {
        generation = UUID()
        if checkingBusy { isCancellingCheck = true }
        task?.cancel()
        // A cancelled refresh cannot leave apparently current device evidence.
        inspection = nil
    }

    public func cancelManagement() {
        automaticManagementTask?.cancel()
        management?.cancel()
    }

    public func applyScenario() {
        guard isPreview else { return }
        if checkingBusy {
            pendingCheckAction = .scenario
            cancel()
            return
        }
        cancel(); failure = nil; inspection = nil; selectedID = nil; selectedTransport = nil; managementSelection = nil; devices = []
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
        default: break
        }
    }

    private func perform(_ action: CheckAction, deviceID: String? = nil, transport: ConnectedDevice.Transport? = nil,
                         apply: @escaping @MainActor (Data, CheckRequest) throws -> Void) {
        guard !busy else { return }
        checkingBusy = true; failure = nil
        isCancellingCheck = false
        let token = UUID(); generation = token; activeCheckID = token
        let request = CheckRequest(action: action, deviceID: deviceID, transport: transport)
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
