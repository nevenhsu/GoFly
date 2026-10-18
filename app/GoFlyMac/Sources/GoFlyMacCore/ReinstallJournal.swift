import Darwin
import Foundation
import CoreFoundation

/// Reopening a transaction header supplies identity and selection, never proof
/// of backup, installation, release, or completion.
public struct MacReinstallContinuation: Equatable, Sendable {
    public let transferID: UUID
    public let deviceID: String
    public let categories: [MacReinstallCategory]

    public init(transferID: UUID, deviceID: String, categories: [MacReinstallCategory]) throws {
        guard setupFullMatch(deviceID, "^(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})$"),
              categories == MacReinstallCategory.allCases.filter(categories.contains) else {
            throw MacReinstallFailure.invalidResponse
        }
        self.transferID = transferID
        self.deviceID = deviceID
        self.categories = categories
    }
}

public protocol MacReinstallJournalReading: Sendable {
    func readContinuation() async throws -> MacReinstallContinuation?
}

public struct MacReinstallJournalReader: MacReinstallJournalReading {
    public let stateRoot: URL
    public init(stateRoot: URL) { self.stateRoot = stateRoot }

    public func readContinuation() async throws -> MacReinstallContinuation? {
        do {
            return try await Task.detached(priority: .utility) { try Self.read(stateRoot) }.value
        } catch { throw MacReinstallFailure.invalidResponse }
    }

    private static func read(_ root: URL) throws -> MacReinstallContinuation? {
        let components = root.path.split(separator: "/")
        guard root.isFileURL, root.path.hasPrefix("/"),
              !components.contains(where: { $0 == "." || $0 == ".." }) else {
            throw MacReinstallFailure.invalidResponse
        }
        var directory = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw MacReinstallFailure.invalidResponse }
        defer { close(directory) }
        for component in components {
            let next = openat(directory, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0 {
                if errno == ENOENT { return nil }
                throw MacReinstallFailure.invalidResponse
            }
            close(directory)
            directory = next
        }
        var rootInfo = stat()
        guard fstat(directory, &rootInfo) == 0, rootInfo.st_uid == getuid(),
              rootInfo.st_mode & 0o7777 == 0o700 else { throw MacReinstallFailure.invalidResponse }
        let file = openat(directory, "reinstall-journal.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if file < 0 {
            if errno == ENOENT { return nil }
            throw MacReinstallFailure.invalidResponse
        }
        defer { close(file) }
        var info = stat()
        let maximum = 2 * 1024 * 1024
        guard fstat(file, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_nlink == 1, info.st_mode & 0o7777 == 0o600,
              info.st_size > 0, info.st_size <= maximum else { throw MacReinstallFailure.invalidResponse }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0, data.count + count <= maximum else { throw MacReinstallFailure.invalidResponse }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        var final = stat()
        guard data.count == info.st_size, fstat(file, &final) == 0,
              final.st_dev == info.st_dev, final.st_ino == info.st_ino, final.st_size == info.st_size,
              final.st_uid == getuid(), final.st_nlink == 1, final.st_mode == info.st_mode,
              final.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
              final.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec else { throw MacReinstallFailure.invalidResponse }
        let object = try SetupWireJSON.object(data, integerKey: "version", integerValue: "1", maximumBytes: maximum)
        let required: Set<String> = ["version", "operation", "transferID", "deviceID", "dataSetID", "nonce", "setupID",
            "knownSource", "targetArtifact", "sourceApp", "requestSHA256", "rawManifestSHA256", "counts", "predecessor",
            "stages", "commands", "backup", "restoreIntent", "setup", "restoreReceipt", "errorCode", "outcome", "options", "proof"]
        guard required.isSubset(of: Set(object.keys)), Set(object.keys).isSubset(of: required.union(["history"])),
              object["operation"] as? String == "reinstall",
              let device = object["deviceID"] as? String,
              let options = object["options"] as? [String: Any],
              Set(options.keys) == ["source", "artifactPath", "teamID", "allowProvisioningUpdates", "categories"],
              let source = (options["source"] as? String).flatMap(MacSetupSource.init(rawValue:)),
              let team = options["teamID"] as? String,
              let updates = options["allowProvisioningUpdates"] as? NSNumber,
              CFGetTypeID(updates) == CFBooleanGetTypeID(),
              let rawCategories = options["categories"] as? [String] else { throw MacReinstallFailure.invalidResponse }
        let categories = rawCategories.compactMap(MacReinstallCategory.init(rawValue:))
        guard categories.count == rawCategories.count else { throw MacReinstallFailure.invalidResponse }
        let artifactPath: String?
        if options["artifactPath"] is NSNull { artifactPath = nil }
        else {
            guard let path = options["artifactPath"] as? String else { throw MacReinstallFailure.invalidResponse }
            artifactPath = path
        }
        _ = try MacReinstallOptions(source: source, artifactPath: artifactPath, teamID: team,
            allowProvisioningUpdates: updates.boolValue, categories: categories)
        var identities: [String: UUID] = [:]
        for key in ["transferID", "dataSetID", "nonce", "setupID"] {
            guard let raw = object[key] as? String, let id = UUID(uuidString: raw),
                  raw == id.uuidString.lowercased() else { throw MacReinstallFailure.invalidResponse }
            identities[key] = id
        }
        guard let transferID = identities["transferID"] else { throw MacReinstallFailure.invalidResponse }
        return try MacReinstallContinuation(transferID: transferID, deviceID: device, categories: categories)
    }
}
