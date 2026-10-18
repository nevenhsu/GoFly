import Foundation

/// Runs the fixed local backup bridge from the verified app bundle.
/// Configuration and script URLs are accepted only when they identify the
/// exact bundled resources; the Python process receives no caller path.
public struct BackupProcessBridge: MacBackupRunning {
    public let configuration: MacSetupConfiguration
    private let configurationURL: URL
    private let scriptURL: URL
    private let bundleResources: MacBundleResources
    private let initialResourceStamp: MacBundleResourceStamp

    public init(configurationURL: URL, scriptURL: URL) throws {
        guard let resources = Bundle.main.resourceURL,
              configurationURL.standardizedFileURL == resources.appendingPathComponent("SetupConfiguration.json").standardizedFileURL,
              scriptURL.standardizedFileURL == resources.appendingPathComponent("Bridge/Backup/bridge.py").standardizedFileURL else {
            throw MacBackupFailure.unavailable
        }
        let bundleResources: MacBundleResources
        do { bundleResources = try MacBundleResources(bundleURL: Bundle.main.bundleURL) }
        catch { throw MacBackupFailure.unavailable }

        let stamp: MacBundleResourceStamp
        let configuration: MacSetupConfiguration
        do {
            stamp = try bundleResources.stamp()
            configuration = try MacSetupConfiguration(verifiedData: bundleResources.read(.setupConfiguration))
        } catch { throw MacBackupFailure.unavailable }

        guard scriptURL.isFileURL,
              (try? scriptURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map({
                  $0.isRegularFile == true && $0.isSymbolicLink != true
              }) == true,
              FileManager.default.isExecutableFile(atPath: configuration.pythonPath),
              FileManager.default.fileExists(atPath: configuration.projectPath) else {
            throw MacBackupFailure.unavailable
        }
        self.configuration = configuration
        self.configurationURL = configurationURL
        self.scriptURL = scriptURL
        self.bundleResources = bundleResources
        self.initialResourceStamp = stamp
    }

    public func run(_ request: MacBackupRequest) async throws -> Data {
        let input = try request.encoded()
        do { try bundleResources.revalidate() }
        catch { throw MacBackupFailure.unavailable }
        let process = BoundedProcess()
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await Task.detached {
                    try process.run(
                        executable: configuration.pythonPath,
                        arguments: ["-I", scriptURL.path, "--config", configurationURL.path],
                        developerDirectory: configuration.developerDirectory,
                        input: input,
                        timeout: request.action == .list ? 30 : 1_800
                    )
                }.value
            } onCancel: {
                process.cancel(reason: .cancelled)
            }
        } catch let error as CheckFailure {
            switch error {
            case .cancelled: throw MacBackupFailure.cancelled
            case .timeout: throw MacBackupFailure.timeout
            case .unavailable: throw MacBackupFailure.unavailable
            case .service(let code): throw MacBackupFailure.service(code)
            default: throw MacBackupFailure.invalidResponse
            }
        } catch is CancellationError {
            throw MacBackupFailure.cancelled
        }
    }
}

public struct UnavailableBackupRunner: MacBackupRunning {
    public init() {}
    public func run(_ request: MacBackupRequest) async throws -> Data {
        throw MacBackupFailure.unavailable
    }
}
