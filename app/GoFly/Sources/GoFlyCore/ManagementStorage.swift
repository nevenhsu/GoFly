import CryptoKit
import Darwin
import Foundation

struct ManagementSetupEvidence: Sendable {
    let rawActivation: Data
    let activation: SetupActivationRecord
    let receipt: SetupReceipt
}

struct ManagementTransferEvidence: Sendable {
    let rawRoot: Data?
    let intent: TransferRestoreIntent?
    let status: TransferRestoreStatus?
    let projection: TransferRuntimeProjection
    let settings: TransferSettings?
}

public final class ManagementPreparedSource: @unchecked Sendable {
    fileprivate let storeID: UUID
    fileprivate let input: ManagementInput
    fileprivate let setupStore: SetupActivationStore
    fileprivate let restoreStore: TransferRestoreStore
    fileprivate init(storeID: UUID, input: ManagementInput,
                     setupStore: SetupActivationStore,
                     restoreStore: TransferRestoreStore) {
        self.storeID = storeID
        self.input = input
        self.setupStore = setupStore
        self.restoreStore = restoreStore
    }
}

public final class ManagementPreparedTarget: @unchecked Sendable {
    fileprivate let storeID: UUID
    fileprivate let input: ManagementInput
    fileprivate let managementStore: ManagementStore
    fileprivate let setupStore: SetupActivationStore
    fileprivate let restoreStore: TransferRestoreStore
    fileprivate init(storeID: UUID, input: ManagementInput,
                     managementStore: ManagementStore,
                     setupStore: SetupActivationStore,
                     restoreStore: TransferRestoreStore) {
        self.storeID = storeID
        self.input = input
        self.managementStore = managementStore
        self.setupStore = setupStore
        self.restoreStore = restoreStore
    }

    /// Internal typed gate used by SetupBootstrapCoordinator immediately
    /// before pairing or activation consumption. The initializer remains
    /// opaque to callers.
    func validateSetupAcceptance(currentApp: SetupAppIdentity,
                                 setupStore: SetupActivationStore) throws {
        try managementStore.validateSetupAcceptance(self, currentApp: currentApp,
                                                     setupStore: setupStore, restoreStore: restoreStore)
    }
}

private struct ManagementRecord: Equatable {
    let managementID: UUID
    let nonce: UUID
    let requestSHA256: String
    let phase: ManagementStatusPhase
    let sourceAdmission: ManagementSourceAdmission
    let currentApp: SetupAppIdentity
    let pid: Int32
    let sourceSetupID: UUID
    let targetSetupID: UUID
    let sourceApp: SetupAppIdentity
    let targetApp: SetupAppIdentity
    let expectedDeviceUDID: String
    let teamID: String
    let sourceActivationSHA256: String
    let sourceRestoreRootSHA256: String?
    let adoptionReceipt: ManagementAdoptionReceipt?
}

private struct ManagementRootState {
    var current: ManagementRecord?
    var history: [ManagementRecord]
}

private enum ManagementStorageMapping {
    static func setup(_ failure: SetupFailure) -> ManagementFailure {
        switch failure {
        case .unsupportedVersion: return .unsupportedVersion
        case .limitExceeded: return .limitExceeded
        case .unsafeFile: return .unsafeFile
        case .storageUnavailable: return .storageUnavailable
        case .receiptCapacity: return .receiptCapacity
        case .identityMismatch: return .identityMismatch
        case .artifactMismatch: return .unavailable
        default: return .invalidInput
        }
    }

    static func transfer(_ failure: TransferFailure) -> ManagementFailure {
        switch failure {
        case .unsupportedVersion: return .unsupportedVersion
        case .limitExceeded: return .limitExceeded
        case .unsafeFile: return .unsafeFile
        case .storageUnavailable: return .storageUnavailable
        case .receiptCapacity: return .receiptCapacity
        case .identityMismatch, .artifactMismatch: return .identityMismatch
        case .busy, .sourceBusy, .updateRequired: return .conflict
        default: return .unavailable
        }
    }
}

private enum ManagementStorageDisk {
    static let rootName = "GoFlyManagement"
    static let responseName = "response.json"
    static let rootMaximum = 512 * 1_024

    static func base(_ value: URL) -> URL {
        let standardized = value.standardizedFileURL.resolvingSymlinksInPath()
        if standardized.path.hasPrefix("/var/"),
           FileManager.default.fileExists(atPath: "/private/var") {
            return URL(fileURLWithPath: "/private" + standardized.path, isDirectory: true)
        }
        return standardized
    }

    static func ensureDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: NSNumber(value: 0o700)])
        } catch {
            throw ManagementFailure.storageUnavailable
        }
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == getuid(), info.st_mode & 0o7777 == 0o700,
              info.st_nlink >= 2 else { throw ManagementFailure.unsafeFile }
    }

    static func validateFile(_ url: URL, maximum: Int, allowIngress: Bool = false) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { throw ManagementFailure.unavailable }
            throw ManagementFailure.unsafeFile
        }
        let mode = info.st_mode & 0o7777
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_nlink == 1,
              mode == 0o600 || (allowIngress && mode == 0o644),
              info.st_size >= 0, info.st_size <= off_t(maximum) else {
            throw ManagementFailure.unsafeFile
        }
    }

    static func read(_ url: URL, maximum: Int, allowIngress: Bool = false) throws -> Data? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw ManagementFailure.unsafeFile
        }
        try validateFile(url, maximum: maximum, allowIngress: allowIngress)
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ManagementFailure.storageUnavailable }
        defer { Darwin.close(fd) }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw ManagementFailure.storageUnavailable }
            if count == 0 {
                guard output.count == Int(info.st_size) else { throw ManagementFailure.storageUnavailable }
                return output
            }
            guard output.count + count <= maximum else { throw ManagementFailure.limitExceeded }
            output.append(contentsOf: buffer.prefix(count))
        }
    }

    static func atomicWrite(_ data: Data, to target: URL,
                            checkpoint: (@Sendable (SetupWriteCheckpoint) throws -> Void)?) throws {
        guard data.count <= rootMaximum else { throw ManagementFailure.limitExceeded }
        try ensureDirectory(target.deletingLastPathComponent())
        let parent = Darwin.open(target.deletingLastPathComponent().path,
                                 O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw ManagementFailure.storageUnavailable }
        defer { Darwin.close(parent) }
        var existing = stat()
        if lstat(target.path, &existing) == 0 {
            try validateFile(target, maximum: rootMaximum)
        } else if errno != ENOENT {
            throw ManagementFailure.unsafeFile
        }
        let stagingName = ".management-\(UUID().uuidString.lowercased()).staging"
        let fd = openat(parent, stagingName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ManagementFailure.storageUnavailable }
        var renamed = false
        defer {
            Darwin.close(fd)
            if !renamed { unlinkat(parent, stagingName, 0) }
        }
        guard fchmod(fd, 0o600) == 0 else { throw ManagementFailure.storageUnavailable }
        try checkpoint?(.stagingSecured)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw ManagementFailure.storageUnavailable }
                offset += written
            }
        }
        try checkpoint?(.contentsWritten)
        guard fsync(fd) == 0 else { throw ManagementFailure.storageUnavailable }
        try checkpoint?(.stagingFlushed)
        try checkpoint?(.beforeRename)
        guard renameat(parent, stagingName, parent, target.lastPathComponent) == 0 else {
            throw ManagementFailure.storageUnavailable
        }
        renamed = true
        do {
            try checkpoint?(.afterRename)
            guard fsync(parent) == 0 else { throw ManagementFailure.storageUnavailable }
            try checkpoint?(.parentDirectoryFlushed)
        } catch {
            throw ManagementFailure.conflict
        }
    }

    static func writeImmutable(_ data: Data, to target: URL, maximum: Int,
                               checkpoint: (@Sendable (SetupWriteCheckpoint) throws -> Void)? = nil) throws {
        if let existing = try read(target, maximum: maximum) {
            guard existing == data else { throw ManagementFailure.conflict }
            return
        }
        try atomicWrite(data, to: target, checkpoint: checkpoint)
    }

    static func sealIngress(_ root: URL) throws {
        var rootInfo = stat()
        if lstat(root.path, &rootInfo) != 0 {
            guard errno == ENOENT else { throw ManagementFailure.unsafeFile }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                         attributes: [.posixPermissions: NSNumber(value: 0o700)])
            } catch { throw ManagementFailure.storageUnavailable }
            guard lstat(root.path, &rootInfo) == 0 else { throw ManagementFailure.storageUnavailable }
        }
        guard rootInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              rootInfo.st_uid == getuid(), rootInfo.st_nlink >= 2 else {
            throw ManagementFailure.unsafeFile
        }
        let rootMode = rootInfo.st_mode & 0o7777
        guard rootMode == 0o700 || rootMode == 0o755 else { throw ManagementFailure.unsafeFile }
        let allowed = Set(["request.json", "root.json", responseName, "generations"])
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        guard Set(names).isSubset(of: allowed) else { throw ManagementFailure.unsafeFile }
        if names.contains("request.json") {
            try validateFile(root.appendingPathComponent("request.json"),
                             maximum: ManagementRequest.maximumBytes, allowIngress: true)
            let requestPath = root.appendingPathComponent("request.json").path
            let requestFD = Darwin.open(requestPath, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            guard requestFD >= 0 else { throw ManagementFailure.unsafeFile }
            defer { Darwin.close(requestFD) }
            guard fchmod(requestFD, 0o600) == 0, fsync(requestFD) == 0 else {
                throw ManagementFailure.storageUnavailable
            }
        }
        if names.contains("root.json") {
            try validateFile(root.appendingPathComponent("root.json"), maximum: rootMaximum)
        }
        if names.contains(responseName) {
            try validateFile(root.appendingPathComponent(responseName), maximum: ManagementSourceReceipt.maximumBytes)
        }
        if names.contains("generations") {
            let generations = root.appendingPathComponent("generations", isDirectory: true)
            try validateDirectory(generations)
            let generationNames = try FileManager.default.contentsOfDirectory(atPath: generations.path)
            guard generationNames.count <= 129 else { throw ManagementFailure.limitExceeded }
            for name in generationNames {
                guard let id = UUID(uuidString: name), id.uuidString.lowercased() == name else {
                    throw ManagementFailure.unsafeFile
                }
                let generation = generations.appendingPathComponent(name, isDirectory: true)
                try validateDirectory(generation)
                let entries = try FileManager.default.contentsOfDirectory(atPath: generation.path)
                guard Set(entries).isSubset(of: ["request.json", "source-activation.json", "source-restore-root.json"]),
                      entries.contains("request.json"), entries.contains("source-activation.json"),
                      entries.count <= 3 else { throw ManagementFailure.unsafeFile }
                try validateFile(generation.appendingPathComponent("request.json"), maximum: ManagementRequest.maximumBytes)
                try validateFile(generation.appendingPathComponent("source-activation.json"), maximum: 256 * 1_024)
                if entries.contains("source-restore-root.json") {
                    try validateFile(generation.appendingPathComponent("source-restore-root.json"), maximum: 1_048_576)
                }
            }
        }
        if rootMode == 0o755 {
            let rootFD = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard rootFD >= 0 else { throw ManagementFailure.unsafeFile }
            defer { Darwin.close(rootFD) }
            guard fchmod(rootFD, 0o700) == 0, fsync(rootFD) == 0 else {
                throw ManagementFailure.storageUnavailable
            }
        }
    }

    fileprivate static func validateDirectory(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == getuid(), info.st_mode & 0o7777 == 0o700,
              info.st_nlink >= 2 else { throw ManagementFailure.unsafeFile }
    }
}

