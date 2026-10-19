import Combine
import CryptoKit
import Darwin
import Foundation
import GoFlyCore
import SwiftUI

enum GoFlySetupBootstrapPhase: Equatable {
    case preparing
    case ordinaryStartup
    case waitingForMac(SetupReadbackRequest)
    case completed(SetupReceipt)
    case blocked(SetupFailure)
    case exportLocked(TransferExportReceipt)
    case restoreLocked(TransferRestoreStatus)
    case transferWaiting(GoFlyTransferWaitReason)
    case transferBlocked(TransferFailure)
    case managementWaiting
    case managementLocked(ManagementStatus)
    case managementBlocked(ManagementFailure)
}

enum GoFlyTransferWaitReason: String, Equatable, Sendable {
    case setup
    case restore
    case export
}

struct GoFlySetupMetadata: Equatable, Sendable {
    let teamID: String
    let signingExpiry: String

    init(receipt: SetupReceipt) {
        teamID = receipt.teamID
        signingExpiry = receipt.signingExpiry
    }
}

/// Process-local generation for the active-scene mailbox observer.  The
/// observer task can be cancelled while an unstructured physical transfer is
/// draining, so cancellation is kept separate from that transfer task.
final class GoFlyMacCommandObservation: @unchecked Sendable {
    let id = UUID()
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Owns only the formal setup check until it has produced an ordinary or
/// completed result. The normal runtime assembly is retained exactly once and
/// is created on the main actor only after that result.
@MainActor
final class GoFlySetupBootstrap: ObservableObject {
    @Published private(set) var phase: GoFlySetupBootstrapPhase = .preparing
    private(set) var runtime: GoFlyRuntimeAssembly?
    private(set) var metadata: GoFlySetupMetadata?

    var startupTask: Task<Void, Never>?
    var transferTask: Task<Void, Never>?
    var transferTaskID: UUID?
    var activeDataLease: GoFlyDataLease?
    var completedManagementControl: ManagementControlCommand?
    var completedTransferControl: TransferControlInput?
    var commandObservation: GoFlyMacCommandObservation?
    var preferManagementCommand = true

    init() {
        start()
    }

    deinit {
        startupTask?.cancel()
        transferTask?.cancel()
    }

    func retry() {
        guard case .blocked = phase else { return }
        start()
    }

