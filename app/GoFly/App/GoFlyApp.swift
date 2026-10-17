import GoFlyCore
import GoFlyTransport
import SwiftUI

@main
struct GoFlyApp: App {
    @StateObject private var service = ServiceController(service: Self.deviceService())
    @StateObject private var favorites = Self.favoritePlacesStore()
    @StateObject private var importedRoutes = Self.importedRoutesStore()
    @StateObject private var favoriteRoutes = Self.favoriteRoutesStore()
    @StateObject private var onboarding = OnboardingController(
        probe: Self.onboardingProbe(), location: GoFlyLocationAuthorization()
    )
    @AppStorage("gofly.onboarding.complete") private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingComplete {
                    GoFlyMapView(service: service)
                } else {
                    GoFlyOnboardingView(controller: onboarding) {
                        onboardingComplete = true
                    }
                }
            }
            .environmentObject(favorites)
            .environmentObject(importedRoutes)
            .environmentObject(favoriteRoutes)
            .task {
                await importedRoutes.load()
                await favoriteRoutes.load()
            }
        }
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
