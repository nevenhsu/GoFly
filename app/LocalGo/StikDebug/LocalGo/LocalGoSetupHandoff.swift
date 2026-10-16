//
//  LocalGoSetupHandoff.swift
//  LocalGo
//
//  A one-shot, private handoff from the macOS USB setup helper.  The helper
//  writes incoming.plist only while this app is terminated.  LocalGo consumes
//  it after launch, once its command engine is idle.
//

import Foundation

/// Coordinates the private macOS-to-iOS setup handoff.
public final class LocalGoSetupHandoff {
    public typealias Importer = (_ pairingFile: Data, _ expectedDeviceUDID: String) throws -> Void

    public enum Outcome: Equatable, Sendable {
        case noPayload
        case imported
        case rejected
        case storageFailure
    }

    fileprivate enum Failure: Swift.Error {
        case storage
        case oversize
    }

    public static let directoryName = "LocalGoSetup"
    public static let incomingFileName = "incoming.plist"
    public static let readyFileName = "ready.plist"
    public static let receiptsDirectoryName = "receipts"

    private let directory: URL
    private let fileManager: FileManager
    private let importer: Importer

    /// Creates a testable handoff with an explicitly scoped directory.
    public init(
        directory: URL,
        fileManager: FileManager = .default,
        importSetupData: @escaping Importer
    ) {
        self.directory = directory.standardizedFileURL
        self.fileManager = fileManager
        self.importer = importSetupData
    }

    /// Label-compatible spelling for callers that refer to the injected
    /// operation simply as an importer.
    public convenience init(
        directory: URL,
        fileManager: FileManager = .default,
        importer: @escaping Importer
    ) {
        self.init(directory: directory, fileManager: fileManager, importSetupData: importer)
    }

    /// Convenience initializer for the app's private Application Support
    /// directory.
    public convenience init(
        fileManager: FileManager = .default,
        importSetupData: @escaping Importer
    ) {
        self.init(
            directory: Self.defaultDirectory(fileManager: fileManager),
            fileManager: fileManager,
            importSetupData: importSetupData
        )
    }

    public convenience init(
        fileManager: FileManager = .default,
        importer: @escaping Importer
    ) {
        self.init(fileManager: fileManager, importSetupData: importer)
    }

    /// Prepares the protected directory and ready marker at app startup.
    @discardableResult
    public func prepare() throws -> URL {
        try Self.prepare(directory: directory, fileManager: fileManager)
    }

    /// Consumes one incoming payload. Callers pass the live engine state so a
    /// handoff cannot replace a pairing record while a device command is in
    /// flight or another setup operation is running.
    public func consume(commandsIdle: Bool = true, isPreparing: Bool = false) -> Outcome {
        guard commandsIdle, !isPreparing else { return .storageFailure }

        let incoming = directory.appendingPathComponent(Self.incomingFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: incoming.path) else { return .noPayload }

        guard isRegularFile(incoming, fileManager: fileManager) else {
            return finish(.rejected, incoming: incoming)
        }

        let incomingData: Data
        do {
            incomingData = try boundedRead(
                incoming,
                maximumBytes: LocalGoSetupProtocol.maximumIncomingFileBytes,
                fileManager: fileManager
            )
        } catch Failure.oversize {
            return finish(.rejected, incoming: incoming)
        } catch {
            return finish(.storageFailure, incoming: incoming)
        }

        let payload: LocalGoSetupProtocol.IncomingPayload
        do {
            payload = try LocalGoSetupProtocol.decodeIncoming(incomingData)
        } catch {
            return finish(.rejected, incoming: incoming)
        }

        do {
            try ensureProtectedDirectory(directory, fileManager: fileManager)
            let receipts = try receiptFiles(fileManager: fileManager)
            let receiptURL = receiptURL(for: payload.transactionID)

            if fileManager.fileExists(atPath: receiptURL.path) {
                guard isRegularFile(receiptURL, fileManager: fileManager) else {
                    return finish(.storageFailure, incoming: incoming)
                }
                // A replay is terminal. Replace even a successful receipt with
                // a rejected one so a macOS producer cannot treat the replay
                // as a successful transaction after reading the receipt.
                _ = try LocalGoSetupProtocol.decodeReceipt(
                    try boundedRead(receiptURL, maximumBytes: 64 * 1024, fileManager: fileManager)
                )
                try writeReceipt(
                    LocalGoSetupProtocol.Receipt(
                        transactionID: payload.transactionID,
                        status: .rejected
                    ),
                    to: receiptURL
                )
                return finish(.rejected, incoming: incoming)
            }

            guard receipts.count < LocalGoSetupProtocol.maximumReceiptCount else {
                // Do not prune old receipts to make room. At capacity the
                // safe result is a generic storage failure with no import.
                return finish(.storageFailure, incoming: incoming)
            }

            do {
                try importer(payload.pairingFile, payload.expectedDeviceUDID)
            } catch {
                // Do not leave a rejected payload queued for another launch.
                // The rejected receipt is committed only after cleanup has
                // succeeded, so a cleanup failure remains retryable.
                do {
                    try removeIncoming(incoming)
                    try writeReceipt(
                        LocalGoSetupProtocol.Receipt(
                            transactionID: payload.transactionID,
                            status: .rejected
                        ),
                        to: receiptURL
                    )
                    return .rejected
                } catch {
                    return .storageFailure
                }
            }

            // The import has committed in the store. Remove the one-shot
            // request before publishing a success receipt; otherwise a crash
            // could leave a successful receipt beside a replayable payload.
            do {
                try removeIncoming(incoming)
                try writeReceipt(
                    LocalGoSetupProtocol.Receipt(
                        transactionID: payload.transactionID,
                        status: .success
                    ),
                    to: receiptURL
                )
                // The import has already committed in the store. A receipt
                // failure is therefore reported as unknown storage state,
                // never as a claim that the old pairing remains active.
                return .imported
            } catch {
                return .storageFailure
            }
        } catch Failure.oversize {
            return finish(.rejected, incoming: incoming)
        } catch {
            return finish(.storageFailure, incoming: incoming)
        }
    }

