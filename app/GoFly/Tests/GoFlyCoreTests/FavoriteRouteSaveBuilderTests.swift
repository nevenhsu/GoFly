import Foundation
import Testing
@testable import GoFlyCore

struct FavoriteRouteSaveBuilderTests {
    @Test func saveUsesOneSuppliedCurrentValueAndPreservesTheLiveDraftAndAllPlaceMetadata() throws {
        let first = place(1)
        let second = place(2)
        let draft = RouteDraft(values: [.place(first), .current, .place(second)])!
        let oldDraft = draft
        let unavailable = try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil)
        #expect(unavailable.source == .manual([first, second]))
        #expect(unavailable.omittedUnavailableCurrent)
        let current = GeoCoordinate(latitude: 25.123456789, longitude: 121.123456789)!
        let available = try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: current)
        guard case .manual(let places) = available.source else { Issue.record("Expected manual source"); return }
        #expect(places.count == 3)
        #expect(places[0] == first)
        #expect(places[1] == MapPlace(id: .coordinate(current), title: current.displayText, coordinate: current))
        #expect(places[2] == second)
        #expect(!available.omittedUnavailableCurrent)
        #expect(draft == oldDraft)
    }
    @Test func saveEligibilityUsesTheActualSuppliedOriginIncludingLateAvailabilityAndExpiry() throws {
        let draft = RouteDraft(values: [.current, .place(place(1))])!
        #expect(throws: FavoriteRoutesFailure.tooFewValidPlaces) {
            try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil)
        }
        let available = try FavoriteRouteSaveBuilder.build(draft: draft,
            currentRouteOrigin: GeoCoordinate(latitude: 25.000000001, longitude: 121)!)
        guard case .manual(let places) = available.source else { Issue.record("Expected manual"); return }
        #expect(places.count == 2)
        #expect(places[0].coordinate.latitude == 25.000000001)
        #expect(!available.omittedUnavailableCurrent)
        // A later Save receives nil when the service's valid-origin evidence has
        // expired. The previous candidate cannot supply a current location.
        #expect(throws: FavoriteRoutesFailure.tooFewValidPlaces) {
            try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil)
        }
        #expect(draft.nodes[0].value == .current)
    }
    @Test func zeroOrOneConfirmedPlaceCannotBeSavedAndTwoConfirmedPlacesNeedNoGPS() throws {
        for values: [RouteNodeValue] in [[], [.current], [.place(place(1))], [.place(place(1)), .current]] {
            let draft = RouteDraft(values: values)!
            #expect(throws: FavoriteRoutesFailure.tooFewValidPlaces) {
                try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil)
            }
        }
        let explicit = RouteDraft(values: [.place(place(1)), .place(place(2))])!
        let candidate = try FavoriteRouteSaveBuilder.build(draft: explicit, currentRouteOrigin: nil)
        #expect(candidate.source == .manual([place(1), place(2)]))
        #expect(!candidate.omittedUnavailableCurrent)
    }
    @Test func manualDuplicateIdentitiesAreOrderedSamplesAndAllTwentySevenPlacesSurviveEncoding() throws {
        let places = (0..<27).map { place($0 % 3 + 1) }
        let candidate = try FavoriteRouteSaveBuilder.build(draft: RouteDraft(values: places.map(RouteNodeValue.place))!, currentRouteOrigin: nil)
        let artifact = try FavoriteRouteArtifact(candidate: candidate)
        let record = try artifact.record(label: "  ")
        #expect(record.count == 27)
        #expect(record.label == nil)
        #expect(try FavoriteRouteSnapshot(record: record, source: candidate.source).source == .manual(places))
    }
    @Test func invalidPlaceIdentityAndBoundedTextAreRejectedAtTheSaveBoundary() {
        let coordinate = GeoCoordinate(latitude: 25, longitude: 121)!
        let other = GeoCoordinate(latitude: 26, longitude: 121)!
        let invalid = [MapPlace(id: .coordinate(other), title: "Mismatch", coordinate: coordinate),
            MapPlace(id: .mapKit(""), title: "Empty ID", coordinate: coordinate),
            MapPlace(id: .mapKit(String(repeating: "x", count: 2_049)), title: "Long ID", coordinate: coordinate),
            MapPlace(id: .mapKit("title"), title: String(repeating: "x", count: 513), coordinate: coordinate),
            MapPlace(id: .mapKit("address"), title: "Address", coordinate: coordinate, address: String(repeating: "x", count: 2_049))]
        for bad in invalid {
            let draft = RouteDraft(values: [.place(bad), .place(place(2))])!
            #expect(throws: FavoriteRoutesFailure.invalidPlace) {
                try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil)
            }
        }
    }
    @Test func gpxSaveKeepsAllGroupsAndRawPointsWithoutUsingAnOrigin() throws {
        let a = GeoCoordinate(latitude: 25, longitude: 121)!
        let b = GeoCoordinate(latitude: 26, longitude: 122)!
        let document = try GPXDocument(content: .tracks([GPXTrack(segments: [[a, a], [b]]), GPXTrack(segments: [[b, a]])]))
        let source = try GPXRouteSource(document: document, displayFilename: "Raw & route.gpx")
        let draft = RouteDraft(gpx: source)
        let candidate = try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil)
        #expect(candidate.source == .gpx(source))
        #expect(!candidate.omittedUnavailableCurrent)
        let artifact = try FavoriteRouteArtifact(candidate: candidate)
        #expect(try GPXCodec.decode(artifact.payload) == document)
        let record = try artifact.record(label: nil)
        #expect(record.count == 5)
        #expect(record.startTitle == nil)
        #expect(record.endTitle == nil)
        #expect(record.displayFilename == "Raw & route.gpx")
        #expect(draft.gpxSource == source)
    }
    private func place(_ number: Int) -> MapPlace {
        MapPlace(id: .mapKit("map-\(number)"), title: "Place \(number)",
            coordinate: GeoCoordinate(latitude: Double(number), longitude: 121)!, address: "Address \(number)")
    }
}
