import Foundation
import Observation

public enum MacPage: String, CaseIterable, Sendable {
    case home, environment, devices, device, install
}

@MainActor @Observable
public final class MacAppModel {
    public private(set) var page: MacPage = .home
    public private(set) var environment: MacEnvironment?
    public private(set) var devices: [ConnectedDevice] = []
    public private(set) var inspection: DeviceInspection?
    public private(set) var selectedID: String?
    public private(set) var selectedTransport: ConnectedDevice.Transport?
    private var checkingBusy = false
    public private(set) var isCancellingCheck = false
    public var isChecking: Bool { checkingBusy }
    public let setup: MacSetupModel?
    private var restoringOperations = false
    public private(set) var failure: CheckFailure?
    public private(set) var firstInstall = true
    public private(set) var selectedTeamID: String?
    public private(set) var hasCheckedEnvironment = false
    @ObservationIgnored private let live: any MacChecking
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeCheckID: UUID?
    @ObservationIgnored private var renewTriggeredSelection: String?
    private static let selectedTeamKey = "gofly.mac.selectedTeamID"

    public init(live: any MacChecking, setup: MacSetupModel? = nil) {
        self.live = live
        self.setup = setup
        self.selectedTeamID = UserDefaults.standard.string(forKey: Self.selectedTeamKey)
    }

    public var busy: Bool {
        checkingBusy || restoringOperations || setup?.isBusy == true
    }
    public var setupLocksDevice: Bool {
        restoringOperations || setup?.locksDevice == true
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

    public var ready: Bool { environment?.ready == true && selectedTeam != nil && !busy }
    public var shouldShowEnvironmentGate: Bool {
        !hasCheckedEnvironment || environment?.ready != true || selectedTeam == nil
    }
    public var selectedTeam: MacTeam? {
        guard let environment, let selectedTeamID else { return nil }
        return environment.teams.first { $0.teamID == selectedTeamID }
    }
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
    public var installedOnFirstInstall: Bool {
        firstInstall && inspection?.installed == true
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
        if destination != .home && destination != .environment &&
            !(destination == activeOperationPage && setupLocksDevice) &&
            !(destination == .install && setup?.hasRecordedTransaction == true) &&
            environment?.ready != true {
            page = .environment; return
        }
        page = destination; failure = nil
    }

    public func openRecordedOperation() {
        navigate(.install)
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
        showDevices(firstInstall: firstInstall, ignoreSetupLock: false)
    }

    /// Pure navigation back to the device list.  An unavailable environment or
    /// a blocked journal must not strand the user on an error page.
    public func returnToDevices() {
        showDevices(firstInstall: false, ignoreSetupLock: true)
    }

    private func showDevices(firstInstall: Bool, ignoreSetupLock: Bool) {
        guard !busy, ignoreSetupLock || !setupLocksDevice else { return }
        setup?.resetSelection()
        self.firstInstall = firstInstall; selectedID = nil; selectedTransport = nil; inspection = nil
        page = .devices
        if environment?.ready == true { refreshDevices() }
    }

    /// Moves from the first-install refusal to the selected phone's management
    /// page without running another inspection or starting setup.
    public func openSelectedDevicePage() {
        guard !busy, !setupLocksDevice, let device = selected else { return }
        setup?.resetSelection()
        firstInstall = false
        selectedID = device.id
        selectedTransport = device.transport
        page = .device
        failure = nil
        renewTriggeredSelection = nil
    }

    public func checkEnvironment() {
        guard !busy else { return }
        perform(.environment) { data, request in
            let value = try ResponseDecoder.decode(data, for: request, as: MacEnvironment.self)
            self.applyEnvironment(value)
        }
    }

    private func applyEnvironment(_ value: MacEnvironment) {
        environment = value
        hasCheckedEnvironment = true
        if let selectedTeamID, value.teams.contains(where: { $0.teamID == selectedTeamID }) {
            return
        }
        if value.teams.count == 1 {
            selectedTeamID = value.teams[0].teamID
        } else {
            selectedTeamID = nil
        }
    }

    public func selectTeam(_ teamID: String) {
        guard let team = environment?.teams.first(where: { $0.teamID == teamID }) else { return }
        selectedTeamID = team.teamID
        UserDefaults.standard.set(team.teamID, forKey: Self.selectedTeamKey)
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
        guard !firstInstall, inspection?.installed == true,
              renewTriggeredSelection != device.connectionID,
              let setup, setup.isRestored, !setup.isBusy, !setup.hasRecordedTransaction,
              let team = selectedTeam?.teamID,
              let options = try? MacSetupOptions(teamID: team) else { return }
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
              let team = selectedTeam?.teamID,
              let options = try? MacSetupOptions(teamID: team) else { return }
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

    private func perform(_ action: CheckAction, deviceID: String? = nil, transport: ConnectedDevice.Transport? = nil,
                         apply: @escaping @MainActor (Data, CheckRequest) throws -> Void) {
        guard !busy else { return }
        checkingBusy = true; failure = nil
        isCancellingCheck = false
        let token = UUID(); generation = token; activeCheckID = token
        let request = CheckRequest(action: action, deviceID: deviceID, transport: transport)
        task = Task {
            defer { self.finishCheck(token) }
            do {
                let result = try await live.check(request)
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
        hasCheckedEnvironment = true
    }
}
