import Foundation
import GoFlyCore

@MainActor
func goFlySessionRecoveryStore() -> SessionRecoveryStore {
    do {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let directory = GoFlyUITestOverrides.namespace(
            "-gofly-ui-session-store", under: support, folder: "SessionRecovery"
        ) ?? support.appendingPathComponent("SessionRecovery", isDirectory: true)
        return SessionRecoveryStore(persistence: FileSessionRecoveryPersistence(directory: directory))
    } catch {
        return SessionRecoveryStore(persistence: UnavailableSessionRecoveryPersistence())
    }
}

/// Creates a recovery store from the already verified runtime projection.
/// The directory is supplied by Core; test namespaces only redirect that root.
@MainActor
func goFlySessionRecoveryStore(directory: URL, allowUITestNamespace: Bool = false) -> SessionRecoveryStore {
    let resolved = allowUITestNamespace
        ? GoFlyUITestOverrides.namespace(
            "-gofly-ui-session-store",
            under: directory.deletingLastPathComponent(),
            folder: "SessionRecovery"
        ) ?? directory
        : directory
    return SessionRecoveryStore(persistence: FileSessionRecoveryPersistence(directory: resolved))
}

private struct UnavailableSessionRecoveryPersistence: SessionRecoveryPersistence {
    func read() throws -> Data? { throw SessionRecoveryFailure.unavailable }
    func replaceAtomically(with data: Data) throws { throw SessionRecoveryFailure.unavailable }
}