private enum ManagementStorageCodec {
    static func encodeRoot(_ state: ManagementRootState) throws -> Data {
        let object: [String: Any] = [
            "version": 1,
            "current": state.current.map(recordObject) ?? NSNull(),
            "history": state.history.map(recordObject)
        ]
        guard JSONSerialization.isValidJSONObject(object) else { throw ManagementFailure.invalidInput }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= ManagementStorageDisk.rootMaximum else { throw ManagementFailure.limitExceeded }
        return data
    }

    static func decodeRoot(_ data: Data) throws -> ManagementRootState {
        guard data.count <= ManagementStorageDisk.rootMaximum else { throw ManagementFailure.limitExceeded }
        do {
            let value = try _SetupJSON.parse(data)
            try value.requireObjectKeys(["version", "current", "history"])
            guard try value.object("version").int() == 1 else { throw ManagementFailure.unsupportedVersion }
            let currentValue = try value.object("current")
            let current = isNull(currentValue) ? nil : try record(currentValue)
            let history = try value.object("history").array().map(record)
            guard history.count <= 128 else { throw ManagementFailure.limitExceeded }
            return ManagementRootState(current: current, history: history)
        } catch let failure as ManagementFailure { throw failure }
        catch let failure as SetupFailure {
            throw ManagementStorageMapping.setup(failure)
        } catch {
            throw ManagementFailure.invalidInput
        }
    }

    private static func recordObject(_ value: ManagementRecord) -> [String: Any] {
        [
            "managementID": value.managementID.uuidString.lowercased(),
            "nonce": value.nonce.uuidString.lowercased(),
            "requestSHA256": value.requestSHA256,
            "phase": value.phase.rawValue,
            "sourceAdmission": value.sourceAdmission.rawValue,
            "currentApp": SetupCodec.appObject(value.currentApp),
            "pid": value.pid,
            "sourceSetupID": value.sourceSetupID.uuidString.lowercased(),
            "targetSetupID": value.targetSetupID.uuidString.lowercased(),
            "sourceApp": SetupCodec.appObject(value.sourceApp),
            "targetApp": SetupCodec.appObject(value.targetApp),
            "expectedDeviceUDID": value.expectedDeviceUDID,
            "teamID": value.teamID,
            "sourceActivationSHA256": value.sourceActivationSHA256,
            "sourceRestoreRootSHA256": value.sourceRestoreRootSHA256 ?? NSNull(),
            "adoptionReceipt": value.adoptionReceipt.map(adoptionObject) ?? NSNull()
        ]
    }

    private static func record(_ value: _SetupJSON) throws -> ManagementRecord {
        try value.requireObjectKeys([
            "managementID", "nonce", "requestSHA256", "phase", "sourceAdmission", "currentApp",
            "pid", "sourceSetupID", "targetSetupID", "sourceApp", "targetApp", "expectedDeviceUDID",
            "teamID", "sourceActivationSHA256", "sourceRestoreRootSHA256", "adoptionReceipt"
        ])
        let adoptionValue = try value.object("adoptionReceipt")
        let adoption: ManagementAdoptionReceipt?
        if isNull(adoptionValue) {
            adoption = nil
        } else {
            let data = try JSONSerialization.data(withJSONObject: try foundation(adoptionValue), options: [.sortedKeys, .withoutEscapingSlashes])
            adoption = try ManagementCodec.decodeAdoptionReceipt(data)
        }
        let phase = try enumValue(ManagementStatusPhase.self, value.object("phase"))
        let admission = try enumValue(ManagementSourceAdmission.self, value.object("sourceAdmission"))
        let pid = try value.object("pid").int()
        guard pid >= 0, pid <= Int(Int32.max) else { throw ManagementFailure.invalidInput }
        let managementID = try uuid(value.object("managementID"))
        let nonce = try uuid(value.object("nonce"))
        let sourceSetupID = try uuid(value.object("sourceSetupID"))
        let targetSetupID = try uuid(value.object("targetSetupID"))
        let currentApp = try app(value.object("currentApp"))
        let sourceApp = try app(value.object("sourceApp"))
        let targetApp = try app(value.object("targetApp"))
        let expectedDeviceUDID = try string(value.object("expectedDeviceUDID"))
        let teamID = try string(value.object("teamID"))
        guard sourceSetupID != targetSetupID,
              SetupValidation.validUDID(expectedDeviceUDID),
              ManagementRequest.validTeamID(teamID),
              currentApp.bundleID == SetupAppIdentity.formalBundleID,
              sourceApp.bundleID == SetupAppIdentity.formalBundleID,
              targetApp.bundleID == SetupAppIdentity.formalBundleID else {
            throw ManagementFailure.invalidInput
        }
        switch (phase, admission) {
        case (.adopted, .cold), (.adopted, .live):
            guard pid == 0, adoption != nil else { throw ManagementFailure.invalidInput }
        case (.preparing, .cold):
            guard pid == 0, adoption == nil else { throw ManagementFailure.invalidInput }
        case (.preparing, .live), (.ready, .live), (.mutationSealed, .live), (.released, .live):
            guard pid > 0, adoption == nil else { throw ManagementFailure.invalidInput }
        default:
            throw ManagementFailure.invalidInput
        }
        return ManagementRecord(
            managementID: managementID,
            nonce: nonce,
            requestSHA256: try hash(value.object("requestSHA256")),
            phase: phase, sourceAdmission: admission,
            currentApp: currentApp, pid: Int32(pid),
            sourceSetupID: sourceSetupID,
            targetSetupID: targetSetupID,
            sourceApp: sourceApp,
            targetApp: targetApp,
            expectedDeviceUDID: expectedDeviceUDID,
            teamID: teamID,
            sourceActivationSHA256: try hash(value.object("sourceActivationSHA256")),
            sourceRestoreRootSHA256: try optionalHash(value.object("sourceRestoreRootSHA256")),
            adoptionReceipt: adoption)
    }