    private func start() {
        startupTask?.cancel()
        // A retry is only available from a blocked state, which cannot have
        // constructed normal owners. Keeping these references here also makes
        // an in-flight export lock independent of SwiftUI view reconstruction.
        if case .blocked = phase {
            runtime = nil
            metadata = nil
        }
        phase = .preparing

        #if targetEnvironment(simulator)
        let requiresMacSetup = false
        #else
        let requiresMacSetup = (Bundle.main.object(forInfoDictionaryKey: "GoFlyRequiresMacSetup") as? Bool) == true
        #endif

        let preferencesStore = GoFlyPreferences.shared.transferStore()
        startupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                do {
                    guard let support = FileManager.default.urls(
                        for: .applicationSupportDirectory, in: .userDomainMask
                    ).first else { return GoFlyBootstrapOutcome.transferBlocked(.storageUnavailable) }
                    let managementStore = ManagementStore(applicationSupport: support)
                    try managementStore.prepareIncomingFiles()
                    let managementInput = try managementStore.readInput()
                    let managementStatus = try managementStore.status()
                    let exportStore = TransferExportStore(applicationSupport: support)
                    let restoreStore = TransferRestoreStore(applicationSupport: support)
                    try exportStore.prepareIncomingFiles()
                    try restoreStore.prepareIncomingFiles()
                    if let receipt = try exportStore.readExport(),
                       [.preparing, .ready, .removalSealed].contains(receipt.phase) {
                        return GoFlyBootstrapOutcome.exportLocked(receipt)
                    }
                    let directory = try GoFlySetupPaths.directory()
                    let store = SetupActivationStore(directory: directory)
                    try store.prepareIncomingFiles()
                    let intent = try restoreStore.readIntent()
                    var managementTarget: ManagementPreparedTarget?
                    var preservedProjection: TransferRuntimeProjection?
                    if let managementInput {
                        let request = managementInput.request
                        let current = try GoFlySetupIdentityReader.read()
                        let formalInput = try store.readInput()
                        let readback = try store.readReadbackRequest()
                        let activation = try store.activation()
                        let targetMetadata = formalInput?.manifest.setupID == request.targetSetupID ||
                            readback?.setupID == request.targetSetupID ||
                            activation?.activeSetupID == request.targetSetupID
                        let sameOperation = managementStatus?.managementID == request.managementID &&
                            managementStatus?.requestSHA256 == managementInput.rawRequestSHA256
                        let currentRestore = intent?.targetApp == current &&
                            (intent?.setupID == activation?.activeSetupID ||
                             intent?.setupID == formalInput?.manifest.setupID)
                        if sameOperation, managementStatus?.sourceAdmission == .live,
                           !targetMetadata, activation?.activeSetupID == request.sourceSetupID,
                           !(managementStatus?.phase == .released && currentRestore) {
                            // Re-emit only the persisted source PID/phase after
                            // a crash. This is historical data, never a fresh
                            // source admission for this newly launched process.
                            _ = try managementStore.replaySourceReadback(
                                currentApp: current, setupStore: store, restoreStore: restoreStore)
                        }
                        if targetMetadata, !(sameOperation && managementStatus?.phase == .adopted) {
                            guard current == request.targetApp else {
                                return GoFlyBootstrapOutcome.managementBlocked(.identityMismatch)
                            }
                            // Capture/recheck the exact predecessor before any
                            // pairing consumption or formal setup commit. There
                            // is no await between this gate and prepare below.
                            managementTarget = try managementStore.prepareTarget(
                                currentApp: current, setupStore: store, restoreStore: restoreStore)
                        } else if sameOperation, managementStatus?.phase == .adopted {
                            if !currentRestore {
                                preservedProjection = try managementStore.writeAdoptionReadback(
                                    currentApp: current, setupStore: store, restoreStore: restoreStore,
                                    preferences: preferencesStore)?.projection
                            }
                        } else if sameOperation, managementStatus?.phase == .released {
                            if !currentRestore {
                                preservedProjection = try managementStore.releasedSourceProjection(
                                    currentApp: current, setupStore: store, restoreStore: restoreStore,
                                    preferences: preferencesStore)
                            }
                        } else {
                            if let managementStatus {
                                return GoFlyBootstrapOutcome.managementLocked(managementStatus)
                            }
                            return GoFlyBootstrapOutcome.managementWaiting
                        }
                    } else if let managementStatus,
                              [.preparing, .ready, .mutationSealed].contains(managementStatus.phase) {
                        return GoFlyBootstrapOutcome.managementBlocked(.conflict)
                    }
                    let coordinator = SetupBootstrapCoordinator(
                        store: store,
                        pairing: GoFlySetupPairingAdapter()
                    )
                    let setup = try coordinator.prepare(identity: GoFlySetupIdentityReader.read,
                                                        management: managementTarget)
                    if requiresMacSetup, case .ordinaryStartup = setup {
                        return GoFlyBootstrapOutcome.transferWaiting(.setup)
                    }
                    if intent != nil, case .ordinaryStartup = setup {
                        return GoFlyBootstrapOutcome.transferWaiting(.setup)
                    }
                    switch setup {
                    case .ordinaryStartup:
                        let projection = try restoreStore.currentProjection()
                        return GoFlyBootstrapOutcome.ordinary(projection)
                    case .waitingForMac(let request):
                        return GoFlyBootstrapOutcome.waitingForMac(request)
                    case .blocked(let failure):
                        return GoFlyBootstrapOutcome.blocked(failure)
                    case .completed(let receipt):
                        if let managementTarget {
                            let result = try managementStore.adoptTarget(
                                managementTarget, currentApp: receipt.app, setupStore: store,
                                restoreStore: restoreStore, preferences: preferencesStore)
                            _ = try managementStore.writeAdoptionReadback(
                                currentApp: receipt.app, setupStore: store, restoreStore: restoreStore,
                                preferences: preferencesStore)
                            return GoFlyBootstrapOutcome.completed(receipt, result.projection)
                        }
                        if let preservedProjection {
                            return GoFlyBootstrapOutcome.completed(receipt, preservedProjection)
                        }
                        guard intent != nil else {
                            let projection = try restoreStore.currentProjection()
                            return GoFlyBootstrapOutcome.completed(receipt, projection)
                        }
                        do {
                            let status = try restoreStore.restore(
                                currentApp: receipt.app, setupStore: store, preferences: preferencesStore
                            )
                            guard status.phase == .committed,
                                  let projection = status.projection else {
                                return GoFlyBootstrapOutcome.transferWaiting(.restore)
                            }
                            return GoFlyBootstrapOutcome.restoreLocked(receipt, status, projection)
                        } catch let failure as TransferFailure {
                            switch failure {
                            case .unavailable:
                                if let status = try? restoreStore.status() {
                                    return GoFlyBootstrapOutcome.restoreWaiting(status)
                                }
                                return GoFlyBootstrapOutcome.transferWaiting(.restore)
                            default: return GoFlyBootstrapOutcome.transferBlocked(failure)
                            }
                        }
                    }
                } catch let failure as ManagementFailure {
                    return GoFlyBootstrapOutcome.managementBlocked(failure)
                } catch let failure as SetupFailure {
                    return GoFlyBootstrapOutcome.blocked(failure)
                } catch let failure as TransferFailure {
                    return GoFlyBootstrapOutcome.transferBlocked(failure)
                } catch {
                    return GoFlyBootstrapOutcome.blocked(.storageUnavailable)
                }
            }.value

