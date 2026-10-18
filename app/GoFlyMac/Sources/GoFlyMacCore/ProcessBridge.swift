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

public struct ProcessBridge: MacChecking {
    private let configurationURL: URL
    private let scriptURL: URL
    private let configuration: BridgeConfiguration

    public init(configurationURL: URL, scriptURL: URL) throws {
        guard let resources = Bundle.main.resourceURL,
              configurationURL.isFileURL, scriptURL.isFileURL,
              configurationURL.standardizedFileURL == resources.appendingPathComponent("LocalConfiguration.json").standardizedFileURL,
              scriptURL.standardizedFileURL == resources.appendingPathComponent("Bridge/bridge.py").standardizedFileURL,
              (try? scriptURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map({
                  $0.isRegularFile == true && $0.isSymbolicLink != true
              }) == true else { throw CheckFailure.unavailable }
        let file = open(configurationURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard file >= 0 else { throw CheckFailure.unavailable }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size > 0, info.st_size <= 32_768 else { throw CheckFailure.unavailable }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0, data.count + count <= 32_768 else { throw CheckFailure.unavailable }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == info.st_size else { throw CheckFailure.unavailable }
        let object = try SetupWireJSON.object(data)
        guard Set(object.keys) == ["workspaceRoot", "pythonPath", "developerDirectory", "projectPath", "targetBundleID", "targetName"] else {
            throw CheckFailure.unavailable
        }
        let configuration = try JSONDecoder().decode(BridgeConfiguration.self, from: data)
        let expected = URL(fileURLWithPath: configuration.workspaceRoot)
            .appendingPathComponent("work/mac-setup-env/bin/python").standardizedFileURL.path
        let root = URL(fileURLWithPath: configuration.workspaceRoot).standardizedFileURL
        let formal = configuration.targetBundleID == "com.neven.gofly" && configuration.targetName == "GoFly" &&
            configuration.projectPath == root.appendingPathComponent("app/GoFly/GoFly.xcodeproj").path
        let legacy = configuration.targetBundleID == "com.neven.localgo" &&
            configuration.projectPath == root.appendingPathComponent("app/LocalGo/StikDebug.xcodeproj").path
        guard configuration.pythonPath == expected, formal || legacy,
              configuration.developerDirectory == "/Applications/Xcode.app/Contents/Developer",
              scriptURL.isFileURL, FileManager.default.fileExists(atPath: scriptURL.path),
              FileManager.default.isExecutableFile(atPath: expected) else { throw CheckFailure.unavailable }
        self.configurationURL = configurationURL; self.scriptURL = scriptURL; self.configuration = configuration
    }

    public func check(_ request: CheckRequest) async throws -> Data {
        let input = try JSONEncoder().encode(request)
        guard input.count <= 32_768 else { throw CheckFailure.invalidResponse }
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
final class BoundedProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var failure: CheckFailure?
    private var finished = false

    func cancel(reason: CheckFailure) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if failure == nil { failure = reason }
        let child = process
        lock.unlock()
        guard let child, child.isRunning else { return }
        let pid = child.processIdentifier
        kill(-pid, SIGTERM)
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            self.lock.lock()
            let active = !self.finished
            self.lock.unlock()
            if active { kill(-pid, SIGKILL); kill(pid, SIGKILL) }
        }
    }

    func run(executable: String, arguments: [String], developerDirectory: String, input: Data,
             timeout: TimeInterval) throws -> Data {
        let child = Process()
        let output = Pipe()
        let stdin = Pipe()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        // Keep system services available, but do not forward the user's Python or library search paths.
        child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
                             "DEVELOPER_DIR": developerDirectory, "PYTHONDONTWRITEBYTECODE": "1"]
        child.standardInput = stdin
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        lock.lock()
        if let failure { lock.unlock(); throw failure }
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
        }
        do { try stdin.fileHandleForWriting.write(contentsOf: input); try stdin.fileHandleForWriting.close() }
        catch { cancel(reason: .invalidResponse) }
        var data = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            guard data.count + chunk.count <= 262_144 else { cancel(reason: .invalidResponse); break }
            data.append(chunk)
        }
        child.waitUntilExit()
        lock.lock(); let finalFailure = failure; lock.unlock()
        if let finalFailure { throw finalFailure }
        // Structured error envelopes may deliberately use a nonzero exit status.
        guard !data.isEmpty else { throw CheckFailure.invalidResponse }
        return data
    }
}
