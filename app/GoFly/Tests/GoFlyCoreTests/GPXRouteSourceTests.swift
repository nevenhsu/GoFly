import Foundation
import Testing
@testable import GoFlyCore

struct GPXRouteSourceTests {
    @Test func preservesRawDocumentAndDisplayNameWithoutEncodingPayload() throws {
        let tiny = GeoCoordinate(latitude: 1e-300, longitude: 1e-300)!
        let document = try GPXDocument(content: .waypoints(Array(repeating: tiny, count: 10_000)))
        #expect(throws: GPXFailure.sizeLimitExceeded) { try GPXCodec.encode(document) }
        let source = try GPXRouteSource(document: document, displayFilename: "  full route.gpx  ")
        #expect(source.document == document)
        #expect(source.displayFilename == "  full route.gpx  ")
        #expect(RouteDraft(gpx: source).gpxSource == source)
    }

    @Test(arguments: ["", "  ", "bad\nname", String(repeating: "a", count: 513), String(repeating: "🧭", count: 513), String(repeating: "🧭\u{fe0f}", count: 400)])
    func rejectsInvalidDisplayNames(name: String) throws {
        let point = GeoCoordinate(latitude: 0, longitude: 0)!
        let document = try GPXDocument(content: .waypoints([point, point]))
        #expect(throws: GPXRouteSourceFailure.invalidFilename) { try GPXRouteSource(document: document, displayFilename: name) }
    }

    @Test func acceptsExactCharacterAndUTF8BoundariesWithoutChangingTheFilename() throws {
        let point = GeoCoordinate(latitude: 0, longitude: 0)!
        let document = try GPXDocument(content: .waypoints([point, point]))
        let name = String(repeating: "🧭", count: 512)
        #expect(name.count == 512 && name.utf8.count == 2_048)
        #expect(try GPXRouteSource(document: document, displayFilename: name).displayFilename == name)
    }

    @Test func importedSnapshotAdaptsToTheSameNeutralSource() throws {
        let first = GeoCoordinate(latitude: 0, longitude: 0)!, end = GeoCoordinate(latitude: 0, longitude: 1)!
        let document = try GPXDocument(content: .waypoints([first, end]))
        let snapshot = try ImportedRouteSnapshot(document: document, filename: "source.gpx")
        #expect(snapshot.source == (try GPXRouteSource(document: document, displayFilename: "source.gpx")))
        #expect(RouteDraft(imported: snapshot).source == .gpx(snapshot.source))
    }
}