            guard !Task.isCancelled else { return }
            self?.apply(result)
        }
    }

    private func apply(_ result: GoFlyBootstrapOutcome) {
        switch result {
        case .ordinary(let projection):
            runtime = GoFlyRuntimeAssembly(projection: projection)
            phase = .ordinaryStartup
        case .completed(let receipt, let projection):
            GoFlyPreferences.shared.refreshPersistedValues()
            runtime = GoFlyRuntimeAssembly(projection: projection)
            metadata = GoFlySetupMetadata(receipt: receipt)
            phase = .completed(receipt)
        case .waitingForMac(let request):
            phase = .waitingForMac(request)
        case .blocked(let failure):
            phase = .blocked(failure)
        case .exportLocked(let receipt):
            phase = .exportLocked(receipt)
        case .restoreLocked(let receipt, _, let projection):
            GoFlyPreferences.shared.refreshPersistedValues()
            runtime = GoFlyRuntimeAssembly(projection: projection)
            metadata = GoFlySetupMetadata(receipt: receipt)
            phase = .completed(receipt)
        case .restoreWaiting(let status):
            phase = .restoreLocked(status)
        case .transferWaiting(let reason):
            phase = .transferWaiting(reason)
        case .transferBlocked(let failure):
            phase = .transferBlocked(failure)
        case .managementWaiting:
            phase = .managementWaiting
        case .managementLocked(let status):
            phase = .managementLocked(status)
        case .managementBlocked(let failure):
            phase = .managementBlocked(failure)
        }
    }

    func setTransferPhase(_ value: GoFlySetupBootstrapPhase) {
        phase = value
    }

    func transferDidFinish(_ id: UUID) {
        guard transferTaskID == id else { return }
        transferTask = nil
        transferTaskID = nil
    }

    func invalidateMacCommandObservation() {
        commandObservation?.cancel()
    }

    func commandObservationIsCurrent(_ token: GoFlyMacCommandObservation?) -> Bool {
        guard let token else { return true }
        return commandObservation?.id == token.id && !token.isCancelled
    }

    func restartAfterTransfer() {
        start()
    }
}

extension GoFlySetupBootstrapPhase {
    var isManagementLocked: Bool {
        switch self {
        case .managementWaiting, .managementLocked, .managementBlocked: return true
        default: return false
        }
    }

    var isTransferLocked: Bool {
        switch self {
        case .exportLocked, .restoreLocked, .transferWaiting, .transferBlocked,
             .managementWaiting, .managementLocked, .managementBlocked: return true
        default: return false
        }
    }
}

private enum GoFlyBootstrapOutcome: Sendable {
    case ordinary(TransferRuntimeProjection)
    case completed(SetupReceipt, TransferRuntimeProjection)
    case waitingForMac(SetupReadbackRequest)
    case blocked(SetupFailure)
    case exportLocked(TransferExportReceipt)
    case restoreLocked(SetupReceipt, TransferRestoreStatus, TransferRuntimeProjection)
    case restoreWaiting(TransferRestoreStatus)
    case transferWaiting(GoFlyTransferWaitReason)
    case transferBlocked(TransferFailure)
    case managementWaiting
    case managementLocked(ManagementStatus)
    case managementBlocked(ManagementFailure)
}