    private static func uuid(_ value: _SetupJSON) throws -> UUID {
        let text = try string(value)
        guard text == text.lowercased(), let id = UUID(uuidString: text),
              id.uuidString.lowercased() == text else { throw ManagementFailure.invalidInput }
        return id
    }
    private static func string(_ value: _SetupJSON) throws -> String {
        do { return try value.string() } catch { throw ManagementFailure.invalidInput }
    }
    private static func hash(_ value: _SetupJSON) throws -> String {
        let text = try string(value)
        guard SetupValidation.isLowerHex(text, count: 64) else { throw ManagementFailure.invalidInput }
        return text
    }
    private static func optionalHash(_ value: _SetupJSON) throws -> String? {
        isNull(value) ? nil : try hash(value)
    }
    private static func app(_ value: _SetupJSON) throws -> SetupAppIdentity {
        do { return try SetupAppIdentity.decode(value) }
        catch let failure as SetupFailure { throw ManagementStorageMapping.setup(failure) }
        catch { throw ManagementFailure.invalidInput }
    }
    private static func isNull(_ value: _SetupJSON) -> Bool {
        if case .null = value { return true }
        return false
    }
    private static func adoptionObject(_ receipt: ManagementAdoptionReceipt) -> Any {
        (try? JSONSerialization.jsonObject(with: (try? ManagementCodec.encodeAdoptionReceipt(receipt)) ?? Data())) ?? NSNull()
    }
    private static func foundation(_ value: _SetupJSON) throws -> Any {
        switch value {
        case .object(let pairs):
            return try Dictionary(uniqueKeysWithValues: pairs.map { (key, value) in (key, try foundation(value)) })
        case .array(let values): return try values.map(foundation)
        case .string(let text): return text
        case .number(let number): return Int(number) ?? number
        case .bool(let value): return value
        case .null: return NSNull()
        }
    }
    private static func enumValue<T: RawRepresentable>(_ type: T.Type, _ value: _SetupJSON) throws -> T where T.RawValue == String {
        guard let result = T(rawValue: try string(value)) else { throw ManagementFailure.invalidInput }
        return result
    }
}

public final class ManagementStore: @unchecked Sendable {
    private let applicationSupport: URL
    private let root: URL
    private let checkpoint: (@Sendable (SetupWriteCheckpoint) throws -> Void)?
    private let storeID = UUID()
    private let lock = NSLock()

    public init(applicationSupport: URL,
                checkpoint: (@Sendable (SetupWriteCheckpoint) throws -> Void)? = nil) {
        let base = ManagementStorageDisk.base(applicationSupport)
        self.applicationSupport = base
        self.root = base.appendingPathComponent(ManagementStorageDisk.rootName, isDirectory: true)
        self.checkpoint = checkpoint
    }

    public func prepareIncomingFiles() throws {
        try locked {
            try ManagementStorageDisk.sealIngress(root)
            if let bytes = try ManagementStorageDisk.read(root.appendingPathComponent("request.json"),
                                                          maximum: ManagementRequest.maximumBytes) {
                _ = try ManagementInput(data: bytes)
            }
        }
    }

    public func readInput() throws -> ManagementInput? {
        try locked {
            guard let bytes = try ManagementStorageDisk.read(root.appendingPathComponent("request.json"),
                                                             maximum: ManagementRequest.maximumBytes,
                                                             allowIngress: true) else { return nil }
            return try ManagementInput(data: bytes)
        }
    }

    public func prepareSource(currentApp: SetupAppIdentity, pid: Int32,
                              setupStore: SetupActivationStore,
                              restoreStore: TransferRestoreStore) throws -> ManagementPreparedSource {
        try locked {
            guard pid > 0 else { throw ManagementFailure.invalidInput }
            let input = try requiredInput()
            guard currentApp == input.request.sourceApp else { throw ManagementFailure.identityMismatch }
            let state = try readState()
            if let current = state.current {
                guard current.managementID == input.request.managementID,
                      current.requestSHA256 == input.rawRequestSHA256 else {
                    if [.released, .adopted].contains(current.phase) {
                        return try prepareNewSource(input: input, currentApp: current, pid: pid,
                                                    setupStore: setupStore, restoreStore: restoreStore,
                                                    state: state)
                    }
                    throw ManagementFailure.conflict
                }
                guard current.phase != .adopted else { throw ManagementFailure.conflict }
                try validateGeneration(input, record: current)
                return ManagementPreparedSource(storeID: storeID, input: input,
                                                setupStore: setupStore, restoreStore: restoreStore)
            }
            guard !state.history.contains(where: { $0.managementID == input.request.managementID }) else {
                throw ManagementFailure.conflict
            }
            return try prepareNewSource(input: input, currentApp: nil, pid: pid,
                                        setupStore: setupStore, restoreStore: restoreStore,
                                        state: state)
        }
    }

    public func commitSourceReady(_ prepared: ManagementPreparedSource,
                                  currentApp: SetupAppIdentity, pid: Int32) throws -> ManagementSourceReceipt {
        try locked {
            guard prepared.storeID == storeID, pid > 0 else { throw ManagementFailure.invalidInput }
            var state = try readState()
            guard var record = try currentRecord(state, input: prepared.input),
                  record.phase == .preparing, record.sourceAdmission == .live,
                  record.currentApp == currentApp else { throw ManagementFailure.conflict }
            let origin = try lineageOrigin(state, request: prepared.input.request)
            let source = try prepared.setupStore.managementEvidence(
                setupID: prepared.input.request.sourceSetupID, app: prepared.input.request.sourceApp,
                expectedDeviceUDID: prepared.input.request.expectedDeviceUDID,
                teamID: prepared.input.request.teamID, requireActive: true)
            try ensureReceiptCapacity(source.activation, targetSetupID: prepared.input.request.targetSetupID)
            guard SetupValidation.sha256(source.rawActivation) == prepared.input.request.sourceActivationSHA256 else {
                throw ManagementFailure.identityMismatch
            }
            _ = try prepared.restoreStore.managementEvidence(
                expectedSetupID: origin.setupID, expectedApp: origin.app,
                expectedDeviceUDID: prepared.input.request.expectedDeviceUDID,
                expectedRootSHA256: prepared.input.request.sourceRestoreRootSHA256)
            try validateGeneration(prepared.input, record: record)
            record = replace(record, phase: .ready, currentApp: currentApp, pid: pid)
            state.current = record
            try writeState(state)
            return try sourceReceipt(record)
        }
    }

