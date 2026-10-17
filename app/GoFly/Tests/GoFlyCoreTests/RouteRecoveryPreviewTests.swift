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

private struct PreviewSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
