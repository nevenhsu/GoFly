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
public struct FileSessionRecoveryPersistence: SessionRecoveryPersistence, Sendable {
    private let file: AtomicFile
    private let checkpoint: @Sendable (SessionRecoveryWriteCheckpoint) throws -> Void

    public init(directory: URL,
                checkpoint: @escaping @Sendable (SessionRecoveryWriteCheckpoint) throws -> Void = { _ in }) {
        file = AtomicFile(directory: directory.standardizedFileURL, filename: "session.json",
                          maximumBytes: SessionRecoveryLimits.recordBytes)
        self.checkpoint = checkpoint
    }

    public func read() throws -> Data? {
        do { return try file.loadData() }
        catch { throw Self.map(error) }
    }

    public func replaceAtomically(with data: Data) throws {
        guard data.count <= SessionRecoveryLimits.recordBytes else { throw SessionRecoveryFailure.limitExceeded }
        do {
            try checkpoint(.stagingSecured)
            try checkpoint(.contentsWritten)
            try file.saveData(data)
            try checkpoint(.stagingFlushed)
            try checkpoint(.beforeCommit)
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: any Error) -> SessionRecoveryFailure {
        if let failure = error as? SessionRecoveryFailure { return failure }
        if error is CocoaError { return .unavailable }
        return .unavailable
    }
}