    public func sealSource(currentApp: SetupAppIdentity, pid: Int32) throws -> ManagementSourceReceipt {
        try locked {
            guard pid > 0 else { throw ManagementFailure.invalidInput }
            let input = try requiredInput()
            var state = try readState()
            guard var record = try currentRecord(state, input: input),
                  record.phase == .ready, record.sourceAdmission == .live,
                  record.currentApp == currentApp else { throw ManagementFailure.conflict }
            record = replace(record, phase: .mutationSealed, currentApp: currentApp, pid: pid)
            state.current = record
            try writeState(state)
            return try sourceReceipt(record)
        }
    }

    public func releaseSource(currentApp: SetupAppIdentity, pid: Int32,
                              setupStore: SetupActivationStore,
                              restoreStore: TransferRestoreStore) throws -> ManagementSourceReceipt {
        try locked {
            guard pid > 0 else { throw ManagementFailure.invalidInput }
            let input = try requiredInput()
            var state = try readState()
            if state.current == nil {
                guard currentApp == input.request.sourceApp else { throw ManagementFailure.identityMismatch }
                let origin = try lineageOrigin(state, request: input.request)
                let source = try setupStore.managementEvidence(
                    setupID: input.request.sourceSetupID, app: input.request.sourceApp,
                    expectedDeviceUDID: input.request.expectedDeviceUDID,
                    teamID: input.request.teamID, requireActive: true)
                try ensureReceiptCapacity(source.activation, targetSetupID: input.request.targetSetupID)
                guard SetupValidation.sha256(source.rawActivation) == input.request.sourceActivationSHA256 else {
                    throw ManagementFailure.identityMismatch
                }
                _ = try restoreStore.managementEvidence(
                    expectedSetupID: origin.setupID, expectedApp: origin.app,
                    expectedDeviceUDID: input.request.expectedDeviceUDID,
                    expectedRootSHA256: input.request.sourceRestoreRootSHA256)
                state.current = makeRecord(input: input, phase: .released, admission: .live,
                                           currentApp: currentApp, pid: pid)
                try writeState(state)
                return try sourceReceipt(state.current!)
            }
            guard var record = try currentRecord(state, input: input),
                  record.sourceAdmission == .live,
                  record.currentApp == currentApp else { throw ManagementFailure.identityMismatch }
            if record.phase == .mutationSealed { throw ManagementFailure.conflict }
            if record.phase == .released {
                guard record.pid == pid else { throw ManagementFailure.identityMismatch }
                return try sourceReceipt(record)
            }
            guard record.phase == .preparing || record.phase == .ready else { throw ManagementFailure.conflict }
            try validateSourceEvidence(input: input, record: record, setupStore: setupStore, restoreStore: restoreStore)
            record = replace(record, phase: .released, currentApp: currentApp, pid: pid)
            state.current = record
            try writeState(state)
            return try sourceReceipt(record)
        }
    }

    public func readSourceReceipt(currentApp: SetupAppIdentity, pid: Int32) throws -> ManagementSourceReceipt? {
        try locked {
            guard let record = try readState().current,
                  record.sourceAdmission == .live,
                  record.phase != .adopted else { return nil }
            guard record.currentApp == currentApp, record.pid == pid else {
                throw ManagementFailure.identityMismatch
            }
            let receipt = try sourceReceipt(record)
            try receipt.bound(to: requiredInput())
            return receipt
        }
    }

    public func writeSourceReadback(currentApp: SetupAppIdentity,
                                    pid: Int32) throws -> ManagementSourceReceipt? {
        try locked {
            guard let record = try readState().current,
                  record.sourceAdmission == .live,
                  record.phase != .adopted else { return nil }
            guard record.currentApp == currentApp, record.pid == pid else {
                throw ManagementFailure.identityMismatch
            }
            let input = try requiredInput()
            let receipt = try sourceReceipt(record)
            try receipt.bound(to: input)
            try ManagementStorageDisk.atomicWrite(
                try ManagementCodec.encodeSourceReceipt(receipt),
                to: root.appendingPathComponent(ManagementStorageDisk.responseName),
                checkpoint: checkpoint)
            return receipt
        }
    }

    /// Re-emits the persisted source acknowledgement after a crash. This
    /// path never accepts a new PID or advances the source phase; it only
    /// revalidates the durable request/evidence and publishes the original
    /// receipt again.
    public func replaySourceReadback(currentApp: SetupAppIdentity,
                                     setupStore: SetupActivationStore,
                                     restoreStore: TransferRestoreStore) throws -> ManagementSourceReceipt? {
        try locked {
            guard let record = try readState().current,
                  record.sourceAdmission == .live,
                  record.phase != .adopted else { return nil }
            guard record.currentApp == currentApp, record.pid > 0 else {
                throw ManagementFailure.identityMismatch
            }
            let input = try requiredInput()
            guard input.rawRequestSHA256 == record.requestSHA256 else {
                throw ManagementFailure.identityMismatch
            }
            let hasGeneration: Bool
            if record.phase != .released {
                hasGeneration = true
            } else {
                hasGeneration = try generationExists(for: record.managementID)
            }
            try validateActualSourceEvidence(input: input, record: record,
                                             setupStore: setupStore, restoreStore: restoreStore,
                                             requireGeneration: hasGeneration)
            let receipt = try sourceReceipt(record)
            try receipt.bound(to: input)
            try ManagementStorageDisk.atomicWrite(
                try ManagementCodec.encodeSourceReceipt(receipt),
                to: root.appendingPathComponent(ManagementStorageDisk.responseName),
                checkpoint: checkpoint)
            return receipt
        }
    }

    public func writeAdoptionReadback(currentApp: SetupAppIdentity,
                                      setupStore: SetupActivationStore,
                                      restoreStore: TransferRestoreStore,
                                      preferences: TransferPreferencesStore) throws -> ManagementAdoptionResult? {
        guard let result = try reopenAdoptedProjection(currentApp: currentApp,
                                                       setupStore: setupStore,
                                                       restoreStore: restoreStore,
                                                       preferences: preferences) else { return nil }
        return try locked {
            try ManagementStorageDisk.atomicWrite(
                try ManagementCodec.encodeAdoptionReceipt(result.receipt),
                to: root.appendingPathComponent(ManagementStorageDisk.responseName),
                checkpoint: checkpoint)
            return result
        }
    }

    public func prepareTarget(currentApp: SetupAppIdentity,
                              setupStore: SetupActivationStore,
                              restoreStore: TransferRestoreStore) throws -> ManagementPreparedTarget {
        try locked {
            let input = try requiredInput()
            guard currentApp == input.request.targetApp else { throw ManagementFailure.identityMismatch }
            let state = try readState()
            try validateIncomingSetupIfPresent(input.request, setupStore: setupStore)
            if let current = state.current,
               current.managementID == input.request.managementID,
               current.requestSHA256 == input.rawRequestSHA256 {
                let isColdPreparation = current.sourceAdmission == .cold && current.phase == .preparing
                let isSealedSource = current.sourceAdmission == .live && current.phase == .mutationSealed
                let isAdoptedReplay = current.phase == .adopted
                guard isColdPreparation || isSealedSource || isAdoptedReplay else {
                    // A released relation is terminal. Reusing its exact
                    // management ID, or accepting a source before its
                    // mutation cutline, would reopen a forbidden operation.
                    throw ManagementFailure.conflict
                }
                let activation = try setupStore.activation()
                if activation?.activeSetupID == input.request.targetSetupID {
                    let target = try setupStore.managementEvidence(
                        setupID: input.request.targetSetupID, app: input.request.targetApp,
                        expectedDeviceUDID: input.request.expectedDeviceUDID,
                        teamID: input.request.teamID, requireActive: true)
                    try validateAdoptedTarget(current, target: target)
                    _ = try validateHistoricalSource(input: input, record: current,
                                                     setupStore: setupStore, restoreStore: restoreStore)
                    try ensureReceiptCapacity(target.activation,
                                              targetSetupID: input.request.targetSetupID,
                                              allowExistingTargetReplay: true)
                } else {
                    try validateSourceEvidence(input: input, record: current,
                                               setupStore: setupStore, restoreStore: restoreStore)
                }
                try validateGeneration(input, record: current)
                return ManagementPreparedTarget(storeID: storeID, input: input,
                                               managementStore: self,
                                               setupStore: setupStore, restoreStore: restoreStore)
            }
            if let current = state.current {
                guard [.released, .adopted].contains(current.phase) else { throw ManagementFailure.conflict }
            }
            guard !state.history.contains(where: { $0.managementID == input.request.managementID }) else {
                throw ManagementFailure.conflict
            }
            let origin = try lineageOrigin(state, request: input.request)
            let source = try setupStore.managementEvidence(
                setupID: input.request.sourceSetupID, app: input.request.sourceApp,
                expectedDeviceUDID: input.request.expectedDeviceUDID, teamID: input.request.teamID,
                requireActive: true)
            try ensureReceiptCapacity(source.activation, targetSetupID: input.request.targetSetupID)
            guard SetupValidation.sha256(source.rawActivation) == input.request.sourceActivationSHA256 else {
                throw ManagementFailure.identityMismatch
            }
            let transfer = try restoreStore.managementEvidence(
                expectedSetupID: origin.setupID, expectedApp: origin.app,
                expectedDeviceUDID: input.request.expectedDeviceUDID,
                expectedRootSHA256: input.request.sourceRestoreRootSHA256)
            try captureGeneration(input, source: source, transfer: transfer)
            var next = state
            try archiveTerminal(&next)
            next.current = makeRecord(input: input, phase: .preparing, admission: .cold,
                                      currentApp: currentApp, pid: 0)
            try writeState(next)
            return ManagementPreparedTarget(storeID: storeID, input: input,
                                           managementStore: self,
                                           setupStore: setupStore, restoreStore: restoreStore)
        }
    }

