import GoFlyCore
import MapKit

@MainActor
final class MapKitPlaceSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] {
        try Task.checkCancellation()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let operation = MapKitSearchOperation(request: request)
        return try await withTaskCancellationHandler {
            let response = try await operation.start()
            try Task.checkCancellation()
            var seen: Set<PlaceIdentity> = []
            return response.mapItems.compactMap { item in
                guard let coordinate = GeoCoordinate(
                    latitude: item.location.coordinate.latitude,
                    longitude: item.location.coordinate.longitude
                ) else { return nil }
                let identity = item.identifier.map { PlaceIdentity.mapKit($0.rawValue) }
                    ?? .coordinate(coordinate)
                guard seen.insert(identity).inserted else { return nil }
                let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let address = item.address?.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = [name, address].compactMap { $0 }.first { !$0.isEmpty } ?? coordinate.displayText
                return MapPlace(id: identity, title: title, coordinate: coordinate, address: address)
            }
        } onCancel: {
            Task { @MainActor in operation.cancel() }
        }
    }
}

/// Keeps the non-Sendable MapKit request on one actor, including cancellation.
@MainActor
private final class MapKitSearchOperation {
    private let search: MKLocalSearch
    init(request: MKLocalSearch.Request) { search = MKLocalSearch(request: request) }
    func start() async throws -> MKLocalSearch.Response { try await search.start() }
    func cancel() { search.cancel() }
}
