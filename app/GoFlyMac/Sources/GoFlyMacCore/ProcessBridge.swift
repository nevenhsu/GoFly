import Foundation
import Darwin

public struct BridgeConfiguration: Codable, Sendable {
    public let workspaceRoot: String
    public let pythonPath: String
    public let developerDirectory: String
    public let projectPath: String
    public let targetBundleID: String
    public let targetName: String
}

extension BridgeConfiguration {
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
        let legacy = targetBundleID == "com.neven.localgo" &&
            projectPath == root.appendingPathComponent("app/LocalGo/StikDebug.xcodeproj").path
        guard workspaceRoot.hasPrefix("/"), root.path == workspaceRoot,
              !workspaceRoot.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              pythonPath == root.appendingPathComponent("work/mac-setup-env/bin/python").path,
              formal || legacy,
              developerDirectory == "/Applications/Xcode.app/Contents/Developer" else {
            throw CheckFailure.unavailable
        }
    }
}

public struct ProcessBridge: MacChecking {
    private let configurationURL: URL
    private let scriptURL: URL
    private let configuration: BridgeConfiguration
    private let bundleResources: MacBundleResources
    private let initialResourceStamp: MacBundleResourceStamp

    public init(configurationURL: URL, scriptURL: URL) throws {
        guard let resources = Bundle.main.resourceURL,
              configurationURL.isFileURL, scriptURL.isFileURL,
              configurationURL.standardizedFileURL == resources.appendingPathComponent("LocalConfiguration.json").standardizedFileURL,
              scriptURL.standardizedFileURL == resources.appendingPathComponent("Bridge/bridge.py").standardizedFileURL,
              (try? scriptURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map({
                  $0.isRegularFile == true && $0.isSymbolicLink != true
              }) == true else { throw CheckFailure.unavailable }
        let bundleURL = Bundle.main.bundleURL
        let bundleResources: MacBundleResources
        do {
            bundleResources = try MacBundleResources(bundleURL: bundleURL)
        } catch {
            throw CheckFailure.unavailable
        }
        let initialResourceStamp: MacBundleResourceStamp
        do {
            initialResourceStamp = try bundleResources.stamp()
            let verifiedConfiguration = try bundleResources.read(.localConfiguration)
            self = try ProcessBridge(verifiedConfigurationData: verifiedConfiguration,
                                      configurationURL: configurationURL,
                                      scriptURL: scriptURL,
                                      bundleResources: bundleResources,
                                      initialResourceStamp: initialResourceStamp)
        } catch let error as CheckFailure {
            throw error
        } catch {
            throw CheckFailure.unavailable
        }
    }

    private init(verifiedConfigurationData data: Data, configurationURL: URL, scriptURL: URL,
                 bundleResources: MacBundleResources, initialResourceStamp: MacBundleResourceStamp) throws {
        self.configuration = try BridgeConfiguration(verifiedData: data)
        guard FileManager.default.isExecutableFile(atPath: configuration.pythonPath) else {
            throw CheckFailure.unavailable
        }
        self.configurationURL = configurationURL
        self.scriptURL = scriptURL
        self.bundleResources = bundleResources
        self.initialResourceStamp = initialResourceStamp
    }

    public func check(_ request: CheckRequest) async throws -> Data {
        let input = try JSONEncoder().encode(request)
        guard input.count <= 32_768 else { throw CheckFailure.invalidResponse }
        do { try bundleResources.revalidate() } catch { throw CheckFailure.unavailable }
        let runner = BoundedProcess()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached {
                try runner.run(executable: self.configuration.pythonPath,
                               arguments: ["-I", self.scriptURL.path, "--config", self.configurationURL.path],
                               developerDirectory: self.configuration.developerDirectory,
                               input: input, timeout: request.action == .inspect ? 100 : 45)
            }.value
        } onCancel: { runner.cancel(reason: .cancelled) }
    }
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
            if active {
                kill(-pid, SIGKILL)
                if child.isRunning { kill(pid, SIGKILL) }
            }
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
        // Keep system services available, but do not forward the user's Python or library search paths.
        child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
                             "DEVELOPER_DIR": developerDirectory, "PYTHONDONTWRITEBYTECODE": "1"]
        child.standardInput = stdin
        child.standardOutput = output
        child.standardError = diagnostics
        lock.lock()
        if let failure { lock.unlock(); throw failure }
        guard !finished, process == nil else { lock.unlock(); throw CheckFailure.unavailable }
        process = child
        // Starting under the same lock closes cancellation's launch race.
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
        // Drain stderr while stdout is read below. Diagnostic bytes never
        // become response content, and excessive diagnostics fail closed.
        streams.enter()
        DispatchQueue.global().async {
            defer { streams.leave() }
            var size = 0
            while true {
                let chunk = diagnostics.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                guard size <= 65_536 - chunk.count else {
                    self.cancel(reason: .invalidResponse)
                    break
                }
                size += chunk.count
            }
        }
        // A child may write before reading stdin. Concurrent input prevents
        // either pipe's capacity from deadlocking the operation.
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
        // Structured error envelopes may deliberately use a nonzero exit status.
        guard !data.isEmpty else { throw CheckFailure.invalidResponse }
        return data
    }
}
