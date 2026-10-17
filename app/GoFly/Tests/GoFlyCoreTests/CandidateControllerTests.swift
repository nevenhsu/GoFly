import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct CandidateControllerTests {
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
}
