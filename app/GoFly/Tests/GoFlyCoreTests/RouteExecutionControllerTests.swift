import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct RouteExecutionControllerTests {
    @Test func currentPickerCandidateMetadataAndSearchChangesNotifyRouteObservers() async throws {
        let resolver = ControlledPlaceResolver(), search = RouteControlledSearch()
        let controller = RouteExecutionController(draft: routeDraft(), planner: RouteTestPlanner(), commands: RouteTestCommands(), search: search)
        #expect(controller.openPicker(for: controller.draft.destination!.id))
        let session = try #require(controller.picker)
        var notifications = 0
        let observation = controller.objectWillChange.sink { notifications += 1 }
        defer { observation.cancel() }
        let tapped = GeoCoordinate(latitude: 26, longitude: 122)!
        session.candidates.selectMapCoordinate(tapped, resolver: resolver)
        #expect(notifications > 0)
        #expect(controller.picker?.candidates.candidate?.place.coordinate == tapped)
        await wait { await resolver.requests == [tapped] }
        notifications = 0
        await resolver.finish(at: tapped, with: MapPlace(id: .coordinate(tapped), title: "Resolved place", coordinate: tapped))
        await wait { session.candidates.candidate?.place.title == "Resolved place" }
        #expect(notifications > 0)
        notifications = 0
        session.candidates.updateQuery("Another place")
        #expect(notifications > 0)
        await wait { await search.waiting }
        notifications = 0
        let result = MapPlace(id: .mapKit("search-result"), title: "Search result", coordinate: tapped)
        await search.finish([result])
        await wait { !session.candidates.isSearching }
        #expect(notifications > 0)
        #expect(controller.picker?.candidates.results == [result])
    }

    @Test(arguments: ["cancel", "confirm", "replace"])
    func closedOrReplacedPickerCandidatesStopNotifyingRouteObservers(action: String) async throws {
        let resolver = ControlledPlaceResolver()
        let controller = RouteExecutionController(draft: routeDraft(), planner: RouteTestPlanner(), commands: RouteTestCommands(), search: RouteTestSearch())
        #expect(controller.openPicker(for: controller.draft.destination!.id))
        let old = try #require(controller.picker)
        let tapped = GeoCoordinate(latitude: 26, longitude: 122)!
        old.candidates.selectMapCoordinate(tapped, resolver: resolver)
        await wait { await resolver.requests == [tapped] }
        var notifications = 0
        let observation = controller.objectWillChange.sink { notifications += 1 }
        defer { observation.cancel() }
        switch action {
        case "cancel": controller.cancelPicker(id: old.id)
        case "confirm": #expect(controller.confirmPicker(id: old.id))
        default: #expect(controller.openPicker(for: controller.draft.start!.id))
        }
        let baseline = notifications, frozen = controller.draft
        await resolver.finish(at: tapped, with: MapPlace(id: .coordinate(tapped), title: "Old metadata", coordinate: tapped))
        await wait { old.candidates.candidate?.place.title == "Old metadata" }
        old.candidates.updateQuery("27, 123")
        #expect(notifications == baseline)
        #expect(controller.draft == frozen)
        if controller.picker == nil { #expect(controller.openPicker(for: controller.draft.start!.id)) }
        let current = try #require(controller.picker)
        #expect(current.id != old.id)
        let beforeCurrent = notifications
        current.candidates.selectMapCoordinate(GeoCoordinate(latitude: 28, longitude: 124)!)
        #expect(notifications > beforeCurrent)
        #expect(controller.picker?.candidates.candidate?.place.coordinate == GeoCoordinate(latitude: 28, longitude: 124))
    }

    @Test(arguments: [false, true])
    func metadataReturningAfterPickerConfirmOrCancelCannotRewriteTheDraftOrNewSession(confirm: Bool) async throws {
        let resolver = ControlledPlaceResolver()
        let controller = RouteExecutionController(draft: routeDraft(), planner: RouteTestPlanner(), commands: RouteTestCommands(), search: RouteTestSearch())
        let original = controller.draft
        #expect(controller.openPicker(for: original.destination!.id))
        let old = try #require(controller.picker)
        let tapped = GeoCoordinate(latitude: 26.123456789, longitude: 122.987654321)!
        old.candidates.selectMapCoordinate(tapped, resolver: resolver)
        await wait { await resolver.requests == [tapped] }
        if confirm { #expect(controller.confirmPicker(id: old.id)) }
        else { controller.cancelPicker(id: old.id) }
        let frozen = controller.draft
        if confirm {
            #expect(frozen.destination?.value == .place(MapPlace(id: .coordinate(tapped), title: tapped.displayText, coordinate: tapped)))
        } else { #expect(frozen == original) }
        #expect(controller.openPicker(for: original.start!.id))
        let latest = try #require(controller.picker)
        latest.candidates.updateQuery("27, 123")
        let newCandidate = latest.candidates.candidate
        await resolver.finish(at: tapped, with: MapPlace(id: .mapKit("late"), title: "Late resolved title", coordinate: tapped, address: "Late address"))
        await wait { old.candidates.candidate?.place.title == "Late resolved title" }
        #expect(controller.draft == frozen)
        #expect(controller.picker?.id == latest.id)
        #expect(latest.candidates.candidate == newCandidate)
        #expect(!controller.confirmPicker(id: old.id))
        #expect(controller.plannedRoute == nil)
        #expect(controller.intent == nil)
        #expect(controller.phase == .editing)
    }

    @Test(arguments: [false, true])
    func anInvalidPlannedEndpointNeverAdmitsAnyNativeCommand(remoteStart: Bool) async throws {
        let device = RouteControlledDevice()
        let service = ServiceController(service: device)
        let draft = routeDraft()
        let remote = GeoCoordinate(latitude: 0, longitude: 0)!
        let points = remoteStart ? [remote, GeoCoordinate(latitude: 25.01, longitude: 121.01)!] : [start, remote]
        let controller = RouteExecutionController(draft: draft, planner: RouteStaticPlanner(points: points), commands: service, search: RouteTestSearch())
        #expect(controller.start())
        await wait { controller.phase == .editing }
        #expect(controller.error == .invalidPath)
        #expect(controller.intent == nil)
        #expect(controller.plannedRoute == nil)
        #expect(service.routeAdmissionRevision == 0)
        #expect(service.preparedOperation == nil)
        #expect(!service.nativeBusy)
        #expect(await device.coordinates.isEmpty)
        #expect(await device.clears == 0)
    }

    @Test func cancelUsesTheReturnedSettlementEvenWithoutAnUnknownPublisherEvent() async throws {
        let commands = RouteTestCommands(), clock = RouteTestClock()
        commands.idleSettlement = .requiresStop(.serviceUnavailable)
        let controller = RouteExecutionController(draft: routeDraft(), planner: RouteTestPlanner(), commands: commands, search: RouteTestSearch(), clock: clock)
        #expect(controller.start())
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        #expect(controller.cancel())
        await wait { controller.phase == .unknown }
        #expect(controller.error == .device(.serviceUnavailable))
        #expect(controller.intent != nil)
        #expect(!controller.canEdit)
        #expect(!controller.canCancel)
    }

    @Test(arguments: [false, true])
    func cancellingAClaimedWriteShowsUnknownUntilExplicitStop(firstPoint: Bool) async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: routeDraft(), planner: RouteTestPlanner(), commands: service, search: RouteTestSearch(), clock: clock)
        #expect(controller.start())
        await wait { await device.waiting }
        if !firstPoint {
            await device.finish(.acknowledged)
            await wait { controller.phase == .running && clock.sleepingCount == 1 }
            clock.advance(by: .milliseconds(500))
            await wait { await device.waiting }
        }
        #expect(await device.claim())
        #expect(controller.cancel())
        #expect(controller.phase == .cancelling)
        #expect(!service.canTeleport)
        await device.finish(.unconfirmed(.serviceUnavailable))
        await wait { controller.phase == .unknown && !service.nativeBusy }
        #expect(controller.error == .device(.serviceUnavailable))
        #expect(!controller.canEdit)
        #expect(!controller.canCancel)
        #expect(controller.completion == nil)
        #expect(service.stop())
        #expect(controller.phase == .editing)
        await wait { !service.nativeBusy }
        #expect(controller.canStart)
        #expect(await device.clears == 1)
    }

    @Test func editingAnExistingNodeRequiresSelectingTheNewNameBeforeConfirm() throws {
        let controller = RouteExecutionController(draft: routeDraft(), planner: RouteTestPlanner(), commands: RouteTestCommands(), search: RouteTestSearch())
        let original = controller.draft
        #expect(controller.openPicker(for: original.destination!.id))
        let session = try #require(controller.picker)
        let retained = try #require(session.candidates.candidate)
        session.candidates.updateQuery("A different destination")
        #expect(!controller.confirmPicker(id: session.id))
        #expect(controller.draft == original)
        #expect(controller.picker?.id == session.id)
        #expect(session.candidates.candidate == retained)
        let coordinate = GeoCoordinate(latitude: 26, longitude: 122)!
        let selected = MapPlace(id: .mapKit("selected"), title: "Selected", coordinate: coordinate)
        session.candidates.select(selected)
        #expect(session.candidates.results == [selected])
        #expect(session.candidates.query == "A different destination")
        #expect(controller.confirmPicker(id: session.id))
        #expect(controller.draft.destination?.value == .place(selected))
        #expect(controller.draft.destination!.id == original.destination!.id)
    }

    @Test func pickerCancelAndConfirmTargetOnlyTheOriginalStableNode() throws {
        let commands = RouteTestCommands()
        let controller = RouteExecutionController(draft: routeDraft(), planner: RouteTestPlanner(), commands: commands, search: RouteTestSearch())
        let original = controller.draft
        #expect(controller.openPicker(for: original.destination!.id))
        let cancelled = try #require(controller.picker)
        cancelled.candidates.updateQuery("25, 121")
        controller.cancelPicker(id: cancelled.id)
        #expect(controller.draft == original)
        #expect(!controller.confirmPicker(id: cancelled.id))
        #expect(controller.openPicker(for: original.destination!.id))
        let session = try #require(controller.picker)
        session.candidates.updateQuery("26, 122")
        #expect(controller.confirmPicker(id: session.id))
        #expect(controller.draft.destination!.id == original.destination!.id)
        #expect(controller.draft.start == original.start)
        #expect(controller.draft.destination?.value == .place(try #require(session.candidates.candidate?.place)))
    }
    @Test func acknowledgementControlsDistanceAndDelayedCadenceNeverCatchesUpOrOverlaps() async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let draft = routeDraft()
        let controller = RouteExecutionController(draft: draft, planner: RouteTestPlanner(), commands: service, search: RouteTestSearch(), clock: clock)
        #expect(controller.start())
        await wait { await device.waiting }
        #expect(await device.coordinates == [start])
        await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        #expect(controller.progress?.committedDistanceMeters == 0)
        clock.advance(by: .seconds(10))
        await wait { await device.waiting }
        #expect(await device.coordinates.count == 2)
        #expect(controller.progress?.committedDistanceMeters == 0)
        clock.advance(by: .seconds(100))
        #expect(await device.coordinates.count == 2)
        await device.finish(.acknowledged)
        await wait { (controller.progress?.committedDistanceMeters ?? 0) > 0 && clock.sleepingCount == 1 }
        #expect(abs(try #require(controller.progress).committedDistanceMeters - 2.7777777777777777) < 0.000001)
        #expect(controller.progress?.activeElapsed == .seconds(110))
        #expect(await device.maxConcurrency == 1)
        let last = service.confirmedSimulatedLocation
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
        #expect(service.confirmedSimulatedLocation == last)
        #expect(await device.clears == 0)
        #expect(controller.draft == draft)
        #expect(!controller.resume())
    }

    @Test(arguments: [false, true])
    func pauseWaitsForActualReturnThenResumeKeepsLeasePathAndDistance(afterClaim: Bool) async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: routeDraft(), planner: RouteTestPlanner(), commands: service, search: RouteTestSearch(), clock: clock)
        #expect(controller.start())
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        let original = try #require(controller.intent)
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        if afterClaim { #expect(await device.claim()) }
        #expect(controller.pause())
        #expect(controller.phase == .pausing)
        #expect(service.movementAuthority.snapshot.runState == .paused)
        clock.advance(by: .seconds(5))
        #expect(controller.phase == .pausing)
        await device.finish(.acknowledged)
        await wait { controller.phase == .paused }
        let distance = try #require(controller.progress).committedDistanceMeters
        #expect(controller.progress?.activeElapsed == .milliseconds(5500))
        #expect(abs(distance - (afterClaim ? 2.7777777777777777 : 0)) < 0.000001)
        clock.advance(by: .seconds(1000))
        #expect(controller.progress?.committedDistanceMeters == distance)
        #expect(controller.resume())
        #expect(controller.intent == original)
        await wait { clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        await device.finish(.acknowledged)
        await wait { (controller.progress?.committedDistanceMeters ?? 0) > distance }
        #expect(controller.progress?.activeElapsed == .seconds(6))
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
        #expect(await device.maxConcurrency == 1)
        #expect(await device.clears == 0)
    }

    @Test(arguments: [false, true])
    func finalAcknowledgementWinsThePauseRaceWhileUnknownNeverCompletes(unknown: Bool) async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let end = GeoCoordinate(latitude: 25.000001, longitude: 121)!
        let draft = routeDraft(destination: end)
        let controller = RouteExecutionController(draft: draft, planner: RouteTestPlanner(), commands: service, search: RouteTestSearch(), clock: clock)
        #expect(controller.start())
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        let id = try #require(controller.intent?.id)
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        #expect(await device.claim())
        #expect(controller.pause())
        await device.finish(unknown ? .unconfirmed(.operationTimedOut) : .acknowledged)
        await wait { controller.phase == (unknown ? .unknown : .editing) }
        if unknown {
            #expect(controller.completion == nil)
            #expect(controller.progress?.committedDistanceMeters == 0)
            #expect(!service.canTeleport)
            #expect(service.stop())
            #expect(controller.phase == .editing)
            await wait { !service.nativeBusy }
        } else {
            #expect(controller.completion?.executionID == id)
            #expect(controller.progress?.fraction == 1)
            #expect(service.confirmedSimulatedLocation == end)
            #expect(service.phase == .ready)
            #expect(service.movementAuthority.snapshot.lease == nil)
            controller.dismissCompletion(executionID: id)
            #expect(controller.completion == nil)
        }
        #expect(controller.draft == draft)
    }

    @Test func pausedStopExitsCompactModeImmediatelyAndAnUnclaimedFailureIsOnlyInterrupted() async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let controller = RouteExecutionController(draft: routeDraft(), planner: RouteTestPlanner(), commands: service, search: RouteTestSearch(), clock: clock)
        #expect(controller.start())
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        await device.finish(.notSent(.tunnelUnavailable))
        await wait { controller.phase == .interrupted }
        #expect(controller.error == .device(.tunnelUnavailable))
        #expect(controller.progress?.committedDistanceMeters == 0)
        #expect(service.movementAuthority.snapshot.health == .interrupted(.tunnelUnavailable))
        #expect(service.confirmedSimulatedLocation == start)
        #expect(!controller.resume())
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
        #expect(controller.start())
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        #expect(controller.pause())
        await wait { controller.phase == .paused }
        #expect(service.stop())
        #expect(controller.phase == .editing)
        #expect(!controller.resume())
        await wait { !service.nativeBusy }
    }

    @Test(arguments: [false, true])
    func runningCancelWaitsForInflightWorkSuppressesLateAcknowledgementAndNeverClears(afterClaim: Bool) async throws {
        let device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let draft = routeDraft()
        let controller = RouteExecutionController(draft: draft, planner: RouteTestPlanner(), commands: service, search: RouteTestSearch(), clock: clock)
        #expect(controller.start())
        await wait { await device.waiting }; await device.finish(.acknowledged)
        await wait { controller.phase == .running && clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500))
        await wait { await device.waiting }
        if afterClaim { #expect(await device.claim()) }
        #expect(controller.cancel())
        #expect(controller.phase == .cancelling)
        #expect(service.movementAuthority.snapshot.lease == nil)
        #expect(!controller.cancel())
        #expect(!controller.start())
        await device.finish(.acknowledged)
        await wait { controller.phase == .editing }
        #expect(controller.progress?.committedDistanceMeters == 0)
        #expect(controller.completion == nil)
        #expect(controller.draft == draft)
        #expect(controller.intent == nil)
        #expect(service.positionMarker?.coordinate == start)
        #expect(service.positionMarker?.freshness == (afterClaim ? .waiting : .fresh))
        #expect(await device.clears == 0)
        #expect(await device.coordinates.count == 2)
    }

    @Test(arguments: ["cancel", "stop", "restore", "reset", "start", "go"])
    func latePlanningCannotRestartAfterCancellationOrANewerExplicitCommand(action: String) async throws {
        let device = RouteControlledDevice(), planner = RouteControlledPlanner()
        let service = ServiceController(service: device)
        if action == "stop" { #expect(service.start()); await wait { !service.nativeBusy } }
        let controller = RouteExecutionController(draft: routeDraft(), planner: planner, commands: service, search: RouteTestSearch(), clock: RouteTestClock())
        #expect(controller.start())
        await wait { await planner.waiting }
        let before = service.routeAdmissionRevision
        switch action {
        case "cancel": #expect(controller.cancel())
        case "stop": #expect(service.stop())
        case "restore": #expect(service.restoreGPS())
        case "reset": #expect(service.resetTunnel())
        case "start": #expect(service.start())
        default:
            let point = GeoCoordinate(latitude: 24, longitude: 120)!
            #expect(service.teleport(to: TeleportCandidate(place: MapPlace(id: .coordinate(point), title: "Newer", coordinate: point))))
            await wait { await device.waiting }; await device.finish(.acknowledged)
        }
        if action != "cancel" { #expect(service.routeAdmissionRevision == before + 1) }
        await wait { !service.nativeBusy }
        await planner.finish()
        await wait { await planner.returned }
        await Task.yield()
        await wait { controller.phase == .editing }
        #expect(controller.intent == nil)
        #expect(await device.coordinates.count == (action == "go" ? 1 : 0))
    }

    @Test func theCurrentOriginAndCompleteDraftAreFrozenBeforePlanningCanReturn() async throws {
        let device = RouteControlledDevice(), planner = RouteControlledPlanner()
        let date = Date()
        let service = ServiceController(service: device, now: { date })
        let first = RealLocationObservation(latitude: 24, longitude: 120, horizontalAccuracy: 5, observedAt: date)!
        service.observeRealLocation(first)
        let end = GeoCoordinate(latitude: 26, longitude: 122)!
        let draft = try #require(RouteDraft(destination: .place(MapPlace(id: .coordinate(end), title: "End", coordinate: end))))
        let controller = RouteExecutionController(draft: draft, planner: planner, commands: service, search: RouteTestSearch(), clock: RouteTestClock())
        #expect(controller.start())
        await wait { await planner.waiting }
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121, horizontalAccuracy: 5, observedAt: date))
        #expect(!controller.setSpeed(RouteSpeed(kilometersPerHour: 100)!))
        #expect(!controller.openPicker(for: draft.start!.id))
        await planner.finish()
        await wait { await device.waiting }
        #expect(await device.coordinates == [first.coordinate])
        #expect(controller.intent?.draft.nodes.map(\.id) == draft.nodes.map(\.id))
        #expect(controller.intent?.draft.start?.value == .place(MapPlace(id: .coordinate(first.coordinate), title: first.coordinate.displayText, coordinate: first.coordinate)))
        #expect(controller.draft == draft)
        #expect(controller.intent?.route.start == first.coordinate)
        #expect(controller.intent?.speed == .standard)
        await device.finish(.acknowledged)
        await wait { controller.phase == .running }
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
    }

    @Test func aLatePickerSearchCannotConfirmIntoAClosedOrDifferentNodeSession() async throws {
        let search = RouteControlledSearch()
        let controller = RouteExecutionController(draft: routeDraft(), planner: RouteTestPlanner(), commands: RouteTestCommands(), search: search)
        let original = controller.draft
        #expect(controller.openPicker(for: original.destination!.id))
        let old = try #require(controller.picker)
        old.candidates.updateQuery("old search")
        await wait { await search.waiting }
        controller.cancelPicker(id: old.id)
        #expect(controller.openPicker(for: original.start!.id))
        let current = try #require(controller.picker)
        current.candidates.updateQuery("26, 122")
        #expect(controller.confirmPicker(id: current.id))
        let changed = controller.draft
        await search.finish([MapPlace(id: .coordinate(start), title: "Old result", coordinate: start)])
        await Task.yield()
        #expect(!controller.confirmPicker(id: old.id))
        #expect(controller.draft == changed)
        #expect(controller.draft.destination == original.destination)
    }

    private var start: GeoCoordinate { GeoCoordinate(latitude: 25, longitude: 121)! }
    private func routeDraft(destination: GeoCoordinate = GeoCoordinate(latitude: 25.01, longitude: 121.01)!) -> RouteDraft {
        RouteDraft(start: .place(MapPlace(id: .coordinate(start), title: "Start", coordinate: start)),
                   destination: .place(MapPlace(id: .coordinate(destination), title: "End", coordinate: destination)))!
    }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }

}