    /// Creates or repairs the private setup directory and its ready marker.
    /// The returned URL is the directory that the macOS helper may use for
    /// its terminated-app handoff.
    @discardableResult
    public static func prepare(
        fileManager: FileManager = .default
    ) throws -> URL {
        try prepare(directory: defaultDirectory(fileManager: fileManager), fileManager: fileManager)
    }

    @discardableResult
    public static func prepare(
        directory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = directory.standardizedFileURL
        let receipts = directory.appendingPathComponent(receiptsDirectoryName, isDirectory: true)
        try ensureProtectedDirectory(directory, fileManager: fileManager)
        try ensureProtectedDirectory(receipts, fileManager: fileManager)

        let readyObject: [String: Any] = [
            "version": LocalGoSetupProtocol.version,
            "status": "ready"
        ]
        let readyData = try PropertyListSerialization.data(
            fromPropertyList: readyObject,
            format: .binary,
            options: 0
        )
        try writeMetadataAtomically(
            readyData,
            to: directory.appendingPathComponent(readyFileName, isDirectory: false),
            fileManager: fileManager
        )
        return directory
    }

    /// Static convenience form used by the app lifecycle. An explicit
    /// directory keeps the same method usable by deterministic core tests.
    public static func consume(
        directory: URL,
        commandsIdle: Bool = true,
        isPreparing: Bool = false,
        fileManager: FileManager = .default,
        importSetupData: @escaping Importer
    ) -> Outcome {
        let handoff = Self(
            directory: directory,
            fileManager: fileManager,
            importSetupData: importSetupData
        )
        return handoff.consume(commandsIdle: commandsIdle, isPreparing: isPreparing)
    }

    public static func consume(
        directory: URL,
        commandsIdle: Bool = true,
        isPreparing: Bool = false,
        fileManager: FileManager = .default,
        importer: @escaping Importer
    ) -> Outcome {
        consume(
            directory: directory,
            commandsIdle: commandsIdle,
            isPreparing: isPreparing,
            fileManager: fileManager,
            importSetupData: importer
        )
    }

    /// Static default-directory form used by the app lifecycle.
    public static func consume(
        commandsIdle: Bool = true,
        isPreparing: Bool = false,
        fileManager: FileManager = .default,
        importSetupData: @escaping Importer
    ) -> Outcome {
        let handoff = Self(fileManager: fileManager, importSetupData: importSetupData)
        return handoff.consume(commandsIdle: commandsIdle, isPreparing: isPreparing)
    }

