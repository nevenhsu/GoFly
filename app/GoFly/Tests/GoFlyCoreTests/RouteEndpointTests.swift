import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct RouteEndpointTests {
    @Test func newDraftHasCurrentStartAndEmptyDestination() {
        let draft = RouteDraft()
        #expect(draft.nodes.map(\.value) == [.current, .empty])
        #expect(draft.hasEmptyEndpoint)
    }

    @Test func clearingStartAndDestinationKeepsRowsButWaypointRowsAreDeleted() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let route = fixture(draft: draft)
        let ids = draft.nodes.map(\.id)

        #expect(route.removeNode(id: ids[1]))
        #expect(route.draft.nodes.map(\.id) == [ids[0], ids[2]], "waypoint row is deleted")

        #expect(route.removeNode(id: ids[0]))
        #expect(route.draft.nodes.map(\.id) == [ids[0], ids[2]], "start row stays")
        #expect(route.draft.start?.value == .empty)
        #expect(route.removeNode(id: ids[2]))
        #expect(route.draft.nodes.map(\.value) == [.empty, .empty])
        #expect(route.draft.nodes.map(\.id) == [ids[0], ids[2]])
    }

    @Test func emptyEndpointDisablesStartAndNeverPlans() async throws {
        let planner = CountingPlanner()
        let draft = try #require(RouteDraft(start: .place(place(1)), destination: .place(place(2))))
        let route = fixture(draft: draft, planner: planner)
        await settle { route.plannedRoute != nil }
        #expect(planner.calls > 0)
        let before = planner.calls

        #expect(route.removeNode(id: draft.nodes[1].id))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!route.canStart)
        #expect(route.plannedRoute == nil)
        #expect(route.error == nil, "an empty endpoint is not a planning error")
        #expect(!route.start())
        #expect(planner.calls == before)
    }

    @Test func reversingSwapsEmptyValuesWithTheirRows() throws {
        let draft = try #require(RouteDraft(nodes: [RouteNode(value: .place(place(1))), RouteNode(value: .empty)]))
        let reversed = try #require(draft.reversing())
        #expect(reversed.nodes.map(\.value) == [.empty, .place(place(1))])
        #expect(reversed.start?.id == draft.nodes[1].id)
    }

    @Test func emptyEndpointsSurviveRecoveryAndLegacyLoneStartIsPadded() throws {
        let snapshot = SessionRecoverySnapshot(mode: .route, draft: RouteDraft())
        let decoded = try SessionRecoveryCodec.decode(SessionRecoveryCodec.encode(snapshot))
        #expect(decoded.draft.nodes.map(\.value) == [.current, .empty])

        let lone = try #require(RouteDraft(nodes: [RouteNode(value: .current)]))
        let padded = try SessionRecoveryCodec.decode(SessionRecoveryCodec.encode(SessionRecoverySnapshot(mode: .route, draft: lone)))
        #expect(padded.draft.nodes.map(\.value) == [.current, .empty])
    }

    @Test func favoriteSaveSkipsEmptyEndpointsAndNeedsTwoPlaces() throws {
        let draft = try #require(RouteDraft(nodes: [RouteNode(value: .place(place(1))), RouteNode(value: .empty)]))
        #expect(throws: FavoriteRoutesFailure.tooFewValidPlaces) {
            try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil)
        }
    }

    @Test func selectionDefaultsToStartAndOnlyTheSelectedFieldIsFilled() throws {
        let route = fixture(draft: RouteDraft())
        let ids = route.draft.nodes.map(\.id)
        #expect(route.selectedNodeID == ids[0], "new routes select the start")
        #expect(route.selectNode(id: ids[1]))
        #expect(route.picker == nil, "selecting a row never opens a picker")
        #expect(route.draft.nodes.map(\.value) == [.current, .empty])

        #expect(route.confirmSelectedNode(with: place(1)))
        #expect(route.draft.nodes.map(\.value) == [.current, .place(place(1))], "only the destination changes")
        #expect(route.selectedNodeID == ids[1])
        #expect(!route.selectNode(id: RouteNodeID()), "unknown rows cannot be selected")
    }

    @Test func selectionFallsBackToTheStartWhenItsRowDisappears() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let route = fixture(draft: draft)
        let ids = draft.nodes.map(\.id)
        #expect(route.selectNode(id: ids[1]))
        #expect(route.removeNode(id: ids[1]))
        #expect(route.selectedNodeID == ids[0])
        #expect(route.clearRoute())
        #expect(route.selectedNodeID == route.draft.start?.id)
    }

    @Test func selectedPickerIsOpenedForTheSelectedFieldOnly() throws {
        let route = fixture(draft: RouteDraft())
        let destination = route.draft.nodes[1].id
        #expect(route.selectNode(id: destination))
        #expect(route.openSelectedPicker())
        #expect(route.picker?.nodeID == destination)
        #expect(route.picker?.role == .destination)
        let session = try #require(route.picker)
        route.cancelPicker(id: session.id)
        #expect(route.draft.nodes[1].value == .empty, "backing out never changes the value")
    }

    @Test func undoRestoresTheOriginalValueAndPosition() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let route = fixture(draft: draft)
        let ids = draft.nodes.map(\.id)

        #expect(!route.canUndoRemoval)
        #expect(route.removeNode(id: ids[1]))
        #expect(route.draft.nodes.count == 2 && route.canUndoRemoval)
        #expect(route.undoRemoval())
        #expect(route.draft.nodes.map(\.id) == ids, "the waypoint row returns in its original position")
        #expect(route.draft.nodes.map(\.value) == draft.nodes.map(\.value))
        #expect(!route.canUndoRemoval, "an undo is consumed")

        #expect(route.removeNode(id: ids[0]))
        #expect(route.draft.start?.value == .empty)
        #expect(route.undoRemoval())
        #expect(route.draft.start?.value == .place(place(1)), "a cleared start gets its value back")
    }

    @Test func onlyTheLatestRemovalCanBeUndone() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3)), .place(place(4))]))
        let route = fixture(draft: draft)
        let ids = draft.nodes.map(\.id)
        #expect(route.removeNode(id: ids[1]))
        #expect(route.removeNode(id: ids[2]))
        #expect(route.draft.nodes.map(\.id) == [ids[0], ids[3]])
        #expect(route.undoRemoval())
        #expect(route.draft.nodes.map(\.id) == [ids[0], ids[2], ids[3]], "only the second delete comes back")
        #expect(!route.undoRemoval(), "the earlier delete is not recoverable")
    }

    @Test func undoIsUnavailableAfterAnotherEdit() throws {
        let draft = try #require(RouteDraft(values: [.place(place(1)), .place(place(2)), .place(place(3))]))
        let route = fixture(draft: draft)
        #expect(route.removeNode(id: draft.nodes[1].id))
        #expect(route.reverseNodes())
        #expect(!route.canUndoRemoval)
        #expect(!route.undoRemoval())
    }

    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    private func fixture(draft: RouteDraft, planner: any RoutePlanning = CountingPlanner()) -> RouteExecutionController {
        RouteExecutionController(draft: draft, planner: planner,
                                 commands: ServiceController(service: EndpointDevice()), search: EndpointSearch())
    }

    private func place(_ index: Int) -> MapPlace {
        let coordinate = GeoCoordinate(latitude: 25 + Double(index) * 0.01, longitude: 121)!
        return MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
    }
}

private final class CountingPlanner: RoutePlanning, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        lock.withLock { count += 1 }
        return [from, to]
    }
}
private struct EndpointSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
private actor EndpointDevice: DeviceService {
    func prepare() async throws {}
    func resetClientConnection() async throws {}
    func rebuildClientConnection() async throws {}
    func clearLocation() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        return .acknowledged
    }
}