enum GoFlySetupIdentityReader {
    static func read() throws -> SetupAppIdentity {
        guard let bundleID = Bundle.main.bundleIdentifier,
              bundleID == SetupAppIdentity.formalBundleID,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty,
              let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let executable = Bundle.main.executableURL else {
            throw SetupFailure.identityMismatch
        }

        return try SetupAppIdentity(
            bundleID: bundleID,
            build: build,
            profileSHA256: try SHA256FileHasher.hex(profile, maximumBytes: 4 * 1_024 * 1_024),
            executableSHA256: try SHA256FileHasher.hex(executable, maximumBytes: 256 * 1_024 * 1_024)
        )
    }
}

private enum SHA256FileHasher {
    static func hex(_ url: URL, maximumBytes: Int) throws -> String {
        let fd = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else { throw SetupFailure.identityMismatch }
        defer { Darwin.close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size >= 0,
              info.st_size <= maximumBytes else {
            throw SetupFailure.identityMismatch
        }

        var digest = SHA256()
        var total = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(fd, $0.baseAddress, $0.count)
            }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw SetupFailure.identityMismatch }
            if count == 0 { break }
            total += count
            guard total <= maximumBytes else { throw SetupFailure.limitExceeded }
            digest.update(data: Data(buffer.prefix(count)))
        }
        guard total == Int(info.st_size) else { throw SetupFailure.identityMismatch }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Bridges the frozen v1 handoff to the existing protected pairing store. All
/// observations are bounded and no-follow; LocalGoSetupHandoff remains the
/// single importer and receipt writer.
private struct GoFlySetupPairingAdapter: SetupPairingAccess {
    private let handoffDirectory: URL

    init(fileManager: FileManager = .default) {
        handoffDirectory = LocalGoSetupHandoff.defaultDirectory(fileManager: fileManager)
    }

    func prepare() throws {
        _ = try LocalGoSetupHandoff.prepare(directory: handoffDirectory)
        try Self.sealIncomingFile(in: handoffDirectory)
        _ = PairingFileStore.prepareURL()
    }

