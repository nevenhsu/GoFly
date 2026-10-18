import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct FavoriteRouteExecutionTests {
    private func loadImported(_ controller: RouteExecutionController, _ snapshot: ImportedRouteSnapshot) -> Bool {
        guard let admission = controller.beginImportedLoad() else { return false }
        return controller.loadImportedRoute(snapshot, expectedAdmissionRevision: admission)
    }

    @Test func loadRequiresAnIssuedOneUseTokenAndTheLatestRequestWinsEvenForSameRecord() throws {
        let controller = make(), snapshot = try favorite()
        #expect(!controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: 0))
        let first = try #require(controller.beginFavoriteLoad())
        let second = try #require(controller.beginFavoriteLoad())
        #expect(first != second)
        #expect(!controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: first))
        #expect(controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: second))
        let loaded = controller.draft
        #expect(!controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: second))
        #expect(controller.draft == loaded)
    }

    @Test func manualLoadRetainsAllMetadataAndLatestOptionsButCreatesNewNodeIdentitiesWithoutAdmission() async throws {
        let commands = FavoriteExecutionCommands(), planner = FavoriteExecutionPlanner()
        let original = RouteDraft(values: (0..<27).map { .place(place($0)) })!
        let controller = make(draft: original, planner: planner, commands: commands)
        let snapshot = try FavoriteRouteSnapshot(source: .manual((0..<27).map(place)))
        let speed = RouteSpeed(kilometersPerHour: 67)!
        #expect(controller.setSpeed(speed))
        #expect(controller.setRoundTripEnabled(true))
        let token = try #require(controller.beginFavoriteLoad())
        #expect(controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: token))
        #expect(controller.draft.nodes.map(\.value) == original.nodes.map(\.value))
        #expect(Set(controller.draft.nodes.map(\.id)).isDisjoint(with: original.nodes.map(\.id)))
        #expect(controller.draft.speed == speed)
        #expect(controller.roundTripEnabled)
        #expect(controller.phase == .editing && controller.intent == nil && controller.plannedRoute == nil)
        #expect(commands.begins.isEmpty && commands.originReads == 0)
        #expect(await planner.calls == 0)
    }

    @Test func gpxTenThousandPointLoadKeepsRawSourceAndImmediatePreviewWithoutGPSPlannerOrNative() async throws {
        let commands = FavoriteExecutionCommands(), planner = FavoriteExecutionPlanner()
        let controller = make(planner: planner, commands: commands)
        let points = (0..<9_999).map { GeoCoordinate(latitude: 20 + Double($0) * 0.000001, longitude: 120)! }
        let document = try GPXDocument(content: .tracks([GPXTrack(segments: [Array(points.prefix(5_000)), Array(points.suffix(5_000))])]))
        // Shared segment boundary is present twice in raw GPX and once in execution.
        let source = try GPXRouteSource(document: document, displayFilename: "Complete.gpx")
        let snapshot = try FavoriteRouteSnapshot(source: .gpx(source))
        let token = try #require(controller.beginFavoriteLoad())
        #expect(controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: token))
        #expect(controller.draft.gpxSource == source)
        #expect(controller.draft.nodes.isEmpty)
        #expect(controller.plannedRoute?.points == points)
        #expect(commands.begins.isEmpty && commands.originReads == 0)
        #expect(await planner.calls == 0)
        #expect(controller.clearImportedRoute())
        #expect(controller.draft.isManual && controller.plannedRoute == nil)
    }

    @Test(arguments: ["dismiss", "remove", "reorder", "picker", "startFailure", "importFailure", "importSuccess", "clear"])
    func acceptedActionsPreventLateFavoritePublication(action: String) throws {
        let controller = make(draft: RouteDraft(values: [.place(place(0)), .place(place(1)), .place(place(2))])!)
        if action == "clear" { #expect(loadImported(controller, try imported())) }
        let token = try #require(controller.beginFavoriteLoad())
        switch action {
        case "dismiss": controller.invalidateFavoriteLoadAdmission()
        case "remove": #expect(controller.removeNode(id: controller.draft.nodes[1].id))
        case "reorder": #expect(controller.moveNode(id: controller.draft.nodes[1].id, toIndex: 2))
        case "picker":
            #expect(controller.openPicker(for: controller.draft.nodes[0].id))
            controller.cancelPicker(id: try #require(controller.picker).id)
        case "startFailure":
            #expect(controller.removeNode(id: controller.draft.nodes[2].id))
            #expect(controller.removeNode(id: controller.draft.nodes[1].id))
            let fresh = try #require(controller.beginFavoriteLoad())
            #expect(!controller.start())
            #expect(!controller.loadFavoriteRoute(try favorite(), expectedAdmissionRevision: fresh))
        case "importFailure": #expect(!loadImported(controller, try imported(gapped: true)))
        case "importSuccess": #expect(loadImported(controller, try imported()))
        default: #expect(controller.clearImportedRoute())
        }
        let current = controller.draft
        #expect(!controller.loadFavoriteRoute(try favorite(), expectedAdmissionRevision: token))
        #expect(controller.draft == current)
    }

    @Test func pickerAdmissionAndRejectedStaleIDsCannotInvalidateANewerRequest() throws {
        let controller = make()
        #expect(controller.openNewPicker())
        let old = try #require(controller.picker).id
        #expect(controller.beginFavoriteLoad() == nil)
        controller.cancelPicker(id: old)
        let token = try #require(controller.beginFavoriteLoad())
        #expect(!controller.clearPickerPlace(id: old))
        #expect(!controller.stagePickerCurrent(id: old))
        #expect(!controller.confirmPicker(id: old))
        controller.cancelPicker(id: old)
        #expect(!controller.openPicker(for: RouteNodeID()))
        #expect(!controller.removeNode(id: RouteNodeID()))
        #expect(!controller.moveNode(id: RouteNodeID(), toIndex: 0))
        #expect(controller.favoriteLoadAdmissionRevision == token)
        #expect(controller.loadFavoriteRoute(try favorite(), expectedAdmissionRevision: token))
    }

    @Test func matchingPickerActionsAdvanceAdmissionAndReplacementCannotReviveOldRequest() throws {
        let controller = make(draft: RouteDraft(values: [.place(place(0)), .place(place(1))])!)
        let token = try #require(controller.beginFavoriteLoad())
        #expect(controller.openPicker(for: controller.draft.nodes[0].id))
        let first = try #require(controller.picker).id
        var revision = controller.favoriteLoadAdmissionRevision
        #expect(controller.clearPickerPlace(id: first))
        #expect(controller.favoriteLoadAdmissionRevision > revision)
        revision = controller.favoriteLoadAdmissionRevision
        #expect(controller.stagePickerCurrent(id: first))
        #expect(controller.favoriteLoadAdmissionRevision > revision)
        #expect(controller.openNewPicker())
        let second = try #require(controller.picker).id
        controller.cancelPicker(id: first)
        #expect(controller.picker?.id == second)
        controller.picker?.candidates.select(place(3))
        revision = controller.favoriteLoadAdmissionRevision
        #expect(controller.confirmPicker(id: second))
        #expect(controller.favoriteLoadAdmissionRevision > revision)
        #expect(!controller.loadFavoriteRoute(try favorite(), expectedAdmissionRevision: token))
    }

    @Test func completedExecutionDoesNotReviveOldAdmissionAndRunningOrPausedCannotIssueOrLoad() async throws {
        let commands = FavoriteExecutionCommands(), clock = RouteTestClock()
        let controller = RouteExecutionController(draft: RouteDraft(values: [.place(place(0)), .place(place(1))])!, planner: FavoriteExecutionPlanner(), commands: commands, search: FavoriteExecutionSearch(), clock: clock)
        let snapshot = try favorite(), token = try #require(controller.beginFavoriteLoad())
        #expect(controller.start())
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        #expect(controller.beginFavoriteLoad() == nil)
        #expect(!controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: token))
        #expect(controller.pause())
        await wait { controller.phase == .paused }
        #expect(controller.beginFavoriteLoad() == nil)
        #expect(!controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: token))
        #expect(controller.resume())
        await wait { clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await wait { controller.phase == .editing }
        #expect(controller.completion != nil)
        #expect(!controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: token))
    }

    @Test func invalidGPXFavoriteLoadDoesNotReplaceDraftOrConsumeValidRequest() throws {
        let controller = make(), original = controller.draft
        let snapshot = try FavoriteRouteSnapshot(source: .gpx(try imported(gapped: true).source))
        let token = try #require(controller.beginFavoriteLoad())
        #expect(!controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: token))
        #expect(controller.error == .imported(.disconnectedSegments))
        #expect(controller.draft == original)
        #expect(controller.loadFavoriteRoute(try favorite(), expectedAdmissionRevision: token))
    }

    @Test func asynchronousSameIDValidationCompletingInReverseOrderLoadsOnlyLatestRequest() async throws {
        let controller = make(), snapshot = try favorite(), validator = HeldFavoriteValidation()
        let firstToken = try #require(controller.beginFavoriteLoad())
        let first = Task { controller.loadFavoriteRoute(await validator.validate(1, snapshot: snapshot), expectedAdmissionRevision: firstToken) }
        await waitAsync { await validator.isWaiting(1) }
        let secondToken = try #require(controller.beginFavoriteLoad())
        let second = Task { controller.loadFavoriteRoute(await validator.validate(2, snapshot: snapshot), expectedAdmissionRevision: secondToken) }
        await waitAsync { await validator.isWaiting(2) }
        await validator.finish(2)
        #expect(await second.value)
        let latest = controller.draft
        await validator.finish(1)
        #expect(!(await first.value))
        #expect(controller.draft == latest)
    }

    @Test func dismissThenEditRejectsAnActuallyPendingValidation() async throws {
        let controller = make(), snapshot = try favorite(), validator = HeldFavoriteValidation()
        let token = try #require(controller.beginFavoriteLoad())
        let pending = Task { controller.loadFavoriteRoute(await validator.validate(1, snapshot: snapshot), expectedAdmissionRevision: token) }
        await waitAsync { await validator.isWaiting(1) }
        controller.invalidateFavoriteLoadAdmission()
        #expect(controller.openNewPicker())
        let session = try #require(controller.picker)
        session.candidates.select(place(8))
        #expect(controller.confirmPicker(id: session.id))
        let edited = controller.draft
        await validator.finish(1)
        #expect(!(await pending.value))
        #expect(controller.draft == edited)
    }

    @Test func explicitStartRejectedByServiceAvailabilityStillInvalidatesTheOutstandingRequest() throws {
        let commands = FavoriteExecutionCommands(), controller = make(commands: commands)
        let token = try #require(controller.beginFavoriteLoad())
        commands.canBeginRoute = false
        #expect(!controller.start())
        commands.canBeginRoute = true
        #expect(!controller.loadFavoriteRoute(try favorite(), expectedAdmissionRevision: token))
    }

    @Test func favoriteGPXStartUsesExactFrozenFirstPointAndACKLifecycleWithoutRoadPlanning() async throws {
        let device = RouteControlledDevice(), service = ServiceController(service: device)
        let planner = FavoriteExecutionPlanner(), clock = RouteTestClock()
        let controller = RouteExecutionController(planner: planner, commands: service, search: FavoriteExecutionSearch(), clock: clock)
        let document = try GPXDocument(content: .tracks([GPXTrack(segments: [[place(0).coordinate, place(0).coordinate, place(1).coordinate]])]))
        let source = try GPXRouteSource(document: document, displayFilename: "Favorite.gpx")
        let token = try #require(controller.beginFavoriteLoad())
        #expect(controller.loadFavoriteRoute(try FavoriteRouteSnapshot(source: .gpx(source)), expectedAdmissionRevision: token))
        #expect(controller.start())
        await waitAsync { await device.waiting }
        #expect(controller.intent?.draft.gpxSource == source)
        #expect(controller.intent?.route.points == [place(0).coordinate, place(1).coordinate])
        #expect(await device.coordinates == [place(0).coordinate])
        #expect(await planner.calls == 0)
        #expect(controller.progress == nil)
        await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        #expect(controller.progress?.committedDistanceMeters == 0)
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
        #expect(controller.draft.gpxSource == source)
        #expect(await device.clears == 0)
    }

    private func waitAsync(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }

    private func make(draft: RouteDraft = RouteDraft(), planner: FavoriteExecutionPlanner = FavoriteExecutionPlanner(), commands: FavoriteExecutionCommands = FavoriteExecutionCommands()) -> RouteExecutionController {
        RouteExecutionController(draft: draft, planner: planner, commands: commands, search: FavoriteExecutionSearch())
    }
    private func place(_ index: Int) -> MapPlace {
        let point = GeoCoordinate(latitude: 25 + Double(index) * 0.000001, longitude: 121)!
        return MapPlace(id: .mapKit("identity-\(index)"), title: "Title \(index)", coordinate: point, address: "Address \(index)")
    }
    private func favorite() throws -> FavoriteRouteSnapshot { try FavoriteRouteSnapshot(source: .manual([place(4), place(5)])) }
    private func imported(gapped: Bool = false) throws -> ImportedRouteSnapshot {
        let groups = gapped ? [GPXRoute(points: [place(0).coordinate, place(1).coordinate]), GPXRoute(points: [place(2).coordinate, place(3).coordinate])] : [GPXRoute(points: [place(0).coordinate, place(1).coordinate])]
        return try ImportedRouteSnapshot(document: GPXDocument(content: .routes(groups)), filename: "source.gpx")
    }
    private func wait(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() && ContinuousClock.now < deadline { await Task.yield() }
        #expect(condition())
    }
}
private actor FavoriteExecutionPlanner: RoutePlanning {
    var calls = 0
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { calls += 1; return [from, to] }
}
private struct FavoriteExecutionSearch: PlaceSearching { func search(query: String) async throws -> [MapPlace] { [] } }
@MainActor private final class FavoriteExecutionCommands: RouteCommanding {
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

private actor HeldFavoriteValidation {
    private var pending: [Int: (FavoriteRouteSnapshot, CheckedContinuation<FavoriteRouteSnapshot, Never>)] = [:]
    func validate(_ request: Int, snapshot: FavoriteRouteSnapshot) async -> FavoriteRouteSnapshot {
        await withCheckedContinuation { pending[request] = (snapshot, $0) }
    }
    func isWaiting(_ request: Int) -> Bool { pending[request] != nil }
    func finish(_ request: Int) {
        guard let (snapshot, continuation) = pending.removeValue(forKey: request) else { return }
        continuation.resume(returning: snapshot)
    }
}
