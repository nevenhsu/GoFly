import Foundation

public enum GPXCodec {
    public static func decode(_ data: Data) throws -> GPXDocument {
        guard data.count <= GPXLimits.fileBytes else { throw GPXFailure.sizeLimitExceeded }
        let xml = try safeXML(data)
        let delegate = GPXParser()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let parsed = parser.parse()
        if let failure = delegate.failure { throw failure }
        guard parsed, delegate.sawRoot else { throw GPXFailure.invalidXML }
        if !delegate.tracks.isEmpty { return try GPXDocument(content: .tracks(delegate.tracks)) }
        if !delegate.routes.isEmpty { return try GPXDocument(content: .routes(delegate.routes)) }
        return try GPXDocument(content: .waypoints(delegate.waypoints))
    }

    public static func encode(_ document: GPXDocument, name: String? = nil) throws -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" version=\"1.1\" creator=\"GoFly\">\n"
        if let name {
            guard name.unicodeScalars.allSatisfy(validXMLScalar) else { throw GPXFailure.invalidXML }
            xml += "<metadata><name>\(escape(name))</name></metadata>\n"
        }
        func point(_ value: GeoCoordinate, tag: String) -> String {
            "<\(tag) lat=\"\(decimal(value.latitude))\" lon=\"\(decimal(value.longitude))\"/>\n"
        }
        switch document.content {
        case .tracks(let tracks):
            for track in tracks {
                xml += "<trk>\n"
                for segment in track.segments {
                    xml += "<trkseg>\n"
                    for coordinate in segment { xml += point(coordinate, tag: "trkpt") }
                    xml += "</trkseg>\n"
                }
                xml += "</trk>\n"
            }
        case .routes(let routes):
            for route in routes {
                xml += "<rte>\n"
                for coordinate in route.points { xml += point(coordinate, tag: "rtept") }
                xml += "</rte>\n"
            }
        case .waypoints(let points):
            for coordinate in points { xml += point(coordinate, tag: "wpt") }
        }
        xml += "</gpx>\n"
        let data = Data(xml.utf8)
        guard data.count <= GPXLimits.fileBytes else { throw GPXFailure.sizeLimitExceeded }
        return data
    }

    private static func validXMLScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 9 || scalar.value == 10 || scalar.value == 13 ||
        (0x20...0xD7FF).contains(scalar.value) || (0xE000...0xFFFD).contains(scalar.value) ||
        (0x10000...0x10FFFF).contains(scalar.value)
    }
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    /// Swift's shortest round-tripping Double representation expanded into XML
    /// Schema decimal notation, without fixed precision or locale conversion.
    private static func decimal(_ value: Double) -> String {
        let raw = String(value)
        guard let exponentIndex = raw.firstIndex(where: { $0 == "e" || $0 == "E" }) else { return raw }
        let exponent = Int(raw[raw.index(after: exponentIndex)...])!
        let mantissa = String(raw[..<exponentIndex])
        let negative = mantissa.hasPrefix("-")
        let unsigned = negative ? String(mantissa.dropFirst()) : mantissa
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        let digits = parts.joined()
        let position = parts[0].count + exponent
        let expanded: String
        if position <= 0 { expanded = "0." + String(repeating: "0", count: -position) + digits }
        else if position >= digits.count { expanded = digits + String(repeating: "0", count: position - digits.count) }
        else {
            let index = digits.index(digits.startIndex, offsetBy: position)
            expanded = String(digits[..<index]) + "." + String(digits[index...])
        }
        return (negative ? "-" : "") + expanded
    }

    private static func safeXML(_ data: Data) throws -> String {
        let bytes = [UInt8](data.prefix(4))
        let encoding: String.Encoding
        var body = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { encoding = .utf8; body = data.dropFirst(3) }
        else if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) || bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            throw GPXFailure.unsupportedEncoding
        }
        else if bytes.starts(with: [0xFF, 0xFE]) { encoding = .utf16LittleEndian; body = data.dropFirst(2) }
        else if bytes.starts(with: [0xFE, 0xFF]) { encoding = .utf16BigEndian; body = data.dropFirst(2) }
        else if bytes.starts(with: [0x3C, 0x00]) { encoding = .utf16LittleEndian }
        else if bytes.starts(with: [0x00, 0x3C]) { encoding = .utf16BigEndian }
        else { encoding = .utf8 }
        guard var xml = String(data: body, encoding: encoding), !xml.contains("\0") else { throw GPXFailure.unsupportedEncoding }
        let uppercase = xml.uppercased()
        guard !uppercase.contains("<!DOCTYPE"), !uppercase.contains("<!ENTITY") else { throw GPXFailure.unsafeXML }
        if xml.hasPrefix("<?xml"), let end = xml.range(of: "?>") {
            let declaration = String(xml[..<end.upperBound])
            let regex = try! NSRegularExpression(pattern: "encoding\\s*=\\s*['\"]([^'\"]+)['\"]", options: .caseInsensitive)
            if let match = regex.firstMatch(in: declaration, range: NSRange(declaration.startIndex..., in: declaration)),
               let range = Range(match.range(at: 1), in: declaration) {
                let declared = declaration[range].uppercased()
                let allowed = encoding == .utf8 ? ["UTF-8", "UTF8"] :
                    (encoding == .utf16LittleEndian ? ["UTF-16", "UTF-16LE"] : ["UTF-16", "UTF-16BE"])
                guard allowed.contains(declared) else { throw GPXFailure.unsupportedEncoding }
            }
            // Preserve the XML version and every declaration attribute except
            // encoding, which must match the normalized UTF-8 parser input.
            let replaced = regex.stringByReplacingMatches(in: declaration,
                range: NSRange(declaration.startIndex..., in: declaration), withTemplate: "encoding=\"UTF-8\"")
            xml.replaceSubrange(xml.startIndex..<end.upperBound, with: replaced)
        }
        return xml
    }
}

