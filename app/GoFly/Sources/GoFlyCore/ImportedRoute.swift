import CryptoKit
import Foundation

public enum ImportedRoutesLimits {
    public static let records = 100
    public static let payloadBytes = 64 * 1_024 * 1_024
    public static let manifestBytes = 1_024 * 1_024
}

public struct ImportedRouteRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let filename: String
    public let kind: GPXKind
    public let pointCount: Int
    public let byteCount: Int
    public let sha256: String
    public let start: GeoCoordinate
    public let end: GeoCoordinate

    public init(id: UUID, filename: String, kind: GPXKind, pointCount: Int, byteCount: Int, sha256: String,
                start: GeoCoordinate, end: GeoCoordinate) throws {
        guard Self.validFilename(filename), (2...GPXLimits.points).contains(pointCount),
              (1...GPXLimits.fileBytes).contains(byteCount), sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw ImportedRoutesFailure.corruptArchive
        }
        self.id = id; self.filename = filename; self.kind = kind
        self.pointCount = pointCount; self.byteCount = byteCount; self.sha256 = sha256
        self.start = start; self.end = end
    }
    static func validFilename(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 512 && name.utf8.count <= 2_048 &&
        !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

public struct ImportedRouteArtifact: Equatable, Sendable {
    public let document: GPXDocument
    public let filename: String
    public let payload: Data
    private let sha256: String
    public init(data: Data, filename: String) throws {
        try self.init(document: GPXCodec.decode(data), filename: filename)
    }
    public init(document: GPXDocument, filename: String) throws {
        guard ImportedRouteRecord.validFilename(filename) else { throw ImportedRoutesFailure.invalidFilename }
        self.document = document; self.filename = filename
        payload = try GPXCodec.encode(document, name: filename)
        sha256 = Self.hash(payload)
    }
    public func record(id: UUID = UUID()) throws -> ImportedRouteRecord {
        try ImportedRouteRecord(id: id, filename: filename, kind: document.kind,
            pointCount: document.pointCount, byteCount: payload.count, sha256: sha256,
            start: document.segments.first!.first!, end: document.segments.last!.last!)
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

public struct ImportedRouteSnapshot: Equatable, Sendable {
    public let record: ImportedRouteRecord
    public let document: GPXDocument
    public init(record: ImportedRouteRecord, document: GPXDocument) throws {
        let artifact = try ImportedRouteArtifact(document: document, filename: record.filename)
        guard try artifact.record(id: record.id) == record else { throw ImportedRoutesFailure.metadataMismatch }
        self.record = record; self.document = document
    }
    public init(document: GPXDocument, filename: String, id: UUID = UUID()) throws {
        let artifact = try ImportedRouteArtifact(document: document, filename: filename)
        try self.init(record: artifact.record(id: id), document: document)
    }
}

public enum ImportedRoutesFailure: Error, Equatable, Sendable {
    case corruptArchive, unsupportedSchema, unsafeFile, unavailable, writeFailed
    case limitExceeded, invalidFilename, notFound, metadataMismatch, hashMismatch, noSelection, busy, nothingToUndo
    case gpx(GPXFailure)
    public var localizationKey: String {
        switch self {
        case .gpx(let reason): reason.localizationKey
        case .corruptArchive: "imports.error.corruptArchive"
        case .unsupportedSchema: "imports.error.unsupportedSchema"
        case .unsafeFile: "imports.error.unsafeFile"
        case .unavailable: "imports.error.unavailable"
        case .writeFailed: "imports.error.writeFailed"
        case .limitExceeded: "imports.error.limitExceeded"
        case .invalidFilename: "imports.error.invalidFilename"
        case .notFound: "imports.error.notFound"
        case .metadataMismatch: "imports.error.metadataMismatch"
        case .hashMismatch: "imports.error.hashMismatch"
        case .noSelection: "imports.error.noSelection"
        case .busy: "imports.error.busy"
        case .nothingToUndo: "imports.error.nothingToUndo"
        }
    }
    static func mapped(_ error: any Error) -> Self {
        if let failure = error as? Self { return failure }
        if let failure = error as? GPXFailure { return .gpx(failure) }
        return .unavailable
    }
}

public enum ImportedRoutesLoadState: Equatable, Sendable {
    case loading, ready, blocked(ImportedRoutesFailure)
}

public struct ImportedRoutesReceipt: Equatable, Sendable {
    public let records: [ImportedRouteRecord]
    public let canUndo: Bool
    public init(records: [ImportedRouteRecord], canUndo: Bool) { self.records = records; self.canUndo = canUndo }
}

public protocol ImportedRoutesPersistence: Sendable {
    func read() async throws -> ImportedRoutesReceipt
    func importArtifact(_ artifact: ImportedRouteArtifact) async throws -> ImportedRoutesReceipt
    func validate(_ id: UUID) async throws -> ImportedRouteSnapshot
    func delete(_ id: UUID) async throws -> ImportedRoutesReceipt
    func undoDelete() async throws -> ImportedRoutesReceipt
}

public struct UnavailableImportedRoutesPersistence: ImportedRoutesPersistence {
    public init() {}
    public func read() async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.unavailable }
    public func importArtifact(_ artifact: ImportedRouteArtifact) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.unavailable }
    public func validate(_ id: UUID) async throws -> ImportedRouteSnapshot { throw ImportedRoutesFailure.unavailable }
    public func delete(_ id: UUID) async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.unavailable }
    public func undoDelete() async throws -> ImportedRoutesReceipt { throw ImportedRoutesFailure.unavailable }
}
