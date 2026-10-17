import Testing
@testable import GoFlyCore

struct GeoCoordinateTests {
    @Test func onlyFiniteCoordinatesWithinGeographicBoundsCanBecomeDestinations() {
        #expect(GeoCoordinate(latitude: 25.033, longitude: 121.5654)?.displayText == "25.033000, 121.565400")
        #expect(GeoCoordinate(latitude: -90, longitude: -180) != nil)
        #expect(GeoCoordinate(latitude: 90, longitude: 180) != nil)
        #expect(GeoCoordinate(latitude: 90.001, longitude: 121) == nil)
        #expect(GeoCoordinate(latitude: 25, longitude: -180.001) == nil)
        #expect(GeoCoordinate(latitude: .nan, longitude: 121) == nil)
        #expect(GeoCoordinate(latitude: 25, longitude: .infinity) == nil)
    }
}
