public protocol PlaceResolving: Sendable {
    func resolve(at coordinate: GeoCoordinate) async throws -> MapPlace?
}
