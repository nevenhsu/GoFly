import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct ImportedRouteExecutionTests {
    @Test func aLoadedGPXPreviewSurvivesImmediatePlanningCancellationAndOnlyExplicitClearRemovesIt() async throws {
        let commands = ImportedCommandSpy(), planner = ImportedPlannerSpy()
        let controller = RouteExecutionController(planner: planner, commands: commands, search: ImportedSearch())
        let imported = try snapshot(), expected = try PlannedRoute(imported: imported.document)
        let speed = RouteSpeed(kilometersPerHour: 42)!
        #expect(controller.setSpeed(speed))
        #expect(controller.setRoundTripEnabled(true))
        #expect(controller.loadImportedRoute(imported))
        #expect(controller.plannedRoute == expected)
        #expect(controller.start())
        #expect(controller.phase == .planning)
        #expect(controller.plannedRoute == expected)
        #expect(controller.cancel())
        #expect(controller.phase == .editing)
        #expect(controller.plannedRoute == expected)
        #expect(controller.intent == nil)
        #expect(controller.draft.importedRoute == imported)
        #expect(controller.draft.speed == speed)
        #expect(controller.roundTripEnabled)
        #expect(await planner.calls == 0)
        #expect(commands.begins.isEmpty)
        #expect(controller.clearImportedRoute())
        #expect(controller.plannedRoute == nil)
    }

    @Test func exhaustedPreDispatchPreparationCanReturnToTheLoadedGPXPreviewWithoutAReplan() async throws {
        let device = RouteControlledDevice(), planner = ImportedPlannerSpy()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(planner: planner, commands: service, search: ImportedSearch())
        let imported = try snapshot(), expected = try PlannedRoute(imported: imported.document)
        #expect(controller.loadImportedRoute(imported))
        #expect(controller.start())
        for _ in 1...3 {
            await wait { await device.waiting }
            await device.finish(.notSent(.pairingRequired))
        }
        await wait { !service.nativeBusy }
        #expect(controller.plannedRoute == expected)
        #expect(controller.phase == .preparing)
        #expect(service.cancelPreparation(id: try #require(service.preparedOperation?.id)))
        #expect(controller.phase == .editing)
        #expect(controller.plannedRoute == expected)
        #expect(controller.draft.importedRoute == imported)
        #expect(await planner.calls == 0)
        #expect(await device.clears == 0)
    }

    @Test(arguments: ["cancel", "stop", "unknown"])
    func importedExecutionUsesItsExactFrozenPathAndTheExistingAcknowledgementLifecycle(ending: String) async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock(), planner = ImportedPlannerSpy()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(planner: planner, commands: service, search: ImportedSearch(), clock: clock)
        let imported = try snapshot(), speed = RouteSpeed(kilometersPerHour: 36)!
        service.observeRealLocation(RealLocationObservation(latitude: 0, longitude: 0, horizontalAccuracy: 5, observedAt: Date()))
        #expect(controller.setSpeed(speed))
        #expect(controller.setRoundTripEnabled(true))
        #expect(controller.loadImportedRoute(imported))
        #expect(await device.coordinates.isEmpty)
        #expect(controller.start())
        #expect(!controller.loadImportedRoute(imported))
        #expect(!controller.clearImportedRoute())
        await wait { await device.waiting }
        #expect(await planner.calls == 0)
        #expect(await device.coordinates == [coordinate(0)])
        #expect(controller.progress == nil)
        #expect(controller.intent?.draft.importedRoute == imported)
        #expect(controller.intent?.draft.nodes.isEmpty == true)
        #expect(controller.intent?.route.points == [coordinate(0), coordinate(1), coordinate(2)])
        #expect(controller.intent?.speed == speed)
        await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        #expect(controller.progress?.committedDistanceMeters == 0)
        #expect(service.confirmedSimulatedLocation == coordinate(0))
        #expect(!controller.loadImportedRoute(imported))
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.progress?.committedDistanceMeters == 5 && clock.sleepingCount == 1 }
        let confirmed = service.confirmedSimulatedLocation
        #expect(controller.pause())
        await wait { controller.phase == .paused }
        #expect(!controller.loadImportedRoute(imported))
        #expect(!controller.clearImportedRoute())
        #expect(controller.resume())
        if ending == "cancel" {
            #expect(controller.cancel())
            await wait { controller.phase == .editing }
            #expect(service.confirmedSimulatedLocation == confirmed)
            #expect(await device.clears == 0)
        } else if ending == "stop" {
            #expect(service.stop())
            await wait { !service.nativeBusy }
            #expect(controller.phase == .editing)
            #expect(await device.clears == 1)
        } else {
            await wait { clock.sleepingCount == 1 }
            clock.advance(by: .milliseconds(500))
            await wait { await device.waiting }
            #expect(await device.claim())
            await device.finish(.unconfirmed(.serviceUnavailable))
            await wait { controller.phase == .unknown }
            #expect(!controller.loadImportedRoute(imported))
            #expect(!controller.clearImportedRoute())
            #expect(!controller.canStart)
            #expect(service.stop())
            await wait { !service.nativeBusy }
            #expect(await device.clears == 1)
        }
        #expect(controller.draft.importedRoute == imported)
        #expect(controller.draft.speed == speed)
        #expect(controller.roundTripEnabled)
        #expect(imported.document.pointCount == 4)
        #expect(await device.maxConcurrency == 1)
    }

    @Test func importedStartNeverReadsCurrentLocationOrInvokesTheRoadPlanner() async throws {
        let commands = ImportedCommandSpy(), planner = ImportedPlannerSpy(), clock = RouteTestClock()
        let controller = RouteExecutionController(planner: planner, commands: commands, search: ImportedSearch(), clock: clock)
        let imported = try snapshot()
        #expect(controller.loadImportedRoute(imported))
        #expect(controller.canStart)
        #expect(controller.start())
        await wait { controller.phase == .running }
        #expect(commands.originReads == 0)
        #expect(await planner.calls == 0)
        #expect(commands.begins.first?.draft.source == .gpx(imported))
        #expect(commands.begins.first?.route.start == coordinate(0))
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
    }

    @Test func staleAdmissionBeforeTheDirectGPXTaskEntersCannotPublishOrAdmitAnIntent() async throws {
        let commands = ImportedCommandSpy(), planner = ImportedPlannerSpy()
        let controller = RouteExecutionController(planner: planner, commands: commands, search: ImportedSearch())
        let imported = try snapshot()
        #expect(controller.loadImportedRoute(imported))
        #expect(controller.start())
        commands.routeAdmissionRevision &+= 1
        await wait { controller.phase == .editing }
        #expect(controller.intent == nil)
        #expect(controller.plannedRoute == (try PlannedRoute(imported: imported.document)))
        #expect(commands.begins.isEmpty)
        #expect(commands.originReads == 0)
        #expect(await planner.calls == 0)
        #expect(controller.draft.importedRoute == imported)
    }

    @Test(arguments: [false, true])
    func evenAnInitiallySeededIneligibleGPXCannotStartOrReadGPS(zeroDistance: Bool) async throws {
        let document = try GPXDocument(content: zeroDistance ? .waypoints([coordinate(0), coordinate(0)])
            : .routes([GPXRoute(points: [coordinate(0), coordinate(1)]), GPXRoute(points: [coordinate(2), coordinate(3)])]))
        let imported = try ImportedRouteSnapshot(document: document, filename: "ineligible.gpx")
        let commands = ImportedCommandSpy(), planner = ImportedPlannerSpy()
        let controller = RouteExecutionController(draft: RouteDraft(imported: imported), planner: planner, commands: commands, search: ImportedSearch())
        #expect(!controller.canStart)
        #expect(!controller.start())
        #expect(controller.error == .imported(zeroDistance ? .zeroDistance : .disconnectedSegments))
        #expect(commands.begins.isEmpty)
        #expect(commands.originReads == 0)
        #expect(await planner.calls == 0)
        #expect(controller.draft.importedRoute == imported)
        #expect(controller.clearImportedRoute())
        #expect(controller.draft.isManual)
    }

    @Test func tenThousandRawSamplesRemainImportedDataRatherThanManualNodes() throws {
        let points = (0..<10_000).map { GeoCoordinate(latitude: 25 + Double($0) * 0.0000001, longitude: 121.123456789)! }
        let document = try GPXDocument(content: .waypoints(points))
        let planned = try PlannedRoute(imported: document)
        #expect(planned.points == points)
        #expect(document.pointCount == 10_000)
        let repeated = try GPXDocument(content: .waypoints(Array(repeating: coordinate(0), count: 9_999) + [coordinate(1)]))
        #expect(try PlannedRoute(imported: repeated).points == [coordinate(0), coordinate(1)])
        #expect(repeated.pointCount == 10_000)
        let imported = try ImportedRouteSnapshot(document: document, filename: "ten-thousand.gpx")
        let controller = RouteExecutionController(planner: ImportedPlannerSpy(), commands: ImportedCommandSpy(), search: ImportedSearch())
        #expect(controller.loadImportedRoute(imported))
        #expect(controller.draft.nodes.isEmpty)
        #expect(controller.draft.importedRoute?.document.pointCount == 10_000)
        #expect(controller.canStart)
    }

    @Test func aManualPlanningTaskRejectsLoadAndItsLateResultCannotReplaceTheDraft() async throws {
        let planner = HeldImportedPlanner(), commands = ImportedCommandSpy()
        let draft = RouteDraft(values: [.place(place(0)), .place(place(1))])!
        let controller = RouteExecutionController(draft: draft, planner: planner, commands: commands, search: ImportedSearch())
        #expect(controller.start())
        await wait { await planner.waiting }
        #expect(!controller.loadImportedRoute(try snapshot()))
        #expect(controller.draft == draft)
        #expect(controller.cancel())
        #expect(controller.loadImportedRoute(try snapshot()))
        let loaded = controller.draft
        await planner.finish()
        await wait { await planner.returned }
        #expect(controller.draft == loaded)
        #expect(commands.begins.isEmpty)
        #expect(controller.intent == nil)
    }

    @Test func executionDerivesAnExactConnectedPathWithoutRewritingImportedGroupsOrDuplicates() throws {
        let a = coordinate(0), b = coordinate(1), c = coordinate(2)
        let document = try GPXDocument(content: .tracks([
            GPXTrack(segments: [[a, a, b], [b]]), GPXTrack(segments: [[b, c, c]])
        ]))
        let original = document.content
        let route = try PlannedRoute(imported: document)
        #expect(route.points == [a, b, c])
        #expect(route.start == a)
        #expect(route.end == c)
        #expect(document.content == original)
        #expect(document.segments == [[a, a, b], [b], [b, c, c]])
        #expect(document.pointCount == 7)
    }

    @Test func exactSegmentGapsAndZeroDistanceHaveDistinctEligibilityFailures() throws {
        let a = coordinate(0), b = coordinate(1)
        let near = GeoCoordinate(latitude: b.latitude + 0.000000001, longitude: b.longitude)!
        let disconnected = try GPXDocument(content: .routes([GPXRoute(points: [a, b]), GPXRoute(points: [near, coordinate(2)])]))
        #expect(throws: ImportedRouteExecutionFailure.disconnectedSegments) { try PlannedRoute(imported: disconnected) }
        let zero = try GPXDocument(content: .waypoints([a, a, a]))
        #expect(throws: ImportedRouteExecutionFailure.zeroDistance) { try PlannedRoute(imported: zero) }
        #expect(disconnected.pointCount == 4)
        #expect(zero.pointCount == 3)
    }

    @Test func loadingAndClearingReplaceTheWholeSourceRetainSettingsAndNeverAdmitAnOperation() throws {
        let commands = ImportedCommandSpy(), planner = ImportedPlannerSpy()
        let speed = RouteSpeed(kilometersPerHour: 36)!
        let controller = RouteExecutionController(draft: RouteDraft(values: [.place(place(0)), .place(place(1))], speed: speed)!, planner: planner, commands: commands, search: ImportedSearch())
        #expect(controller.setRoundTripEnabled(true))
        #expect(controller.openPicker(for: controller.draft.nodes[0].id))
        let stale = try #require(controller.picker)
        let snapshot = try snapshot()
        #expect(controller.loadImportedRoute(snapshot))
        #expect(controller.draft.source == .gpx(snapshot))
        #expect(controller.draft.importedRoute == snapshot)
        #expect(!controller.draft.isManual)
        #expect(controller.draft.nodes.isEmpty)
        #expect(controller.draft.start == nil)
        #expect(controller.draft.destination == nil)
        #expect(controller.picker == nil)
        #expect(!controller.canAddNode)
        #expect(!controller.openNewPicker())
        #expect(!controller.removeNode(id: stale.nodeID))
        #expect(!controller.moveNode(id: stale.nodeID, toIndex: 0))
        #expect(!controller.confirmPicker(id: stale.id))
        #expect(controller.draft.speed == speed)
        #expect(controller.roundTripEnabled)
        #expect(controller.phase == .editing)
        #expect(controller.intent == nil)
        #expect(controller.plannedRoute?.points == [coordinate(0), coordinate(1), coordinate(2)])
        #expect(commands.begins.isEmpty)
        #expect(commands.originReads == 0)
        let changedSpeed = RouteSpeed(kilometersPerHour: 42)!
        #expect(controller.setSpeed(changedSpeed))
        #expect(controller.draft.importedRoute == snapshot)
        #expect(controller.canClearImportedRoute)
        #expect(controller.clearImportedRoute())
        #expect(controller.plannedRoute == nil)
        #expect(controller.draft.isManual)
        #expect(controller.draft.nodes.map(\.value) == [.current])
        #expect(controller.draft.speed == changedSpeed)
        #expect(controller.roundTripEnabled)
        #expect(!controller.clearImportedRoute())
        #expect(commands.begins.isEmpty)
        #expect(snapshot.document.pointCount == 4)
    }

    @Test func anIneligibleLoadPreservesTheManualDraftAndPublishesItsConcreteReason() throws {
        let commands = ImportedCommandSpy()
        let controller = RouteExecutionController(planner: ImportedPlannerSpy(), commands: commands, search: ImportedSearch())
        let original = controller.draft
        let document = try GPXDocument(content: .routes([GPXRoute(points: [coordinate(0), coordinate(1)]), GPXRoute(points: [coordinate(2), coordinate(3)])]))
        let invalid = try ImportedRouteSnapshot(document: document, filename: "gap.gpx")
        #expect(!controller.loadImportedRoute(invalid))
        #expect(controller.error == .imported(.disconnectedSegments))
        #expect(controller.draft == original)
        #expect(controller.intent == nil)
        #expect(commands.begins.isEmpty)
    }

    private func coordinate(_ index: Int) -> GeoCoordinate {
        GeoCoordinate(latitude: 25.123456789 + Double(index) * 0.0002, longitude: 121.987654321)!
    }
    private func place(_ index: Int) -> MapPlace {
        let point = coordinate(index)
        return MapPlace(id: .coordinate(point), title: "Place \(index)", coordinate: point)
    }
    private func snapshot() throws -> ImportedRouteSnapshot {
        let document = try GPXDocument(content: .tracks([GPXTrack(segments: [[coordinate(0), coordinate(0), coordinate(1), coordinate(2)]])]))
        return try ImportedRouteSnapshot(document: document, filename: "Exact imported route.gpx")
    }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

