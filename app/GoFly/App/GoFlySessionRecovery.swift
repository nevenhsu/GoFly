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

private struct UnavailableSessionRecoveryPersistence: SessionRecoveryPersistence {
    func read() throws -> Data? { throw SessionRecoveryFailure.unavailable }
    func replaceAtomically(with data: Data) throws { throw SessionRecoveryFailure.unavailable }
}