    public static func consume(
        commandsIdle: Bool = true,
        isPreparing: Bool = false,
        fileManager: FileManager = .default,
        importer: @escaping Importer
    ) -> Outcome {
        consume(
            commandsIdle: commandsIdle,
            isPreparing: isPreparing,
            fileManager: fileManager,
            importSetupData: importer
        )
    }

    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private var receiptsDirectory: URL {
        directory.appendingPathComponent(Self.receiptsDirectoryName, isDirectory: true)
    }

    private func receiptURL(for transactionID: UUID) -> URL {
        receiptsDirectory.appendingPathComponent(
            transactionID.uuidString.lowercased() + ".plist",
            isDirectory: false
        )
    }

    private func receiptFiles(fileManager: FileManager) throws -> [URL] {
        guard isDirectory(receiptsDirectory, fileManager: fileManager) else {
            throw Failure.storage
        }
        try removeStaleMetadataTemps(in: receiptsDirectory, fileManager: fileManager)
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: receiptsDirectory,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
                options: []
            )
        } catch {
            throw Failure.storage
        }

        var result: [URL] = []
        result.reserveCapacity(entries.count)
        for entry in entries {
            guard entry.pathExtension == "plist",
                  isCanonicalReceiptFilename(entry.deletingPathExtension().lastPathComponent),
                  isRegularFile(entry, fileManager: fileManager) else {
                throw Failure.storage
            }
            let receipt: LocalGoSetupProtocol.Receipt
            do {
                receipt = try LocalGoSetupProtocol.decodeReceipt(
                    try boundedRead(entry, maximumBytes: 64 * 1024, fileManager: fileManager)
                )
            } catch {
                throw Failure.storage
            }
            guard entry.deletingPathExtension().lastPathComponent
                == receipt.transactionID.uuidString.lowercased() else {
                throw Failure.storage
            }
            result.append(entry)
        }
        return result
    }

    private func writeReceipt(
        _ receipt: LocalGoSetupProtocol.Receipt,
        to destination: URL
    ) throws {
        guard isDirectory(receiptsDirectory, fileManager: fileManager) else {
            throw Failure.storage
        }
        if fileManager.fileExists(atPath: destination.path),
           !isRegularFile(destination, fileManager: fileManager) {
            throw Failure.storage
        }
        let data: Data
        do {
            data = try LocalGoSetupProtocol.encodeReceipt(receipt)
        } catch {
            throw Failure.storage
        }
        try writeMetadataAtomically(data, to: destination, fileManager: fileManager)
    }

    /// Completes a terminal path by deleting the one-shot request before
    /// returning. This is intentionally explicit rather than a `defer`: Swift
    /// evaluates a return value before running deferred statements, so a
    /// deferred mutation cannot surface cleanup failure to the caller.
    private func finish(_ outcome: Outcome, incoming: URL) -> Outcome {
        do {
            try removeIncoming(incoming)
            return outcome
        } catch {
            return .storageFailure
        }
    }

    private func removeIncoming(_ incoming: URL) throws {
        guard fileManager.fileExists(atPath: incoming.path) else { return }
        do {
            try fileManager.removeItem(at: incoming)
        } catch {
            throw Failure.storage
        }
        guard !fileManager.fileExists(atPath: incoming.path) else {
            throw Failure.storage
        }
    }
}

private func isCanonicalReceiptFilename(_ value: String) -> Bool {
    guard value.utf8.count == 36,
          let uuid = UUID(uuidString: value) else { return false }
    return uuid.uuidString.lowercased() == value
}

private func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
    guard !isSymbolicLink(url, fileManager: fileManager),
          let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let type = attributes[.type] as? FileAttributeType else { return false }
    return type == .typeDirectory
}

private func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
    guard !isSymbolicLink(url, fileManager: fileManager),
          let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let type = attributes[.type] as? FileAttributeType else { return false }
    return type == .typeRegular
}

private func isSymbolicLink(_ url: URL, fileManager: FileManager) -> Bool {
    if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
       let type = attributes[.type] as? FileAttributeType,
       type == .typeSymbolicLink {
        return true
    }
    if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
       values.isSymbolicLink == true {
        return true
    }
    return false
}

