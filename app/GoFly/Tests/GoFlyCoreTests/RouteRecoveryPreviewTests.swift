import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct RouteRecoveryPreviewTests {
    @Test func constructorBuildsAFullGPXPreviewWithoutAdapterCommands() async throws {
        let coordinates = (0..<10_000).map {
            GeoCoordinate(latitude: 25 + Double($0) / 1_000_000, longitude: 121)!
        }
        let document = try GPXDocument(content: .routes([GPXRoute(points: coordinates)]))
        let source = try GPXRouteSource(document: document, displayFilename: "saved.gpx")
        let draft = RouteDraft(gpx: source)
        let device = PreviewDevice()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: draft, planner: PreviewPlanner(), commands: service,
                                                   search: PreviewSearch())

        #expect(controller.plannedRoute?.points.count == 10_000)
        #expect(controller.draft.gpxSource == source)
        #expect(await device.prepareCount == 0)
        #expect(await device.moveCount == 0)
    }

    @Test func manualDraftPlansPreviewRouteAutomaticallyWhenValid() async throws {
        let c1 = GeoCoordinate(latitude: 25.0, longitude: 121.0)!
        let c2 = GeoCoordinate(latitude: 25.1, longitude: 121.1)!
        let p1 = MapPlace(id: .coordinate(c1), title: "Start", coordinate: c1)
        let p2 = MapPlace(id: .coordinate(c2), title: "End", coordinate: c2)
        guard let draft = RouteDraft(values: [.place(p1), .place(p2)]) else {
            Issue.record("Failed to create manual draft")
            return
        }
        let device = PreviewDevice()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: draft, planner: PreviewPlanner(), commands: service,
                                                   search: PreviewSearch())

        // Allow preview Task to run
        try await Task.sleep(for: .milliseconds(50))

        #expect(controller.plannedRoute != nil)
        #expect(controller.error == nil)
        #expect(controller.canEdit)
        #expect(await device.prepareCount == 0)
    }

    @Test func manualDraftPlanningFailureSetsErrorForToast() async throws {
        let c1 = GeoCoordinate(latitude: 25.0, longitude: 121.0)!
        let c2 = GeoCoordinate(latitude: 48.8, longitude: 2.3)!
        let p1 = MapPlace(id: .coordinate(c1), title: "Taipei", coordinate: c1)
        let p2 = MapPlace(id: .coordinate(c2), title: "Paris", coordinate: c2)
        guard let draft = RouteDraft(values: [.place(p1), .place(p2)]) else {
            Issue.record("Failed to create manual draft")
            return
        }
        let device = PreviewDevice()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: draft, planner: FailingPlanner(), commands: service,
                                                   search: PreviewSearch())

        // Allow preview Task to run
        try await Task.sleep(for: .milliseconds(50))

        #expect(controller.plannedRoute == nil)
        #expect(controller.error == RouteExecutionFailure.planningFailed)
        #expect(controller.canEdit)
    }
}

private actor PreviewDevice: DeviceService {
    private(set) var prepareCount = 0
    private(set) var moveCount = 0
    func prepare() async throws { prepareCount += 1 }
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        moveCount += 1
        return .notSent(.operationCancelled)
    }
}

private struct PreviewPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}

private struct FailingPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        throw RouteExecutionFailure.planningFailed
    }
}

private struct PreviewSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
