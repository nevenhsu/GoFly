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
        let recovery = goFlySessionRecoveryStore()
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
        self.favorites = Self.favoritePlacesStore()
        self.importedRoutes = Self.importedRoutesStore()
        self.favoriteRoutes = Self.favoriteRoutesStore()
        self.onboarding = OnboardingController(
            probe: Self.onboardingProbe(), location: GoFlyLocationAuthorization()
        )
    }

    private static func deviceService() -> any DeviceService {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-unconfirmed-point") {
            return UnconfirmedPointUITestService()
        }
        #endif
        return NativeDeviceService()
    }

    private static func favoritePlacesStore() -> FavoritePlacesStore {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            var directory = support.appendingPathComponent("FavoritePlaces", isDirectory: true)
            #if DEBUG && targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-gofly-ui-favorites-store"),
               arguments.indices.contains(index + 1),
               let namespace = UUID(uuidString: arguments[index + 1]) {
                directory = support.appendingPathComponent("UITests/FavoritePlaces", isDirectory: true)
                    .appendingPathComponent(namespace.uuidString, isDirectory: true)
            }
            #endif
            return FavoritePlacesStore(persistence: FileFavoritePlacesPersistence(directory: directory))
        } catch {
            return FavoritePlacesStore(persistence: UnavailableFavoritePlacesPersistence())
        }
    }

    private static func importedRoutesStore() -> ImportedRoutesStore {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            var directory = support.appendingPathComponent("ImportedRoutes", isDirectory: true)
            #if DEBUG && targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-gofly-ui-imports-store"),
               arguments.indices.contains(index + 1), let namespace = UUID(uuidString: arguments[index + 1]) {
                directory = support.appendingPathComponent("UITests/ImportedRoutes", isDirectory: true)
                    .appendingPathComponent(namespace.uuidString, isDirectory: true)
            }
            #endif
            return ImportedRoutesStore(persistence: FileImportedRoutesPersistence(directory: directory))
        } catch {
            return ImportedRoutesStore(persistence: UnavailableImportedRoutesPersistence())
        }
    }

    private static func favoriteRoutesStore() -> FavoriteRoutesStore {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            var directory = support.appendingPathComponent("FavoriteRoutes", isDirectory: true)
            #if DEBUG && targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-gofly-ui-favorite-routes-store"),
               arguments.indices.contains(index + 1), let namespace = UUID(uuidString: arguments[index + 1]) {
                directory = support.appendingPathComponent("UITests/FavoriteRoutes", isDirectory: true)
                    .appendingPathComponent(namespace.uuidString, isDirectory: true)
            }
            #endif
            return FavoriteRoutesStore(persistence: FileFavoriteRoutesPersistence(directory: directory))
        } catch {
            return FavoriteRoutesStore(persistence: UnavailableFavoriteRoutesPersistence())
        }
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
