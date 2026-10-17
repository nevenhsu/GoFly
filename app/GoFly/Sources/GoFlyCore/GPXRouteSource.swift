import Foundation

public enum GPXRouteSourceFailure: Error, Equatable, Sendable {
    case invalidFilename
}

/// A complete GPX route and its display name, independent of any storage record.
public struct GPXRouteSource: Equatable, Sendable {
    public let document: GPXDocument
    public let displayFilename: String

    public init(document: GPXDocument, displayFilename: String) throws {
        guard Self.validDisplayFilename(displayFilename) else { throw GPXRouteSourceFailure.invalidFilename }
        self.document = document
        self.displayFilename = displayFilename
    }

    static func validDisplayFilename(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 512 && name.utf8.count <= 2_048 &&
        !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}