    func validateSetupAcceptance(_ prepared: ManagementPreparedTarget,
                                 currentApp: SetupAppIdentity,
                                 setupStore: SetupActivationStore,
                                 restoreStore: TransferRestoreStore) throws {
        try locked {
            guard prepared.storeID == storeID,
                  prepared.managementStore === self,
                  prepared.setupStore === setupStore,
                  prepared.restoreStore === restoreStore else {
                throw ManagementFailure.invalidInput
            }
            let input = try requiredInput()
            guard input.rawRequestSHA256 == prepared.input.rawRequestSHA256,
                  currentApp == input.request.targetApp else {
                throw ManagementFailure.identityMismatch
            }
            let state = try readState()
            guard let record = try currentRecord(state, input: input),
                  (record.sourceAdmission == .cold && record.phase == .preparing) ||
                  (record.sourceAdmission == .live && record.phase == .mutationSealed) ||
                  record.phase == .adopted else {
                throw ManagementFailure.conflict
            }
            try validateIncomingSetupIfPresent(input.request, setupStore: setupStore)
            try validateGeneration(input, record: record)
            let activation = try setupStore.activation()
            if activation?.activeSetupID == input.request.targetSetupID {
                let target = try setupStore.managementEvidence(
                    setupID: input.request.targetSetupID, app: input.request.targetApp,
                    expectedDeviceUDID: input.request.expectedDeviceUDID,
                    teamID: input.request.teamID, requireActive: true)
                try validateAdoptedTarget(record, target: target)
                _ = try validateHistoricalSource(input: input, record: record,
                                                 setupStore: setupStore, restoreStore: restoreStore)
                try ensureReceiptCapacity(target.activation,
                                          targetSetupID: input.request.targetSetupID,
                                          allowExistingTargetReplay: true)
            } else {
                try validateSourceEvidence(input: input, record: record,
                                           setupStore: setupStore, restoreStore: restoreStore)
            }
        }
    }

    public func adoptTarget(_ prepared: ManagementPreparedTarget,
                            currentApp: SetupAppIdentity,
                            setupStore: SetupActivationStore,
                            restoreStore: TransferRestoreStore,
                            preferences: TransferPreferencesStore) throws -> ManagementAdoptionResult {
        try locked {
            guard prepared.storeID == storeID else { throw ManagementFailure.invalidInput }
            let input = prepared.input
            guard currentApp == input.request.targetApp else { throw ManagementFailure.identityMismatch }
            var state = try readState()
            guard var record = try currentRecord(state, input: input) else { throw ManagementFailure.conflict }
            try validateGeneration(input, record: record)
            let target = try setupStore.managementEvidence(
                setupID: input.request.targetSetupID, app: input.request.targetApp,
                expectedDeviceUDID: input.request.expectedDeviceUDID, teamID: input.request.teamID,
                requireActive: true)
            let historical = try validateHistoricalSource(input: input, record: record,
                                                         setupStore: setupStore, restoreStore: restoreStore)
            let savedReceipt = historical.sourceReceipt
            if input.request.kind == .renew {
                guard target.receipt.pairingTransactionID == savedReceipt.pairingTransactionID,
                      target.receipt.pairingSHA256 == savedReceipt.pairingSHA256 else {
                    throw ManagementFailure.identityMismatch
                }
            }
            try ensureReceiptCapacity(target.activation,
                                      targetSetupID: input.request.targetSetupID,
                                      allowExistingTargetReplay: true)
            let transfer = historical.transfer
            if let settings = transfer.settings,
               transfer.projection.transferID != nil,
               try preferences.currentValues().marker != transfer.projection.transferID {
                try preferences.activate(settings: settings, transferID: transfer.projection.transferID!)
            }
            let projection = transfer.projection
            if record.phase == .adopted {
                guard let receipt = record.adoptionReceipt,
                      target.receipt.setupID == receipt.targetSetupID,
                      target.receipt.app == receipt.targetApp,
                      target.receipt.expectedDeviceUDID == receipt.expectedDeviceUDID,
                      target.receipt.teamID == receipt.teamID,
                      SetupValidation.sha256(target.rawActivation) == receipt.targetActivationSHA256 else {
                    throw ManagementFailure.identityMismatch
                }
                return ManagementAdoptionResult(receipt: receipt, projection: projection)
            }
            guard record.phase == .preparing || record.phase == .ready ||
                  record.phase == .mutationSealed else {
                throw ManagementFailure.conflict
            }
            let adoption = try ManagementCodec.makeAdoptionReceipt(
                managementID: input.request.managementID, nonce: input.request.nonce,
                requestSHA256: input.rawRequestSHA256, sourceSetupID: input.request.sourceSetupID,
                targetSetupID: input.request.targetSetupID, sourceApp: input.request.sourceApp,
                targetApp: input.request.targetApp, expectedDeviceUDID: input.request.expectedDeviceUDID,
                teamID: input.request.teamID, sourceActivationSHA256: input.request.sourceActivationSHA256,
                sourceRestoreRootSHA256: input.request.sourceRestoreRootSHA256,
                targetActivationSHA256: SetupValidation.sha256(target.rawActivation))
            record = replace(record, phase: .adopted, currentApp: currentApp, pid: 0,
                             adoptionReceipt: adoption)
            state.current = record
            try writeState(state)
            return ManagementAdoptionResult(receipt: adoption, projection: projection)
        }
    }

