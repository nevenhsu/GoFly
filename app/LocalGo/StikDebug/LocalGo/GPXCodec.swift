import Foundation

#if canImport(FoundationXML)
import FoundationXML
#endif

public enum GPXCodecError: Error, Equatable, Sendable {
    case dataTooLarge
    case forbiddenMarkup
    case externalEntityRejected
    case malformedXML
    case noPoints
    case tooManyPoints
    case invalidCoordinate
    case exportTooLarge
    case unsupportedPlatform
}

public enum GPXCodec {
    public static let maximumBytes = 2 * 1024 * 1024

    private static let maximumPoints = 10_000

    public static func decode(_ data: Data) throws -> [GeoPoint] {
        guard data.count <= maximumBytes else {
            throw GPXCodecError.dataTooLarge
        }
        guard !containsForbiddenMarkup(data) else {
            throw GPXCodecError.forbiddenMarkup
        }

        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        let parsed = parser.parse()
        if let failure = delegate.failure {
            throw failure
        }
        guard parsed else {
            throw GPXCodecError.malformedXML
        }

        let points: [GeoPoint]
        if !delegate.trackPoints.isEmpty {
            points = delegate.trackPoints
        } else if !delegate.routePoints.isEmpty {
            points = delegate.routePoints
        } else {
            points = delegate.waypointPoints
        }
        guard !points.isEmpty else {
            throw GPXCodecError.noPoints
        }
        return points
    }

    public static func encode(points: [GeoPoint], name: String) throws -> Data {
        guard !points.isEmpty else {
            throw GPXCodecError.noPoints
        }
        guard points.count <= maximumPoints else {
            throw GPXCodecError.tooManyPoints
        }

        let escapedName = escapeXML(name)
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        xml += "<gpx version=\"1.1\" creator=\"LocalGo\" xmlns=\"http://www.topografix.com/GPX/1/1\">"
        xml += "<trk><name>\(escapedName)</name><trkseg>"
        for point in points {
            let latitude = String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), point.latitude)
            let longitude = String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), point.longitude)
            xml += "<trkpt lat=\"\(latitude)\" lon=\"\(longitude)\"/>"
        }
        xml += "</trkseg></trk></gpx>"

        guard let data = xml.data(using: .utf8) else {
            throw GPXCodecError.exportTooLarge
        }
        guard data.count <= maximumBytes else {
            throw GPXCodecError.exportTooLarge
        }
        return data
    }

    private static func containsForbiddenMarkup(_ data: Data) -> Bool {
        // XMLParser understands UTF-8, UTF-16, and UTF-32 input, so a UTF-8
        // string conversion would miss declarations in the wider encodings.
        // Removing NUL bytes gives us a bounded, encoding-independent ASCII
        // token scan for the declarations that must never reach the parser.
        var normalized = [UInt8]()
        normalized.reserveCapacity(data.count)
        for byte in data where byte != 0 {
            normalized.append(byte >= 65 && byte <= 90 ? byte + 32 : byte)
        }
        return contains(token: Array("<!doctype".utf8), in: normalized)
            || contains(token: Array("<!entity".utf8), in: normalized)
    }

    private static func contains(token: [UInt8], in bytes: [UInt8]) -> Bool {
        guard !token.isEmpty, bytes.count >= token.count else { return false }
        for index in 0...(bytes.count - token.count) {
            if bytes[index..<(index + token.count)].elementsEqual(token) {
                return true
            }
        }
        return false
    }

    private static func escapeXML(_ value: String) -> String {
        value.reduce(into: String()) { result, character in
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        enum PointKind {
            case track
            case route
            case waypoint
        }

        var trackPoints = [GeoPoint]()
        var routePoints = [GeoPoint]()
        var waypointPoints = [GeoPoint]()
        var failure: GPXCodecError?
        private var pointCount = 0
        private var rootSeen = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard failure == nil else { return }
            let localName = elementName.split(separator: ":").last.map(String.init)?.lowercased()
            if !rootSeen {
                rootSeen = true
                guard localName == "gpx" else {
                    fail(.malformedXML, parser: parser)
                    return
                }
            }
            guard let kind = pointKind(for: elementName) else { return }

            pointCount += 1
            guard pointCount <= maximumPoints else {
                fail(.tooManyPoints, parser: parser)
                return
            }

            guard let latitudeText = attribute(named: "lat", in: attributeDict),
                  let longitudeText = attribute(named: "lon", in: attributeDict),
                  let latitude = Double(latitudeText),
                  let longitude = Double(longitudeText) else {
                fail(.invalidCoordinate, parser: parser)
                return
            }

            do {
                let point = try GeoPoint(latitude: latitude, longitude: longitude)
                switch kind {
                case .track: trackPoints.append(point)
                case .route: routePoints.append(point)
                case .waypoint: waypointPoints.append(point)
                }
            } catch {
                fail(.invalidCoordinate, parser: parser)
            }
        }

        func parser(
            _ parser: XMLParser,
            resolveExternalEntityName name: String,
            systemID: String?
        ) -> Data? {
            fail(.externalEntityRejected, parser: parser)
            return nil
        }

        func parser(
            _ parser: XMLParser,
            foundInternalEntityDeclarationWithName name: String,
            value: String?
        ) {
            fail(.externalEntityRejected, parser: parser)
        }

        func parser(
            _ parser: XMLParser,
            foundExternalEntityDeclarationWithName name: String,
            publicID: String?,
            systemID: String?
        ) {
            fail(.externalEntityRejected, parser: parser)
        }

        func parser(
            _ parser: XMLParser,
            foundUnparsedEntityDeclarationWithName name: String,
            publicID: String?,
            systemID: String?,
            notationName: String?
        ) {
            fail(.externalEntityRejected, parser: parser)
        }

        private func pointKind(for elementName: String) -> PointKind? {
            let localName = elementName.split(separator: ":").last.map(String.init)?.lowercased()
            switch localName {
            case "trkpt": return .track
            case "rtept": return .route
            case "wpt": return .waypoint
            default: return nil
            }
        }

        private func attribute(named name: String, in attributes: [String: String]) -> String? {
            attributes.first { key, _ in
                key.split(separator: ":").last.map(String.init)?.lowercased() == name
            }?.value
        }

        private func fail(_ error: GPXCodecError, parser: XMLParser) {
            failure = error
            parser.abortParsing()
        }
    }
}
