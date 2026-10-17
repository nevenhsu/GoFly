import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct CandidateControllerTests {
    @Test(arguments: ["tap", "query", "selection"])
    func lateMapMetadataCannotReplaceANewerExplicitAction(action: String) async throws {
        let resolver = ControlledPlaceResolver()
        let controller = CandidateController(search: EmptyPlaceSearch(), debounce: .zero)
        let old = GeoCoordinate(latitude: 25, longitude: 121)!
        let latest = GeoCoordinate(latitude: 26, longitude: 122)!
        controller.selectMapCoordinate(old, resolver: resolver)
        await wait { await resolver.requests == [old] }
        switch action {
        case "tap":
            controller.selectMapCoordinate(latest, resolver: resolver)
            await wait { await resolver.requests == [old, latest] }
            await resolver.finish(at: latest, with: MapPlace(id: .coordinate(latest), title: "Latest tap", coordinate: latest))
            await wait { controller.candidate?.place.title == "Latest tap" }
        case "query":
            controller.updateQuery("A new name query")
            await wait { !controller.isSearching }
        default:
            controller.select(place("Explicit selection", latitude: 26, longitude: 122))
        }
        let candidate = controller.candidate, query = controller.query, results = controller.results
        let queryKind = controller.queryKind, canGo = controller.canGo
        await resolver.finish(at: old, with: MapPlace(id: .coordinate(old), title: "Stale metadata", coordinate: old))
        await wait { await resolver.returned.contains(old) }
        for _ in 0..<10 { await Task.yield() }
        #expect(controller.candidate == candidate)
        #expect(controller.query == query)
        #expect(controller.queryKind == queryKind)
        #expect(controller.results == results)
        #expect(controller.canGo == canGo)
        #expect(!controller.searchFailed)
    }

    @Test(arguments: [false, true])
    func unavailableMapMetadataLeavesTheImmediateCoordinateSelectionValid(failure: Bool) async throws {
        let resolver = ControlledPlaceResolver()
        let controller = CandidateController(search: EmptyPlaceSearch())
        let tapped = GeoCoordinate(latitude: 25.123456789, longitude: 121.987654321)!
        controller.selectMapCoordinate(tapped, resolver: resolver)
        let original = try #require(controller.candidate)
        await wait { await resolver.requests == [tapped] }
        if failure { await resolver.fail(at: tapped) }
        else { await resolver.finish(at: tapped, with: nil) }
        await wait { await resolver.returned.contains(tapped) }
        for _ in 0..<10 { await Task.yield() }
        #expect(controller.candidate == original)
        #expect(controller.query == tapped.displayText)
        #expect(controller.queryKind == .coordinate)
        #expect(controller.results == [original.place])
        #expect(controller.canGo)
        #expect(controller.inputError == nil)
        #expect(!controller.isSearching)
        #expect(!controller.searchFailed)
    }

    @Test(arguments: [false, true])
    func mapMetadataUsesAddressOrCoordinateFallbackWithoutLaunchingNameSearch(hasAddress: Bool) async throws {
        let resolver = ControlledPlaceResolver(), search = ControlledPlaceSearch()
        let controller = CandidateController(search: search, debounce: .zero)
        let tapped = GeoCoordinate(latitude: 25, longitude: 121)!
        controller.selectMapCoordinate(tapped, resolver: resolver)
        let id = controller.candidate?.id
        await wait { await resolver.requests == [tapped] }
        let metadata = MapPlace(id: .mapKit("metadata"), title: "", coordinate: tapped, address: hasAddress ? "Somewhere Road" : nil)
        await resolver.finish(at: tapped, with: metadata)
        await wait { await resolver.returned.contains(tapped) }
        for _ in 0..<10 { await Task.yield() }
        #expect(controller.candidate?.id == id)
        #expect(controller.query == (hasAddress ? "Somewhere Road" : tapped.displayText))
        #expect(controller.queryKind == (hasAddress ? .name : .coordinate))
        #expect(controller.results == [try #require(controller.candidate?.place)])
        #expect(await search.queries.isEmpty)
        #expect(controller.canGo)
    }

    @Test func mapMetadataRefinesOnlyTheLabelWhileKeepingExactTapIdentityAndCandidateID() async throws {
        let resolver = ControlledPlaceResolver()
        let controller = CandidateController(search: EmptyPlaceSearch())
        let tapped = GeoCoordinate(latitude: 25.123456789, longitude: 121.987654321)!
        controller.selectMapCoordinate(tapped, resolver: resolver)
        let original = try #require(controller.candidate)
        let key = try #require(FavoritePlaceKey(place: original.place))
        #expect(controller.query == tapped.displayText)
        #expect(controller.queryKind == .coordinate)
        #expect(controller.canGo)
        #expect(!controller.isSearching)
        await wait { await resolver.requests == [tapped] }
        let snapped = GeoCoordinate(latitude: 26, longitude: 122)!
        let metadata = MapPlace(id: .mapKit("untrusted-result"), title: "A nearby park", coordinate: snapped, address: "Park Road")
        await resolver.finish(at: tapped, with: metadata)
        await wait { controller.candidate?.place.title == metadata.title }
        let refined = try #require(controller.candidate)
        #expect(refined.id == original.id)
        #expect(refined.place.id == .coordinate(tapped))
        #expect(refined.place.coordinate == tapped)
        #expect(refined.place.address == "Park Road")
        #expect(FavoritePlaceKey(place: refined.place) == key)
        #expect(controller.query == "A nearby park")
        #expect(controller.queryKind == .name)
        #expect(controller.results == [refined.place])
        #expect(controller.canGo)
        #expect(!controller.isSearching)
        #expect(!controller.searchFailed)
    }

    @Test(arguments: [false, true])
    func anExplicitExternalChoiceRemainsVisibleAfterEmptyOrFailedNameResults(failedSearch: Bool) async throws {
        let search = ControlledPlaceSearch()
        let controller = CandidateController(search: search, debounce: .zero)
        controller.updateQuery("Unmatched name")
        await wait { await search.queries == ["Unmatched name"] }
        if failedSearch { await search.fail("Unmatched name") }
        else { await search.finish("Unmatched name", with: []) }
        await wait { !controller.isSearching }
        #expect(controller.results.isEmpty)
        #expect(controller.searchFailed == failedSearch)
        let favorite = place("Chosen favorite", latitude: 25, longitude: 121)
        controller.select(favorite)
        #expect(controller.results == [favorite])
        #expect(controller.candidate?.place == favorite)
        #expect(controller.canGo)
        #expect(!controller.searchFailed)
        #expect(controller.inputError == nil)
        #expect(controller.query == "Unmatched name")
        #expect(controller.queryKind == .name)
    }

    @Test func aNewNameQueryRequiresSelectionWithoutDiscardingThePreviousCandidate() throws {
        let controller = CandidateController(search: EmptyPlaceSearch())
        let originalPlace = place("Existing", latitude: 25, longitude: 121)
        controller.select(originalPlace)
        let original = try #require(controller.candidate)
        controller.updateQuery("New name")
        #expect(controller.candidate == original)
        #expect(!controller.canGo)
        controller.updateQuery("  ")
        #expect(controller.canGo)
        controller.updateQuery("91, 121")
        controller.updateQuery("Another name")
        controller.updateQuery("")
        #expect(!controller.canGo)
        controller.select(originalPlace)
        #expect(controller.canGo)
        controller.updateQuery("New name")
        controller.selectMapCoordinate(originalPlace.coordinate)
        #expect(controller.canGo)
        controller.updateQuery("New name")
        controller.updateQuery("26, 122")
        #expect(controller.canGo)
    }

    @Test func clearingInvalidInputDoesNotSilentlyEnableTheOldGo() throws {
        let controller = CandidateController(search: EmptyPlaceSearch(), debounce: .zero)
        controller.updateQuery("25, 121")
        let original = try #require(controller.candidate)
        controller.updateQuery("91, 121")
        #expect(controller.inputError == .latitudeRange)
        controller.updateQuery("")
        #expect(controller.candidate == original)
        #expect(!controller.canGo)
        controller.select(original.place)
        #expect(controller.canGo)
        controller.updateQuery("25, not-a-longitude")
        #expect(controller.inputError == .format)
        #expect(!controller.canGo)
    }

    @Test func lateSearchCannotReplaceNewerSelectionAndCompletionClearsOnlyItsOwnCandidate() async throws {
        let search = ControlledPlaceSearch()
        let controller = CandidateController(search: search, debounce: .zero)
        controller.updateQuery("old query")
        await wait { await search.queries == ["old query"] }
        controller.updateQuery("new query")
        await wait { await search.queries.count == 2 }
        let latest = place("New result", latitude: 26, longitude: 122)
        await search.finish("new query", with: [latest])
        await wait { !controller.isSearching }
        controller.select(latest)
        let oldCandidate = try #require(controller.candidate)
        await search.finish("old query", with: [place("Old result", latitude: 24, longitude: 120)])
        for _ in 0..<10 { await Task.yield() }
        #expect(controller.results == [latest])
        #expect(controller.candidate == oldCandidate)

        controller.updateQuery("pending query")
        await wait { await search.queries.count == 3 }
        let tapped = try #require(GeoCoordinate(latitude: 25.123456789, longitude: 121.987654321))
        controller.selectMapCoordinate(tapped)
        let newCandidate = try #require(controller.candidate)
        #expect(newCandidate.place.coordinate == tapped)
        #expect(newCandidate.id != oldCandidate.id)
        #expect(controller.queryKind == .coordinate)
        await search.finish("pending query", with: [latest])
        for _ in 0..<10 { await Task.yield() }
        #expect(controller.candidate == newCandidate)
        #expect(controller.results == [newCandidate.place])
        controller.clearCandidate(ifMatching: oldCandidate.id)
        #expect(controller.candidate == newCandidate)
        controller.clearCandidate(ifMatching: newCandidate.id)
        #expect(controller.candidate == nil)
        #expect(!controller.canGo)
    }

    @Test func nameSearchNeverPreselectsAndExplicitSelectionPreservesTheResultList() async throws {
        let search = ControlledPlaceSearch()
        let controller = CandidateController(search: search, debounce: .zero)
        let first = place("臺北車站", latitude: 25.0478, longitude: 121.5170)
        let second = place("台北站前", latitude: 25.045, longitude: 121.515)
        controller.updateQuery("臺北車站")
        await wait { await search.queries == ["臺北車站"] }
        await search.finish("臺北車站", with: [first, second])
        await wait { !controller.isSearching }
        #expect(controller.results == [first, second])
        #expect(controller.candidate == nil)
        #expect(!controller.canGo)
        controller.select(second)
        #expect(controller.candidate?.place == second)
        #expect(controller.results == [first, second])
        #expect(controller.canGo)
    }

    @Test func invalidCoordinatesRetainTheLastCandidateButBlockGoUntilAValidSelection() throws {
        let controller = CandidateController(search: EmptyPlaceSearch(), debounce: .zero)
        controller.updateQuery("25.033, 121.5654")
        let original = try #require(controller.candidate)
        #expect(original.place.coordinate == GeoCoordinate(latitude: 25.033, longitude: 121.5654))
        #expect(controller.queryKind == .coordinate)
        #expect(controller.canGo)
        controller.updateQuery("25.0, 181.0")
        #expect(controller.candidate == original)
        #expect(controller.inputError == .longitudeRange)
        #expect(!controller.canGo)
        controller.updateQuery("26.1, 122.2")
        #expect(controller.candidate?.id != original.id)
        #expect(controller.candidate?.place.coordinate == GeoCoordinate(latitude: 26.1, longitude: 122.2))
        #expect(controller.inputError == nil)
        #expect(controller.canGo)
    }

    private func place(_ title: String, latitude: Double, longitude: Double) -> MapPlace {
        let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)!
        return MapPlace(id: .mapKit(title), title: title, coordinate: coordinate)
    }

    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}

