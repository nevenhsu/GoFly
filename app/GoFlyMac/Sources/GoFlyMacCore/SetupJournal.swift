import Foundation
import Darwin

/// Reopening this identity grants no installation or completion evidence.
public struct MacSetupContinuation: Equatable, Sendable {
    public let setupID: UUID
    public let deviceID: String

    public init(setupID: UUID, deviceID: String) throws {
        let normalized = deviceID.lowercased()
        guard setupFullMatch(normalized, "^(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})$") else {
            throw MacSetupFailure.invalidResponse
        }
        self.setupID = setupID
        self.deviceID = normalized
    }
}

public protocol MacSetupJournalReading: Sendable {
    func readContinuation() async throws -> MacSetupContinuation?
}

/// Reads only the current authoritative private journal. Never creates state
/// or queries a device merely because the Mac app was opened.
public struct MacSetupJournalReader: MacSetupJournalReading {
    public let stateRoot: URL

    public init(stateRoot: URL) { self.stateRoot = stateRoot }

    public func readContinuation() async throws -> MacSetupContinuation? {
        do { return try await Task.detached(priority: .utility) { try Self.read(self.stateRoot) }.value }
        catch { throw MacSetupFailure.invalidResponse }
    }

    private static func read(_ root: URL) throws -> MacSetupContinuation? {
        guard root.isFileURL, root.path.hasPrefix("/") else { throw MacSetupFailure.invalidResponse }
        let directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if directory < 0 {
            if errno == ENOENT { return nil }
            throw MacSetupFailure.invalidResponse
        }
        defer { close(directory) }
        var directoryInfo = stat()
        guard fstat(directory, &directoryInfo) == 0,
              directoryInfo.st_uid == getuid(), directoryInfo.st_mode & 0o7777 == 0o700 else {
            throw MacSetupFailure.invalidResponse
        }
        let file = openat(directory, "journal.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if file < 0 {
            if errno == ENOENT { return nil }
            throw MacSetupFailure.invalidResponse
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_nlink == 1, info.st_mode & 0o7777 == 0o600,
              info.st_size > 0, info.st_size <= 262_144 else { throw MacSetupFailure.invalidResponse }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0, data.count + count <= 262_144 else { throw MacSetupFailure.invalidResponse }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == info.st_size else { throw MacSetupFailure.invalidResponse }
        let object = try SetupWireJSON.object(data, integerKey: "version", integerValue: "1")
        guard object["operation"] as? String == "setup",
              let rawID = object["setupID"] as? String, rawID.utf8.count == 36,
              let id = UUID(uuidString: rawID),
              let device = object["deviceID"] as? String, device == device.lowercased() else {
            throw MacSetupFailure.invalidResponse
        }
        return try MacSetupContinuation(setupID: id, deviceID: device)
    }
}