private func ensureProtectedDirectory(_ directory: URL, fileManager: FileManager) throws {
    if fileManager.fileExists(atPath: directory.path) {
        guard isDirectory(directory, fileManager: fileManager) else { throw LocalGoSetupHandoff.Failure.storage }
    } else {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw LocalGoSetupHandoff.Failure.storage
        }
    }

    do {
        try fileManager.setAttributes(
            [
                .posixPermissions: NSNumber(value: 0o700),
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ],
            ofItemAtPath: directory.path
        )
        var protected = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        guard let attributes = try? fileManager.attributesOfItem(atPath: directory.path),
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              permissions & 0o777 == 0o700 else {
            throw LocalGoSetupHandoff.Failure.storage
        }
    } catch let error as LocalGoSetupHandoff.Failure {
        throw error
    } catch {
        throw LocalGoSetupHandoff.Failure.storage
    }
}

private func writeMetadataAtomically(
    _ data: Data,
    to destination: URL,
    fileManager: FileManager
) throws {
    let parent = destination.deletingLastPathComponent()
    guard isDirectory(parent, fileManager: fileManager) else {
        throw LocalGoSetupHandoff.Failure.storage
    }
    let temporary = parent.appendingPathComponent(".metadata-\(UUID().uuidString).tmp", isDirectory: false)
    do {
        try data.write(to: temporary, options: [])
        try protectMetadataFile(temporary, fileManager: fileManager)

        if fileManager.fileExists(atPath: destination.path) {
            guard isRegularFile(destination, fileManager: fileManager) else {
                throw LocalGoSetupHandoff.Failure.storage
            }
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: temporary,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    } catch let error as LocalGoSetupHandoff.Failure {
        try? fileManager.removeItem(at: temporary)
        throw error
    } catch {
        try? fileManager.removeItem(at: temporary)
        throw LocalGoSetupHandoff.Failure.storage
    }
}

private func removeStaleMetadataTemps(in directory: URL, fileManager: FileManager) throws {
    let entries: [URL]
    do {
        entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
            options: []
        )
    } catch {
        throw LocalGoSetupHandoff.Failure.storage
    }

    for entry in entries
        where isMetadataTempFilename(entry.lastPathComponent) {
        // Only remove regular, non-symlink files that match the exact temp
        // naming scheme owned by this handoff. Unknown files remain for the
        // strict receipt scan to reject rather than being silently deleted.
        guard isRegularFile(entry, fileManager: fileManager) else { continue }
        do {
            try fileManager.removeItem(at: entry)
        } catch {
            throw LocalGoSetupHandoff.Failure.storage
        }
    }
}

private func isMetadataTempFilename(_ value: String) -> Bool {
    guard value.hasPrefix(".metadata-"), value.hasSuffix(".tmp") else { return false }
    let start = value.index(value.startIndex, offsetBy: ".metadata-".count)
    let end = value.index(value.endIndex, offsetBy: -".tmp".count)
    let uuidString = String(value[start..<end])
    guard uuidString.utf8.count == 36,
          let uuid = UUID(uuidString: uuidString) else { return false }
    return uuid.uuidString.caseInsensitiveCompare(uuidString) == .orderedSame
}

private func protectMetadataFile(_ file: URL, fileManager: FileManager) throws {
    do {
        try fileManager.setAttributes(
            [
                .posixPermissions: NSNumber(value: 0o600),
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ],
            ofItemAtPath: file.path
        )
        var protected = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              permissions & 0o777 == 0o600 else {
            throw LocalGoSetupHandoff.Failure.storage
        }
    } catch let error as LocalGoSetupHandoff.Failure {
        throw error
    } catch {
        throw LocalGoSetupHandoff.Failure.storage
    }
}

private func boundedRead(
    _ url: URL,
    maximumBytes: Int,
    fileManager: FileManager
) throws -> Data {
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let type = attributes[.type] as? FileAttributeType,
          type == .typeRegular else {
        throw LocalGoSetupHandoff.Failure.storage
    }
    if let size = (attributes[.size] as? NSNumber)?.intValue,
       size > maximumBytes {
        throw LocalGoSetupHandoff.Failure.oversize
    }

    let handle: FileHandle
    do {
        handle = try FileHandle(forReadingFrom: url)
    } catch {
        throw LocalGoSetupHandoff.Failure.storage
    }
    defer { try? handle.close() }

    do {
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        if data.count > maximumBytes {
            throw LocalGoSetupHandoff.Failure.oversize
        }
        return data
    } catch let error as LocalGoSetupHandoff.Failure {
        throw error
    } catch {
        throw LocalGoSetupHandoff.Failure.storage
    }
}
