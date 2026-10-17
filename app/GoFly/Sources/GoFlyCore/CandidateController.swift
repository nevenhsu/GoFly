import Combine
import Foundation

public protocol PlaceSearching: Sendable {
    func search(query: String) async throws -> [MapPlace]
}

public enum CoordinateInputFailure: String, Equatable, Sendable {
    case format = "search.coordinateFormat"
    case latitudeRange = "search.latitudeRange"
    case longitudeRange = "search.longitudeRange"
}

public enum PlaceQueryKind: Equatable, Sendable { case empty, name, coordinate, invalidCoordinate }

@MainActor
public final class CandidateController: ObservableObject {
    @Published public private(set) var query = ""
    @Published public private(set) var queryKind: PlaceQueryKind = .empty
    @Published public private(set) var results: [MapPlace] = []
    @Published public private(set) var candidate: TeleportCandidate?
    @Published public private(set) var inputError: CoordinateInputFailure?
    @Published public private(set) var isSearching = false
    @Published public private(set) var searchFailed = false
    private var blockedByInvalidInput = false
    private var blockedByUnselectedNameQuery = false
    private let search: any PlaceSearching
    private let debounce: Duration
    private var revision: UInt64 = 0
    private var searchTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?

    public init(search: any PlaceSearching, debounce: Duration = .milliseconds(300)) {
        self.search = search
        self.debounce = debounce
    }
    deinit { searchTask?.cancel(); metadataTask?.cancel() }
    public var canGo: Bool { candidate != nil && !blockedByInvalidInput && !blockedByUnselectedNameQuery }
    var editingRevision: UInt64 { revision }
    public func updateQuery(_ text: String) {
        cancelSearch()
        query = text
        inputError = nil
        searchFailed = false
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
        let first = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let coordinateLike = parts.count > 1 && (Double(first) != nil || first.first.map { $0.isNumber || "+-.".contains($0) } == true)
        guard coordinateLike else {
            queryKind = trimmed.isEmpty ? .empty : .name
            blockedByUnselectedNameQuery = !trimmed.isEmpty
            results = []
            if !trimmed.isEmpty { searchNames(trimmed) }
            return
        }
        guard parts.count == 2,
              let latitude = Double(first),
              let longitude = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              latitude.isFinite, longitude.isFinite else {
            rejectCoordinates(.format)
            return
        }
        guard (-90...90).contains(latitude) else { rejectCoordinates(.latitudeRange); return }
        guard (-180...180).contains(longitude) else { rejectCoordinates(.longitudeRange); return }
        guard let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude) else { return }
        let place = MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
        queryKind = .coordinate
        blockedByInvalidInput = false
        blockedByUnselectedNameQuery = false
        results = [place]
        candidate = TeleportCandidate(place: place)
    }

    private func rejectCoordinates(_ failure: CoordinateInputFailure) {
        queryKind = .invalidCoordinate
        inputError = failure
        blockedByInvalidInput = true
        results = []
    }
    public func select(_ place: MapPlace) {
        cancelSearch()
        if queryKind == .invalidCoordinate {
            query = place.coordinate.displayText
            queryKind = .coordinate
            results = [place]
        }
        if results.isEmpty { results = [place] }
        inputError = nil
        searchFailed = false
        blockedByInvalidInput = false
        blockedByUnselectedNameQuery = false
        candidate = TeleportCandidate(place: place)
    }
    public func selectMapCoordinate(_ coordinate: GeoCoordinate, resolver: (any PlaceResolving)? = nil) {
        cancelSearch()
        let place = MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
        query = coordinate.displayText
        queryKind = .coordinate
        results = [place]
        inputError = nil
        searchFailed = false
        blockedByInvalidInput = false
        blockedByUnselectedNameQuery = false
        let selected = TeleportCandidate(place: place)
        candidate = selected
        if let resolver { resolveMetadata(at: coordinate, candidateID: selected.id, resolver: resolver) }
    }
    public func clearCandidate(ifMatching id: UUID) {
        guard candidate?.id == id else { return }
        candidate = nil
    }
    public func resetSelection() {
        cancelSearch()
        query = ""; queryKind = .empty; results = []; candidate = nil
        inputError = nil; searchFailed = false
        blockedByInvalidInput = false; blockedByUnselectedNameQuery = false
    }
    func cancelPendingLookups() { cancelSearch() }

    private func cancelSearch() {
        revision &+= 1
        searchTask?.cancel()
        searchTask = nil
        metadataTask?.cancel()
        metadataTask = nil
        isSearching = false
    }

    private func resolveMetadata(at coordinate: GeoCoordinate, candidateID: UUID, resolver: any PlaceResolving) {
        let token = revision
        metadataTask = Task { [weak self] in
            do {
                guard let resolved = try await resolver.resolve(at: coordinate) else { return }
                try Task.checkCancellation()
                guard let self, self.revision == token, self.candidate?.id == candidateID,
                      self.candidate?.place.coordinate == coordinate else { return }
                let refined = MapPlace(id: .coordinate(coordinate), title: resolved.title,
                    coordinate: coordinate, address: resolved.address)
                self.query = refined.title
                self.queryKind = refined.title == coordinate.displayText ? .coordinate : .name
                self.results = [refined]
                self.candidate = TeleportCandidate(id: candidateID, place: refined)
            } catch {
                // Optional display metadata cannot invalidate an exact, explicitly selected map point.
            }
        }
    }

    private func searchNames(_ query: String) {
        isSearching = true
        let token = revision
        let search = search
        let debounce = debounce
        searchTask = Task { [weak self] in
            do {
                if debounce > .zero { try await Task.sleep(for: debounce) }
                try Task.checkCancellation()
                let places = try await search.search(query: query)
                try Task.checkCancellation()
                guard let self, self.revision == token else { return }
                self.results = places
                self.isSearching = false
            } catch {
                guard let self, self.revision == token else { return }
                self.isSearching = false
                self.searchFailed = !(error is CancellationError)
                self.results = []
            }
        }
    }
}
