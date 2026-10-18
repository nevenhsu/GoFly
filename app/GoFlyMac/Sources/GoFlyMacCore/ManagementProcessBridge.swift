import Foundation

/// Management shares the verified project, runtime and state root used by
/// reinstall. It has its own executable entry point and protocol boundary.
public struct ManagementProcessBridge: MacManagementRunning {
    public let configuration: MacReinstallConfiguration
    private let configurationURL: URL
    private let scriptURL: URL
    private let resources: MacBundleResources

    public init(configurationURL: URL, scriptURL: URL) throws {
        guard let root = Bundle.main.resourceURL,
              configurationURL.standardizedFileURL == root.appendingPathComponent("ReinstallConfiguration.json").standardizedFileURL,
              scriptURL.standardizedFileURL == root.appendingPathComponent("Bridge/Management/management_bridge.py").standardizedFileURL else {
            throw MacManagementFailure.unavailable
        }
        do {
            let resources = try MacBundleResources(bundleURL: Bundle.main.bundleURL)
            let configuration = try MacReinstallConfiguration(
                verifiedData: resources.read(.reinstallConfiguration), bundleRoot: Bundle.main.bundleURL)
            _ = try resources.read(.managementScript)
            guard FileManager.default.isExecutableFile(atPath: configuration.pythonPath),
                  FileManager.default.isExecutableFile(atPath: configuration.validatorPath),
                  FileManager.default.fileExists(atPath: configuration.projectPath) else {
                throw MacManagementFailure.unavailable
            }
            self.configuration = configuration
            self.configurationURL = configurationURL
            self.scriptURL = scriptURL
            self.resources = resources
        } catch { throw MacManagementFailure.unavailable }
    }

    public func run(_ request: MacManagementRequest) async throws -> Data {
        let input = try request.encoded()
        do { try resources.revalidate() } catch { throw MacManagementFailure.unavailable }
        let process = BoundedProcess()
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await Task.detached {
                    try process.run(executable: configuration.pythonPath,
                        arguments: ["-I", scriptURL.path, "--config", configurationURL.path],
                        developerDirectory: configuration.developerDirectory, input: input,
                        timeout: request.action == .query ? 30 : request.action == .preflight ? 120 : 1800)
                }.value
            } onCancel: { process.cancel(reason: .cancelled) }
        } catch let error as CheckFailure {
            switch error {
            case .cancelled: throw MacManagementFailure.cancelled
            case .timeout: throw MacManagementFailure.timeout
            case .unavailable: throw MacManagementFailure.unavailable
            default: throw MacManagementFailure.invalidResponse
            }
        } catch is CancellationError { throw MacManagementFailure.cancelled }
    }
}

public struct UnavailableManagementRunner: MacManagementRunning {
    public init() {}
    public func run(_ request: MacManagementRequest) async throws -> Data { throw MacManagementFailure.unavailable }
}
