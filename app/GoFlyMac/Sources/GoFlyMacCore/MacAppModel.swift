import Foundation
import Observation

public enum MacPage: String, CaseIterable, Sendable {
    case home, environment, devices, device, install, handoff
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
    private var checkingBusy = false
    private var verifiedSetupID: UUID?
    public private(set) var isCancellingCheck = false
    public var isChecking: Bool { checkingBusy }
    public let setup: MacSetupModel?
    private var restoringOperations = false
    public private(set) var failure: CheckFailure?
    public private(set) var firstInstall = true
    public private(set) var previewStage = 0
    public private(set) var previewMessage: String?
    public var previewScenario: PreviewScenario = .ready
    @ObservationIgnored private let live: any MacChecking
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeCheckID: UUID?
    private enum PendingCheckAction { case mode(Bool), scenario }
    @ObservationIgnored private var pendingCheckAction: PendingCheckAction?
    @ObservationIgnored private var renewTriggeredSelection: String?

    public init(live: any MacChecking, setup: MacSetupModel? = nil) {
        self.live = live
        self.setup = setup
    }

    public var busy: Bool {
        checkingBusy || restoringOperations || (!isPreview && setup?.isBusy == true)
    }
    public var setupLocksDevice: Bool {
        restoringOperations || (!isPreview && setup?.locksDevice == true)
    }
    private var activeOperationPage: MacPage { .install }

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
            environment?.ready != true {
            page = .environment; return
        }
        page = destination; failure = nil; previewMessage = nil
    }

    public func openRecordedOperation() {
        navigate(.install)
    }

    public func switchMode(preview: Bool) {
        guard !setupLocksDevice else { return }
        if checkingBusy {
            pendingCheckAction = .mode(preview)
            cancel()
            return
        }
        setup?.resetSelection()
        cancel()
        isPreview = preview; environment = nil; devices = []; inspection = nil
        selectedID = nil; selectedTransport = nil
        page = .home; previewStage = 0; previewMessage = nil; failure = nil
        if !preview && setup?.isRestored == false {
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
        }
        selectedID = id; selectedTransport = choice.transport
        inspection = nil; failure = nil
        renewTriggeredSelection = nil
    }

    public func openDevices(firstInstall: Bool) {
        guard ready, !setupLocksDevice else { return }
        setup?.resetSelection()
        self.firstInstall = firstInstall; selectedID = nil; selectedTransport = nil; inspection = nil
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
        devices = []; selectedID = nil; selectedTransport = nil; inspection = nil
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
            self.triggerAutomaticRenewIfNeeded(device)
        }
    }

    private func triggerAutomaticRenewIfNeeded(_ device: ConnectedDevice) {
        guard !isPreview, !firstInstall, inspection?.installed == true,
              renewTriggeredSelection != device.connectionID,
              let setup, setup.isRestored, !setup.isBusy, !setup.hasRecordedTransaction,
              let team = environment?.teamID,
              let options = try? MacSetupOptions(source: .project, teamID: team) else { return }
        renewTriggeredSelection = device.connectionID
        do {
            try setup.beginRenew(deviceID: device.id, options: options)
        } catch {
            renewTriggeredSelection = nil
        }
    }

    public func startRenew() {
        guard !busy, let device = selected, inspection?.installed == true,
              let setup, setup.isRestored, !setup.isBusy,
              let team = environment?.teamID,
              let options = try? MacSetupOptions(source: .project, teamID: team) else { return }
        if setup.hasRecordedTransaction && setup.snapshot?.isComplete != true {
            page = .install
            return
        }
        do {
            try setup.beginRenew(deviceID: device.id, options: options)
            page = .install
        } catch {
            page = .install
        }
    }

    public func cancel() {
        generation = UUID()
        if checkingBusy { isCancellingCheck = true }
        task?.cancel()
        inspection = nil
    }

    public func applyScenario() {
        guard isPreview else { return }
        if checkingBusy {
            pendingCheckAction = .scenario
            cancel()
            return
        }
        cancel(); failure = nil; inspection = nil; selectedID = nil; selectedTransport = nil; devices = []
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
