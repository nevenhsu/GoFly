import Darwin
import Foundation
import GoFlyCore

/// Resolves the fixed private setup directory used by the future bootstrap
/// coordinator. Resolution has no filesystem side effects.
enum GoFlySetupPaths {
    static let directoryName = "GoFlySetup"

    static func directory(fileManager: FileManager = .default) throws -> URL {
        guard let support = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            throw GoFlySetupFixtureError.storageUnavailable
        }

        var directory = support.appendingPathComponent(directoryName, isDirectory: true)
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-gofly-ui-setup-store") {
            guard arguments.indices.contains(index + 1),
                  let namespace = UUID(uuidString: arguments[index + 1]) else {
                throw GoFlySetupFixtureError.invalidNamespace
            }
            directory = support.appendingPathComponent("UITests/GoFlySetup", isDirectory: true)
                .appendingPathComponent(namespace.uuidString, isDirectory: true)
        }
        #endif
        return directory
    }
}

/// Seeds only the requested, file-backed negative states in the Debug
/// simulator. It never creates setup files during ordinary startup.
enum GoFlySetupFixture {
    static func seedIfRequested() {
        #if DEBUG && targetEnvironment(simulator)
        do {
            guard let fixture = try fixtureArgument() else { return }
            try seed(fixture)
        } catch {
            // A requested fixture is test setup. Do not swallow an IO or
            // validation failure and make the UI appear to have passed.
            preconditionFailure("GoFly setup fixture failed: \(error)")
        }
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private static func fixtureArgument() throws -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-gofly-ui-setup-fixture") else { return nil }
        guard arguments.indices.contains(index + 1),
              !arguments[index + 1].hasPrefix("-") else {
            throw GoFlySetupFixtureError.missingFixtureArgument
        }
        return arguments[index + 1]
    }

    private static func seed(_ fixture: String) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard let storeIndex = arguments.firstIndex(of: "-gofly-ui-setup-store"),
              arguments.indices.contains(storeIndex + 1),
              UUID(uuidString: arguments[storeIndex + 1]) != nil else {
            throw GoFlySetupFixtureError.invalidNamespace
        }
        let directory = try GoFlySetupPaths.directory()
        switch fixture {
        case "malformed-input":
            // Valid JSON with an invalid setup schema. The Core reader must
            // reject it as actual incoming.json content.
            try writeIfAbsent(
                Data(#"{"version":99}"#.utf8),
                to: directory,
                name: "incoming.json"
            )
        case "request-without-profile":
            let request = try makeRequest()
            try writeIfAbsent(request.encoded(), to: directory, name: "readback-request.json")
        default:
            throw GoFlySetupFixtureError.unsupportedFixture
        }
    }

    private static func makeRequest() throws -> SetupReadbackRequest {
        let buildValue = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
        let build: String
        if let value = buildValue as? String, !value.isEmpty {
            build = value
        } else if let value = buildValue as? NSNumber, !value.stringValue.isEmpty {
            build = value.stringValue
        } else {
            throw GoFlySetupFixtureError.bundleBuildUnavailable
        }

        let app = try SetupAppIdentity(
            bundleID: SetupAppIdentity.formalBundleID,
            build: build,
            profileSHA256: String(repeating: "0", count: 64),
            executableSHA256: String(repeating: "1", count: 64)
        )
        return try SetupReadbackRequest(
            setupID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            nonce: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            expectedDeviceUDID: "00000000-0000000000000000",
            app: app
        )
    }

    private static func writeIfAbsent(_ data: Data, to directory: URL, name: String) throws {
        guard data.count <= 64 * 1_024 else { throw GoFlySetupFixtureError.tooLarge }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        } catch {
            throw GoFlySetupFixtureError.storageUnavailable
        }

        let parent = directory.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard parent >= 0 else { throw GoFlySetupFixtureError.storageUnavailable }
        defer { Darwin.close(parent) }
        try validatePrivateDirectory(parent)

        let file = name.withCString {
            openat(
                parent, $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard file >= 0 else {
            if errno == EEXIST {
                var existing = stat()
                let result = name.withCString {
                    fstatat(parent, $0, &existing, AT_SYMLINK_NOFOLLOW)
                }
                guard result == 0 else { throw GoFlySetupFixtureError.unsafeFile }
                try validatePrivateFile(existing)
                return
            }
            throw GoFlySetupFixtureError.storageUnavailable
        }

        var committed = false
        defer {
            Darwin.close(file)
            if !committed {
                _ = name.withCString { unlinkat(parent, $0, 0) }
            }
        }

        guard fchmod(file, mode_t(0o600)) == 0 else {
            throw GoFlySetupFixtureError.storageUnavailable
        }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw GoFlySetupFixtureError.storageUnavailable }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(file, base.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw GoFlySetupFixtureError.storageUnavailable }
                offset += count
            }
        }
        guard Darwin.fsync(file) == 0, Darwin.fsync(parent) == 0 else {
            throw GoFlySetupFixtureError.storageUnavailable
        }
        committed = true
    }

    private static func validatePrivateDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == geteuid(),
              info.st_mode & mode_t(0o7777) == mode_t(0o700),
              info.st_nlink >= 2 else {
            throw GoFlySetupFixtureError.unsafeFile
        }
    }

    private static func validatePrivateFile(_ info: stat) throws {
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == geteuid(),
              info.st_mode & mode_t(0o7777) == mode_t(0o600),
              info.st_nlink == 1,
              info.st_size >= 0 else {
            throw GoFlySetupFixtureError.unsafeFile
        }
    }
    #endif
}

enum GoFlySetupFixtureError: Error, CustomStringConvertible {
    case invalidNamespace
    case missingFixtureArgument
    case unsupportedFixture
    case bundleBuildUnavailable
    case tooLarge
    case unsafeFile
    case storageUnavailable

    var description: String {
        switch self {
        case .invalidNamespace: return "invalid setup store namespace"
        case .missingFixtureArgument: return "setup fixture argument is missing"
        case .unsupportedFixture: return "unsupported setup fixture"
        case .bundleBuildUnavailable: return "actual app bundle build is unavailable"
        case .tooLarge: return "setup fixture exceeds its bounded size"
        case .unsafeFile: return "setup fixture directory is unsafe"
        case .storageUnavailable: return "setup fixture storage is unavailable"
        }
    }
}
