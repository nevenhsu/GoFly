import Foundation

public enum SessionRecoveryWriteCheckpoint: CaseIterable, Equatable, Sendable {
    case stagingSecured, contentsWritten, stagingFlushed, beforeCommit
}

public protocol SessionRecoveryPersistence: Sendable {
    func read() throws -> Data?
    /// The old session.json remains authoritative until the atomic replacement commits.
    func replaceAtomically(with data: Data) throws
}

/// File-backed session checkpoint in the dedicated SessionRecovery directory.
/// All path resolution and writes go through SecureArchiveDirectory's no-follow
/// descriptor so symlinks and non-regular authoritative files are rejected.
public struct FileSessionRecoveryPersistence: SessionRecoveryPersistence, Sendable {
    private let directory: URL
    private let checkpoint: @Sendable (SessionRecoveryWriteCheckpoint) throws -> Void

    private static let sessionFilename = "session.json"

    public init(directory: URL,
                checkpoint: @escaping @Sendable (SessionRecoveryWriteCheckpoint) throws -> Void = { _ in }) {
        self.directory = directory.standardizedFileURL
        self.checkpoint = checkpoint
    }

    public func read() throws -> Data? {
        do {
            guard let archive = try SecureArchiveDirectory.open(directory, create: false, secureDirectory: true) else {
                return nil
            }
            return try archive.read(Self.sessionFilename, maximum: SessionRecoveryLimits.recordBytes)
        } catch {
            throw Self.map(error)
        }
    }

    public func replaceAtomically(with data: Data) throws {
        guard data.count <= SessionRecoveryLimits.recordBytes else { throw SessionRecoveryFailure.limitExceeded }
        do {
            guard let archive = try SecureArchiveDirectory.open(directory, create: true, secureDirectory: true) else {
                throw SecureArchiveFailure.unavailable
            }
            cleanupOwnedStaging(in: archive)
            try archive.replaceAtomically(data, target: Self.sessionFilename,
                                          staging: ".session-\(UUID().uuidString).staging",
                                          checkpoint: { point in
                                              switch point {
                                              case .secured: try checkpoint(.stagingSecured)
                                              case .written: try checkpoint(.contentsWritten)
                                              case .flushed: try checkpoint(.stagingFlushed)
                                              }
                                          }, beforeCommit: { try checkpoint(.beforeCommit) })
            cleanupOwnedStaging(in: archive)
        } catch {
            throw Self.map(error)
        }
    }

    private func cleanupOwnedStaging(in archive: SecureArchiveDirectory) {
        guard let names = try? archive.names() else { return }
        for name in names where Self.ownedStagingUUID(name) != nil {
            // Cleanup only an owned regular staging file. A symlink, directory or
            // foreign path is left untouched so a fault cannot delete user data.
            do { _ = try archive.attributes(name) }
            catch { continue }
            try? archive.removeRegularFile(name)
        }
    }

    private static func ownedStagingUUID(_ name: String) -> UUID? {
        guard name.hasPrefix(".session-"), name.hasSuffix(".staging") else { return nil }
        let start = name.index(name.startIndex, offsetBy: 9)
        let end = name.index(name.endIndex, offsetBy: -8)
        let value = String(name[start..<end])
        guard let id = UUID(uuidString: value), id.uuidString == value else { return nil }
        return id
    }

    private static func map(_ error: any Error) -> SessionRecoveryFailure {
        if let failure = error as? SessionRecoveryFailure { return failure }
        switch error as? SecureArchiveFailure {
        case .unsafeFile?: return .unsafeFile
        case .limitExceeded?: return .limitExceeded
        case .writeFailed?: return .writeFailed
        case .unavailable?: return .unavailable
        case nil: return .unavailable
        }
    }
}
