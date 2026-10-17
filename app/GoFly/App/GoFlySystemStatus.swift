import Combine
import CoreLocation
import GoFlyCore
import UIKit

/// Reads system status for the settings pages. Constructing this model never
/// asks for location access, opens another app, or creates a device session.
@MainActor
final class GoFlySystemStatus: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var locationAuthorization: CLAuthorizationStatus
    @Published private(set) var locationServicesEnabled: Bool?
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var backgroundRefreshStatus: UIBackgroundRefreshStatus
    @Published private(set) var externalOpenFailed = false

    private let locationManager: CLLocationManager
    private var servicesQueryTask: Task<Void, Never>?

    override init() {
        locationManager = CLLocationManager()
        locationAuthorization = locationManager.authorizationStatus
        locationServicesEnabled = nil
        accuracyAuthorization = locationManager.accuracyAuthorization
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        super.init()
        locationManager.delegate = self
        refresh()
    }

    var locationStatusKey: String {
        guard let locationServicesEnabled else { return "settings.status.unknown" }
        guard locationServicesEnabled else { return "settings.status.locationServicesOff" }
        switch locationAuthorization {
        case .authorizedAlways, .authorizedWhenInUse:
            return accuracyAuthorization == .fullAccuracy
                ? "settings.status.authorized" : "settings.status.authorizedApproximate"
        case .denied: return "settings.status.denied"
        case .restricted: return "settings.status.restricted"
        case .notDetermined: return "settings.status.notDetermined"
        @unknown default: return "settings.status.unknown"
        }
    }

    var backgroundStatusKey: String {
        switch backgroundRefreshStatus {
        case .available: return "settings.background.on"
        case .denied: return "settings.background.off"
        case .restricted: return "settings.status.restricted"
        @unknown default: return "settings.status.unknown"
        }
    }

    func refresh() {
        locationAuthorization = locationManager.authorizationStatus
        if servicesQueryTask == nil {
            servicesQueryTask = Task { @MainActor [weak self] in
                let enabled = await Task.detached(priority: .utility) {
                    CLLocationManager.locationServicesEnabled()
                }.value
                guard let self else { return }
                self.locationServicesEnabled = enabled
                self.servicesQueryTask = nil
            }
        }
        accuracyAuthorization = locationManager.accuracyAuthorization
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
    }

    /// Opens the actual system settings URL and records only whether the OS
    /// accepted the open request. Returning to the app triggers a fresh read.
    func openSystemSettings() {
        externalOpenFailed = false
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            externalOpenFailed = true
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            Task { @MainActor in
                if !opened { self?.externalOpenFailed = true }
            }
        }
    }

    func openLocalDevVPN() {
        externalOpenFailed = false
        guard let url = URL(string: "localdevvpn://") else {
            externalOpenFailed = true
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            Task { @MainActor in
                if !opened { self?.externalOpenFailed = true }
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    func deviceSnapshot(service: ServiceController) -> GoFlyDeviceSnapshot {
        GoFlyDeviceSnapshot(
            pairingReady: PairingFileStore.isReady,
            signingExpiry: nil,
            serviceStatus: goFlyString(service.statusKey),
            appVersion: Self.appVersion,
            deviceName: UIDevice.current.name,
            deviceModel: UIDevice.current.model,
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion
        )
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "\(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return version
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return goFlyString("settings.notObtained")
        }
    }
}

@MainActor
struct GoFlyDeviceSnapshot {
    let pairingReady: Bool
    let signingExpiry: String?
    let serviceStatus: String
    let appVersion: String
    let deviceName: String
    let deviceModel: String
    let systemName: String
    let systemVersion: String

    var pairingStatus: String {
        goFlyString(pairingReady ? "settings.device.pairingReady" : "settings.notObtained")
    }

    var signingExpiryStatus: String {
        signingExpiry ?? goFlyString("settings.notObtained")
    }
}

extension VPNCheckState {
    var settingsStatusKey: String {
        switch self {
        case .unknown: return "settings.status.unknown"
        case .checking: return "settings.status.checking"
        case .reachable: return "settings.status.available"
        case .unavailable: return "settings.status.unavailable"
        case .timedOut: return "settings.status.timedOut"
        }
    }
}
