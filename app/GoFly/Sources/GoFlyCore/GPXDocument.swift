import Foundation

public enum GPXLimits {
    public static let fileBytes = 2 * 1_024 * 1_024
    public static let points = 10_000
    public static let depth = 64
    public static let elements = 100_000
}

public enum GPXKind: String, Codable, Equatable, Sendable {
    case tracks, routes, waypoints
}

public struct GPXTrack: Equatable, Sendable {
    public let segments: [[GeoCoordinate]]
    public init(segments: [[GeoCoordinate]]) { self.segments = segments }
}

public struct GPXRoute: Equatable, Sendable {
    public let points: [GeoCoordinate]
    public init(points: [GeoCoordinate]) { self.points = points }
}

public enum GPXContent: Equatable, Sendable {
    case tracks([GPXTrack])
    case routes([GPXRoute])
    case waypoints([GeoCoordinate])
}

/// The imported coordinate content is immutable. Execution normalization belongs
/// to PlannedRoute and never changes these groups or original samples.
public struct GPXDocument: Equatable, Sendable {
    public let content: GPXContent
    public init(content: GPXContent) throws {
        self.content = content
        switch content {
        case .tracks(let tracks):
            guard !tracks.isEmpty, tracks.allSatisfy({ !$0.segments.isEmpty && $0.segments.allSatisfy({ !$0.isEmpty }) }) else {
                throw GPXFailure.emptyGroup
            }
        case .routes(let routes):
            guard !routes.isEmpty, routes.allSatisfy({ !$0.points.isEmpty }) else { throw GPXFailure.emptyGroup }
        case .waypoints(let points):
            guard !points.isEmpty else { throw GPXFailure.tooFewPoints }
        }
        guard pointCount >= 2 else { throw GPXFailure.tooFewPoints }
        guard pointCount <= GPXLimits.points else { throw GPXFailure.pointLimitExceeded }
    }
    public var kind: GPXKind {
        switch content { case .tracks: .tracks; case .routes: .routes; case .waypoints: .waypoints }
    }
    public var segments: [[GeoCoordinate]] {
        switch content {
        case .tracks(let tracks): tracks.flatMap(\.segments)
        case .routes(let routes): routes.map(\.points)
        case .waypoints(let points): [points]
        }
    }
    public var pointCount: Int { segments.reduce(0) { $0 + $1.count } }
}

public enum GPXFailure: String, Error, Equatable, Sendable {
    case invalidXML = "gpx.error.invalidXML"
    case unsupportedVersion = "gpx.error.unsupportedVersion"
    case unsupportedNamespace = "gpx.error.unsupportedNamespace"
    case unsupportedEncoding = "gpx.error.unsupportedEncoding"
    case unsafeXML = "gpx.error.unsafeXML"
    case invalidPoint = "gpx.error.invalidPoint"
    case invalidParent = "gpx.error.invalidParent"
    case mixedKinds = "gpx.error.mixedKinds"
    case emptyGroup = "gpx.error.emptyGroup"
    case tooFewPoints = "gpx.error.tooFewPoints"
    case pointLimitExceeded = "gpx.error.pointLimitExceeded"
    case sizeLimitExceeded = "gpx.error.sizeLimitExceeded"
    case resourceLimitExceeded = "gpx.error.resourceLimitExceeded"
    public var localizationKey: String { rawValue }
}
