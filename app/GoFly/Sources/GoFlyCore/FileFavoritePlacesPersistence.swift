import Foundation

public enum FavoritePlacesWriteCheckpoint: CaseIterable, Equatable, Sendable {
    case stagingSecured, contentsWritten, stagingFlushed
}

/// A private, normal-backup-eligible favorites archive.
public struct FileFavoritePlacesPersistence: FavoritePlacesPersistence {
    public let fileURL: URL
    private let file: AtomicFile
    private let checkpoint: @Sendable (FavoritePlacesWriteCheckpoint) throws -> Void
    private static let filename = "favorites.json"

    public init(directory: URL,
                checkpoint: @escaping @Sendable (FavoritePlacesWriteCheckpoint) throws -> Void = { _ in }) {
        let absoluteDirectory = directory.absoluteURL
        fileURL = absoluteDirectory.appendingPathComponent(Self.filename)
        file = AtomicFile(directory: absoluteDirectory, filename: Self.filename,
                          maximumBytes: FavoritePlacesLimits.fileBytes)
        self.checkpoint = checkpoint
    }

    public func read() throws -> Data? {
        do { return try file.loadData() }
        catch { throw FavoritePlacesFailure.unavailable }
    }

    public func replaceAtomically(with data: Data) throws {
        guard data.count <= FavoritePlacesLimits.fileBytes else { throw FavoritePlacesFailure.limitExceeded }
        do {
            try checkpoint(.stagingSecured)
            try checkpoint(.contentsWritten)
            try file.saveData(data)
            try checkpoint(.stagingFlushed)
        } catch let failure as FavoritePlacesFailure { throw failure }
        catch { throw FavoritePlacesFailure.writeFailed }
    }
}
