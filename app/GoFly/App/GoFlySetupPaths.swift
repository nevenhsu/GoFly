import Foundation
import GoFlyCore

/// Resolves the fixed private setup directory used by the bootstrap coordinator.
/// Resolution has no filesystem side effects.
enum GoFlySetupPaths {
    static let directoryName = "GoFlySetup"

    static func directory(fileManager: FileManager = .default) throws -> URL {
        guard let support = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            throw GoFlySetupPathsError.storageUnavailable
        }
        return GoFlyUITestOverrides.namespace(
            "-gofly-ui-setup-store", under: support, folder: directoryName
        ) ?? support.appendingPathComponent(directoryName, isDirectory: true)
    }
}

enum GoFlySetupPathsError: Error {
    case storageUnavailable
}
