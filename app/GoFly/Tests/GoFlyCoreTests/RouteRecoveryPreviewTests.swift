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

        let deadline = ContinuousClock.now + .seconds(2)
        while controller.plannedRoute == nil && ContinuousClock.now < deadline { await Task.yield() }

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

        let deadline = ContinuousClock.now + .seconds(2)
        while controller.error == nil && ContinuousClock.now < deadline { await Task.yield() }

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

@Suite @MainActor
struct RoutePreviewUpdateTests {
    private let start = GeoCoordinate(latitude: 25.0477816, longitude: 121.5171495)!
    private let end = GeoCoordinate(latitude: 25.033649, longitude: 121.564824)!

    private func draft(to destination: GeoCoordinate) -> RouteDraft {
        RouteDraft(values: [start, destination].map {
            .place(MapPlace(id: .coordinate($0), title: $0.displayText, coordinate: $0))
        })!
    }

    @Test func retryReacquiresPreviewWhileDisconnectedWithoutStartingMovement() async throws {
        let device = PreviewDevice(), service = ServiceController(service: device)
        service.setMovementConnectionAvailable(false)
        let planner = RetryPreviewPlanner()
        let route = RouteExecutionController(draft: draft(to: end), planner: planner,
                                             commands: service, search: PreviewSearch())
        try await wait { route.error != nil }
        #expect(route.retryPlanning())
        try await wait { route.plannedRoute != nil }
        #expect(await planner.calls == 2)
        #expect(route.phase == .editing)
        #expect(route.error == nil)
        #expect(await device.prepareCount == 0)
        #expect(await device.moveCount == 0)
    }

    @Test func changingInputIgnoresOldResultEvenWhenProviderDoesNotCancel() async throws {
        let planner = HeldPreviewPlanner()
        let route = RouteExecutionController(draft: draft(to: end), planner: planner,
            commands: ServiceController(service: PreviewDevice()), search: PreviewSearch())
        try await wait { await planner.count == 1 }
        let replacement = GeoCoordinate(latitude: 25.02, longitude: 121.55)!
        #expect(route.openPicker(for: route.draft.destination!.id))
        let picker = try #require(route.picker)
        picker.candidates.select(MapPlace(id: .coordinate(replacement), title: "New end", coordinate: replacement))
        #expect(route.confirmPicker(id: picker.id))
        try await wait { await planner.count == 2 }
        await planner.finish(1)
        try await wait { route.plannedRoute?.end == replacement }
        await planner.finish(0)
        try await Task.sleep(for: .milliseconds(30))
        #expect(route.plannedRoute?.end == replacement)
        #expect(route.error == nil)
        #expect(route.phase == .editing)
    }

    @Test func multipleStopsContinueFromThePreviousRoadEntrance() async throws {
        let final = GeoCoordinate(latitude: 25.02, longitude: 121.55)!
        let source = draft(to: end).appendingDestination(MapPlace(id: .coordinate(final), title: "Final", coordinate: final))!
        let planner = EntrancePreviewPlanner()
        let route = RouteExecutionController(draft: source, planner: planner,
            commands: ServiceController(service: PreviewDevice()), search: PreviewSearch())
        try await wait { route.plannedRoute != nil || route.error != nil }
        let preview = try #require(route.plannedRoute)
        let starts = await planner.starts
        #expect(starts.count == 2)
        #expect(preview.waypoints.count == 1)
        #expect(starts.last == preview.waypoints.first)
        #expect(preview.waypoints.first != end)
    }

    @Test func startReusesSnappedPreviewAndBeginsAtItsRoadEntrance() async throws {
        let device = RouteControlledDevice(), service = ServiceController(service: device)
        let planner = EntrancePreviewPlanner()
        let route = RouteExecutionController(draft: draft(to: end), planner: planner,
                                             commands: service, search: PreviewSearch())
        try await wait { route.plannedRoute != nil }
        let roadStart = try #require(route.plannedRoute?.start)
        #expect(roadStart != start)
        #expect(route.start())
        try await wait { await device.waiting }
        #expect(await planner.calls == 1)
        #expect(await device.coordinates.first == roadStart)
        #expect(route.cancel())
        await device.finish(.notSent(.operationCancelled))
        try await wait { route.phase == .editing }
    }

    private func wait(_ predicate: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Preview did not settle")
    }
}

private actor RetryPreviewPlanner: RoutePlanning {
    private(set) var calls = 0
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        calls += 1
        if calls == 1 { throw RouteExecutionFailure.planningFailed }
        return [from, to]
    }
}

private actor HeldPreviewPlanner: RoutePlanning {
    private var pending: [(GeoCoordinate, GeoCoordinate, CheckedContinuation<[GeoCoordinate], any Error>)] = []
    var count: Int { pending.count }
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        try await withCheckedThrowingContinuation { pending.append((from, to, $0)) }
    }
    func finish(_ index: Int) {
        let (from, to, continuation) = pending[index]
        continuation.resume(returning: [from, to])
    }
}

private actor EntrancePreviewPlanner: RoutePlanning {
    private(set) var calls = 0
    private(set) var starts: [GeoCoordinate] = []
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        calls += 1
        starts.append(from)
        return [calls == 1 ? GeoCoordinate(latitude: from.latitude - 0.001, longitude: from.longitude)! : from,
                GeoCoordinate(latitude: to.latitude, longitude: to.longitude + 0.001)!]
    }
}
