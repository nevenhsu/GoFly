import Combine
import CoreLocation
import Foundation

enum LocalGoRecenterResult: Equatable {
    case available
    case waitingForPermission
    case openSettings
}

/// A foreground-only location reader used for explicit map recentering.
///
/// It never asks for authorization during startup. Permission is requested
/// only after the user taps the recenter control.
@MainActor
final class LocalGoCurrentLocation: NSObject, ObservableObject {
    @Published private(set) var coordinate: CLLocationCoordinate2D? = nil
    @Published private(set) var courseDegrees: CLLocationDirection? = nil
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var recenterGeneration: UInt64 = 0

    private let manager: CLLocationManager
    private var pendingRecenter = false
    private var foreground = false
    private var coordinateDate: Date?

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1
    }

    func start() {
        foreground = true
        authorizationStatus = manager.authorizationStatus
        guard isAuthorized(authorizationStatus) else {
            coordinate = nil
            courseDegrees = nil
            coordinateDate = nil
            return
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        foreground = false
        manager.stopUpdatingLocation()
        coordinate = nil
        courseDegrees = nil
        coordinateDate = nil
    }

    func requestRecenter() -> LocalGoRecenterResult {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            if coordinate != nil, let coordinateDate, Self.isRecent(coordinateDate) { return .available }
            coordinate = nil
            courseDegrees = nil
            coordinateDate = nil
            pendingRecenter = true
            return .waitingForPermission
        case .notDetermined:
            pendingRecenter = true
            manager.requestWhenInUseAuthorization()
            return .waitingForPermission
        case .denied, .restricted:
            pendingRecenter = false
            return .openSettings
        @unknown default:
            pendingRecenter = false
            return .openSettings
        }
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedAlways || status == .authorizedWhenInUse
    }

    private func receiveAuthorization(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        guard isAuthorized(status) else {
            coordinate = nil
            courseDegrees = nil
            coordinateDate = nil
            if status == .denied || status == .restricted {
                pendingRecenter = false
            }
            return
        }
        guard foreground else { return }
        manager.startUpdatingLocation()
    }

    private func receiveLocation(coordinate: CLLocationCoordinate2D, course: CLLocationDirection, timestamp: Date) {
        guard foreground, isAuthorized(manager.authorizationStatus),
              CLLocationCoordinate2DIsValid(coordinate), Self.isRecent(timestamp) else { return }
        self.coordinate = coordinate
        coordinateDate = timestamp
        courseDegrees = course.isFinite && course >= 0 ? Self.normalized(course) : nil

        guard pendingRecenter else { return }
        pendingRecenter = false
        recenterGeneration &+= 1
    }

    private static func normalized(_ degrees: CLLocationDirection) -> CLLocationDirection {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private static func isRecent(_ timestamp: Date) -> Bool {
        let age = Date().timeIntervalSince(timestamp)
        return age >= -5 && age <= 30
    }
}

extension LocalGoCurrentLocation: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.receiveAuthorization(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy.isFinite, location.horizontalAccuracy >= 0 else { return }
        let coordinate = location.coordinate
        let course = location.course
        let timestamp = location.timestamp
        Task { @MainActor [weak self] in
            self?.receiveLocation(coordinate: coordinate, course: course, timestamp: timestamp)
        }
    }
}
