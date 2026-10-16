import Foundation
import XCTest
@testable import LocalGoCore

final class FeatureDomainTests: XCTestCase {
    func testGeoPointRejectsInvalidValuesAndCodableDecodingValidates() throws {
        XCTAssertThrowsError(try GeoPoint(latitude: .nan, longitude: 0))
        XCTAssertThrowsError(try GeoPoint(latitude: 91, longitude: 0))
        XCTAssertThrowsError(try GeoPoint(latitude: 0, longitude: -181))

        let invalid = Data(#"{"latitude": 0, "longitude": 181}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(GeoPoint.self, from: invalid))
    }

    func testRoutePathUsesShortestDatelineArcAndClampsEndpoints() throws {
        let start = try GeoPoint(latitude: 0, longitude: 179)
        let end = try GeoPoint(latitude: 0, longitude: -179)
        let route = try RoutePath(points: [start, end])

        XCTAssertEqual(route.point(atDistanceMeters: -1), start)
        XCTAssertEqual(route.point(atDistanceMeters: route.lengthMeters + 1), end)
        let midpoint = route.point(atDistanceMeters: route.lengthMeters / 2)
        XCTAssertEqual(midpoint.latitude, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(abs(midpoint.longitude), 179.9)
        XCTAssertLessThan(route.lengthMeters, 250_000)
    }

    func testRoutePathAllowsZeroLengthSegmentsButRejectsZeroTotal() throws {
        let point = try GeoPoint(latitude: 25, longitude: 121)
        let other = try GeoPoint(latitude: 25.1, longitude: 121.1)
        let route = try RoutePath(points: [point, point, other])

        XCTAssertEqual(route.point(atDistanceMeters: 0), point)
        XCTAssertEqual(route.point(atDistanceMeters: route.lengthMeters), other)
        XCTAssertThrowsError(try RoutePath(points: [point, point]))
        XCTAssertThrowsError(try RoutePath(points: [point]))
    }

    func testMovedUsesSphericalDestinationAndNormalizesAntimeridian() throws {
        let point = try GeoPoint(latitude: 0, longitude: 179.9)
        let moved = point.moved(distanceMeters: 30_000, headingDegrees: 90)

        XCTAssertEqual(moved.latitude, 0, accuracy: 1e-8)
        XCTAssertLessThanOrEqual(moved.longitude, 180)
        XCTAssertGreaterThanOrEqual(moved.longitude, -180)
        XCTAssertLessThan(moved.longitude, -179)
    }

    func testGPXPrefersTracksAndRoundTripsEscapedName() throws {
        let points = [
            try GeoPoint(latitude: 25.033, longitude: 121.565),
            try GeoPoint(latitude: 25.034, longitude: 121.566)
        ]
        let name = #"A & <route> "Taipei" 'north'"#
        let data = try GPXCodec.encode(points: points, name: name)
        let xml = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(xml.contains("&amp;"))
        XCTAssertTrue(xml.contains("&lt;route&gt;"))
        XCTAssertTrue(xml.contains("&quot;Taipei&quot;"))
        XCTAssertTrue(xml.contains("&apos;north&apos;"))
        XCTAssertEqual(try GPXCodec.decode(data), points)

        let preferred = Data("""
            <gpx>
              <wpt lat="1" lon="1"/>
              <rte><rtept lat="2" lon="2"/><rtept lat="3" lon="3"/></rte>
              <trk><trkseg><trkpt lat="4" lon="4"/><trkpt lat="5" lon="5"/></trkseg></trk>
            </gpx>
            """.utf8)
        let selected = try GPXCodec.decode(preferred)
        XCTAssertEqual(selected.first?.latitude, 4)
        XCTAssertEqual(selected.last?.longitude, 5)
    }

    func testGPXRejectsOversizedForbiddenAndInvalidInput() throws {
        XCTAssertThrowsError(try GPXCodec.decode(Data(repeating: 0, count: GPXCodec.maximumBytes + 1)))
        XCTAssertThrowsError(try GPXCodec.decode(Data("<!DOCTYPE gpx [<!ENTITY x SYSTEM \"file:///tmp/x\">]><gpx/>".utf8)))
        XCTAssertThrowsError(try GPXCodec.decode(Data("<gpx><trk><trkpt lat=\"oops\" lon=\"2\"/></trk></gpx>".utf8)))
        XCTAssertThrowsError(try GPXCodec.decode(Data("<document><trkpt lat=\"1\" lon=\"2\"/></document>".utf8)))

        let utf16Document = "<!DOCTYPE gpx [<!ENTITY x SYSTEM \"file:///tmp/x\">]><gpx/>"
        var utf16Forbidden = Data([0xFF, 0xFE])
        utf16Forbidden.append(try XCTUnwrap(utf16Document.data(using: .utf16LittleEndian)))
        XCTAssertThrowsError(try GPXCodec.decode(utf16Forbidden))

        let oversizedName = String(repeating: "x", count: GPXCodec.maximumBytes)
        let point = try GeoPoint(latitude: 0, longitude: 0)
        XCTAssertThrowsError(try GPXCodec.encode(points: [point], name: oversizedName))
    }

    func testGPXAcceptsValidUTF16() throws {
        let utf16Document = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><gpx><wpt lat=\"1\" lon=\"2\"/></gpx>"
        var data = Data([0xFF, 0xFE])
        data.append(try XCTUnwrap(utf16Document.data(using: .utf16LittleEndian)))

        let decoded = try GPXCodec.decode(data)
        XCTAssertEqual(decoded, [try GeoPoint(latitude: 1, longitude: 2)])
    }

    func testGPXEnforcesPointCapDuringParsingAndExport() throws {
        var xml = "<gpx>"
        for index in 0...10_000 {
            xml += "<wpt lat=\"0\" lon=\"\(Double(index % 180))\"/>"
        }
        xml += "</gpx>"
        XCTAssertThrowsError(try GPXCodec.decode(Data(xml.utf8)))

        let point = try GeoPoint(latitude: 0, longitude: 0)
        XCTAssertThrowsError(try GPXCodec.encode(points: Array(repeating: point, count: 10_001), name: "too many"))
    }

    func testLocalPlaceStoreRoundTripsAndRejectsCorruptionAndBounds() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try LocalPlaceStore(directory: directory)
        let point = try GeoPoint(latitude: 25, longitude: 121)
        let favorite = SavedPlace(name: "Home", point: point)
        let archive = PlaceArchive(favorites: [favorite], history: [favorite])
        try store.save(archive)
        let loaded = try store.load()
        XCTAssertEqual(loaded.favorites, archive.favorites)
        XCTAssertEqual(loaded.history, archive.history)

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.uint16Value, 0o700)
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("places.json").path
        )
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.uint16Value, 0o600)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: directory.appendingPathComponent("places.json").path
        )
        let updatedArchive = PlaceArchive(history: [favorite])
        try store.save(updatedArchive)
        let replacedAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("places.json").path
        )
        XCTAssertEqual((replacedAttributes[.posixPermissions] as? NSNumber)?.uint16Value, 0o600)

        #if os(iOS)
        XCTAssertEqual(
            replacedAttributes[.protectionKey] as? FileProtectionType,
            .completeUntilFirstUserAuthentication
        )
        let replacedURL = directory.appendingPathComponent("places.json")
        XCTAssertEqual(
            try replacedURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
        #endif

        let rejectedBeforeCommit = PlaceArchive(
            favorites: [SavedPlace(name: String(repeating: "x", count: 121), point: point)]
        )
        XCTAssertThrowsError(try store.save(rejectedBeforeCommit))
        let preserved = try store.load()
        XCTAssertEqual(preserved.favorites, updatedArchive.favorites)
        XCTAssertEqual(preserved.history, updatedArchive.history)

        let file = directory.appendingPathComponent("places.json")
        try Data("not-json".utf8).write(to: file)
        XCTAssertThrowsError(try store.load())

        let tooManyFavorites = PlaceArchive(
            favorites: (0..<101).map { _ in SavedPlace(name: "x", point: point) }
        )
        XCTAssertThrowsError(try store.save(tooManyFavorites)) { error in
            XCTAssertEqual(error as? LocalPlaceStoreError, .tooManyFavorites)
        }

        let tooManyHistory = PlaceArchive(
            history: (0..<101).map { _ in SavedPlace(name: "x", point: point) }
        )
        XCTAssertThrowsError(try store.save(tooManyHistory)) { error in
            XCTAssertEqual(error as? LocalPlaceStoreError, .tooManyHistoryEntries)
        }

        let tooLongName = PlaceArchive(
            favorites: [SavedPlace(name: String(repeating: "x", count: 121), point: point)]
        )
        XCTAssertThrowsError(try store.save(tooLongName)) { error in
            XCTAssertEqual(error as? LocalPlaceStoreError, .nameTooLong)
        }
    }

    func testLocalPlaceStoreRejectsUnsupportedSchema() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalPlaceStore(directory: directory)
        let file = directory.appendingPathComponent("places.json")
        try Data(#"{"schemaVersion":99,"favorites":[],"history":[]}"#.utf8).write(to: file)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? LocalPlaceStoreError, .unsupportedSchemaVersion(99))
        }
    }

    func testLocalPlaceStoreBoundsReadBeforeDecoding() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalPlaceStore(directory: directory)
        let file = directory.appendingPathComponent("places.json")
        try Data(repeating: 0x7B, count: 1_048_577).write(to: file)

        XCTAssertThrowsError(try store.load())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalGoCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