private struct RouteTestPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}
private struct RouteStaticPlanner: RoutePlanning {
    let points: [GeoCoordinate]
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { points }
}
private struct RouteTestSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
@MainActor private final class RouteTestCommands: RouteCommanding {
    var currentRouteOrigin: GeoCoordinate? = GeoCoordinate(latitude: 25, longitude: 121)
    var routeAdmissionRevision: UInt64 = 0
    var canBeginRoute = true
    var idleSettlement: RouteIdleSettlement = .settled
    private let events = PassthroughSubject<RouteCommandEvent, Never>()
    var routeEvents: AnyPublisher<RouteCommandEvent, Never> { events.eraseToAnyPublisher() }
    func beginRoute(_ intent: RouteExecutionIntent, expectedAdmissionRevision: UInt64) async -> RouteCommandOutcome { .acknowledged }
    func sendRoutePoint(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, coordinate: GeoCoordinate) async -> RouteCommandOutcome { .acknowledged }
    func pauseRoute(executionID: UUID, lease: MovementTaskLease) -> Bool { true }
    func resumeRoute(executionID: UUID, lease: MovementTaskLease) -> Bool { true }
    func endRoute(executionID: UUID, lease: MovementTaskLease) {}
    func waitForRouteIdle(executionID: UUID, lease: MovementTaskLease) async -> RouteIdleSettlement { idleSettlement }
}

private actor RouteControlledPlanner: RoutePlanning {
    private var continuation: CheckedContinuation<[GeoCoordinate], Never>?
    private var endpoints: [GeoCoordinate] = []
    var waiting: Bool { continuation != nil }
    var returned = false
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        endpoints = [from, to]
        let result = await withCheckedContinuation { continuation = $0 }
        returned = true
        return result
    }
    func finish() { continuation?.resume(returning: endpoints); continuation = nil }
}
private actor RouteControlledSearch: PlaceSearching {
    private var continuation: CheckedContinuation<[MapPlace], Never>?
    var waiting: Bool { continuation != nil }
    func search(query: String) async throws -> [MapPlace] { await withCheckedContinuation { continuation = $0 } }
    func finish(_ places: [MapPlace]) { continuation?.resume(returning: places); continuation = nil }
}
