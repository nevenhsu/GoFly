import Darwin
import Foundation

/// The durable identity of a management transaction.  A journal header is an
/// identity record only; it does not claim that an effect, release, or device
/// observation has been confirmed.
public struct MacManagementContinuation: Equatable, Sendable {
    public let managementID: UUID
    public let deviceID: String
    public let selectionID: UUID
    public let kind: MacManagementKind
    public let initialTransport: MacManagementTransport
    public let connectionRevision: Int
    public let currentTransport: MacManagementTransport
    public let options: MacManagementOptions?

    public init(managementID: UUID, deviceID: String, selectionID: UUID,
                kind: MacManagementKind, initialTransport: MacManagementTransport,
                connectionRevision: Int, currentTransport: MacManagementTransport,
                options: MacManagementOptions?) throws {
        let normalized = deviceID.lowercased()
        guard normalized == deviceID, MacManagementWire.validDeviceID(normalized),
              (0...31).contains(connectionRevision),
              connectionRevision != 0 || currentTransport == initialTransport else {
            throw MacManagementFailure.invalidResponse
        }
        switch kind {
        case .renew: guard options != nil else { throw MacManagementFailure.invalidResponse }
        case .repair: guard options == nil else { throw MacManagementFailure.invalidResponse }
        }
        self.managementID = managementID
        self.deviceID = normalized
        self.selectionID = selectionID
        self.kind = kind
        self.initialTransport = initialTransport
        self.connectionRevision = connectionRevision
        self.currentTransport = currentTransport
        self.options = options
    }
}

public protocol MacManagementJournalReading: Sendable {
    func readContinuation() async throws -> MacManagementContinuation?
    func findSelection(_ selectionID: UUID) async throws -> MacManagementContinuation?
}

/// Reads the producer's private management journal without creating state,
/// launching a bridge, or querying a device.  Only the immutable header and
/// revision/selection associations are promoted into a continuation.
public struct MacManagementJournalReader: MacManagementJournalReading {
    public let stateRoot: URL

    public init(stateRoot: URL) { self.stateRoot = stateRoot }

    public func readContinuation() async throws -> MacManagementContinuation? {
        do {
            return try await Task.detached(priority: .utility) {
                try Self.readCurrent(stateRoot)
            }.value
        } catch let failure as MacManagementFailure {
            throw failure
        } catch {
            throw MacManagementFailure.invalidResponse
        }
    }

    public func findSelection(_ selectionID: UUID) async throws -> MacManagementContinuation? {
        do {
            return try await Task.detached(priority: .utility) {
                try Self.find(selectionID, stateRoot: stateRoot)
            }.value
        } catch let failure as MacManagementFailure {
            throw failure
        } catch {
            throw MacManagementFailure.invalidResponse
        }
    }

    private struct ParsedDocument {
        let continuation: MacManagementContinuation
        let selectionIDs: Set<UUID>
    }

    private static let maximumBytes = 2 * 1024 * 1024
    private static let maximumHistory = 128

    private static func readCurrent(_ root: URL) throws -> MacManagementContinuation? {
        let descriptor: Int32
        do { descriptor = try openStateRoot(root) }
        catch is MissingStateRoot { return nil }
        defer { close(descriptor) }
        guard let data = try readRegularFile(parent: descriptor, name: "management-journal.json",
                                             allowMissing: true) else { return nil }
        return try parse(data).continuation
    }

    private static func find(_ selectionID: UUID, stateRoot root: URL) throws -> MacManagementContinuation? {
        let descriptor: Int32
        do { descriptor = try openStateRoot(root) }
        catch is MissingStateRoot { return nil }
        defer { close(descriptor) }

        var matches: [MacManagementContinuation] = []
        if let data = try readRegularFile(parent: descriptor, name: "management-journal.json",
                                          allowMissing: true) {
            let parsed = try parse(data)
            if parsed.selectionIDs.contains(selectionID) { matches.append(parsed.continuation) }
        }

        guard let history = try openDirectory(parent: descriptor, name: "management-history",
                                               allowMissing: true) else {
            return try uniqueMatch(matches)
        }
        defer { close(history) }
        let names = try directoryNames(history)
        guard names.count <= maximumHistory else { throw MacManagementFailure.invalidResponse }
        for name in names {
            guard name.hasSuffix(".json") else { throw MacManagementFailure.invalidResponse }
            let stem = String(name.dropLast(5))
            guard let fileID = MacManagementWire.uuid(.string(stem)),
                  let data = try readRegularFile(parent: history, name: name, allowMissing: false) else {
                throw MacManagementFailure.invalidResponse
            }
            let parsed = try parse(data)
            guard parsed.continuation.managementID == fileID else {
                throw MacManagementFailure.invalidResponse
            }
            if parsed.selectionIDs.contains(selectionID) { matches.append(parsed.continuation) }
        }
        return try uniqueMatch(matches)
    }