private final class GPXParser: NSObject, XMLParserDelegate {
    static let namespace = "http://www.topografix.com/GPX/1/1"
    var failure: GPXFailure?
    var sawRoot = false
    var tracks: [GPXTrack] = []
    var routes: [GPXRoute] = []
    var waypoints: [GeoCoordinate] = []
    private var stack: [String] = []
    private var ignoredDepth: Int?
    private var elementCount = 0
    private var pointCount = 0
    private var kind: GPXKind?
    private var trackSegments: [[GeoCoordinate]] = []
    private var segment: [GeoCoordinate] = []

    private func reject(_ parser: XMLParser, _ reason: GPXFailure) {
        if failure == nil { failure = reason }
        parser.abortParsing()
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        elementCount += 1
        guard stack.count < GPXLimits.depth, elementCount <= GPXLimits.elements else { reject(parser, .resourceLimitExceeded); return }
        let parent = stack.last
        stack.append(name)
        if stack.count == 1 {
            guard name == "gpx" else { reject(parser, .invalidXML); return }
            guard namespaceURI == Self.namespace else { reject(parser, .unsupportedNamespace); return }
            guard attributes["version"] == "1.1" else { reject(parser, .unsupportedVersion); return }
            sawRoot = true
            return
        }
        if ignoredDepth != nil { return }
        if namespaceURI != Self.namespace || name == "extensions" { ignoredDepth = stack.count; return }
        let pointKind: GPXKind?
        switch name {
        case "trk":
            guard parent == "gpx" else { reject(parser, .invalidParent); return }
            trackSegments = []; pointKind = .tracks
        case "trkseg":
            guard parent == "trk" else { reject(parser, .invalidParent); return }
            segment = []; pointKind = nil
        case "rte":
            guard parent == "gpx" else { reject(parser, .invalidParent); return }
            segment = []; pointKind = .routes
        case "trkpt", "rtept", "wpt":
            let expectedParent = name == "trkpt" ? "trkseg" : (name == "rtept" ? "rte" : "gpx")
            guard parent == expectedParent else { reject(parser, .invalidParent); return }
            pointKind = name == "trkpt" ? .tracks : (name == "rtept" ? .routes : .waypoints)
            pointCount += 1
            guard pointCount <= GPXLimits.points else { reject(parser, .pointLimitExceeded); return }
            guard let lat = decimal(attributes["lat"]), let lon = decimal(attributes["lon"]),
                  let coordinate = GeoCoordinate(latitude: lat, longitude: lon) else { reject(parser, .invalidPoint); return }
            if name == "wpt" { waypoints.append(coordinate) } else { segment.append(coordinate) }
        default: pointKind = nil
        }
        if let pointKind {
            guard kind == nil || kind == pointKind else { reject(parser, .mixedKinds); return }
            kind = pointKind
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { if !stack.isEmpty { stack.removeLast() } }
        if let ignoredDepth {
            if stack.count == ignoredDepth { self.ignoredDepth = nil }
            return
        }
        switch name {
        case "trkseg":
            guard !segment.isEmpty else { reject(parser, .emptyGroup); return }
            trackSegments.append(segment)
        case "trk":
            guard !trackSegments.isEmpty else { reject(parser, .emptyGroup); return }
            tracks.append(GPXTrack(segments: trackSegments))
        case "rte":
            guard !segment.isEmpty else { reject(parser, .emptyGroup); return }
            routes.append(GPXRoute(points: segment))
        default: break
        }
    }
    private func decimal(_ value: String?) -> Double? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)$", options: .regularExpression) != nil else { return nil }
        return Double(trimmed)
    }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName: String, value: String?) { reject(parser, .unsafeXML) }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName: String, publicID: String?, systemID: String?) { reject(parser, .unsafeXML) }
    func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName: String, publicID: String?, systemID: String?, notationName: String?) { reject(parser, .unsafeXML) }
    func parser(_ parser: XMLParser, foundNotationDeclarationWithName: String, publicID: String?, systemID: String?) { reject(parser, .unsafeXML) }
    func parser(_ parser: XMLParser, foundElementDeclarationWithName: String, model: String) { reject(parser, .unsafeXML) }
    func parser(_ parser: XMLParser, foundAttributeDeclarationWithName: String, forElement: String, type: String?, defaultValue: String?) { reject(parser, .unsafeXML) }
    func parser(_ parser: XMLParser, resolveExternalEntityName: String, systemID: String?) -> Data? { reject(parser, .unsafeXML); return nil }
}
