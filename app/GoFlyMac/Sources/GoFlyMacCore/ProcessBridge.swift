import Foundation
import Darwin

public struct BridgeConfiguration: Codable, Sendable {
    public let workspaceRoot: String
    public let pythonPath: String
    public let developerDirectory: String
    public let projectPath: String
    public let targetBundleID: String
    public let targetName: String

    init(verifiedData data: Data) throws {
        guard !data.isEmpty, data.count <= 32_768 else { throw CheckFailure.unavailable }
        let object = try SetupWireJSON.object(data)
        guard Set(object.keys) == ["workspaceRoot", "pythonPath", "developerDirectory", "projectPath", "targetBundleID", "targetName"] else {
            throw CheckFailure.unavailable
        }
        self = try JSONDecoder().decode(Self.self, from: data)
        let root = URL(fileURLWithPath: workspaceRoot).standardizedFileURL
        let formal = targetBundleID == "com.neven.gofly" && targetName == "GoFly" &&
            projectPath == root.appendingPathComponent("app/GoFly/GoFly.xcodeproj").path
        guard workspaceRoot.hasPrefix("/"), root.path == workspaceRoot,
              !workspaceRoot.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              pythonPath == root.appendingPathComponent("work/mac-setup-env/bin/python").path, formal,
              developerDirectory == "/Applications/Xcode.app/Contents/Developer" else { throw CheckFailure.unavailable }
    }
}

public struct MacSetupConfiguration: Decodable, Sendable {
    public let workspaceRoot: String
    public let pythonPath: String
    public let developerDirectory: String
    public let projectPath: String
    public let targetBundleID: String
    public let targetName: String
    public let stateRoot: String

    init(verifiedData data: Data) throws {
        guard !data.isEmpty, data.count <= 32_768 else { throw MacSetupFailure.invalidRequest }
        let object = try SetupWireJSON.object(data)
        guard Set(object.keys) == ["workspaceRoot", "pythonPath", "developerDirectory", "projectPath",
                                   "targetBundleID", "targetName", "stateRoot"] else {
            throw MacSetupFailure.invalidRequest
        }
        self = try JSONDecoder().decode(Self.self, from: data)
        try Self.validate(self, failure: MacSetupFailure.invalidRequest)
    }

