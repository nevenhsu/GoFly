import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum FavoritePlacesWriteCheckpoint: CaseIterable, Equatable, Sendable {
    case stagingSecured, contentsWritten, stagingFlushed
}

/// A private, normal-backup-eligible favorites archive. All throwable work is
/// precommit; the final rename is the single authoritative commit operation.
public struct FileFavoritePlacesPersistence: FavoritePlacesPersistence {
    public let fileURL: URL
    private let directory: URL
    private let checkpoint: @Sendable (FavoritePlacesWriteCheckpoint) throws -> Void
    private static let filename = "favorites.json"

    public init(directory: URL,
                checkpoint: @escaping @Sendable (FavoritePlacesWriteCheckpoint) throws -> Void = { _ in }) {
        self.directory = directory.standardizedFileURL
        fileURL = directory.standardizedFileURL.appendingPathComponent(Self.filename)
        self.checkpoint = checkpoint
    }

    public func read() throws -> Data? {
        do {
            guard let archive = try SecureArchiveDirectory.open(directory, create: false, secureDirectory: false) else { return nil }
            return try archive.read(Self.filename, maximum: FavoritePlacesLimits.fileBytes)
        } catch { throw mapped(error) }
    }

    public func replaceAtomically(with data: Data) throws {
        guard data.count <= FavoritePlacesLimits.fileBytes else { throw FavoritePlacesFailure.limitExceeded }
        do {
            guard let archive = try SecureArchiveDirectory.open(directory, create: true, secureDirectory: true) else {
                throw FavoritePlacesFailure.unavailable
            }
            try archive.replaceAtomically(data, target: Self.filename, staging: ".favorites-\(UUID().uuidString).staging") { point in
                switch point {
                case .secured: try checkpoint(.stagingSecured)
                case .written: try checkpoint(.contentsWritten)
                case .flushed: try checkpoint(.stagingFlushed)
                }
            }
        } catch { throw mapped(error) }
    }
    private func mapped(_ error: any Error) -> any Error {
        guard let failure = error as? SecureArchiveFailure else { return error }
        switch failure {
        case .unsafeFile: return FavoritePlacesFailure.unsafeFile
        case .unavailable: return FavoritePlacesFailure.unavailable
        case .writeFailed: return FavoritePlacesFailure.writeFailed
        case .limitExceeded: return FavoritePlacesFailure.limitExceeded
        }
    }
}