private struct EmptyPlaceSearch: PlaceSearching {
    func search(query: String) async throws -> [MapPlace] { [] }
}

private actor ControlledPlaceSearch: PlaceSearching {
    var queries: [String] = []
    private var pending: [String: CheckedContinuation<[MapPlace], any Error>] = [:]
    func search(query: String) async throws -> [MapPlace] {
        queries.append(query)
        return try await withCheckedThrowingContinuation { pending[query] = $0 }
    }
    func finish(_ query: String, with results: [MapPlace]) {
        pending.removeValue(forKey: query)?.resume(returning: results)
    }
    func fail(_ query: String) {
        pending.removeValue(forKey: query)?.resume(throwing: CocoaError(.fileReadUnknown))
    }
}

actor ControlledPlaceResolver: PlaceResolving {
    var requests: [GeoCoordinate] = []
    var returned: Set<GeoCoordinate> = []
    private var pending: [GeoCoordinate: CheckedContinuation<MapPlace?, any Error>] = [:]
    func resolve(at coordinate: GeoCoordinate) async throws -> MapPlace? {
        requests.append(coordinate)
        defer { returned.insert(coordinate) }
        return try await withCheckedThrowingContinuation { pending[coordinate] = $0 }
    }
    func finish(at coordinate: GeoCoordinate, with place: MapPlace?) { pending.removeValue(forKey: coordinate)?.resume(returning: place) }
    func fail(at coordinate: GeoCoordinate) { pending.removeValue(forKey: coordinate)?.resume(throwing: CocoaError(.fileReadUnknown)) }
}