    public init(configurationURL: URL) throws {
        do {
            guard configurationURL.isFileURL else { throw MacSetupFailure.invalidRequest }
            let file = open(configurationURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard file >= 0 else { throw MacSetupFailure.invalidRequest }
            defer { close(file) }
            var info = stat()
            guard fstat(file, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  info.st_size > 0, info.st_size <= 32_768 else { throw MacSetupFailure.invalidRequest }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
                if count < 0, errno == EINTR { continue }
                guard count >= 0, data.count + count <= 32_768 else { throw MacSetupFailure.invalidRequest }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            guard data.count == info.st_size else { throw MacSetupFailure.invalidRequest }
            let object = try SetupWireJSON.object(data)
            guard Set(object.keys) == ["workspaceRoot", "pythonPath", "developerDirectory", "projectPath",
                                       "targetBundleID", "targetName", "stateRoot"] else {
                throw MacSetupFailure.invalidRequest
            }
            self = try JSONDecoder().decode(Self.self, from: data)
            try Self.validate(self, failure: MacSetupFailure.invalidRequest)
        } catch { throw MacSetupFailure.invalidRequest }
    }

    static func validate(_ value: MacSetupConfiguration, failure: MacSetupFailure) throws {
        let workspace = URL(fileURLWithPath: value.workspaceRoot).standardizedFileURL
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoFlySetup").path
        guard value.workspaceRoot.hasPrefix("/"), workspace.path == value.workspaceRoot,
              !value.workspaceRoot.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              value.pythonPath == workspace.appendingPathComponent("work/mac-setup-env/bin/python").path,
              value.projectPath == workspace.appendingPathComponent("app/GoFly/GoFly.xcodeproj").path,
              value.developerDirectory == "/Applications/Xcode.app/Contents/Developer",
              value.targetBundleID == "com.neven.gofly", value.targetName == "GoFly",
              value.stateRoot == support else { throw failure }
    }
}

/// One bounded Python process boundary for both read-only checks and setup.
public struct ProcessBridge: MacChecking, MacSetupRunning {
    private enum Role { case readOnly, setup }
    private let role: Role
    private let configurationURL: URL
    private let scriptURL: URL
    private let pythonPath: String
    private let developerDirectory: String
    private let bundleResources: MacBundleResources
    private let initialResourceStamp: MacBundleResourceStamp

    public init(configurationURL: URL, scriptURL: URL) throws {
        guard let resources = Bundle.main.resourceURL,
              configurationURL.isFileURL, scriptURL.isFileURL,
              scriptURL.standardizedFileURL == resources.appendingPathComponent("Bridge/bridge.py").standardizedFileURL,
              (try? scriptURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map({
                  $0.isRegularFile == true && $0.isSymbolicLink != true
              }) == true else { throw CheckFailure.bundleInvalid }
        let setup = configurationURL.standardizedFileURL == resources.appendingPathComponent("SetupConfiguration.json").standardizedFileURL
        let readOnly = configurationURL.standardizedFileURL == resources.appendingPathComponent("LocalConfiguration.json").standardizedFileURL
        guard setup || readOnly else { throw CheckFailure.bundleInvalid }
        let resourcesBundle: MacBundleResources
        let stamp: MacBundleResourceStamp
        do {
            resourcesBundle = try MacBundleResources(bundleURL: Bundle.main.bundleURL)
            stamp = try resourcesBundle.stamp()
        } catch { throw CheckFailure.bundleInvalid }
        if setup {
            let config: MacSetupConfiguration
            do {
                config = try MacSetupConfiguration(verifiedData: resourcesBundle.read(.setupConfiguration))
                try MacSetupConfiguration.validate(config, failure: MacSetupFailure.unavailable)
            } catch { throw CheckFailure.bundleInvalid }
            guard FileManager.default.isExecutableFile(atPath: config.pythonPath) else {
                throw CheckFailure.pythonUnavailable
            }
            guard FileManager.default.fileExists(atPath: config.projectPath) else {
                throw CheckFailure.unavailable
            }
            self.init(role: .setup, configurationURL: configurationURL, scriptURL: scriptURL,
                      pythonPath: config.pythonPath, developerDirectory: config.developerDirectory,
                      bundleResources: resourcesBundle, initialResourceStamp: stamp)
        } else {
            let config: BridgeConfiguration
            do { config = try BridgeConfiguration(verifiedData: resourcesBundle.read(.localConfiguration)) }
            catch { throw CheckFailure.bundleInvalid }
            guard FileManager.default.isExecutableFile(atPath: config.pythonPath) else {
                throw CheckFailure.pythonUnavailable
            }
            self.init(role: .readOnly, configurationURL: configurationURL, scriptURL: scriptURL,
                      pythonPath: config.pythonPath, developerDirectory: config.developerDirectory,
                      bundleResources: resourcesBundle, initialResourceStamp: stamp)
        }
    }

    private init(role: Role, configurationURL: URL, scriptURL: URL, pythonPath: String,
                 developerDirectory: String, bundleResources: MacBundleResources,
                 initialResourceStamp: MacBundleResourceStamp) {
        self.role = role
        self.configurationURL = configurationURL
        self.scriptURL = scriptURL
        self.pythonPath = pythonPath
        self.developerDirectory = developerDirectory
        self.bundleResources = bundleResources
        self.initialResourceStamp = initialResourceStamp
    }

    public func check(_ request: CheckRequest) async throws -> Data {
        guard role == .readOnly else { throw CheckFailure.unavailable }
        let input = try JSONEncoder().encode(request)
        guard input.count <= 32_768 else { throw CheckFailure.invalidResponse }
        do { try bundleResources.revalidate() } catch { throw CheckFailure.unavailable }
        let runner = BoundedProcess()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached {
                try runner.run(executable: self.pythonPath,
                               arguments: ["-I", self.scriptURL.path, "--config", self.configurationURL.path],
                               developerDirectory: self.developerDirectory, input: input,
                               timeout: request.action == .inspect ? 100 : 45)
            }.value
        } onCancel: { runner.cancel(reason: .cancelled) }
    }

    public func run(_ request: MacSetupRequest) async throws -> Data {
        guard role == .setup else { throw MacSetupFailure.unavailable }
        let input = try JSONEncoder().encode(request)
        guard input.count <= 32_768 else { throw MacSetupFailure.invalidRequest }
        do { try bundleResources.revalidate() } catch { throw MacSetupFailure.unavailable }
        let process = BoundedProcess()
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await Task.detached {
                    try process.run(executable: self.pythonPath,
                                    arguments: ["-I", self.scriptURL.path, "--config", self.configurationURL.path],
                                    developerDirectory: self.developerDirectory, input: input,
                                    timeout: request.action == .status ? 30 : request.action == .preflight ? 120 : 1_800)
                }.value
            } onCancel: { process.cancel(reason: .cancelled) }
        } catch let error as CheckFailure {
            switch error {
            case .cancelled: throw MacSetupFailure.cancelled
            case .timeout: throw MacSetupFailure.timeout
            case .unavailable: throw MacSetupFailure.unavailable
            default: throw MacSetupFailure.invalidResponse
            }
        } catch is CancellationError { throw MacSetupFailure.cancelled }
    }
}

public struct BridgeStatusJournalReader: MacSetupJournalReading {
    private let runner: any MacSetupRunning

