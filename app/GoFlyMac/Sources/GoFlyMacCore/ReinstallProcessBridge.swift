import Darwin
import Foundation

public struct MacReinstallConfiguration: Decodable, Sendable {
    public let workspaceRoot: String
    public let pythonPath: String
    public let developerDirectory: String
    public let projectPath: String
    public let targetBundleID: String
    public let targetName: String
    public let stateRoot: String
    public let validatorPath: String

    init(verifiedData data: Data, bundleRoot: URL) throws {
        guard !data.isEmpty, data.count <= 32_768 else { throw MacReinstallFailure.invalidRequest }
        let object = try SetupWireJSON.object(data)
        guard Set(object.keys) == ["workspaceRoot", "pythonPath", "developerDirectory", "projectPath",
                                   "targetBundleID", "targetName", "stateRoot", "validatorPath"] else {
            throw MacReinstallFailure.invalidRequest
        }
        self = try JSONDecoder().decode(Self.self, from: data)
        let root = URL(fileURLWithPath: workspaceRoot).standardizedFileURL
        let expectedState = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoFlySetup").path
        let expectedValidator = bundleRoot.appendingPathComponent("Contents/MacOS/GoFlyTransferValidator").path
        guard workspaceRoot.hasPrefix("/"), root.path == workspaceRoot,
              !workspaceRoot.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              pythonPath == root.appendingPathComponent("work/mac-setup-env/bin/python").path,
              projectPath == root.appendingPathComponent("app/GoFly/GoFly.xcodeproj").path,
              developerDirectory == "/Applications/Xcode.app/Contents/Developer",
              targetBundleID == "com.neven.gofly", targetName == "GoFly", stateRoot == expectedState,
              validatorPath == expectedValidator else { throw MacReinstallFailure.invalidRequest }
    }

    public init(configurationURL: URL) throws {
        do {
            guard configurationURL.isFileURL else { throw MacReinstallFailure.invalidRequest }
            let file = open(configurationURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard file >= 0 else { throw MacReinstallFailure.invalidRequest }
            defer { close(file) }
            var info = stat()
            guard fstat(file, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  info.st_size > 0, info.st_size <= 32_768 else { throw MacReinstallFailure.invalidRequest }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
                if count < 0, errno == EINTR { continue }
                guard count >= 0, data.count + count <= 32_768 else { throw MacReinstallFailure.invalidRequest }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            guard data.count == info.st_size else { throw MacReinstallFailure.invalidRequest }
            let object = try SetupWireJSON.object(data)
            guard Set(object.keys) == ["workspaceRoot", "pythonPath", "developerDirectory", "projectPath",
                "targetBundleID", "targetName", "stateRoot", "validatorPath"] else { throw MacReinstallFailure.invalidRequest }
            self = try JSONDecoder().decode(Self.self, from: data)
            let root = URL(fileURLWithPath: workspaceRoot).standardizedFileURL
            let expectedState = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("GoFlySetup").path
            let expectedValidator = configurationURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("MacOS/GoFlyTransferValidator").path
            guard workspaceRoot.hasPrefix("/"), root.path == workspaceRoot,
                  !workspaceRoot.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  pythonPath == root.appendingPathComponent("work/mac-setup-env/bin/python").path,
                  projectPath == root.appendingPathComponent("app/GoFly/GoFly.xcodeproj").path,
                  developerDirectory == "/Applications/Xcode.app/Contents/Developer",
                  targetBundleID == "com.neven.gofly", targetName == "GoFly", stateRoot == expectedState,
                  validatorPath == expectedValidator else { throw MacReinstallFailure.invalidRequest }
        } catch { throw MacReinstallFailure.invalidRequest }
    }
}

public struct ReinstallProcessBridge: MacReinstallRunning {
    public let configuration: MacReinstallConfiguration
    private let configurationURL: URL
    private let scriptURL: URL
    private let bundleResources: MacBundleResources
    private let initialResourceStamp: MacBundleResourceStamp

    public init(configurationURL: URL, scriptURL: URL) throws {
        guard let resources = Bundle.main.resourceURL,
              configurationURL.standardizedFileURL == resources.appendingPathComponent("ReinstallConfiguration.json").standardizedFileURL,
              scriptURL.standardizedFileURL == resources.appendingPathComponent("Bridge/Reinstall/reinstall_bridge.py").standardizedFileURL else {
            throw MacReinstallFailure.unavailable
        }
        let bundleURL = Bundle.main.bundleURL
        let bundleResources: MacBundleResources
        do {
            bundleResources = try MacBundleResources(bundleURL: bundleURL)
        } catch {
            throw MacReinstallFailure.unavailable
        }
        let stamp: MacBundleResourceStamp
        let configuration: MacReinstallConfiguration
        do {
            stamp = try bundleResources.stamp()
            configuration = try MacReinstallConfiguration(
                verifiedData: bundleResources.read(.reinstallConfiguration), bundleRoot: bundleURL
            )
        } catch {
            throw MacReinstallFailure.unavailable
        }
        guard (try? scriptURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map({
            $0.isRegularFile == true && $0.isSymbolicLink != true
        }) == true,
              FileManager.default.isExecutableFile(atPath: configuration.pythonPath),
              FileManager.default.isExecutableFile(atPath: configuration.validatorPath),
              FileManager.default.fileExists(atPath: configuration.projectPath) else { throw MacReinstallFailure.unavailable }
        self.configuration = configuration
        self.configurationURL = configurationURL
        self.scriptURL = scriptURL
        self.bundleResources = bundleResources
        self.initialResourceStamp = stamp
    }

    public func run(_ request: MacReinstallRequest) async throws -> Data {
        let input = try request.encoded()
        do { try bundleResources.revalidate() } catch { throw MacReinstallFailure.unavailable }
        let process = BoundedProcess()
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await Task.detached {
                    try process.run(executable: configuration.pythonPath,
                        arguments: ["-I", scriptURL.path, "--config", configurationURL.path],
                        developerDirectory: configuration.developerDirectory, input: input,
                        timeout: request.action == .status ? 30 : request.action == .preflight ? 120 : 1800)
                }.value
            } onCancel: { process.cancel(reason: .cancelled) }
        } catch let error as CheckFailure {
            switch error {
            case .cancelled: throw MacReinstallFailure.cancelled
            case .timeout: throw MacReinstallFailure.timeout
            case .unavailable: throw MacReinstallFailure.unavailable
            default: throw MacReinstallFailure.invalidResponse
            }
        } catch is CancellationError { throw MacReinstallFailure.cancelled }
    }
}

public struct UnavailableReinstallRunner: MacReinstallRunning {
    public init() {}
    public func run(_ request: MacReinstallRequest) async throws -> Data { throw MacReinstallFailure.unavailable }
}
