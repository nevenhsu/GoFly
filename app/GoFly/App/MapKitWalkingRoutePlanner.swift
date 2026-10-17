import CoreLocation
import GoFlyCore
import MapKit

/// Directions planning never opens a device session or moves the phone.
@MainActor
final class MapKitWalkingRoutePlanner: RoutePlanning {
    func plan(from start: GeoCoordinate, to end: GeoCoordinate) async throws -> [GeoCoordinate] {
        try Task.checkCancellation()
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        let operation = WalkingDirectionsOperation(request: request)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let response = try await operation.calculate()
            try Task.checkCancellation()
            guard let route = response.routes.first,
                  (2...10_000).contains(route.polyline.pointCount) else {
                throw RouteExecutionFailure.planningFailed
            }
            var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: route.polyline.pointCount)
            route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
            let points = coordinates.compactMap { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
            guard points.count == coordinates.count else { throw RouteExecutionFailure.invalidPath }
            return points
        } onCancel: {
            Task { @MainActor in operation.cancel() }
        }
    }
}

@MainActor
private final class WalkingDirectionsOperation {
    private let directions: MKDirections
    init(request: MKDirections.Request) { directions = MKDirections(request: request) }
    func calculate() async throws -> MKDirections.Response { try await directions.calculate() }
    func cancel() { directions.cancel() }
}
