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
        let service: ServiceController
        #if DEBUG && targetEnvironment(simulator)
        let isUITestFixture = GoFlyUITestOverrides.isFrameMode
        if isUITestFixture {
            service = ServiceController(service: GoFlyUITestDeviceService())
        } else {
            service = ServiceController(service: NativeDeviceService())
        }
        #else
        let isUITestFixture = false
        service = ServiceController(service: NativeDeviceService())
        #endif
        let snapshot = recovery.initialSnapshot
        let restoredPosition: SessionDisplayPosition?
#if DEBUG && targetEnvironment(simulator)
        if isUITestFixture, GoFlyUITestOverrides.frameNeedsMapRuntime,
           let coordinate = GeoCoordinate(latitude: 25.05712, longitude: 121.52281) {
            restoredPosition = SessionDisplayPosition(coordinate: coordinate, source: .simulation)
        } else {
            restoredPosition = snapshot.position
        }
#else
        restoredPosition = snapshot.position
#endif
        _ = service.restoreColdRecovery(position: restoredPosition)
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
            probe: Self.onboardingProbe(isUITestFixture: isUITestFixture),
            location: Self.onboardingLocationAuthorization(isUITestFixture: isUITestFixture)
        )
        self.movement.observeDataErrors(recoveryStore: recovery, favorites: favorites,
            importedRoutes: importedRoutes, favoriteRoutes: favoriteRoutes)
    }

#if DEBUG && targetEnvironment(simulator)
    func prepareUITestData() async {
        guard GoFlyUITestOverrides.isFrameMode else { return }
        let places = GoFlyUITestOverrides.fixturePlaces
        if favorites.favorites.isEmpty {
            _ = favorites.save(place: places[0], label: "公司")
            _ = favorites.save(place: places[2], label: "測試點 A")
        }

        await importedRoutes.load()
        if importedRoutes.records.isEmpty {
            let points = (0..<14).compactMap { index in
                GeoCoordinate(latitude: 25.04776 + Double(index) * 0.001,
                              longitude: 121.51706 + Double(index) * 0.001)
            }
            if let document = try? GPXDocument(content: .tracks([GPXTrack(segments: [points])])),
               let data = try? GPXCodec.encode(document, name: "GoFly fixture") {
                _ = await importedRoutes.importData(data, filename: "GoFly fixture.gpx")
            }
        }

        await favoriteRoutes.load()
        if favoriteRoutes.records.isEmpty,
           let draft = RouteDraft(values: [.place(places[0]), .place(places[1])]),
           let candidate = try? FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: nil) {
            _ = await favoriteRoutes.save(candidate, label: "台北散步")
        }
    }
#endif

    func captureCurrentRecoverySnapshotAndFlush() async -> Bool {
        let snapshot = movement.recovery.snapshot(mode: movement.presentationMode)
        guard sessionRecovery.capture(snapshot) else { return false }
        return await sessionRecovery.flush()
    }

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

    private static func onboardingProbe(isUITestFixture: Bool) -> any TunnelProbing {
#if DEBUG && targetEnvironment(simulator)
        if isUITestFixture { return GoFlyUITestOverrides.fixtureTunnelProbe(for: GoFlyUITestOverrides.frame) }
#endif
        return GoFlyUITestOverrides.tunnelProbe() ?? NetworkTunnelProbe()
    }

    private static func onboardingLocationAuthorization(isUITestFixture: Bool) -> any LocationAuthorizing {
#if DEBUG && targetEnvironment(simulator)
        if isUITestFixture { return GoFlyUITestOverrides.fixtureLocationAuthorization() }
#endif
        return GoFlyLocationAuthorization()
    }
}

private struct UnavailableFavoritePlacesPersistence: FavoritePlacesPersistence {
    func read() throws -> Data? { throw FavoritePlacesFailure.unavailable }
    func replaceAtomically(with data: Data) throws { throw FavoritePlacesFailure.unavailable }
}
