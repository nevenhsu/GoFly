import Foundation
import Darwin

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
        let workspace = URL(fileURLWithPath: workspaceRoot).standardizedFileURL
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoFlySetup").path
        guard workspaceRoot.hasPrefix("/"), workspace.path == workspaceRoot,
              !workspaceRoot.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              pythonPath == workspace.appendingPathComponent("work/mac-setup-env/bin/python").path,
              projectPath == workspace.appendingPathComponent("app/GoFly/GoFly.xcodeproj").path,
              developerDirectory == "/Applications/Xcode.app/Contents/Developer",
              targetBundleID == "com.neven.gofly", targetName == "GoFly", stateRoot == support else {
            throw MacSetupFailure.invalidRequest
        }
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
            let workspace = URL(fileURLWithPath: workspaceRoot).standardizedFileURL
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("GoFlySetup").path
            guard workspaceRoot.hasPrefix("/"), workspace.path == workspaceRoot,
                  !workspaceRoot.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  pythonPath == workspace.appendingPathComponent("work/mac-setup-env/bin/python").path,
                  projectPath == workspace.appendingPathComponent("app/GoFly/GoFly.xcodeproj").path,
                  developerDirectory == "/Applications/Xcode.app/Contents/Developer",
                  targetBundleID == "com.neven.gofly", targetName == "GoFly", stateRoot == support else {
                throw MacSetupFailure.invalidRequest
            }
        } catch { throw MacSetupFailure.invalidRequest }
    }
}

public struct SetupProcessBridge: MacSetupRunning {
    public let configuration: MacSetupConfiguration
    private let configurationURL: URL
    private let scriptURL: URL
    private let bundleResources: MacBundleResources
    private let initialResourceStamp: MacBundleResourceStamp

    public init(configurationURL: URL, scriptURL: URL) throws {
        guard let resources = Bundle.main.resourceURL,
              configurationURL.standardizedFileURL == resources.appendingPathComponent("SetupConfiguration.json").standardizedFileURL,
              scriptURL.standardizedFileURL == resources.appendingPathComponent("Bridge/Setup/setup_bridge.py").standardizedFileURL else {
            throw MacSetupFailure.unavailable
        }
        let bundleResources: MacBundleResources
        do {
            bundleResources = try MacBundleResources(bundleURL: Bundle.main.bundleURL)
        } catch {
            throw MacSetupFailure.unavailable
        }
        let stamp: MacBundleResourceStamp
        let configuration: MacSetupConfiguration
        do {
            stamp = try bundleResources.stamp()
            configuration = try MacSetupConfiguration(verifiedData: bundleResources.read(.setupConfiguration))
        } catch {
            throw MacSetupFailure.unavailable
        }
        guard scriptURL.isFileURL, scriptURL.lastPathComponent == "setup_bridge.py",
              scriptURL.deletingLastPathComponent().lastPathComponent == "Setup",
              (try? scriptURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map({
                  $0.isRegularFile == true && $0.isSymbolicLink != true
              }) == true,
              FileManager.default.isExecutableFile(atPath: configuration.pythonPath),
              FileManager.default.fileExists(atPath: configuration.projectPath) else {
            throw MacSetupFailure.unavailable
        }
        self.configuration = configuration
        self.configurationURL = configurationURL
        self.scriptURL = scriptURL
        self.bundleResources = bundleResources
        self.initialResourceStamp = stamp
    }

    public func run(_ request: MacSetupRequest) async throws -> Data {
        let input = try JSONEncoder().encode(request)
        guard input.count <= 32_768 else { throw MacSetupFailure.invalidRequest }
        do { try bundleResources.revalidate() } catch { throw MacSetupFailure.unavailable }
        let process = BoundedProcess()
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await Task.detached {
                    try process.run(executable: configuration.pythonPath,
                                    arguments: ["-I", scriptURL.path, "--config", configurationURL.path],
                                    developerDirectory: configuration.developerDirectory, input: input,
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

public struct UnavailableSetupRunner: MacSetupRunning {
    public init() {}
    public func run(_ request: MacSetupRequest) async throws -> Data { throw MacSetupFailure.unavailable }
}
