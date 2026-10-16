import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum LocalPlaceStoreError: Error, Equatable, Sendable {
    case tooManyFavorites
    case tooManyHistoryEntries
    case nameTooLong
    case unsupportedSchemaVersion(Int)
}

/// Small, local-only JSON persistence for saved places.
public final class LocalPlaceStore {
    private static let schemaVersion = 1
    private static let filename = "places.json"
    private static let maximumEntries = 100
    private static let maximumNameCharacters = 120
    private static let maximumReadBytes = 1 * 1024 * 1024

    private let directory: URL
    private let fileURL: URL

    public init(directory: URL? = nil) throws {
        if let directory {
            self.directory = directory.standardizedFileURL
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directory = applicationSupport
                .appendingPathComponent("Places", isDirectory: true)
                .standardizedFileURL
        }
        self.fileURL = self.directory.appendingPathComponent(Self.filename, isDirectory: false)

        try FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true
        )
        try Self.setPermissions(at: self.directory, mode: 0o700)
        try Self.setFileProtection(at: self.directory)
        try Self.excludeFromBackup(self.directory)
    }

    public func load() throws -> PlaceArchive {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PlaceArchive()
        }

        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
           let fileSize = attributes[.size] as? NSNumber,
           fileSize.uint64Value > UInt64(Self.maximumReadBytes) {
            throw CorruptFileError.tooLarge
        }

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        let data = try fileHandle.read(upToCount: Self.maximumReadBytes + 1) ?? Data()
        guard data.count <= Self.maximumReadBytes else {
            throw CorruptFileError.tooLarge
        }
        let persisted = try JSONDecoder().decode(PersistedArchive.self, from: data)
        guard persisted.schemaVersion == Self.schemaVersion else {
            throw LocalPlaceStoreError.unsupportedSchemaVersion(persisted.schemaVersion)
        }

        let archive = PlaceArchive(
            favorites: persisted.favorites,
            history: persisted.history
        )
        try Self.validate(archive)
        return archive
    }

    public func save(_ archive: PlaceArchive) throws {
        try Self.validate(archive)

        let persisted = PersistedArchive(
            schemaVersion: Self.schemaVersion,
            favorites: archive.favorites,
            history: archive.history
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(persisted)

        let stagingURL = directory.appendingPathComponent(
            ".\(Self.filename).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        var committed = false
        defer {
            if !committed {
                try? FileManager.default.removeItem(at: stagingURL)
            }
        }

        // Configure the staged file before the final replacement. Any failure
        // here leaves the previous archive untouched.
        try data.write(to: stagingURL)
        try Self.setPermissions(at: stagingURL, mode: 0o600)
        try Self.setFileProtection(at: stagingURL)
        try Self.excludeFromBackup(stagingURL)

        // This is the sole commit operation. There are no required fallible
        // operations after it, so a successful save cannot be reported as a
        // failure after replacing the previous archive.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(
                fileURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try FileManager.default.moveItem(at: stagingURL, to: fileURL)
        }
        committed = true
    }

    private static func validate(_ archive: PlaceArchive) throws {
        guard archive.favorites.count <= maximumEntries else {
            throw LocalPlaceStoreError.tooManyFavorites
        }
        guard archive.history.count <= maximumEntries else {
            throw LocalPlaceStoreError.tooManyHistoryEntries
        }
        for place in archive.favorites + archive.history {
            guard place.name.count <= maximumNameCharacters else {
                throw LocalPlaceStoreError.nameTooLong
            }
        }
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private static func setFileProtection(at url: URL) throws {
        #if canImport(Darwin)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #else
        _ = url
        #endif
    }

    private static func setPermissions(at url: URL, mode: UInt16) throws {
        #if canImport(Darwin)
        let result = url.path.withCString { path in
            chmod(path, mode_t(mode))
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
        #else
        _ = (url, mode)
        #endif
    }

    private enum CorruptFileError: Error {
        case tooLarge
    }

    private struct PersistedArchive: Codable {
        let schemaVersion: Int
        let favorites: [SavedPlace]
        let history: [SavedPlace]
    }
}
