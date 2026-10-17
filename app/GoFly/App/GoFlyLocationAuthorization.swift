import CoreLocation
import GoFlyCore

/// Requests permission only. Onboarding never asks for a GPS fix.
@MainActor
final class GoFlyLocationAuthorization: NSObject, LocationAuthorizing, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<LocationAuthorization, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
    }

    var authorization: LocationAuthorization {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestAuthorization() async -> LocationAuthorization {
        guard authorization == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            let isFirstRequest = waiters.isEmpty
            waiters.append(continuation)
            if isFirstRequest { manager.requestWhenInUseAuthorization() }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.authorization != .notDetermined else { return }
            let result = self.authorization
            let continuations = self.waiters
            self.waiters.removeAll()
            for continuation in continuations { continuation.resume(returning: result) }
        }
    }
}
