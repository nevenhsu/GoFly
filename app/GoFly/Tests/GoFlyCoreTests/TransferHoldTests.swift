import Foundation
import Testing
import GoFlyCore

@Suite @MainActor
struct TransferHoldTests {
    @Test func ownerBoundHoldBlocksMutationsAndRejectsForeignOrStaleTokens() throws {
        let persistence = EmptyFavoritePlacesPersistence()
        let first = FavoritePlacesStore(persistence: persistence)
        let second = FavoritePlacesStore(persistence: persistence)
        let hold = try #require(first.acquireTransferHold())
        let foreign = try #require(second.acquireTransferHold())
        #expect(first.acquireTransferHold() == nil)
        #expect(!first.releaseTransferHold(foreign))
        #expect(second.releaseTransferHold(foreign))
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let place = MapPlace(id: .coordinate(coordinate), title: "Taipei", coordinate: coordinate)
        #expect(!first.toggle(place))
        #expect(!first.releaseTransferHold(foreign))
        #expect(first.releaseTransferHold(hold))
        #expect(!first.releaseTransferHold(hold))
    }
}

private struct EmptyFavoritePlacesPersistence: FavoritePlacesPersistence {
    func read() throws -> Data? { nil }
    func transferSnapshot() throws -> Data? { nil }
    func replaceAtomically(with data: Data) throws {}
}