    func observeStoredPairing(expectedDeviceUDID: String) throws -> SetupPairingObservation {
        let rawURL = PairingFileStore.url
        guard try Self.present(rawURL) || Self.present(
            rawURL.deletingLastPathComponent().appendingPathComponent("pairingFile.envelope.plist")
        ) else {
            return .absent
        }
        guard PairingFileStore.verifyStoredRecord(expectedDeviceUDID: expectedDeviceUDID),
              let data = try Self.read(rawURL, maximum: 1 * 1_024 * 1_024) else {
            return .invalid
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return .verified(expectedDeviceUDID: expectedDeviceUDID.lowercased(), sha256: hash)
    }

    func observe(for input: SetupInput) throws -> SetupPairingEvidence {
        let stored = try observeStoredPairing(expectedDeviceUDID: input.manifest.expectedDeviceUDID)
        let inputObservation = try observeInput(for: input)
        let receiptObservation = try observeReceipt(for: input.manifest.pairingTransactionID)
        return SetupPairingEvidence(stored: stored, input: inputObservation, receipt: receiptObservation)
    }

    func consumeExactPending(for input: SetupInput) throws {
        guard try observeInput(for: input) == .exact,
              try observeReceipt(for: input.manifest.pairingTransactionID) == .absent else {
            throw SetupFailure.pairingRejected
        }

        let expectedDeviceUDID = input.manifest.expectedDeviceUDID
        let expectedPairingSHA256 = input.manifest.pairingSHA256
        let handoff = LocalGoSetupHandoff(directory: handoffDirectory) { pairingData, receivedDeviceUDID in
            guard receivedDeviceUDID.lowercased() == expectedDeviceUDID,
                  Self.hex(Data(SHA256.hash(data: pairingData))) == expectedPairingSHA256 else {
                throw SetupFailure.pairingRejected
            }
            if PairingFileStore.verifyStoredRecord(expectedDeviceUDID: expectedDeviceUDID),
               let existing = try? Self.read(PairingFileStore.url, maximum: LocalGoSetupProtocol.maximumPairingFileBytes),
               SHA256.hash(data: existing) == SHA256.hash(data: pairingData) {
                return
            }
            try PairingFileStore.importSetupData(pairingData, expectedDeviceUDID: receivedDeviceUDID)
        }

        switch handoff.consume(
            commandsIdle: true,
            isPreparing: false,
            expectedTransactionID: input.manifest.pairingTransactionID
        ) {
        case .imported: return
        case .rejected: throw SetupFailure.pairingRejected
        case .storageFailure: throw SetupFailure.storageUnavailable
        case .noPayload: throw SetupFailure.pairingUnknown
        }
    }

    private func observeInput(for input: SetupInput) throws -> SetupV1InputObservation {
        guard let data = try Self.read(
            handoffDirectory.appendingPathComponent(LocalGoSetupHandoff.incomingFileName),
            maximum: LocalGoSetupProtocol.maximumIncomingFileBytes
        ) else { return .absent }

        guard let payload = try? LocalGoSetupProtocol.decodeIncoming(data),
              payload.transactionID == input.manifest.pairingTransactionID,
              payload.expectedDeviceUDID == input.manifest.expectedDeviceUDID,
              Self.hex(payload.sha256) == input.manifest.pairingSHA256 else {
            return .malformedOrMismatched
        }
        return .exact
    }

    private func observeReceipt(for transactionID: UUID) throws -> SetupV1ReceiptObservation {
        let receiptsDirectory = handoffDirectory.appendingPathComponent(LocalGoSetupHandoff.receiptsDirectoryName)
        guard try Self.present(receiptsDirectory) else { return .absent }
        guard Self.isPrivateDirectory(receiptsDirectory) else { throw SetupFailure.unsafeFile }

        let entries = try Self.directoryEntries(
            receiptsDirectory,
            maximum: LocalGoSetupProtocol.maximumReceiptCount
        )

        var found: LocalGoSetupProtocol.Receipt?
        var seenTransactions = Set<UUID>()
        for entry in entries {
            guard entry.pathExtension == "plist",
                  let name = entry.deletingPathExtension().lastPathComponent.lowercased() as String?,
                  UUID(uuidString: name)?.uuidString.lowercased() == name,
                  let data = try Self.read(entry, maximum: 64 * 1_024) else {
                throw SetupFailure.pairingRejected
            }
            guard let receipt = try? LocalGoSetupProtocol.decodeReceipt(data),
                  receipt.transactionID.uuidString.lowercased() == name else {
                throw SetupFailure.pairingRejected
            }
            guard seenTransactions.insert(receipt.transactionID).inserted else {
                throw SetupFailure.pairingRejected
            }
            if receipt.transactionID == transactionID { found = receipt }
        }

        guard let found else { return .absent }
        return found.status == .success ? .success : .rejectedOrMalformed
    }

    private static func present(_ url: URL) throws -> Bool {
        var info = stat()
        guard url.path.withCString({ lstat($0, &info) }) == 0 else {
            if errno == ENOENT { return false }
            throw SetupFailure.storageUnavailable
        }
        return true
    }

    private static func isPrivateDirectory(_ url: URL) -> Bool {
        let fd = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var info = stat()
        return fstat(fd, &info) == 0 &&
            info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
            info.st_uid == geteuid() && info.st_mode & mode_t(0o7777) == mode_t(0o700)
    }

    /// AFC cannot set permissions on the incoming handoff. Seal only that
    /// fixed file after the existing handoff prepares its private root; the
    /// bytes, replay state, and receipts remain owned by LocalGo's consumer.
    private static func sealIncomingFile(in directory: URL) throws {
        let root = directory.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard root >= 0 else { throw SetupFailure.storageUnavailable }
        defer { Darwin.close(root) }

        var rootInfo = stat()
        guard fstat(root, &rootInfo) == 0,
              rootInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              rootInfo.st_uid == geteuid(),
              rootInfo.st_mode & mode_t(0o7777) == mode_t(0o700) else {
            throw SetupFailure.unsafeFile
        }

        let incoming = LocalGoSetupHandoff.incomingFileName
        let fd = incoming.withCString {
            openat(root, $0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else {
            if errno == ENOENT { return }
            throw SetupFailure.storageUnavailable
        }
        defer { Darwin.close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == geteuid(),
              info.st_nlink == 1,
              info.st_size > 0,
              info.st_size <= LocalGoSetupProtocol.maximumIncomingFileBytes else {
            throw SetupFailure.unsafeFile
        }
        let permissions = info.st_mode & mode_t(0o7777)
        guard permissions == mode_t(0o600) || permissions == mode_t(0o644) else {
            throw SetupFailure.unsafeFile
        }
        guard fchmod(fd, mode_t(0o600)) == 0,
              fsync(fd) == 0 else {
            throw SetupFailure.storageUnavailable
        }
    }

    private static func directoryEntries(_ url: URL, maximum: Int) throws -> [URL] {
        let fd = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw SetupFailure.storageUnavailable }
        guard let stream = fdopendir(fd) else {
            Darwin.close(fd)
            throw SetupFailure.storageUnavailable
        }
        defer { closedir(stream) }

        var names: [String] = []
        names.reserveCapacity(min(maximum, 32))
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }
            names.append(name)
            guard names.count <= maximum else { throw SetupFailure.limitExceeded }
            errno = 0
        }
        guard errno == 0 else { throw SetupFailure.storageUnavailable }
        return names.map { url.appendingPathComponent($0, isDirectory: false) }
    }

    private static func read(_ url: URL, maximum: Int) throws -> Data? {
        let fd = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw SetupFailure.storageUnavailable
        }
        defer { Darwin.close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == geteuid(),
              info.st_mode & mode_t(0o7777) == mode_t(0o600),
              info.st_nlink == 1,
              info.st_size >= 0,
              info.st_size <= maximum else { throw SetupFailure.unsafeFile }

        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw SetupFailure.storageUnavailable }
            if count == 0 {
                guard data.count == Int(info.st_size) else { throw SetupFailure.storageUnavailable }
                return data
            }
            guard data.count + count <= maximum else { throw SetupFailure.limitExceeded }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

struct GoFlySetupLockView: View {
    let phase: GoFlySetupBootstrapPhase
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: iconName)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(GoFlyStyle.primary)
                    .accessibilityHidden(true)
                Text(goFlyString(titleKey))
                    .font(.title2.weight(.semibold))
                Text(goFlyString(messageKey))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if case .blocked = phase {
                    Button(action: onRetry) {
                        Text(goFlyString("setup.retry"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(GoFlyActionStyle(primary: true))
                    .accessibilityIdentifier("setup.retry")
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .background(GoFlyStyle.canvas.ignoresSafeArea())
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var titleKey: String {
        switch phase {
        case .preparing: return "setup.preparing.title"
        case .ordinaryStartup: return "setup.preparing.title"
        case .waitingForMac: return "setup.waiting.title"
        case .completed: return "setup.completed.title"
        case .blocked: return "setup.blocked.title"
        case .exportLocked, .restoreLocked, .transferWaiting: return "setup.transfer.title"
        case .transferBlocked: return "setup.blocked.title"
        case .managementWaiting, .managementLocked, .managementBlocked: return "setup.management.title"
        }
    }

    private var messageKey: String {
        switch phase {
        case .preparing: return "setup.preparing.message"
        case .ordinaryStartup: return "setup.preparing.message"
        case .waitingForMac: return "setup.waiting.message"
        case .completed: return "setup.completed.message"
        case .blocked(let failure): return failure.messageKey
        case .exportLocked, .restoreLocked, .transferWaiting: return "setup.transfer.message"
        case .transferBlocked: return "setup.blocked.storage"
        case .managementWaiting, .managementLocked, .managementBlocked: return "setup.management.message"
        }
    }

    private var iconName: String {
        switch phase {
        case .blocked: return GoFlySymbols.locked
        case .waitingForMac: return "desktopcomputer"
        case .exportLocked, .restoreLocked, .transferWaiting: return GoFlySymbols.locked
        default: return "checkmark.shield"
        }
    }

    private var accessibilityIdentifier: String {
        switch phase {
        case .preparing: return "setup.preparing"
        case .ordinaryStartup, .completed: return "setup.ready"
        case .waitingForMac: return "setup.waiting"
        case .blocked: return "setup.blocked"
        case .exportLocked, .restoreLocked, .transferWaiting: return "setup.transfer"
        case .transferBlocked: return "setup.blocked"
        case .managementWaiting, .managementLocked, .managementBlocked: return "setup.management"
        }
    }
}

private extension SetupFailure {
    var messageKey: String {
        switch self {
        case .identityMismatch: return "setup.blocked.identity"
        case .pairingUnknown, .pairingRejected: return "setup.blocked.pairing"
        case .artifactMismatch: return "setup.blocked.artifact"
        case .invalidInput, .unsupportedVersion: return "setup.blocked.input"
        default: return "setup.blocked.storage"
        }
    }
}