    public func reopenAdoptedProjection(currentApp: SetupAppIdentity,
                                        setupStore: SetupActivationStore,
                                        restoreStore: TransferRestoreStore,
                                        preferences: TransferPreferencesStore) throws -> ManagementAdoptionResult? {
        try locked {
            guard let record = try readState().current, record.phase == .adopted,
                  record.currentApp == currentApp, let receipt = record.adoptionReceipt else { return nil }
            let input = try requiredInput()
            guard input.request.managementID == record.managementID,
                  input.rawRequestSHA256 == record.requestSHA256,
                  receipt.managementID == input.request.managementID,
                  receipt.nonce == input.request.nonce,
                  receipt.requestSHA256 == input.rawRequestSHA256,
                  receipt.sourceSetupID == input.request.sourceSetupID,
                  receipt.targetSetupID == input.request.targetSetupID,
                  receipt.sourceApp == input.request.sourceApp,
                  receipt.targetApp == input.request.targetApp,
                  receipt.expectedDeviceUDID == input.request.expectedDeviceUDID,
                  receipt.teamID == input.request.teamID,
                  receipt.sourceActivationSHA256 == input.request.sourceActivationSHA256,
                  receipt.sourceRestoreRootSHA256 == input.request.sourceRestoreRootSHA256 else {
                throw ManagementFailure.identityMismatch
            }
            _ = try ManagementCodec.decodeAdoptionReceipt(
                try ManagementCodec.encodeAdoptionReceipt(receipt))
            guard try setupStore.activation()?.activeSetupID == input.request.targetSetupID else { return nil }
            let target = try setupStore.managementEvidence(
                setupID: input.request.targetSetupID, app: currentApp,
                expectedDeviceUDID: input.request.expectedDeviceUDID, teamID: input.request.teamID,
                requireActive: true)
            guard target.receipt.setupID == receipt.targetSetupID,
                  target.receipt.app == receipt.targetApp,
                  target.receipt.expectedDeviceUDID == receipt.expectedDeviceUDID,
                  target.receipt.teamID == receipt.teamID,
                  SetupValidation.sha256(target.rawActivation) == receipt.targetActivationSHA256 else {
                throw ManagementFailure.identityMismatch
            }
            let origin = try lineageOrigin(try readState(), request: input.request)
            let transfer = try restoreStore.managementEvidence(
                expectedSetupID: origin.setupID, expectedApp: origin.app,
                expectedDeviceUDID: input.request.expectedDeviceUDID,
                expectedRootSHA256: input.request.sourceRestoreRootSHA256)
            if let settings = transfer.settings,
               let transferID = transfer.projection.transferID,
               try preferences.currentValues().marker != transferID {
                try preferences.activate(settings: settings, transferID: transferID)
            }
            return ManagementAdoptionResult(receipt: receipt, projection: transfer.projection)
        }
    }

    /// Reopens the current editable projection while a newer management
    /// request has been released before target mutation. The released
    /// request remains an evidence gate only: it cannot publish an adoption
    /// receipt, seed Session, or replace the fixed response.
    public func releasedSourceProjection(currentApp: SetupAppIdentity,
                                         setupStore: SetupActivationStore,
                                         restoreStore: TransferRestoreStore,
                                         preferences: TransferPreferencesStore) throws -> TransferRuntimeProjection? {
        try locked {
            guard let record = try readState().current,
                  record.phase == .released,
                  record.sourceAdmission == .live,
                  record.currentApp == currentApp else { return nil }
            let input = try requiredInput()
            guard record.managementID == input.request.managementID,
                  record.nonce == input.request.nonce,
                  record.requestSHA256 == input.rawRequestSHA256,
                  record.sourceSetupID == input.request.sourceSetupID,
                  record.targetSetupID == input.request.targetSetupID,
                  record.sourceApp == input.request.sourceApp,
                  record.targetApp == input.request.targetApp,
                  record.expectedDeviceUDID == input.request.expectedDeviceUDID,
                  record.teamID == input.request.teamID,
                  record.sourceActivationSHA256 == input.request.sourceActivationSHA256,
                  record.sourceRestoreRootSHA256 == input.request.sourceRestoreRootSHA256,
                  input.request.sourceApp == currentApp else {
                throw ManagementFailure.identityMismatch
            }
            if try generationExists(for: record.managementID) {
                try validateGeneration(input, record: record)
            }
            let source = try setupStore.managementEvidence(
                setupID: input.request.sourceSetupID, app: input.request.sourceApp,
                expectedDeviceUDID: input.request.expectedDeviceUDID,
                teamID: input.request.teamID, requireActive: true)
            guard SetupValidation.sha256(source.rawActivation) == input.request.sourceActivationSHA256 else {
                throw ManagementFailure.identityMismatch
            }
            let origin = try lineageOrigin(try readState(), request: input.request)
            let transfer = try restoreStore.managementEvidence(
                expectedSetupID: origin.setupID, expectedApp: origin.app,
                expectedDeviceUDID: input.request.expectedDeviceUDID,
                expectedRootSHA256: input.request.sourceRestoreRootSHA256)
            if let settings = transfer.settings,
               let transferID = transfer.projection.transferID,
               try preferences.currentValues().marker != transferID {
                try preferences.activate(settings: settings, transferID: transferID)
            }
            return transfer.projection
        }
    }

    public func status() throws -> ManagementStatus? {
        try locked {
            guard let record = try readState().current else { return nil }
            return ManagementStatus(phase: record.phase, managementID: record.managementID,
                                    requestSHA256: record.requestSHA256, currentApp: record.currentApp,
                                    sourceAdmission: record.sourceAdmission)
        }
    }

    public func isBlocking() throws -> Bool {
        try locked {
            guard let phase = try readState().current?.phase else { return false }
            return [.preparing, .ready, .mutationSealed].contains(phase)
        }
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        do { return try operation() }
        catch let failure as ManagementFailure { throw failure }
        catch let failure as SetupFailure { throw ManagementStorageMapping.setup(failure) }
        catch let failure as TransferFailure { throw ManagementStorageMapping.transfer(failure) }
        catch { throw ManagementFailure.storageUnavailable }
    }

    private func requiredInput() throws -> ManagementInput {
        guard let bytes = try ManagementStorageDisk.read(root.appendingPathComponent("request.json"),
                                                         maximum: ManagementRequest.maximumBytes,
                                                         allowIngress: true) else {
            throw ManagementFailure.unavailable
        }
        return try ManagementInput(data: bytes)
    }

    private func readState() throws -> ManagementRootState {
        guard let data = try ManagementStorageDisk.read(root.appendingPathComponent("root.json"),
                                                        maximum: ManagementStorageDisk.rootMaximum) else {
            return ManagementRootState(current: nil, history: [])
        }
        return try ManagementStorageCodec.decodeRoot(data)
    }

    private func writeState(_ state: ManagementRootState) throws {
        try ManagementStorageDisk.atomicWrite(try ManagementStorageCodec.encodeRoot(state),
                                               to: root.appendingPathComponent("root.json"),
                                               checkpoint: checkpoint)
    }

    private func prepareNewSource(input: ManagementInput, currentApp: ManagementRecord?,
                                  pid: Int32, setupStore: SetupActivationStore,
                                  restoreStore: TransferRestoreStore,
                                  state: ManagementRootState) throws -> ManagementPreparedSource {
        guard currentApp == nil || currentApp!.phase == .released || currentApp!.phase == .adopted else {
            throw ManagementFailure.conflict
        }
        let origin = try lineageOrigin(state, request: input.request)
        let source = try setupStore.managementEvidence(
            setupID: input.request.sourceSetupID, app: input.request.sourceApp,
            expectedDeviceUDID: input.request.expectedDeviceUDID, teamID: input.request.teamID,
            requireActive: true)
        try ensureReceiptCapacity(source.activation, targetSetupID: input.request.targetSetupID)
        guard SetupValidation.sha256(source.rawActivation) == input.request.sourceActivationSHA256 else {
            throw ManagementFailure.identityMismatch
        }
        let transfer = try restoreStore.managementEvidence(
            expectedSetupID: origin.setupID, expectedApp: origin.app,
            expectedDeviceUDID: input.request.expectedDeviceUDID,
            expectedRootSHA256: input.request.sourceRestoreRootSHA256)
        try captureGeneration(input, source: source, transfer: transfer)
        var next = state
        try archiveTerminal(&next)
        next.current = makeRecord(input: input, phase: .preparing, admission: .live,
                                  currentApp: input.request.sourceApp, pid: pid)
        try writeState(next)
        return ManagementPreparedSource(storeID: storeID, input: input,
                                        setupStore: setupStore, restoreStore: restoreStore)
    }

