import Combine
import CoreLocation
import GoFlyCore

/// Opt-in, one-shot GPS observation. Creating this object never requests permission.
@MainActor
final class GoFlyRealLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var observation: RealLocationObservation?
    @Published private(set) var noticeKey: String?

    private let manager = CLLocationManager()
    private var awaitingPermission = false
    private var shownNoticeCauses: Set<String> = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestRecenter() {
        guard CLLocationManager.locationServicesEnabled() else {
            fail("location.disabled")
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            awaitingPermission = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            fail("location.permissionDenied")
        @unknown default:
            fail("location.noFix")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.awaitingPermission,
                  self.manager.authorizationStatus != .notDetermined else { return }
            self.awaitingPermission = false
            self.requestRecenter()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let observation = locations.last.flatMap { location -> RealLocationObservation? in
            guard abs(location.timestamp.timeIntervalSinceNow) <= 15 else { return nil }
            return RealLocationObservation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                observedAt: location.timestamp,
                isSoftwareSimulated: location.sourceInformation?.isSimulatedBySoftware == true
            )
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let observation else {
                self.fail("location.noFix")
                return
            }
            self.observation = observation
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in self?.fail("location.noFix") }
    }

    private func fail(_ key: String) {
        observation = nil
        guard shownNoticeCauses.insert(key).inserted else { return }
        noticeKey = key
    }

    func dismissNotice() {
        noticeKey = nil
    }

    func acceptedFix() {
        noticeKey = nil
    }

    func rejectedFix() {
        fail("location.noFix")
    }
}
