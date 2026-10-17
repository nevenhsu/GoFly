import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct RouteWaypointsTests {
    @Test(arguments: [false, true])
    func stagingCurrentCancelsPendingLookupsWithoutChangingTheRetainedChoiceOrGoLock(metadata: Bool) async throws {
        let resolver = ControlledPlaceResolver(), search = WaypointLookupSearch()
        let controller = RouteExecutionController(draft: RouteDraft(values: [.place(place(0)), .place(place(1))])!, planner: WaypointPlanner(), commands: WaypointCommands(), search: search)
        #expect(controller.openPicker(for: controller.draft.nodes[0].id))
        let session = try #require(controller.picker)
        let tapped = place(3).coordinate
        if metadata {
            session.candidates.selectMapCoordinate(tapped, resolver: resolver)
            await wait { await resolver.requests == [tapped] }
        } else {
            session.candidates.updateQuery("Pending name")
            await wait { await search.waiting }
        }
        let candidate = session.candidates.candidate, query = session.candidates.query
        let results = session.candidates.results, canGo = session.candidates.canGo
        #expect(controller.stagePickerCurrent(id: session.id))
        #expect(!session.candidates.isSearching)
        #expect(session.candidates.candidate == candidate)
        #expect(session.candidates.query == query)
        #expect(session.candidates.results == results)
        #expect(session.candidates.canGo == canGo)
        if metadata {
            await resolver.finish(at: tapped, with: MapPlace(id: .mapKit("late"), title: "Late metadata", coordinate: tapped))
            await wait { await resolver.returned.contains(tapped) }
        } else {
            await search.finish([place(4)])
            await wait { await search.returned }
        }
        for _ in 0..<10 { await Task.yield() }
        #expect(session.candidates.candidate == candidate)
        #expect(session.candidates.query == query)
        #expect(session.candidates.results == results)
        #expect(session.candidates.canGo == canGo)
        #expect(!session.candidates.searchFailed)
        #expect(controller.confirmPicker(id: session.id, useCurrentLocation: false) == canGo)
        #expect(controller.draft.nodes[0].value == .place(metadata ? try #require(candidate?.place) : place(0)))
    }

    @Test func stagingCurrentKeepsInvalidCoordinateValidationAndRetainedCandidateForAnUncheckedChoice() throws {
        let controller = controller(values: [.place(place(0)), .place(place(1))])
        #expect(controller.openPicker(for: controller.draft.nodes[0].id))
        let session = try #require(controller.picker)
        let original = session.candidates.candidate
        session.candidates.updateQuery("91, 121")
        #expect(controller.stagePickerCurrent(id: session.id))
        #expect(session.candidates.query == "91, 121")
        #expect(session.candidates.inputError == .latitudeRange)
        #expect(session.candidates.candidate == original)
        #expect(!session.candidates.canGo)
        #expect(!controller.confirmPicker(id: session.id, useCurrentLocation: false))
        session.candidates.updateQuery("")
        #expect(!session.candidates.canGo)
        #expect(!controller.confirmPicker(id: session.id, useCurrentLocation: false))
    }

    @Test(arguments: [false, true])
    func staleOrIneligibleCurrentStagingCannotCancelTheActiveMetadataLookup(ineligible: Bool) async throws {
        let resolver = ControlledPlaceResolver()
        let values: [RouteNodeValue] = [ineligible ? .current : .place(place(0)), .place(place(1))]
        let controller = self.controller(values: values)
        #expect(controller.openPicker(for: controller.draft.nodes[ineligible ? 1 : 0].id))
        let session = try #require(controller.picker)
        let tapped = place(3).coordinate
        session.candidates.selectMapCoordinate(tapped, resolver: resolver)
        await wait { await resolver.requests == [tapped] }
        #expect(!controller.stagePickerCurrent(id: UUID()))
        if ineligible { #expect(!controller.stagePickerCurrent(id: session.id)) }
        let metadata = MapPlace(id: .mapKit("resolved"), title: "Still active metadata", coordinate: tapped)
        await resolver.finish(at: tapped, with: metadata)
        await wait { session.candidates.candidate?.place.title == metadata.title }
        #expect(session.candidates.query == metadata.title)
        #expect(session.candidates.canGo)
    }

    @Test func stagingCurrentRevokesDeletionUntilAnotherDedicatedClearAndDoesNotInventASelection() throws {
        let controller = controller(values: [.place(place(0)), .place(place(1)), .place(place(2))])
        let initial = controller.draft
        #expect(controller.openPicker(for: initial.nodes[0].id))
        let session = try #require(controller.picker)
        #expect(controller.clearPickerPlace(id: session.id))
        #expect(controller.picker?.clearedPlace == true)
        #expect(controller.stagePickerCurrent(id: session.id))
        #expect(controller.picker?.clearedPlace == false)
        #expect(session.candidates.candidate == nil)
        #expect(session.candidates.query.isEmpty)
        #expect(!controller.confirmPicker(id: session.id, useCurrentLocation: false))
        #expect(controller.draft == initial)
        #expect(controller.clearPickerPlace(id: session.id))
        #expect(controller.confirmPicker(id: session.id))
        #expect(!controller.draft.nodes.contains { $0.id == initial.nodes[0].id })
        let empty = self.controller(values: [])
        #expect(empty.openNewPicker())
        let new = try #require(empty.picker)
        #expect(empty.stagePickerCurrent(id: new.id))
        #expect(!empty.confirmPicker(id: new.id, useCurrentLocation: false))
        #expect(empty.confirmPicker(id: new.id, useCurrentLocation: true))
        #expect(empty.draft.nodes.map(\.value) == [.current])
    }

    @Test(arguments: ["invalid", "name"])
    func ordinaryQueryClearingCannotReviveAnEarlierDedicatedDelete(input: String) async throws {
        let controller = controller(values: [.place(place(0)), .place(place(1)), .place(place(2))])
        let node = controller.draft.nodes[1]
        #expect(controller.openPicker(for: node.id))
        let session = try #require(controller.picker)
        #expect(controller.clearPickerPlace(id: session.id))
        #expect(controller.picker?.clearedPlace == true)
        session.candidates.updateQuery(input == "invalid" ? "91, 121" : "No matching results")
        await wait { !session.candidates.isSearching }
        #expect(controller.picker?.clearedPlace == false)
        #expect(!controller.confirmPicker(id: session.id))
        session.candidates.updateQuery("")
        #expect(controller.picker?.clearedPlace == false)
        #expect(!controller.confirmPicker(id: session.id))
        #expect(controller.draft.nodes[1] == node)
        #expect(controller.clearPickerPlace(id: session.id))
        #expect(controller.picker?.clearedPlace == true)
        #expect(controller.confirmPicker(id: session.id))
        #expect(!controller.draft.nodes.contains { $0.id == node.id })
    }

    @Test(arguments: ["selection", "tap", "reset"])
    func anotherExplicitEditPermanentlyInvalidatesThePreviousDeleteIntent(action: String) throws {
        let controller = controller(values: [.place(place(0)), .place(place(1)), .place(place(2))])
        let node = controller.draft.nodes[1]
        #expect(controller.openPicker(for: node.id))
        let session = try #require(controller.picker)
        #expect(controller.clearPickerPlace(id: session.id))
        switch action {
        case "selection": session.candidates.select(place(3))
        case "tap": session.candidates.selectMapCoordinate(place(3).coordinate)
        default: session.candidates.resetSelection()
        }
        session.candidates.resetSelection()
        session.candidates.updateQuery("")
        #expect(controller.picker?.clearedPlace == false)
        #expect(!controller.confirmPicker(id: session.id))
        #expect(controller.draft.nodes[1] == node)
    }

    @Test func cancelledLateMetadataCannotInvalidateAFreshDedicatedClear() async throws {
        let resolver = ControlledPlaceResolver()
        let controller = controller(values: [.place(place(0)), .place(place(1)), .place(place(2))])
        let node = controller.draft.nodes[1]
        #expect(controller.openPicker(for: node.id))
        let session = try #require(controller.picker)
        let tapped = place(3).coordinate
        session.candidates.selectMapCoordinate(tapped, resolver: resolver)
        await wait { await resolver.requests == [tapped] }
        #expect(controller.clearPickerPlace(id: session.id))
        await resolver.finish(at: tapped, with: place(3))
        await wait { await resolver.returned.contains(tapped) }
        for _ in 0..<10 { await Task.yield() }
        #expect(controller.picker?.clearedPlace == true)
        #expect(controller.confirmPicker(id: session.id))
        #expect(!controller.draft.nodes.contains { $0.id == node.id })
    }

    @Test func deletingTheEditedNodeClosesAndDetachesItsStalePicker() async throws {
        let resolver = ControlledPlaceResolver()
        let controller = controller(values: [.place(place(0)), .place(place(1)), .place(place(2))])
        let id = controller.draft.nodes[1].id
        #expect(controller.openPicker(for: id))
        let old = try #require(controller.picker)
        let tapped = place(3).coordinate
        old.candidates.selectMapCoordinate(tapped, resolver: resolver)
        await wait { await resolver.requests == [tapped] }
        var notifications = 0
        let observation = controller.objectWillChange.sink { notifications += 1 }
        defer { observation.cancel() }
        #expect(controller.removeNode(id: id))
        #expect(controller.picker == nil)
        let baseline = notifications, frozen = controller.draft
        await resolver.finish(at: tapped, with: place(3))
        await wait { old.candidates.candidate?.place.title == place(3).title }
        #expect(notifications == baseline)
        #expect(controller.draft == frozen)
        #expect(!controller.confirmPicker(id: old.id))
    }

    @Test func nativeAdmissionWaitsForTheCompleteOrderedPlanAndStartsAtItsExactFirstNode() async throws {
        let planner = ControlledWaypointPlanner(), device = RouteControlledDevice(), clock = RouteTestClock()
        let service = ServiceController(service: device)
        let values = (0...2).map { RouteNodeValue.place(place($0)) }
        let controller = RouteExecutionController(draft: RouteDraft(values: values)!, planner: planner, commands: service, search: WaypointSearch(), clock: clock)
        #expect(controller.start())
        await wait { await planner.calls.count == 1 }
        #expect(await device.coordinates.isEmpty)
        await planner.finish()
        await wait { await planner.calls.count == 2 }
        #expect(await device.coordinates.isEmpty)
        #expect(service.preparedOperation == nil)
        await planner.finish()
        await wait { await device.waiting }
        #expect(await device.coordinates == [place(0).coordinate])
        #expect(controller.intent?.route.points == (0...2).map { place($0).coordinate })
        #expect(controller.progress == nil)
        await device.finish(.acknowledged)
        await wait { controller.phase == .running }
        #expect(controller.progress?.committedDistanceMeters == 0)
        #expect(service.confirmedSimulatedLocation == place(0).coordinate)
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
        #expect(await device.clears == 0)
    }

    @Test func draftsContainOnlyConfirmedNodesAndRolesFollowStableIdentity() throws {
        let empty = try #require(RouteDraft(values: []))
        #expect(empty.nodes.isEmpty)
        #expect(empty.start == nil)
        #expect(empty.destination == nil)
        let initial = RouteDraft()
        #expect(initial.nodes.count == 1)
        #expect(initial.start?.value == .current)
        #expect(initial.destination == nil)
        let draft = try #require(RouteDraft(values: [.place(place(0)), .current, .place(place(2))]))
        #expect(draft.role(of: draft.nodes[0].id) == .start)
        #expect(draft.role(of: draft.nodes[1].id) == .waypoint(1))
        #expect(draft.role(of: draft.nodes[2].id) == .destination)
        #expect(RouteDraft(values: [.current, .current]) == nil)
        #expect(RouteDraft(values: Array(repeating: .place(place(0)), count: 28)) == nil)
        #expect(RouteDraft(values: Array(repeating: .place(place(0)), count: 27))?.nodes.count == 27)
        #expect(RouteDraft(start: .current, destination: .current) == nil)
        #expect(RouteDraft(start: nil, destination: nil)?.nodes.isEmpty == true)
    }

    @Test func provisionalAdditionCancelAndConfirmationNeverInsertAnEmptyNode() throws {
        let controller = controller(values: [])
        #expect(!controller.canStart)
        #expect(controller.openNewPicker())
        let first = try #require(controller.picker)
        #expect(first.isNew)
        #expect(first.role == .start)
        #expect(first.allowsCurrent)
        #expect(controller.draft.nodes.isEmpty)
        #expect(!controller.confirmPicker(id: first.id))
        controller.cancelPicker(id: first.id)
        #expect(controller.draft.nodes.isEmpty)
        #expect(controller.openNewPicker())
        let start = try #require(controller.picker)
        start.candidates.select(place(0))
        #expect(controller.confirmPicker(id: start.id))
        #expect(controller.draft.nodes.map(\.id) == [start.nodeID])
        #expect(controller.openNewPicker())
        let end = try #require(controller.picker)
        #expect(end.role == .destination)
        end.candidates.select(place(2))
        #expect(controller.confirmPicker(id: end.id))
        #expect(controller.openNewPicker())
        let middle = try #require(controller.picker)
        #expect(middle.role == .waypoint(1))
        middle.candidates.select(place(1))
        #expect(controller.confirmPicker(id: middle.id))
        #expect(controller.draft.nodes.map(\.id) == [start.nodeID, middle.nodeID, end.nodeID])
    }

    @Test func editsFollowTheOriginalIDAfterReorderAndDeletedSessionsCannotCommit() throws {
        let controller = controller(values: [.place(place(0)), .place(place(1)), .place(place(2))])
        let original = controller.draft.nodes
        #expect(controller.openPicker(for: original[1].id))
        let session = try #require(controller.picker)
        #expect(controller.moveNode(id: original[1].id, toIndex: 0))
        #expect(controller.picker?.role == .start)
        session.candidates.select(place(3))
        #expect(controller.confirmPicker(id: session.id))
        #expect(controller.draft.nodes.map(\.id) == [original[1].id, original[0].id, original[2].id])
        #expect(controller.draft.nodes[0].value == .place(place(3)))
        #expect(controller.openPicker(for: original[2].id))
        let deleted = try #require(controller.picker)
        #expect(controller.removeNode(id: deleted.nodeID))
        deleted.candidates.select(place(4))
        #expect(!controller.confirmPicker(id: deleted.id))
        #expect(controller.draft.nodes.count == 2)
        #expect(controller.draft.destination?.id == original[0].id)
        #expect(!controller.moveNode(id: original[2].id, toIndex: 0))
        #expect(!controller.moveNode(id: original[0].id, toIndex: 2))
        #expect(controller.removeNode(id: original[1].id))
        #expect(controller.draft.destination == nil)
        #expect(controller.removeNode(id: original[0].id))
        #expect(controller.draft.start == nil)
        #expect(!controller.canStart)
    }

    @Test func explicitClearRequiresAnActuallyEmptyEditorWhileQueryClearNeverDeletes() throws {
        let controller = controller(values: [.place(place(0)), .place(place(1)), .place(place(2))])
        let middle = controller.draft.nodes[1]
        #expect(controller.openPicker(for: middle.id))
        let queryOnly = try #require(controller.picker)
        queryOnly.candidates.updateQuery("")
        #expect(!queryOnly.clearedPlace)
        #expect(controller.confirmPicker(id: queryOnly.id))
        #expect(controller.draft.nodes[1] == middle)
        #expect(controller.openPicker(for: middle.id))
        let clear = try #require(controller.picker)
        #expect(controller.clearPickerPlace(id: clear.id))
        #expect(controller.picker?.clearedPlace == true)
        #expect(controller.draft.nodes.count == 3)
        clear.candidates.updateQuery("91, 121")
        #expect(controller.picker?.clearedPlace == false)
        #expect(!controller.confirmPicker(id: clear.id))
        #expect(controller.draft.nodes[1] == middle)
        clear.candidates.select(place(3))
        #expect(controller.picker?.clearedPlace == false)
        #expect(controller.confirmPicker(id: clear.id))
        #expect(controller.draft.nodes[1].id == middle.id)
        #expect(controller.draft.nodes[1].value == .place(place(3)))
        #expect(controller.openPicker(for: middle.id))
        let remove = try #require(controller.picker)
        #expect(controller.clearPickerPlace(id: remove.id))
        #expect(controller.confirmPicker(id: remove.id))
        #expect(!controller.draft.nodes.contains { $0.id == middle.id })
        #expect(controller.draft.nodes.count == 2)
    }

    @Test func nodeCapacityIsCheckedAtProvisionalConfirmationAndFreedByRemoval() throws {
        let controller = controller(values: (0..<26).map { .place(place($0)) })
        let destination = try #require(controller.draft.destination)
        #expect(controller.openNewPicker())
        let final = try #require(controller.picker)
        #expect(controller.draft.nodes.count == 26)
        final.candidates.select(place(26))
        #expect(controller.confirmPicker(id: final.id))
        #expect(controller.draft.nodes.count == 27)
        #expect(controller.draft.nodes[25].id == final.nodeID)
        #expect(controller.draft.destination?.id == destination.id)
        #expect(controller.draft.role(of: final.nodeID) == .waypoint(25))
        #expect(!controller.canAddNode)
        #expect(!controller.openNewPicker())
        #expect(!controller.confirmPicker(id: final.id))
        #expect(controller.removeNode(id: final.nodeID))
        #expect(controller.canAddNode)
        #expect(controller.openNewPicker())
        let cancelled = try #require(controller.picker)
        controller.cancelPicker(id: cancelled.id)
        #expect(controller.draft.nodes.count == 26)
    }

    @Test func currentEligibilityAndRolesRecheckAfterReorderWithoutChangingTheCurrentNode() throws {
        let controller = controller(values: [.current, .place(place(1)), .place(place(2))])
        let initial = controller.draft.nodes
        #expect(controller.openPicker(for: initial[1].id))
        let session = try #require(controller.picker)
        #expect(!session.allowsCurrent)
        #expect(controller.moveNode(id: initial[1].id, toIndex: 0))
        #expect(controller.picker?.role == .start)
        #expect(controller.picker?.allowsCurrent == false)
        let noCurrent = self.controller(values: [.place(place(0)), .place(place(1)), .place(place(2))])
        let firstID = noCurrent.draft.nodes[0].id
        #expect(noCurrent.openPicker(for: firstID))
        let eligible = try #require(noCurrent.picker)
        #expect(eligible.allowsCurrent)
        #expect(noCurrent.moveNode(id: firstID, toIndex: 2))
        #expect(noCurrent.picker?.role == .destination)
        #expect(noCurrent.picker?.allowsCurrent == false)
        #expect(!noCurrent.confirmPicker(id: eligible.id, useCurrentLocation: true))
        #expect(!noCurrent.draft.nodes.contains { $0.value == .current })
        #expect(!controller.confirmPicker(id: session.id, useCurrentLocation: true))
        #expect(controller.draft.nodes[1].id == initial[0].id)
        #expect(controller.draft.nodes[1].value == .current)
        #expect(controller.removeNode(id: initial[0].id))
        #expect(controller.picker?.allowsCurrent == true)
        #expect(controller.confirmPicker(id: session.id, useCurrentLocation: true))
        #expect(controller.draft.nodes[0].id == initial[1].id)
        #expect(controller.draft.nodes[0].value == .current)
        #expect(controller.moveNode(id: initial[1].id, toIndex: 1))
        #expect(controller.draft.destination?.value == .current)
        #expect(controller.draft.nodes.filter { $0.value == .current }.count == 1)
        #expect(controller.openPicker(for: initial[1].id))
        #expect(controller.picker?.role == .destination)
        #expect(controller.picker?.allowsCurrent == false)
    }

    @Test(arguments: [1, 2])
    func movedCurrentNodesResolveOnceAtStartAndEveryLegUsesTheFrozenOrder(currentIndex: Int) async throws {
        let planner = ControlledWaypointPlanner(), commands = WaypointCommands(), clock = RouteTestClock()
        let controller = RouteExecutionController(draft: RouteDraft(values: [.current, .place(place(1)), .place(place(2))])!, planner: planner, commands: commands, search: WaypointSearch(), clock: clock)
        let currentID = controller.draft.nodes[0].id
        #expect(controller.moveNode(id: currentID, toIndex: currentIndex))
        let source = controller.draft
        let resolved = GeoCoordinate(latitude: 24.5, longitude: 120.5)!
        commands.origin = resolved
        #expect(controller.start())
        #expect(commands.originReads == 1)
        await wait { await planner.calls.count == 1 }
        #expect(commands.begins.isEmpty)
        #expect(controller.intent == nil)
        #expect(!controller.openNewPicker())
        #expect(!controller.removeNode(id: currentID))
        #expect(!controller.moveNode(id: currentID, toIndex: 0))
        commands.origin = GeoCoordinate(latitude: 30, longitude: 130)!
        await planner.finish()
        await wait { await planner.calls.count == 2 }
        #expect(commands.begins.isEmpty)
        await planner.finish()
        await wait { controller.phase == .running }
        let intent = try #require(commands.begins.first)
        let ordered = source.nodes.map { node -> GeoCoordinate in
            if case .place(let place) = node.value { return place.coordinate }; return resolved
        }
        #expect(await planner.calls == [WaypointLeg(from: ordered[0], to: ordered[1]), WaypointLeg(from: ordered[1], to: ordered[2])])
        #expect(intent.route.points == ordered)
        #expect(intent.draft.nodes.map(\.id) == source.nodes.map(\.id))
        #expect(intent.draft.nodes[currentIndex].value == .place(MapPlace(id: .coordinate(resolved), title: resolved.displayText, coordinate: resolved)))
        #expect(controller.draft == source)
        #expect(commands.originReads == 1)
        #expect(controller.progress?.committedDistanceMeters == 0)
        #expect(controller.cancel())
        await wait { controller.phase == .editing }
    }

    @Test func missingCurrentOrAdjacentEqualCoordinatesCannotPlanOrAdmit() async throws {
        let planner = ControlledWaypointPlanner(), commands = WaypointCommands()
        commands.origin = nil
        let missing = RouteExecutionController(draft: RouteDraft(values: [.place(place(0)), .current])!, planner: planner, commands: commands, search: WaypointSearch())
        #expect(!missing.canStart)
        #expect(!missing.start())
        #expect(missing.error == .currentLocationUnavailable)
        commands.origin = place(0).coordinate
        let equal = RouteExecutionController(draft: RouteDraft(values: [.place(place(0)), .current, .place(place(1))])!, planner: planner, commands: commands, search: WaypointSearch())
        #expect(!equal.canStart)
        #expect(!equal.start())
        #expect(equal.error == .invalidPath)
        #expect(await planner.calls.isEmpty)
        #expect(commands.begins.isEmpty)
    }

    @Test(arguments: [1, 2])
    func aFailureInAnySequentialLegDiscardsTheEntirePlanWithoutAdmission(failedLeg: Int) async throws {
        let planner = ControlledWaypointPlanner(), commands = WaypointCommands()
        let controller = RouteExecutionController(draft: RouteDraft(values: [.place(place(0)), .place(place(1)), .place(place(2))])!, planner: planner, commands: commands, search: WaypointSearch())
        #expect(controller.start())
        for index in 1...failedLeg {
            await wait { await planner.calls.count == index }
            #expect(controller.intent == nil)
            #expect(controller.plannedRoute == nil)
            #expect(commands.begins.isEmpty)
            await planner.finish(failure: index == failedLeg)
        }
        await wait { controller.phase == .editing }
        #expect(controller.error == .planningFailed)
        #expect(controller.intent == nil)
        #expect(controller.plannedRoute == nil)
        #expect(commands.begins.isEmpty)
        #expect(await planner.calls.count == failedLeg)
    }

    @Test(arguments: [false, true])
    func cancellationOrAdmissionChangeBetweenLegsCannotAdmitAPartialPlan(cancel: Bool) async throws {
        let planner = ControlledWaypointPlanner(), commands = WaypointCommands()
        let controller = RouteExecutionController(draft: RouteDraft(values: [.place(place(0)), .place(place(1)), .place(place(2))])!, planner: planner, commands: commands, search: WaypointSearch())
        #expect(controller.start())
        await wait { await planner.calls.count == 1 }
        await planner.finish()
        await wait { await planner.calls.count == 2 }
        if cancel { #expect(controller.cancel()) }
        else { commands.routeAdmissionRevision &+= 1 }
        await planner.finish()
        await wait { controller.phase == .editing }
        #expect(controller.intent == nil)
        #expect(controller.plannedRoute == nil)
        #expect(commands.begins.isEmpty)
    }

    @Test(arguments: [false, true])
    func theGlobalPathCapIncludesEveryLegAndOnlyDropsSharedBoundaries(overCap: Bool) async throws {
        let commands = WaypointCommands(), clock = RouteTestClock()
        let controller = RouteExecutionController(draft: RouteDraft(values: [.place(place(0)), .place(place(1)), .place(place(2))])!, planner: DenseWaypointPlanner(firstCount: overCap ? 5_001 : 5_000), commands: commands, search: WaypointSearch(), clock: clock)
        #expect(controller.start())
        await wait { controller.phase != .planning && controller.phase != .preparing }
        if overCap {
            #expect(controller.phase == .editing)
            #expect(controller.error == .invalidPath)
            #expect(controller.intent == nil)
            #expect(controller.plannedRoute == nil)
            #expect(commands.begins.isEmpty)
        } else {
            #expect(controller.phase == .running)
            let route = try #require(commands.begins.first?.route)
            #expect(route.points.count == 10_000)
            #expect(route.points.filter { $0 == place(1).coordinate }.count == 1)
            #expect(route.start == place(0).coordinate)
            #expect(route.end == place(2).coordinate)
            #expect(controller.cancel())
            await wait { controller.phase == .editing }
        }
    }

    private func place(_ index: Int) -> MapPlace {
        let coordinate = GeoCoordinate(latitude: 25 + Double(index) * 0.001, longitude: 121)!
        return MapPlace(id: .coordinate(coordinate), title: "Place \(index)", coordinate: coordinate)
    }
    private func controller(values: [RouteNodeValue]) -> RouteExecutionController {
        RouteExecutionController(draft: RouteDraft(values: values)!, planner: WaypointPlanner(), commands: WaypointCommands(), search: WaypointSearch())
    }
    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

private struct WaypointPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] { [from, to] }
}
private struct WaypointSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}
private actor WaypointLookupSearch: PlaceSearching {
    private var pending: CheckedContinuation<[MapPlace], Never>?
    var waiting: Bool { pending != nil }
    var returned = false
    func search(query: String) async throws -> [MapPlace] {
        let result = await withCheckedContinuation { pending = $0 }
        returned = true
        return result
    }
    func finish(_ places: [MapPlace]) { pending?.resume(returning: places); pending = nil }
}
@MainActor private final class WaypointCommands: RouteCommanding {
    var origin: GeoCoordinate? = GeoCoordinate(latitude: 24, longitude: 120)
    var originReads = 0
    var currentRouteOrigin: GeoCoordinate? { originReads += 1; return origin }
    var begins: [RouteExecutionIntent] = []
    var routeAdmissionRevision: UInt64 = 0
    var canBeginRoute = true
    private let events = PassthroughSubject<RouteCommandEvent, Never>()
    var routeEvents: AnyPublisher<RouteCommandEvent, Never> { events.eraseToAnyPublisher() }
    func beginRoute(_ intent: RouteExecutionIntent, expectedAdmissionRevision: UInt64) async -> RouteCommandOutcome { begins.append(intent); return .acknowledged }
    func sendRoutePoint(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, coordinate: GeoCoordinate) async -> RouteCommandOutcome { .acknowledged }
    func pauseRoute(executionID: UUID, lease: MovementTaskLease) -> Bool { true }
    func resumeRoute(executionID: UUID, lease: MovementTaskLease) -> Bool { true }
    func endRoute(executionID: UUID, lease: MovementTaskLease) {}
    func waitForRouteIdle(executionID: UUID, lease: MovementTaskLease) async -> RouteIdleSettlement { .settled }
}

private struct WaypointLeg: Equatable, Sendable { let from: GeoCoordinate; let to: GeoCoordinate }
private actor ControlledWaypointPlanner: RoutePlanning {
    var calls: [WaypointLeg] = []
    private var pending: CheckedContinuation<[GeoCoordinate], any Error>?
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        calls.append(WaypointLeg(from: from, to: to))
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish(failure: Bool = false) {
        let continuation = pending; pending = nil
        if failure { continuation?.resume(throwing: RouteExecutionFailure.planningFailed) }
        else if let leg = calls.last { continuation?.resume(returning: [leg.from, leg.to]) }
    }
}
private actor DenseWaypointPlanner: RoutePlanning {
    let firstCount: Int
    private var count = 0
    init(firstCount: Int) { self.firstCount = firstCount }
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        count += 1
        let points = count == 1 ? firstCount : 5_001
        return (0..<points).map { index in
            if index == 0 { return from }; if index == points - 1 { return to }
            let fraction = Double(index) / Double(points - 1)
            return GeoCoordinate(latitude: from.latitude + (to.latitude - from.latitude) * fraction,
                longitude: from.longitude + (to.longitude - from.longitude) * fraction)!
        }
    }
}