    private func captureGeneration(_ input: ManagementInput,
                                   source: ManagementSetupEvidence,
                                   transfer: ManagementTransferEvidence) throws {
        let generations = root.appendingPathComponent("generations", isDirectory: true)
        var generationsInfo = stat()
        if lstat(generations.path, &generationsInfo) == 0 {
            try ManagementStorageDisk.validateDirectory(generations)
        } else {
            guard errno == ENOENT else { throw ManagementFailure.unsafeFile }
            try ManagementStorageDisk.ensureDirectory(generations)
        }
        let generation = generations.appendingPathComponent(input.request.managementID.uuidString.lowercased(), isDirectory: true)
        var generationInfo = stat()
        if lstat(generation.path, &generationInfo) == 0 {
            throw ManagementFailure.conflict
        }
        guard errno == ENOENT else { throw ManagementFailure.unsafeFile }
        try ManagementStorageDisk.ensureDirectory(generation)
        try ManagementStorageDisk.writeImmutable(input.rawRequest, to: generation.appendingPathComponent("request.json"),
                                                  maximum: ManagementRequest.maximumBytes, checkpoint: checkpoint)
        try ManagementStorageDisk.writeImmutable(source.rawActivation,
                                                  to: generation.appendingPathComponent("source-activation.json"),
                                                  maximum: 256 * 1_024, checkpoint: checkpoint)
        let restoreURL = generation.appendingPathComponent("source-restore-root.json")
        if let rawRoot = transfer.rawRoot {
            try ManagementStorageDisk.writeImmutable(rawRoot, to: restoreURL, maximum: 1_048_576, checkpoint: checkpoint)
        } else if FileManager.default.fileExists(atPath: restoreURL.path) {
            throw ManagementFailure.conflict
        }
    }

    private func generationEvidence(_ input: ManagementInput,
                                    record: ManagementRecord) throws -> (request: Data, activation: Data, restoreRoot: Data?) {
        let generation = root.appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(record.managementID.uuidString.lowercased(), isDirectory: true)
        guard let request = try ManagementStorageDisk.read(generation.appendingPathComponent("request.json"),
                                                           maximum: ManagementRequest.maximumBytes),
              let activation = try ManagementStorageDisk.read(generation.appendingPathComponent("source-activation.json"),
                                                               maximum: 256 * 1_024),
              request == input.rawRequest,
              SetupValidation.sha256(activation) == record.sourceActivationSHA256 else {
            throw ManagementFailure.identityMismatch
        }
        let restore = try ManagementStorageDisk.read(generation.appendingPathComponent("source-restore-root.json"),
                                                     maximum: 1_048_576)
        guard (restore == nil) == (record.sourceRestoreRootSHA256 == nil),
              restore.map(SetupValidation.sha256) == record.sourceRestoreRootSHA256 else {
            throw ManagementFailure.identityMismatch
        }
        return (request, activation, restore)
    }

    private func validateGeneration(_ input: ManagementInput, record: ManagementRecord) throws {
        _ = try generationEvidence(input, record: record)
    }

    private func generationExists(for managementID: UUID) throws -> Bool {
        let generation = root.appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(managementID.uuidString.lowercased(), isDirectory: true)
        var info = stat()
        if lstat(generation.path, &info) == 0 {
            try ManagementStorageDisk.validateDirectory(generation)
            return true
        }
        guard errno == ENOENT else { throw ManagementFailure.unsafeFile }
        return false
    }

    private func validateActualSourceEvidence(input: ManagementInput,
                                              record: ManagementRecord,
                                              setupStore: SetupActivationStore,
                                              restoreStore: TransferRestoreStore,
                                              requireGeneration: Bool) throws {
        let origin = try lineageOrigin(try readState(), request: input.request)
        let source = try setupStore.managementEvidence(
            setupID: input.request.sourceSetupID, app: input.request.sourceApp,
            expectedDeviceUDID: input.request.expectedDeviceUDID,
            teamID: input.request.teamID, requireActive: true)
        guard SetupValidation.sha256(source.rawActivation) == input.request.sourceActivationSHA256 else {
            throw ManagementFailure.identityMismatch
        }
        _ = try restoreStore.managementEvidence(
            expectedSetupID: origin.setupID, expectedApp: origin.app,
            expectedDeviceUDID: input.request.expectedDeviceUDID,
            expectedRootSHA256: input.request.sourceRestoreRootSHA256)
        if requireGeneration { try validateGeneration(input, record: record) }
    }

    private func validateSourceEvidence(input: ManagementInput, record: ManagementRecord,
                                        setupStore: SetupActivationStore,
                                        restoreStore: TransferRestoreStore) throws {
        try validateActualSourceEvidence(input: input, record: record,
                                          setupStore: setupStore, restoreStore: restoreStore,
                                          requireGeneration: true)
        let source = try setupStore.managementEvidence(
            setupID: input.request.sourceSetupID, app: input.request.sourceApp,
            expectedDeviceUDID: input.request.expectedDeviceUDID,
            teamID: input.request.teamID, requireActive: true)
        try ensureReceiptCapacity(source.activation, targetSetupID: input.request.targetSetupID)
    }

    private func validateHistoricalSource(input: ManagementInput,
                                          record: ManagementRecord,
                                          setupStore: SetupActivationStore,
                                          restoreStore: TransferRestoreStore) throws ->
        (sourceReceipt: SetupReceipt, transfer: ManagementTransferEvidence) {
        let generation = try generationEvidence(input, record: record)
        let savedActivation = try SetupCodec.decodeActivation(generation.activation)
        guard savedActivation.activeSetupID == input.request.sourceSetupID,
              let savedReceipt = savedActivation.receipts.first(where: {
                  $0.setupID == input.request.sourceSetupID
              }),
              savedReceipt.app == input.request.sourceApp,
              savedReceipt.expectedDeviceUDID == input.request.expectedDeviceUDID,
              savedReceipt.teamID == input.request.teamID else {
            throw ManagementFailure.identityMismatch
        }
        let presentSource = try setupStore.managementEvidence(
            setupID: input.request.sourceSetupID, app: input.request.sourceApp,
            expectedDeviceUDID: input.request.expectedDeviceUDID,
            teamID: input.request.teamID, requireActive: false)
        guard presentSource.receipt == savedReceipt else {
            throw ManagementFailure.identityMismatch
        }
        let origin = try lineageOrigin(try readState(), request: input.request)
        let transfer = try restoreStore.managementEvidence(
            expectedSetupID: origin.setupID, expectedApp: origin.app,
            expectedDeviceUDID: input.request.expectedDeviceUDID,
            expectedRootSHA256: input.request.sourceRestoreRootSHA256)
        return (savedReceipt, transfer)
    }

    private func validateAdoptedTarget(_ record: ManagementRecord,
                                       target: ManagementSetupEvidence) throws {
        guard record.phase == .adopted else { return }
        guard let receipt = record.adoptionReceipt,
              SetupValidation.sha256(target.rawActivation) == receipt.targetActivationSHA256 else {
            throw ManagementFailure.identityMismatch
        }
    }

    private func ensureReceiptCapacity(_ activation: SetupActivationRecord,
                                       targetSetupID: UUID,
                                       allowExistingTargetReplay: Bool = false) throws {
        if activation.receipts.count < SetupActivationRecord.maximumReceipts { return }
        guard activation.receipts.count == SetupActivationRecord.maximumReceipts,
              allowExistingTargetReplay,
              activation.activeSetupID == targetSetupID,
              activation.receipts.contains(where: { $0.setupID == targetSetupID }) else {
            throw ManagementFailure.receiptCapacity
        }
    }

    private func validateIncomingSetupIfPresent(_ request: ManagementRequest,
                                                setupStore: SetupActivationStore) throws {
        guard let incoming = try setupStore.readInput() else { return }
        let manifest = incoming.manifest
        guard manifest.expectedDeviceUDID == request.expectedDeviceUDID,
              manifest.teamID == request.teamID else {
            throw ManagementFailure.identityMismatch
        }
        if manifest.setupID == request.sourceSetupID {
            // A source input can still be present while the target gate is
            // being opened. It is evidence of the old setup only and never
            // authorizes the target generation.
            guard manifest.app == request.sourceApp else {
                throw ManagementFailure.identityMismatch
            }
            return
        }
        guard manifest.setupID == request.targetSetupID,
              manifest.app == request.targetApp else {
            throw ManagementFailure.identityMismatch
        }
        if request.kind != .repair {
            let source = try setupStore.managementEvidence(
                setupID: request.sourceSetupID, app: request.sourceApp,
                expectedDeviceUDID: request.expectedDeviceUDID,
                teamID: request.teamID, requireActive: false)
            guard manifest.pairingTransactionID == source.receipt.pairingTransactionID,
                  manifest.pairingSHA256 == source.receipt.pairingSHA256 else {
                throw ManagementFailure.identityMismatch
            }
        }
    }