private actor ImportedPlannerSpy: RoutePlanning {
    var calls = 0
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { calls += 1; throw RouteExecutionFailure.planningFailed }
}
private actor HeldImportedPlanner: RoutePlanning {
    private var pending: CheckedContinuation<[GeoCoordinate], Never>?
    private var points: [GeoCoordinate] = []
    var waiting: Bool { pending != nil }
    var returned = false
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        points = [from, to]
        let value = await withCheckedContinuation { pending = $0 }
        returned = true
        return value
    }
    func finish() { pending?.resume(returning: points); pending = nil }
}
private struct ImportedSearch: PlaceSearching { func search(query: String) async throws -> [MapPlace] { [] } }
@MainActor private final class ImportedCommandSpy: RouteCommanding {
    var canBeginRoute = true
    var routeAdmissionRevision: UInt64 = 0
    var originReads = 0
    var currentRouteOrigin: GeoCoordinate? { originReads += 1; return nil }
    var begins: [RouteExecutionIntent] = []
    private let events = PassthroughSubject<RouteCommandEvent, Never>()
    var routeEvents: AnyPublisher<RouteCommandEvent, Never> { events.eraseToAnyPublisher() }
    func beginRoute(_ intent: RouteExecutionIntent, expectedAdmissionRevision: UInt64) async -> RouteCommandOutcome { begins.append(intent); return .acknowledged }
    func routeControlRevision(executionID: UUID, lease: MovementTaskLease) -> UInt64? { 0 }
    func reviseRouteControl(executionID: UUID, lease: MovementTaskLease) -> UInt64? { 1 }
    func sendRoutePoint(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedControlRevision: UInt64, coordinate: GeoCoordinate) async -> RouteCommandOutcome { .acknowledged }
    func pauseRoute(executionID: UUID, lease: MovementTaskLease) -> Bool { true }
    func resumeRoute(executionID: UUID, lease: MovementTaskLease) -> Bool { true }
    func endRoute(executionID: UUID, lease: MovementTaskLease) {}
    func waitForRouteIdle(executionID: UUID, lease: MovementTaskLease) async -> RouteIdleSettlement { .settled }
}
