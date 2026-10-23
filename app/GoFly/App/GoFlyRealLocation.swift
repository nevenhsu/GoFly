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
        if CLLocationManager.locationServicesEnabled(),
           manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            start()
        }
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if let loc = manager.location {
                publish(loc)
            }
            manager.startUpdatingLocation()
        case .notDetermined, .denied, .restricted:
            break
        @unknown default:
            break
        }
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
            if let loc = manager.location {
                publish(loc)
            }
            manager.startUpdatingLocation()
        case .denied, .restricted:
            fail("location.permissionDenied")
        @unknown default:
            fail("location.noFix")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.awaitingPermission, self.manager.authorizationStatus != .notDetermined {
                self.awaitingPermission = false
                self.requestRecenter()
            } else if self.manager.authorizationStatus == .authorizedWhenInUse || self.manager.authorizationStatus == .authorizedAlways {
                self.start()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.publish(location)
        }
    }

    private func publish(_ location: CLLocation) {
        let observation = RealLocationObservation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            observedAt: location.timestamp,
            isSoftwareSimulated: location.sourceInformation?.isSimulatedBySoftware == true
        )
        self.observation = observation
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in self?.fail("location.noFix") }
    }

    private func fail(_ key: String) {
        observation = nil
        // Indoor lack of GPS is normal in simulation; never surface a warning banner or block operation.
        guard key != "location.noFix" else { return }
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
