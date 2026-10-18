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

    private static func deviceService() -> any DeviceService {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-unconfirmed-point") {
            return UnconfirmedPointUITestService()
        }
        #endif
        return NativeDeviceService()
    }

    private static func favoritePlacesStore(directory: URL, allowUITestNamespace: Bool) -> FavoritePlacesStore {
        var resolved = directory
        #if DEBUG && targetEnvironment(simulator)
        if allowUITestNamespace,
           let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-gofly-ui-favorites-store"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let namespace = UUID(uuidString: ProcessInfo.processInfo.arguments[index + 1]) {
            let support = directory.deletingLastPathComponent()
            resolved = support.appendingPathComponent("UITests/FavoritePlaces", isDirectory: true)
                .appendingPathComponent(namespace.uuidString, isDirectory: true)
        }
        #endif
        return FavoritePlacesStore(persistence: FileFavoritePlacesPersistence(directory: resolved))
    }

    private static func importedRoutesStore(directory: URL, allowUITestNamespace: Bool) -> ImportedRoutesStore {
        var resolved = directory
        #if DEBUG && targetEnvironment(simulator)
        if allowUITestNamespace,
           let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-gofly-ui-imports-store"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let namespace = UUID(uuidString: ProcessInfo.processInfo.arguments[index + 1]) {
            let support = directory.deletingLastPathComponent()
            resolved = support.appendingPathComponent("UITests/ImportedRoutes", isDirectory: true)
                .appendingPathComponent(namespace.uuidString, isDirectory: true)
        }
        #endif
        return ImportedRoutesStore(persistence: FileImportedRoutesPersistence(directory: resolved))
    }

    private static func favoriteRoutesStore(directory: URL, allowUITestNamespace: Bool) -> FavoriteRoutesStore {
        var resolved = directory
        #if DEBUG && targetEnvironment(simulator)
        if allowUITestNamespace,
           let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-gofly-ui-favorite-routes-store"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let namespace = UUID(uuidString: ProcessInfo.processInfo.arguments[index + 1]) {
            let support = directory.deletingLastPathComponent()
            resolved = support.appendingPathComponent("UITests/FavoriteRoutes", isDirectory: true)
                .appendingPathComponent(namespace.uuidString, isDirectory: true)
        }
        #endif
        return FavoriteRoutesStore(persistence: FileFavoriteRoutesPersistence(directory: resolved))
    }

    private static func onboardingProbe() -> any TunnelProbing {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-unreachable") {
            return NetworkTunnelProbe.unavailableUITestProbe
        }
        #endif
        return NetworkTunnelProbe()
    }
}

private struct UnavailableFavoritePlacesPersistence: FavoritePlacesPersistence {
    func read() throws -> Data? { throw FavoritePlacesFailure.unavailable }
    func replaceAtomically(with data: Data) throws { throw FavoritePlacesFailure.unavailable }
}
