import Testing
@testable import GoFlyCore

@MainActor
struct CandidateControllerTests {
    private struct NoResults: PlaceSearching {
        func search(query: String) async throws -> [MapPlace] { [] }
    }

    @Test func unchangedTextAfterSelectingAResultKeepsGoEnabled() throws {
        let search = CandidateController(search: NoResults(), debounce: .seconds(60))
        let coordinate = try #require(GeoCoordinate(latitude: 25.0340, longitude: 121.5645))
        search.updateQuery("taipei 101")
        #expect(!search.canGo)
        search.select(MapPlace(id: .coordinate(coordinate), title: "Taipei 101", coordinate: coordinate))
        #expect(search.canGo)
        // The field re-sends its text on focus loss.
        search.updateQuery("taipei 101")
        #expect(search.canGo)
        search.updateQuery("taipei 10")
        #expect(!search.canGo, "a real edit still requires a new selection")
    }
}