    private static func uniqueMatch(_ matches: [MacManagementContinuation]) throws -> MacManagementContinuation? {
        guard let first = matches.first else { return nil }
        guard matches.dropFirst().allSatisfy({ $0 == first }) else {
            throw MacManagementFailure.invalidResponse
        }
        return first
    }

    private static func parse(_ data: Data) throws -> ParsedDocument {
        let root = try MacManagementWire.object(data, maximum: maximumBytes)
        guard MacManagementWire.int(root["version"]) == 1,
              MacManagementWire.string(root["operation"]) == "management",
              let header = MacManagementWire.object(root["header"]),
              MacManagementWire.keys(header, required: [
                "managementID", "nonce", "targetSetupID", "setupNonce", "deviceID",
                "selectionID", "kind", "transport", "options"
              ]) else { throw MacManagementFailure.invalidResponse }

        guard let managementID = MacManagementWire.uuid(header["managementID"]),
              MacManagementWire.uuid(header["nonce"]) != nil,
              MacManagementWire.uuid(header["targetSetupID"]) != nil,
              MacManagementWire.uuid(header["setupNonce"]) != nil,
              let deviceID = MacManagementWire.string(header["deviceID"]),
              deviceID == deviceID.lowercased(), MacManagementWire.validDeviceID(deviceID),
              let selectionID = MacManagementWire.uuid(header["selectionID"]),
              let kind = MacManagementKind(rawValue: MacManagementWire.string(header["kind"]) ?? ""),
              let initialTransport = MacManagementTransport(rawValue: MacManagementWire.string(header["transport"]) ?? "") else {
            throw MacManagementFailure.invalidResponse
        }

        let options = try decodeOptions(header["options"], kind: kind)
        guard let revisions = root["revisions"], case .array(let revisionValues) = revisions,
              !revisionValues.isEmpty, revisionValues.count <= 32 else {
            throw MacManagementFailure.invalidResponse
        }

        var parsedRevisions: [(selectionID: UUID, transport: MacManagementTransport)] = []
        var revisionSelections = Set<UUID>()
        for (index, value) in revisionValues.enumerated() {
            guard let revision = MacManagementWire.object(value),
                  MacManagementWire.keys(revision, required: [
                    "number", "selectionID", "transport", "previous", "resolvedThroughSHA256"
                  ]),
                  MacManagementWire.int(revision["number"]) == index,
                  let revisionSelection = MacManagementWire.uuid(revision["selectionID"]),
                  revisionSelections.insert(revisionSelection).inserted,
                  let transport = MacManagementTransport(rawValue: MacManagementWire.string(revision["transport"]) ?? "") else {
                throw MacManagementFailure.invalidResponse
            }
            if index == 0 {
                guard revisionSelection == selectionID, transport == initialTransport,
                      revision["previous"]?.isNull == true,
                      revision["resolvedThroughSHA256"]?.isNull == true else {
                    throw MacManagementFailure.invalidResponse
                }
            } else {
                guard MacManagementWire.int(revision["previous"]) == index - 1,
                      let resolved = MacManagementWire.string(revision["resolvedThroughSHA256"]),
                      MacManagementWire.validHash(resolved),
                      transport != parsedRevisions[index - 1].transport else {
                    throw MacManagementFailure.invalidResponse
                }
            }
            parsedRevisions.append((revisionSelection, transport))
        }

        var selectionIDs = revisionSelections
        if let selectionValue = root["selections"] {
            guard case .array(let values) = selectionValue, !values.isEmpty,
                  values.count <= 128 else { throw MacManagementFailure.invalidResponse }
            var associations = Set<UUID>()
            var represented = Set<Int>()
            for value in values {
                guard let association = MacManagementWire.object(value),
                      MacManagementWire.keys(association, required: ["selectionID", "revision"]),
                      let id = MacManagementWire.uuid(association["selectionID"]),
                      associations.insert(id).inserted,
                      let revision = MacManagementWire.int(association["revision"]),
                      revision < parsedRevisions.count else {
                    throw MacManagementFailure.invalidResponse
                }
                represented.insert(revision)
                selectionIDs.insert(id)
            }
            guard associations.contains(selectionID),
                  values.contains(where: { value in
                      guard let object = MacManagementWire.object(value),
                            MacManagementWire.uuid(object["selectionID"]) == selectionID else { return false }
                      return MacManagementWire.int(object["revision"]) == 0
                  }),
                  represented.count == parsedRevisions.count else {
                throw MacManagementFailure.invalidResponse
            }
            // Every revision's primary selection remains represented by the
            // association list, while additional same-transport selections
            // may point at that revision.
            guard parsedRevisions.allSatisfy({ selectionIDs.contains($0.selectionID) }) else {
                throw MacManagementFailure.invalidResponse
            }
        }

        let last = parsedRevisions[parsedRevisions.count - 1]
        let continuation = try MacManagementContinuation(
            managementID: managementID, deviceID: deviceID, selectionID: selectionID,
            kind: kind, initialTransport: initialTransport,
            connectionRevision: parsedRevisions.count - 1,
            currentTransport: last.transport, options: options)
        return ParsedDocument(continuation: continuation, selectionIDs: selectionIDs)
    }