    public init(runner: any MacSetupRunning) { self.runner = runner }

    public func readContinuation() async throws -> MacSetupContinuation? {
        let request = try MacSetupRequest(action: .status)
        do {
            let data = try await runner.run(request)
            let root = try SetupWireJSON.object(data)
            if root["status"] as? String == "error" {
                guard root["action"] as? String == "status",
                      let rawID = root["requestID"] as? String,
                      UUID(uuidString: rawID) == request.requestID,
                      root["code"] as? String == "transaction-unknown" else {
                    throw MacSetupFailure.invalidResponse
                }
                return nil
            }
            guard root["status"] as? String == "ok",
                  let rawID = root["setupID"] as? String, let id = UUID(uuidString: rawID),
                  let device = root["deviceID"] as? String else {
                throw MacSetupFailure.invalidResponse
            }
            let mode: MacSetupMode
            if let rawMode = root["mode"] as? String {
                guard let parsed = MacSetupMode(rawValue: rawMode) else {
                    throw MacSetupFailure.invalidResponse
                }
                mode = parsed
            } else {
                // Older journals predate the mode header.  They are installs.
                mode = .install
            }
            if let payload = root["payload"] as? [String: Any],
               payload["stage"] as? String == "complete",
               payload["outcome"] as? String == "confirmed" {
                // A completed journal has nothing to resume and must never lock
                // the app.  Its result remains available through the producer.
                return nil
            }
            return try MacSetupContinuation(setupID: id, deviceID: device, mode: mode)
        } catch MacSetupFailure.service("transaction-unknown") {
            return nil
        } catch let error as MacSetupFailure {
            throw error
        } catch {
            throw MacSetupFailure.invalidResponse
        }
    }
}

public struct UnavailableChecker: MacChecking, MacSetupRunning {
    public let reason: CheckFailure
    public init(reason: CheckFailure = .unavailable) { self.reason = reason }
    public func check(_ request: CheckRequest) async throws -> Data { throw reason }
    public func run(_ request: MacSetupRequest) async throws -> Data { throw MacSetupFailure.unavailable }
}

/// Owns one child. No shell, no logs, bounded output, and group termination on cancellation.
public final class BoundedProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var failure: CheckFailure?
    private var finished = false

    public init() {}

    public func cancel(reason: CheckFailure) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if failure == nil { failure = reason }
        let child = process
        lock.unlock()
        guard let child else { return }
        let pid = child.processIdentifier
        kill(-pid, SIGTERM)
        if child.isRunning { kill(pid, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            self.lock.lock()
            let active = !self.finished
            self.lock.unlock()
            if active { kill(-pid, SIGKILL); if child.isRunning { kill(pid, SIGKILL) } }
        }
    }

    public func run(executable: String, arguments: [String], developerDirectory: String, input: Data,
                    timeout: TimeInterval) throws -> Data {
        let child = Process()
        let output = Pipe()
        let stdin = Pipe()
        let diagnostics = Pipe()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
                             "DEVELOPER_DIR": developerDirectory, "PYTHONDONTWRITEBYTECODE": "1"]
        child.standardInput = stdin
        child.standardOutput = output
        child.standardError = diagnostics
        lock.lock()
        if let failure { lock.unlock(); throw failure }
        guard !finished, process == nil else { lock.unlock(); throw CheckFailure.unavailable }
        process = child
        do { try child.run() } catch { finished = true; lock.unlock(); throw CheckFailure.unavailable }
        lock.unlock()
        let deadline = DispatchWorkItem { self.cancel(reason: .timeout) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer {
            deadline.cancel()
            lock.lock(); finished = true; process = nil; lock.unlock()
            try? output.fileHandleForReading.close()
            try? stdin.fileHandleForWriting.close()
            try? diagnostics.fileHandleForReading.close()
        }
        let streams = DispatchGroup()
        streams.enter()
        DispatchQueue.global().async {
            defer { streams.leave() }
            var size = 0
            while true {
                let chunk = diagnostics.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                guard size <= 65_536 - chunk.count else { self.cancel(reason: .invalidResponse); break }
                size += chunk.count
            }
        }
        streams.enter()
        DispatchQueue.global().async {
            defer { streams.leave() }
            do {
                try stdin.fileHandleForWriting.write(contentsOf: input)
                try stdin.fileHandleForWriting.close()
            } catch { self.cancel(reason: .invalidResponse) }
        }
        var data = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            guard data.count + chunk.count <= 262_144 else { cancel(reason: .invalidResponse); break }
            data.append(chunk)
        }
        child.waitUntilExit()
        streams.wait()
        lock.lock(); let finalFailure = failure; lock.unlock()
        if let finalFailure { throw finalFailure }
        guard !data.isEmpty else { throw CheckFailure.invalidResponse }
        return data
    }
}
