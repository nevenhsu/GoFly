import AppKit
import IOKit.pwr_mgt
import Network
@preconcurrency import UserNotifications
import GoFlyMacCore

@MainActor
final class MacAutoRenewRuntime {
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.neven.gofly.mac-network-monitor")
    private var scheduler: Task<Void, Never>?
    private var assertionID: IOPMAssertionID?
    private var lastHandledState: MacAutoRenewState = .idle

    func start(model: MacAppModel) {
        guard scheduler == nil else { return }
        monitor.pathUpdateHandler = { [weak model] path in
            Task { @MainActor in model?.setNetworkAvailable(path.status == .satisfied) }
        }
        monitor.start(queue: monitorQueue)
        scheduler = Task { @MainActor [weak model] in
            guard let model else { return }
            while !Task.isCancelled && (model.isChecking || !model.hasNetworkStatus) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            await model.checkAutomaticRenewal()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(MacAutoRenewPolicy.checkInterval))
                guard !Task.isCancelled else { return }
                await model.checkAutomaticRenewal()
            }
        }
    }

    func handle(_ state: MacAutoRenewState) {
        guard state != lastHandledState else { return }
        lastHandledState = state
        switch state {
        case .idle:
            break
        case .running:
            keepAwake()
            notify(titleKey: "auto-renew.notification.started.title",
                   bodyKey: "auto-renew.notification.started.body")
        case .completed:
            releaseAssertion()
            notify(titleKey: "auto-renew.notification.completed.title",
                   bodyKey: "auto-renew.notification.completed.body")
        case .failed:
            releaseAssertion()
            notify(titleKey: "auto-renew.notification.failed.title",
                   bodyKey: "auto-renew.notification.failed.body")
        case .cancelled:
            releaseAssertion()
        }
    }

    private func keepAwake() {
        guard assertionID == nil else { return }
        var identifier: IOPMAssertionID = 0
        let reason = MacLocalization.text("auto-renew.sleep-assertion.reason") as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &identifier
        )
        if result == kIOReturnSuccess { assertionID = identifier }
    }

    private func releaseAssertion() {
        guard let assertionID else { return }
        IOPMAssertionRelease(assertionID)
        self.assertionID = nil
    }

    private func notify(titleKey: String, bodyKey: String) {
        let title = MacLocalization.text(titleKey)
        let body = MacLocalization.text(bodyKey)
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            var authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
            }
            guard authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                                         content: content, trigger: nil))
        }
    }
}
