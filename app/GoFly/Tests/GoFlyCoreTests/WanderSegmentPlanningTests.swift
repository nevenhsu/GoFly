import Testing
@testable import GoFlyCore

@MainActor
struct WanderSegmentPlanningTests {
    @Test func segmentStartsAtTheLivePositionWhenTheRoadStartsElsewhere() async throws {
        let origin = try #require(GeoCoordinate(latitude: 25.0340, longitude: 121.5645))
        let road = try #require(GeoCoordinate(latitude: 25.0343, longitude: 121.5649))
        let target = try #require(GeoCoordinate(latitude: 25.0600, longitude: 121.5645))
        let route = RouteExecutionController(planner: RoadPlanner(roadStart: road),
            commands: ServiceController(service: SegmentDevice()), search: SegmentSearch())
        let planned = try await route.planWanderSegment(from: origin, to: target)
        #expect(planned.start == origin)
        #expect(planned.points[1] == road)
    }

    @Test func segmentAlreadyOnTheRoadIsUnchanged() async throws {
        let origin = try #require(GeoCoordinate(latitude: 25.0340, longitude: 121.5645))
        let target = try #require(GeoCoordinate(latitude: 25.0600, longitude: 121.5645))
        let route = RouteExecutionController(planner: RoadPlanner(roadStart: origin),
            commands: ServiceController(service: SegmentDevice()), search: SegmentSearch())
        let planned = try await route.planWanderSegment(from: origin, to: target)
        #expect(planned.points == [origin, target])
    }
}

private struct RoadPlanner: RoutePlanning {
    let roadStart: GeoCoordinate
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [roadStart, to] }
}
private struct SegmentSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
private actor SegmentDevice: DeviceService {
    func prepare() async throws {}
    func resetClientConnection() async throws {}
    func rebuildClientConnection() async throws {}
    func clearLocation() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        return .acknowledged
    }
}
