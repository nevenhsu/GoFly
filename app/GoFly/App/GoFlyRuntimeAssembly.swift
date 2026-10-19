import GoFlyCore
import GoFlyTransport
import SwiftUI

/// Retains the normal runtime owners for the lifetime of the App scene after
/// setup bootstrap admits ordinary or completed startup.
@MainActor
final class GoFlyRuntimeAssembly: ObservableObject {
    let projection: TransferRuntimeProjection
    let service: ServiceController
    let sessionRecovery: SessionRecoveryStore
    let movement: GoFlyMovementModel
    let favorites: FavoritePlacesStore
    let importedRoutes: ImportedRoutesStore
    let favoriteRoutes: FavoriteRoutesStore
    let onboarding: OnboardingController

    init(projection: TransferRuntimeProjection) {
        self.projection = projection
        let useUITestNamespaces = projection.transferID == nil
        let recovery = goFlySessionRecoveryStore(directory: projection.sessionDirectory,
                                                  allowUITestNamespace: useUITestNamespaces)
        let service = ServiceController(service: Self.deviceService())
        let snapshot = recovery.initialSnapshot
        _ = service.restoreColdRecovery(
            position: snapshot.position,
            requiresConfirmation: recovery.loadState != .ready ||
                snapshot.activeMovement != nil || snapshot.uncertainty != nil
        )

        self.service = service
        self.sessionRecovery = recovery
        self.movement = GoFlyMovementModel(service: service, recoveryStore: recovery)
        self.favorites = Self.favoritePlacesStore(directory: projection.favoritesDirectory,
                                                  allowUITestNamespace: useUITestNamespaces)
        self.importedRoutes = Self.importedRoutesStore(directory: projection.importedRoutesDirectory,
                                                       allowUITestNamespace: useUITestNamespaces)
        self.favoriteRoutes = Self.favoriteRoutesStore(directory: projection.favoriteRoutesDirectory,
                                                        allowUITestNamespace: useUITestNamespaces)
        self.onboarding = OnboardingController(
            probe: Self.onboardingProbe(), location: GoFlyLocationAuthorization()
        )
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