    private func validatePersistedAdoptedRecord(_ record: ManagementRecord) throws {
        guard record.phase == .adopted, let adoption = record.adoptionReceipt else {
            throw ManagementFailure.conflict
        }
        let generation = root.appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(record.managementID.uuidString.lowercased(), isDirectory: true)
        guard let requestData = try ManagementStorageDisk.read(
                generation.appendingPathComponent("request.json"), maximum: ManagementRequest.maximumBytes) else {
            throw ManagementFailure.identityMismatch
        }
        let savedInput = try ManagementInput(data: requestData)
        guard savedInput.rawRequestSHA256 == record.requestSHA256,
              savedInput.request.managementID == record.managementID,
              savedInput.request.nonce == record.nonce,
              savedInput.request.sourceSetupID == record.sourceSetupID,
              savedInput.request.targetSetupID == record.targetSetupID,
              savedInput.request.sourceApp == record.sourceApp,
              savedInput.request.targetApp == record.targetApp,
              savedInput.request.expectedDeviceUDID == record.expectedDeviceUDID,
              savedInput.request.teamID == record.teamID,
              savedInput.request.sourceActivationSHA256 == record.sourceActivationSHA256,
              savedInput.request.sourceRestoreRootSHA256 == record.sourceRestoreRootSHA256 else {
            throw ManagementFailure.identityMismatch
        }
        let evidence = try generationEvidence(savedInput, record: record)
        let activation = try SetupCodec.decodeActivation(evidence.activation)
        guard activation.activeSetupID == record.sourceSetupID,
              let sourceReceipt = activation.receipts.first(where: { $0.setupID == record.sourceSetupID }),
              sourceReceipt.app == record.sourceApp,
              sourceReceipt.expectedDeviceUDID == record.expectedDeviceUDID,
              sourceReceipt.teamID == record.teamID else {
            throw ManagementFailure.identityMismatch
        }
        guard adoption.managementID == record.managementID,
              adoption.nonce == record.nonce,
              adoption.requestSHA256 == record.requestSHA256,
              adoption.sourceSetupID == record.sourceSetupID,
              adoption.targetSetupID == record.targetSetupID,
              adoption.sourceApp == record.sourceApp,
              adoption.targetApp == record.targetApp,
              adoption.expectedDeviceUDID == record.expectedDeviceUDID,
              adoption.teamID == record.teamID,
              adoption.sourceActivationSHA256 == record.sourceActivationSHA256,
              adoption.sourceRestoreRootSHA256 == record.sourceRestoreRootSHA256 else {
            throw ManagementFailure.identityMismatch
        }
        _ = try ManagementCodec.decodeAdoptionReceipt(
            try ManagementCodec.encodeAdoptionReceipt(adoption))
    }

    private func currentRecord(_ state: ManagementRootState, input: ManagementInput) throws -> ManagementRecord? {
        guard let record = state.current else { return nil }
        guard record.managementID == input.request.managementID,
              record.requestSHA256 == input.rawRequestSHA256 else { throw ManagementFailure.conflict }
        return record
    }

    private func makeRecord(input: ManagementInput, phase: ManagementStatusPhase,
                            admission: ManagementSourceAdmission,
                            currentApp: SetupAppIdentity, pid: Int32,
                            adoptionReceipt: ManagementAdoptionReceipt? = nil) -> ManagementRecord {
        ManagementRecord(managementID: input.request.managementID, nonce: input.request.nonce,
                         requestSHA256: input.rawRequestSHA256, phase: phase,
                         sourceAdmission: admission, currentApp: currentApp, pid: pid,
                         sourceSetupID: input.request.sourceSetupID, targetSetupID: input.request.targetSetupID,
                         sourceApp: input.request.sourceApp, targetApp: input.request.targetApp,
                         expectedDeviceUDID: input.request.expectedDeviceUDID, teamID: input.request.teamID,
                         sourceActivationSHA256: input.request.sourceActivationSHA256,
                         sourceRestoreRootSHA256: input.request.sourceRestoreRootSHA256,
                         adoptionReceipt: adoptionReceipt)
    }

    private func replace(_ record: ManagementRecord, phase: ManagementStatusPhase,
                         currentApp: SetupAppIdentity, pid: Int32,
                         adoptionReceipt: ManagementAdoptionReceipt? = nil) -> ManagementRecord {
        ManagementRecord(managementID: record.managementID, nonce: record.nonce,
                         requestSHA256: record.requestSHA256, phase: phase,
                         sourceAdmission: record.sourceAdmission, currentApp: currentApp, pid: pid,
                         sourceSetupID: record.sourceSetupID, targetSetupID: record.targetSetupID,
                         sourceApp: record.sourceApp, targetApp: record.targetApp,
                         expectedDeviceUDID: record.expectedDeviceUDID, teamID: record.teamID,
                         sourceActivationSHA256: record.sourceActivationSHA256,
                         sourceRestoreRootSHA256: record.sourceRestoreRootSHA256,
                         adoptionReceipt: adoptionReceipt ?? record.adoptionReceipt)
    }

    private func sourceReceipt(_ record: ManagementRecord) throws -> ManagementSourceReceipt {
        guard record.sourceAdmission == .live, record.phase != .adopted,
              let phase = ManagementSourcePhase(rawValue: record.phase.rawValue),
              record.pid > 0 else { throw ManagementFailure.conflict }
        return try ManagementSourceReceipt(
            managementID: record.managementID, nonce: record.nonce,
            requestSHA256: record.requestSHA256, phase: phase, pid: record.pid,
            app: record.sourceApp, sourceSetupID: record.sourceSetupID,
            activationSHA256: record.sourceActivationSHA256,
            restoreRootSHA256: record.sourceRestoreRootSHA256)
    }

    private func archiveTerminal(_ state: inout ManagementRootState) throws {
        guard let current = state.current else { return }
        guard [.released, .adopted].contains(current.phase) else { throw ManagementFailure.conflict }
        guard state.history.count < 128 else { throw ManagementFailure.conflict }
        state.history.append(current)
        state.current = nil
    }

    private func lineageOrigin(_ state: ManagementRootState,
                               request: ManagementRequest) throws -> (setupID: UUID, app: SetupAppIdentity) {
        let records = state.history + (state.current.map { [$0] } ?? [])
        guard !records.contains(where: {
            $0.targetSetupID == request.targetSetupID && $0.managementID != request.managementID
        }) else { throw ManagementFailure.conflict }
        let links = records.filter { $0.phase == .adopted }
        var targetIDs = Set<UUID>()
        for relation in links {
            guard targetIDs.insert(relation.targetSetupID).inserted else {
                throw ManagementFailure.conflict
            }
            try validatePersistedAdoptedRecord(relation)
        }
        var currentSetup = request.sourceSetupID
        var currentApp = request.sourceApp
        var seenManagement: Set<UUID> = []
        var seenSetup: Set<UUID> = []
        while true {
            guard seenSetup.insert(currentSetup).inserted else { throw ManagementFailure.conflict }
            let matching = links.filter { $0.targetSetupID == currentSetup }
            guard matching.count <= 1 else { throw ManagementFailure.conflict }
            guard let relation = matching.first else {
                guard !records.contains(where: {
                    $0.targetSetupID == currentSetup && $0.phase != .adopted
                }) else { throw ManagementFailure.conflict }
                break
            }
            guard relation.targetApp == currentApp,
                  relation.expectedDeviceUDID == request.expectedDeviceUDID,
                  relation.teamID == request.teamID,
                  relation.sourceRestoreRootSHA256 == request.sourceRestoreRootSHA256 else {
                throw ManagementFailure.identityMismatch
            }
            guard seenManagement.insert(relation.managementID).inserted else { throw ManagementFailure.conflict }
            currentSetup = relation.sourceSetupID
            currentApp = relation.sourceApp
            guard seenManagement.count <= 128 else { throw ManagementFailure.limitExceeded }
        }
        return (currentSetup, currentApp)
    }
}