    private static func decodeOptions(_ value: MacManagementWire.Value?,
                                      kind: MacManagementKind) throws -> MacManagementOptions? {
        guard let value else { throw MacManagementFailure.invalidResponse }
        if kind == .repair {
            guard value.isNull else { throw MacManagementFailure.invalidResponse }
            return nil
        }
        guard let object = MacManagementWire.object(value),
              MacManagementWire.keys(object, required: [
                "source", "artifactPath", "teamID", "allowProvisioningUpdates"
              ]),
              let source = MacManagementSource(rawValue: MacManagementWire.string(object["source"]) ?? ""),
              let teamID = MacManagementWire.string(object["teamID"]),
              let allow = MacManagementWire.bool(object["allowProvisioningUpdates"]) else {
            throw MacManagementFailure.invalidResponse
        }
        let artifactPath: String?
        if object["artifactPath"]?.isNull == true { artifactPath = nil }
        else {
            guard let value = MacManagementWire.string(object["artifactPath"]) else {
                throw MacManagementFailure.invalidResponse
            }
            artifactPath = value
        }
        do {
            return try MacManagementOptions(source: source, artifactPath: artifactPath,
                                             teamID: teamID, allowProvisioningUpdates: allow)
        } catch { throw MacManagementFailure.invalidResponse }
    }

    private static func openStateRoot(_ root: URL) throws -> Int32 {
        guard root.isFileURL, root.path.hasPrefix("/"), root.path != "/" else {
            throw MacManagementFailure.invalidResponse
        }
        let components = root.path.split(separator: "/")
        guard !components.contains(where: { $0 == "." || $0 == ".." }) else {
            throw MacManagementFailure.invalidResponse
        }
        var directory = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw MacManagementFailure.invalidResponse }
        for component in components {
            let next = openat(directory, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0 {
                let missing = errno == ENOENT
                close(directory)
                if missing { throw MissingStateRoot() }
                throw MacManagementFailure.invalidResponse
            }
            close(directory)
            directory = next
        }
        var info = stat()
        guard fstat(directory, &info) == 0, info.st_uid == getuid(),
              info.st_mode & 0o7777 == 0o700 else {
            close(directory)
            throw MacManagementFailure.invalidResponse
        }
        return directory
    }

    private static func openDirectory(parent: Int32, name: String, allowMissing: Bool) throws -> Int32? {
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if allowMissing && errno == ENOENT { return nil }
            throw MacManagementFailure.invalidResponse
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
              info.st_mode & 0o7777 == 0o700 else {
            close(descriptor)
            throw MacManagementFailure.invalidResponse
        }
        return descriptor
    }

    private static func readRegularFile(parent: Int32, name: String, allowMissing: Bool) throws -> Data? {
        let descriptor = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if descriptor < 0 {
            if allowMissing && errno == ENOENT { return nil }
            throw MacManagementFailure.invalidResponse
        }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              before.st_uid == getuid(), before.st_nlink == 1,
              before.st_mode & 0o7777 == 0o600,
              before.st_size > 0, before.st_size <= maximumBytes else {
            throw MacManagementFailure.invalidResponse
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0, data.count + count <= maximumBytes else {
                throw MacManagementFailure.invalidResponse
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard data.count == before.st_size, fstat(descriptor, &after) == 0,
              stable(before, after) else { throw MacManagementFailure.invalidResponse }
        return data
    }

    private static func stable(_ first: stat, _ second: stat) -> Bool {
        first.st_dev == second.st_dev && first.st_ino == second.st_ino &&
            first.st_size == second.st_size && first.st_uid == second.st_uid &&
            first.st_nlink == second.st_nlink && first.st_mode == second.st_mode &&
            first.st_mtimespec.tv_sec == second.st_mtimespec.tv_sec &&
            first.st_mtimespec.tv_nsec == second.st_mtimespec.tv_nsec
    }

    private static func directoryNames(_ descriptor: Int32) throws -> [String] {
        let duplicate = dup(descriptor)
        guard duplicate >= 0, let stream = fdopendir(duplicate) else {
            if duplicate >= 0 { close(duplicate) }
            throw MacManagementFailure.invalidResponse
        }
        defer { closedir(stream) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        guard errno == 0 else { throw MacManagementFailure.invalidResponse }
        return names
    }

    private struct MissingStateRoot: Error {}
}
