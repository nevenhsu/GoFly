import GoFlyCore
import GoFlyTransport
import SwiftUI

/// Retains the normal runtime owners for the lifetime of the App scene after
/// setup bootstrap admits ordinary or completed startup.
@MainActor
final class GoFlyRuntimeAssembly: ObservableObject {
    let service: ServiceController
    let sessionRecovery: SessionRecoveryStore
    let movement: GoFlyMovementModel
    let favorites: FavoritePlacesStore
    let importedRoutes: ImportedRoutesStore
    let favoriteRoutes: FavoriteRoutesStore
    let onboarding: OnboardingController

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recovery = goFlySessionRecoveryStore()
        let service = ServiceController(service: Self.deviceService())
        let snapshot = recovery.initialSnapshot
        _ = service.restoreColdRecovery(position: snapshot.position)
        if snapshot.activeMovement != nil || snapshot.uncertainty != nil {
            service.markColdClearPending()
            _ = service.beginColdClear()
        }

        self.service = service
        self.sessionRecovery = recovery
        self.movement = GoFlyMovementModel(service: service, recoveryStore: recovery)
        self.favorites = Self.favoritePlacesStore(
            directory: support.appendingPathComponent("FavoritePlaces", isDirectory: true),
            allowUITestNamespace: true)
        self.importedRoutes = Self.importedRoutesStore(
            directory: support.appendingPathComponent("ImportedRoutes", isDirectory: true),
            allowUITestNamespace: true)
        self.favoriteRoutes = Self.favoriteRoutesStore(
            directory: support.appendingPathComponent("FavoriteRoutes", isDirectory: true),
            allowUITestNamespace: true)
        self.onboarding = OnboardingController(
            probe: Self.onboardingProbe(), location: GoFlyLocationAuthorization()
        )
        self.movement.observeDataErrors(recoveryStore: recovery, favorites: favorites,
            importedRoutes: importedRoutes, favoriteRoutes: favoriteRoutes)
    }

    func captureCurrentRecoverySnapshotAndFlush() async -> Bool {
        let snapshot = movement.recovery.snapshot(mode: movement.presentationMode)
        guard sessionRecovery.capture(snapshot) else { return false }
        return await sessionRecovery.flush()
    }

    private static func deviceService() -> any DeviceService { NativeDeviceService() }

    private static func favoritePlacesStore(directory: URL, allowUITestNamespace: Bool) -> FavoritePlacesStore {
        let resolved = allowUITestNamespace
            ? GoFlyUITestOverrides.namespace(
                "-gofly-ui-favorites-store",
                under: directory.deletingLastPathComponent(),
                folder: "FavoritePlaces"
            ) ?? directory
            : directory
        return FavoritePlacesStore(persistence: FileFavoritePlacesPersistence(directory: resolved))
    }

    private static func importedRoutesStore(directory: URL, allowUITestNamespace: Bool) -> ImportedRoutesStore {
        let resolved = allowUITestNamespace
            ? GoFlyUITestOverrides.namespace(
                "-gofly-ui-imports-store",
                under: directory.deletingLastPathComponent(),
                folder: "ImportedRoutes"
            ) ?? directory
            : directory
        return ImportedRoutesStore(persistence: FileImportedRoutesPersistence(directory: resolved))
    }

    private static func favoriteRoutesStore(directory: URL, allowUITestNamespace: Bool) -> FavoriteRoutesStore {
        let resolved = allowUITestNamespace
            ? GoFlyUITestOverrides.namespace(
                "-gofly-ui-favorite-routes-store",
                under: directory.deletingLastPathComponent(),
                folder: "FavoriteRoutes"
            ) ?? directory
            : directory
        return FavoriteRoutesStore(persistence: FileFavoriteRoutesPersistence(directory: resolved))
    }

    private static func onboardingProbe() -> any TunnelProbing {
        GoFlyUITestOverrides.tunnelProbe() ?? NetworkTunnelProbe()
    }
}

private struct UnavailableFavoritePlacesPersistence: FavoritePlacesPersistence {
    func read() throws -> Data? { throw FavoritePlacesFailure.unavailable }
    func replaceAtomically(with data: Data) throws { throw FavoritePlacesFailure.unavailable }
}
