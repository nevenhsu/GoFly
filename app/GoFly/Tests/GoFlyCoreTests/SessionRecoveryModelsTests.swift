import Foundation
import Testing
import GoFlyCore

struct SessionRecoveryModelsTests {
    @Test func routeDraftNodeConstructorPreservesIDsOrderAndRejectsInvalidManualData() throws {
        let startID = RouteNodeID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let destinationID = RouteNodeID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let nodes = [RouteNode(id: startID, value: .current),
                     RouteNode(id: destinationID, value: .place(place(1)))]

        let draft = try #require(RouteDraft(nodes: nodes, speed: .standard))
        #expect(draft.nodes.map(\.id) == [startID, destinationID])
        #expect(draft.nodes.map(\.value) == nodes.map(\.value))

        #expect(RouteDraft(nodes: [RouteNode(value: .current), RouteNode(value: .current)]) == nil)
        #expect(RouteDraft(nodes: Array(repeating: RouteNode(value: .place(place(2))), count: 28)) == nil)
        #expect(RouteDraft(nodes: [RouteNode(id: startID, value: .current),
                                   RouteNode(id: startID, value: .place(place(3)))]) == nil)
    }

    private func place(_ index: Int) -> MapPlace {
        let coordinate = GeoCoordinate(latitude: 25 + Double(index) * 0.001, longitude: 121)!
        return MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
    }

}
