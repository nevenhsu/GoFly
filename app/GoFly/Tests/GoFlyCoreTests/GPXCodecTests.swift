import Foundation
import Testing
@testable import GoFlyCore

struct GPXCodecTests {
    @Test func typedDocumentPreservesTrackGroupsSegmentsAndEveryRawPoint() throws {
        let a = GeoCoordinate(latitude: 25, longitude: 121)!
        let b = GeoCoordinate(latitude: 26, longitude: 122)!
        let document = try GPXDocument(content: .tracks([
            GPXTrack(segments: [[a, a], [b]]), GPXTrack(segments: [[b, a]])
        ]))
        #expect(document.kind == .tracks)
        #expect(document.pointCount == 5)
        #expect(document.segments == [[a, a], [b], [b, a]])
        #expect(throws: GPXFailure.emptyGroup) {
            try GPXDocument(content: .tracks([GPXTrack(segments: [[]])]))
        }
    }

    @Test func namespacedXMLRoundTripsGroupsPrecisionAndEscapedDisplayName() throws {
        let xml = wrap("<trk><trkseg><trkpt lat=\"25.123456789012345\" lon=\"121\"/><trkpt lat=\"25.123456789012345\" lon=\"121\"/></trkseg><trkseg><trkpt lat=\".00000000000000000000000000001\" lon=\"-0.0000000000000001\"/></trkseg></trk><trk><trkseg><trkpt lat=\"90\" lon=\"180\"/></trkseg></trk>")
        let document = try GPXCodec.decode(Data(xml.utf8))
        #expect(document.pointCount == 4)
        #expect(document.segments.count == 3)
        let encoded = try GPXCodec.encode(document, name: "A & <B> ' \"")
        #expect(try GPXCodec.decode(encoded) == document)
        #expect(String(decoding: encoded, as: UTF8.self).contains("A &amp; &lt;B&gt; &apos; &quot;"))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("e-"))
    }

    @Test(arguments: ["NaN", "Infinity", "1e1", "1junk", "91", "--1", ""])
    func invalidPointFailsTheEntireDocument(latitude: String) {
        #expect(throws: GPXFailure.invalidPoint) {
            try GPXCodec.decode(Data(wrap("<wpt lat=\"1\" lon=\"2\"/><wpt lat=\"\(latitude)\" lon=\"2\"/>").utf8))
        }
    }

    @Test func namespaceVersionParentMixedKindsAndEmptyGroupsAreExplicitFailures() {
        let points = "<wpt lat=\"1\" lon=\"2\"/><wpt lat=\"2\" lon=\"3\"/>"
        #expect(throws: GPXFailure.unsupportedNamespace) { try GPXCodec.decode(Data("<gpx version=\"1.1\">\(points)</gpx>".utf8)) }
        #expect(throws: GPXFailure.unsupportedVersion) { try GPXCodec.decode(Data(wrap(points).replacingOccurrences(of: "1.1", with: "1.0").utf8)) }
        #expect(throws: GPXFailure.invalidParent) { try GPXCodec.decode(Data(wrap("<metadata>\(points)</metadata>").utf8)) }
        #expect(throws: GPXFailure.mixedKinds) { try GPXCodec.decode(Data(wrap(points + "<rte><rtept lat=\"1\" lon=\"2\"/></rte>").utf8)) }
        for empty in ["<trk/>", "<trk><trkseg/></trk>", "<rte/>"] {
            #expect(throws: GPXFailure.emptyGroup) { try GPXCodec.decode(Data(wrap(empty + points).utf8)) }
        }
    }

    @Test func routeWaypointAndExtensionRulesPreserveOrderedRawContent() throws {
        let routes = try GPXCodec.decode(Data(wrap("<rte><rtept lat=\"1\" lon=\"2\"/></rte><rte><rtept lat=\"4\" lon=\"5\"/></rte>").utf8))
        #expect(routes.kind == .routes)
        #expect(routes.segments.count == 2)
        let points = "<wpt lat=\"1\" lon=\"2\"/><wpt lat=\"2\" lon=\"3\"/>"
        let extended = try GPXCodec.decode(Data(wrap(points + "<extensions><wpt lat=\"NaN\" lon=\"NaN\"/><x:wpt xmlns:x=\"urn:other\"/></extensions>").utf8))
        #expect(extended.kind == .waypoints)
        #expect(extended.pointCount == 2)
        #expect(try GPXCodec.decode(GPXCodec.encode(routes)) == routes)
    }

    @Test(arguments: [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian])
    func safeEncodingAndUnsafeDTDUseTheSameRules(encoding: String.Encoding) throws {
        let points = "<wpt lat=\"1\" lon=\"2\"/><wpt lat=\"2\" lon=\"3\"/>"
        let safe = wrap(points)
        let bom: Data = encoding == .utf16LittleEndian ? Data([0xFF, 0xFE]) : (encoding == .utf16BigEndian ? Data([0xFE, 0xFF]) : Data([0xEF, 0xBB, 0xBF]))
        #expect(try GPXCodec.decode(bom + safe.data(using: encoding)!).pointCount == 2)
        let unsafe = "<!DOCTYPE gpx [<!ENTITY x SYSTEM 'file:///etc/passwd'>]>" + safe
        #expect(throws: GPXFailure.unsafeXML) { try GPXCodec.decode(bom + unsafe.data(using: encoding)!) }
    }

    @Test func sizePointDepthAndElementLimitsHaveExactBoundaries() throws {
        let point = "<wpt lat=\"1\" lon=\"2\"/>"
        let maximum = try GPXCodec.decode(Data(wrap(String(repeating: point, count: 10_000)).utf8))
        #expect(maximum.pointCount == 10_000)
        #expect(try GPXCodec.decode(GPXCodec.encode(maximum)) == maximum)
        #expect(throws: GPXFailure.pointLimitExceeded) { try GPXCodec.decode(Data(wrap(String(repeating: point, count: 10_001)).utf8)) }
        let base = wrap(point + point)
        let padding = GPXLimits.fileBytes - base.utf8.count
        #expect(try GPXCodec.decode(Data((base + String(repeating: " ", count: padding)).utf8)).pointCount == 2)
        #expect(throws: GPXFailure.sizeLimitExceeded) { try GPXCodec.decode(Data((base + String(repeating: " ", count: padding + 1)).utf8)) }
        #expect(throws: GPXFailure.resourceLimitExceeded) {
            try GPXCodec.decode(Data(wrap(String(repeating: "<x>", count: 64) + String(repeating: "</x>", count: 64)).utf8))
        }
        #expect(throws: GPXFailure.resourceLimitExceeded) {
            try GPXCodec.decode(Data(wrap(String(repeating: "<x/>", count: 100_000)).utf8))
        }
        let depthBoundary = wrap(String(repeating: "<x>", count: 63) + String(repeating: "</x>", count: 63) + point + point)
        #expect(try GPXCodec.decode(Data(depthBoundary.utf8)).pointCount == 2)
        let elementBoundary = wrap(String(repeating: "<x/>", count: 99_997) + point + point)
        #expect(try GPXCodec.decode(Data(elementBoundary.utf8)).pointCount == 2)
    }

    @Test func outputKeepsAllFiniteDoubleDigitsAndRefusesAnOversizedCanonicalArtifact() throws {
        let values: [Double] = [Double.leastNonzeroMagnitude, 0.000000001, 25.123456789012345, -89.99999999999999, -0.0]
        for value in values {
            let point = GeoCoordinate(latitude: value, longitude: value)!
            let document = try GPXDocument(content: .waypoints([point, point]))
            #expect(try GPXCodec.decode(GPXCodec.encode(document)) == document)
        }
        let tiny = GeoCoordinate(latitude: Double.leastNonzeroMagnitude, longitude: Double.leastNonzeroMagnitude)!
        let document = try GPXDocument(content: .waypoints(Array(repeating: tiny, count: 10_000)))
        #expect(throws: GPXFailure.sizeLimitExceeded) { try GPXCodec.encode(document) }
        #expect(throws: GPXFailure.sizeLimitExceeded) { try ImportedRouteArtifact(document: document, filename: "huge.gpx") }
    }

    @Test func encodingDeclarationsAndUnsupportedEncodingsCannotBypassUnsafeXMLChecks() throws {
        let content = wrap("<wpt lat=\"1\" lon=\"2\"/><wpt lat=\"3\" lon=\"4\"/>")
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            let declaration = "<?xml version=\"1.0\" encoding=\"UTF-16\"?>"
            let bom = encoding == .utf16LittleEndian ? Data([0xFF, 0xFE]) : Data([0xFE, 0xFF])
            #expect(try GPXCodec.decode(bom + (declaration + content).data(using: encoding)!).pointCount == 2)
            #expect(throws: GPXFailure.unsafeXML) {
                try GPXCodec.decode(bom + (declaration + "<!DOCTYPE gpx SYSTEM 'https://example.invalid/evil.dtd'>" + content).data(using: encoding)!)
            }
        }
        #expect(throws: GPXFailure.unsupportedEncoding) {
            try GPXCodec.decode(Data(("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>" + content).utf8))
        }
        #expect(throws: GPXFailure.unsupportedEncoding) {
            try GPXCodec.decode(Data([0xFF, 0xFE, 0, 0]) + content.data(using: .utf32LittleEndian)!)
        }
    }

    private func wrap(_ content: String) -> String {
        "<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" version=\"1.1\">\(content)</gpx>"
    }
}
