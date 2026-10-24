import Combine
import GoFlyCore
import GoFlyTransport
import MapKit
import SwiftUI
import UIKit

/// One App-owned assembly, created before SwiftUI attaches its observers.
/// View reconstruction reuses these exact domain owners and cannot fence live work.
struct GoFlyMovementPresentation: Equatable {
    var status: GoFlySessionStatus = .started
    var marker: PositionMarker?
    var errorKeys: [String] = []
    var route: PlannedRoute?
    var routeDistance: Double?
}

@MainActor
final class GoFlyMovementModel: ObservableObject {
    @Published private(set) var presentation = GoFlyMovementPresentation()
    private var presentationUpdateQueued = false
    private let network = GoFlyNetworkMonitor.shared
    private var dataErrorKeys: @MainActor () -> [String] = { [] }
    @Published private(set) var presentationMode: SessionMapMode
    let route: RouteExecutionController
    let joystick: JoystickMovementController
    let recovery: ConnectionRecoveryController
    let continuation: MovementContinuationController
    let positionHold: PositionHoldController
    private let service: ServiceController
    private var subscriptions: [AnyCancellable] = []
    private var speedSynchronizer: MovementSpeedSynchronizer?
    private var mapAdmission: (@MainActor () -> Bool)?

    init(service: ServiceController, recoveryStore: SessionRecoveryStore) {
        self.service = service
        let snapshot = recoveryStore.initialSnapshot
        presentationMode = snapshot.mode
        route = RouteExecutionController(
            draft: Self.routeDraft(restoring: snapshot.draft), planner: Self.routePlanner(),
            commands: service, search: MapKitPlaceSearch()
        )
        _ = route.setRoundTripEnabled(snapshot.roundTripEnabled)
        joystick = JoystickMovementController(commands: service, speed: GoFlyPreferences.shared.movementSpeed)
        positionHold = PositionHoldController(service: service)
        recovery = ConnectionRecoveryController(
            service: service, route: route, joystick: joystick,
            probe: NetworkTunnelProbe(), positionHold: positionHold, retainedColdSnapshot: snapshot
        )
        let routeForPresentation = route
        continuation = MovementContinuationController(
            service: service, route: route, joystick: joystick, recovery: recovery, positionHold: positionHold,
            driver: GoFlyContinuedProcessingDriver.shared,
            presentation: { kind, progress in
                if kind != .finiteRoute {
                    let percent = min(100, max(0, Int(progress.cumulativeAcknowledgedDurationSeconds / 43_200 * 100)))
                    return (title: goFlyString("background.activity.\(kind.rawValue)"),
                            subtitle: goFlyLocalizedFormat(goFlyString("background.activity.durationProgress"), percent))
                }
                let percent = min(100, max(0, Int((routeForPresentation.progress?.fraction ?? 0) * 100)))
                return (title: goFlyString("background.activity.\(kind.rawValue)"),
                 subtitle: goFlyLocalizedFormat(
                    goFlyString("background.activity.routeProgress"), percent))
            }
        )
        speedSynchronizer = MovementSpeedSynchronizer(
            route: route, joystick: joystick, initial: GoFlyPreferences.shared.movementSpeed,
            onChange: { GoFlyPreferences.shared.setMovementSpeed($0) })
        // Both screens observe this owner and read the same status projection.
        subscriptions = [service.objectWillChange, recovery.objectWillChange,
                         route.objectWillChange, joystick.objectWillChange,
                         positionHold.objectWillChange, continuation.objectWillChange,
                         network.objectWillChange, recoveryStore.objectWillChange].map { publisher in
            publisher.sink { [weak self] _ in self?.queuePresentationUpdate() }
        }
    }

    var status: GoFlySessionStatus { presentation.status }

    private func queuePresentationUpdate() {
        guard !presentationUpdateQueued else { return }
        presentationUpdateQueued = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.presentationUpdateQueued = false
            let running = self.route.phase == .running || self.joystick.phase == .moving || self.positionHold.phase == .running
            let paused = self.route.phase == .paused || self.joystick.phase == .paused || self.positionHold.phase == .paused
                || self.route.phase == .interrupted || self.joystick.phase == .interrupted
                || self.route.phase == .unknown || self.joystick.phase == .unknown || self.positionHold.phase == .unknown
            let errors = SessionStatusErrors(connection: self.recovery.connectionState,
                service: self.service.error, route: self.route.error, joystick: self.joystick.error,
                wander: self.joystick.wanderError, wifiAvailable: self.network.isWiFiConnected,
                dataErrors: self.dataErrorKeys())
            let hasError = !errors.isEmpty || self.recovery.automaticRepairInProgress || !self.service.movementConnectionAvailable
            let next = GoFlyMovementPresentation(
                status: GoFlySessionStatus(hasError: hasError, running: running, paused: paused,
                    hasSimulated: self.service.hasSimulated),
                marker: self.service.displayPositionMarker, errorKeys: errors.keys,
                route: self.route.intent?.route,
                routeDistance: self.route.progress?.committedDistanceMeters)
            if self.presentation != next { self.presentation = next }
        }
    }

    func observeDataErrors(recoveryStore: SessionRecoveryStore, favorites: FavoritePlacesStore,
                           importedRoutes: ImportedRoutesStore, favoriteRoutes: FavoriteRoutesStore) {
        dataErrorKeys = {
            var keys = [recoveryStore.error?.localizationKey, favorites.error?.rawValue,
                        importedRoutes.error?.localizationKey, favoriteRoutes.error?.localizationKey].compactMap { $0 }
            if case .blocked(let failure) = recoveryStore.loadState { keys.append(failure.localizationKey) }
            if case .blocked(let failure) = favorites.loadState { keys.append(failure.rawValue) }
            if case .blocked(let failure) = importedRoutes.loadState { keys.append(failure.localizationKey) }
            if case .blocked(let failure) = favoriteRoutes.loadState { keys.append(failure.localizationKey) }
            return keys
        }
        subscriptions += [favorites.objectWillChange, importedRoutes.objectWillChange,
                          favoriteRoutes.objectWillChange].map { publisher in
            publisher.sink { [weak self] _ in self?.queuePresentationUpdate() }
        }
        queuePresentationUpdate()
    }

    func setPresentationMode(_ mode: SessionMapMode) {
        guard route.canEdit else { return }
        presentationMode = mode
    }

    func attachMapAdmission(_ admission: @escaping @MainActor () -> Bool) {
        mapAdmission = admission
    }

    func detachMapAdmission() { mapAdmission = nil }

    var canExportFromMap: Bool {
        guard mapAdmission?() == true, UIApplication.shared.applicationState == .active,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow && !$0.isHidden })?.rootViewController else { return false }
        // Read the actual presentation tree, including sheets and importers
        // owned by child views. Export must not dismiss an unfinished editor.
        var pending = [root]
        var visited = 0
        while let controller = pending.popLast() {
            visited += 1
            guard visited <= 128, controller.presentedViewController == nil else { return false }
            pending.append(contentsOf: controller.children)
        }
        return true
    }

    private static func routeDraft(restoring saved: RouteDraft) -> RouteDraft { saved }

    private static func routePlanner() -> any RoutePlanning {
        FallbackRoutePlanner(provider: MapKitRoutePathProvider())
    }

}

struct GoFlyMapView: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    @ObservedObject private var movement: GoFlyMovementModel
    @ObservedObject var service: ServiceController
    @ObservedObject var recoveryStore: SessionRecoveryStore
    let setupMetadata: GoFlySetupMetadata?
    @ObservedObject private var route: RouteExecutionController
    @ObservedObject private var joystick: JoystickMovementController
    @ObservedObject private var recovery: ConnectionRecoveryController
    @ObservedObject private var continuation: MovementContinuationController
    @ObservedObject private var positionHold: PositionHoldController
    @ObservedObject private var network = GoFlyNetworkMonitor.shared
    private var mode: GoFlyMapMode {
        get { movement.presentationMode }
        nonmutating set { movement.setPresentationMode(newValue) }
    }
    @State private var lastCapturedSnapshot: SessionRecoverySnapshot
    @State private var checkpointWindowStarted = false
    @State private var checkpointWindowID: UUID?
    @State private var checkpointBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    @State private var checkpointFlushTask: Task<Void, Never>?
    @StateObject private var location = GoFlyRealLocation()
    @StateObject private var search = CandidateController(search: MapKitPlaceSearch())
    @StateObject private var wanderSearch = CandidateController(search: MapKitPlaceSearch())
    @State private var cameraIntent: GoFlyCameraIntent?
    private let mapPlaces = MapKitPlaceResolver()
    @State private var pendingGPSRecenter = false
    @State private var projection: GoFlyMapProjection?
    @State private var topFrame = CGRect.zero
    @State private var panelFrame = CGRect.zero
    @State private var teleportCardFrame = CGRect.zero
    @State private var bottomContentHeight: CGFloat = 260
    @State private var sheetDetent: GoFlySheetDetent = .collapsed
    @State private var sheetHeight: CGFloat = 320
    @State private var presentedSheet: GoFlyMapSheet?
    @State private var searchFocusRequest: UUID?
    @State private var showingSearch = false
    @State private var searchFavorites = false
    @State private var recentPlaces: [MapPlace] = []
    @State private var snackbar: GoFlySnackbarMessage?
    @State private var bottomBarHeight: CGFloat = 83
    @State private var candidateHeight: CGFloat = 96
    @ScaledMetric(relativeTo: .body) private var goWidth: CGFloat = 68
    @State private var showingSettings = false
    @State private var serviceNoticeDismissed = false
    @State private var selectedWanderPlace: MapPlace? = nil
    @State private var recoveryNoticeDismissed = false
    @State private var continuationNoticeDismissed = false
    @State private var joystickErrorDismissed = false
    @State private var routeErrorDismissed = false
    @State private var returnedFromUnconfirmed: UUID?
    @State private var isMapPicking = false
    @State private var settingJoystickOrigin = false
    @State private var joystickOriginIntentID: UUID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    init(
        service: ServiceController,
        recoveryStore: SessionRecoveryStore,
        movement: GoFlyMovementModel,
        setupMetadata: GoFlySetupMetadata? = nil
    ) {
        let snapshot = recoveryStore.initialSnapshot
        self.movement = movement
        _service = ObservedObject(wrappedValue: service)
        _recoveryStore = ObservedObject(wrappedValue: recoveryStore)
        self.setupMetadata = setupMetadata
        _route = ObservedObject(wrappedValue: movement.route)
        _joystick = ObservedObject(wrappedValue: movement.joystick)
        _recovery = ObservedObject(wrappedValue: movement.recovery)
        _continuation = ObservedObject(wrappedValue: movement.continuation)
        _positionHold = ObservedObject(wrappedValue: movement.positionHold)
        _lastCapturedSnapshot = State(initialValue: snapshot)
    }

    private var isWanderMap: Bool { mode == .joystick && joystick.wanderEnabled && route.picker == nil }
    private var activeSearch: CandidateController {
        route.picker?.candidates ?? (isWanderMap ? wanderSearch : search)
    }
    private var activeCandidate: TeleportCandidate? {
        if let picker = route.picker { return picker.candidates.candidate }
        if isWanderMap { return wanderSearch.candidate }
        return mode == .teleport && route.canEdit ? search.candidate : nil
    }
    private var canSwitchMode: Bool { route.canEdit && route.picker == nil && !showsOperationPanel }

    private var viewportGap: CGFloat { dynamicTypeSize.isAccessibilitySize ? 4 : 8 }
    private var bottomPadding: CGFloat { dynamicTypeSize.isAccessibilitySize ? 8 : 12 }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                mapContent(in: geometry)
                .coordinateSpace(name: "mapRoot")
                .accessibilityHidden(presentedSheet != nil || showingSearch || route.picker != nil)
            }
            .background(GoFlyStyle.canvas.ignoresSafeArea())
            .goFlyNativeBackTitle()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingSettings) {
                ServiceSettingsView(
                    service: service,
                    movement: movement,
                    continuation: continuation,
                    recovery: recovery,
                    setupMetadata: setupMetadata
                )
            }
            .onAppear {
                movement.attachMapAdmission {
                    !showingSettings && !showingSearch && presentedSheet == nil && route.picker == nil
                }
                location.start()
                if cameraIntent == nil {
                    if mode == .route, let planned = route.plannedRoute {
                        cameraIntent = GoFlyCameraIntent(route: planned)
                    } else if let position = service.positionMarker {
                        cameraIntent = GoFlyCameraIntent(coordinate: position.coordinate)
                    }
                }
                if scenePhase == .active { continuation.sceneDidBecomeActive() }
                recovery.requestForegroundCheck()
                service.warmupSession()
                if dynamicTypeSize.isAccessibilitySize { sheetDetent = .expanded }
            }
            .onChange(of: dynamicTypeSize) { _, size in
                if size.isAccessibilitySize { sheetDetent = .expanded }
            }
            .onDisappear { movement.detachMapAdmission() }
            .onReceive(service.$error) { error in
                serviceNoticeDismissed = false
                if let error {
                    UIAccessibility.post(notification: .announcement, argument: goFlyString(error.rawValue))
                }
            }
            .onChange(of: service.preparedOperation?.id) { _, id in
                if id != nil { dismissKeyboard() }
            }
            .onReceive(location.$observation) { observation in
                let explicitlyRequested = pendingGPSRecenter
                pendingGPSRecenter = false
                service.observeRealLocation(observation)
                guard observation != nil else { return }
                guard let accepted = service.realLocation else {
                    location.rejectedFix()
                    return
                }
                location.acceptedFix()
                guard service.confirmedSimulatedLocation == nil,
                      mode != .joystick || explicitlyRequested,
                      mode == .teleport || route.plannedRoute == nil || explicitlyRequested,
                      (route.picker == nil ? activeCandidate == nil : activeSearch.candidate == nil) || explicitlyRequested,
                      let coordinate = GeoCoordinate(latitude: accepted.latitude, longitude: accepted.longitude) else { return }
                cameraIntent = GoFlyCameraIntent(coordinate: coordinate, headingDegrees: explicitlyRequested ? 0 : nil)
            }
            .onChange(of: route.picker?.id) { _, id in
                if id != nil {
                    searchFocusRequest = UUID()
                } else {
                    searchFocusRequest = nil
                    dismissKeyboard()
                }
            }
            .onChange(of: route.plannedRoute) { _, planned in
                if mode == .route, let planned { cameraIntent = GoFlyCameraIntent(route: planned) }
            }
            .onChange(of: mode) { _, mode in
                if mode == .joystick {
                    service.warmupSession()
                }
                dismissKeyboard()
                if mode == .route, let planned = route.plannedRoute {
                    cameraIntent = GoFlyCameraIntent(route: planned)
                } else if mode == .teleport, let candidate = search.candidate {
                    cameraIntent = GoFlyCameraIntent(coordinate: candidate.place.coordinate)
                }
                captureCheckpoint()
            }
            .onChange(of: scenePhase) { _, phase in
                Diagnostics.shared.record("movement.scene", category: .movement, level: .notice, [
                    "phase": .text(String(describing: phase)),
                    "route": .text(String(describing: route.phase)),
                    "joystick": .text(String(describing: joystick.phase)),
                    "service": .text(service.phase.rawValue),
                    "grant": .flag(continuation.hasRuntime)
                ])
                if phase == .active {
                    checkpointWindowStarted = false
                    finishCheckpointWindow(id: checkpointWindowID)
                    continuation.sceneDidBecomeActive()
                    recovery.requestForegroundCheck()
                } else {
                    continuation.releaseForInactiveScene()
                    captureCheckpoint()
                    beginCheckpointFlush()
                }
            }
            .onChange(of: recovery.checkpointRevision) { _, _ in captureCheckpoint() }
            .onChange(of: joystick.wanderEnabled) { _, enabled in
                if !enabled { wanderSearch.resetSelection() }
            }
            .task(id: route.completion?.executionID) {
                guard let id = route.completion?.executionID else { return }
                snackbar = GoFlySnackbarMessage(text: goFlyString("route.completed"))
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                route.dismissCompletion(executionID: id)
            }
            .onChange(of: service.pointState) { _, state in
                guard case .acknowledged(let intent) = state else { return }
                snackbar = GoFlySnackbarMessage(text: goFlyLocalizedFormat(goFlyString("teleport.completed"), intent.candidate.place.title))
                search.clearCandidate(ifMatching: intent.candidate.id)
                if search.candidate == nil {
                    cameraIntent = GoFlyCameraIntent(coordinate: intent.candidate.place.coordinate)
                }
                dismissKeyboard()
                if settingJoystickOrigin, mode == .teleport, joystickOriginIntentID == intent.id {
                    joystickOriginIntentID = nil
                    if search.candidate == nil {
                        settingJoystickOrigin = false
                        mode = .joystick
                    }
                }
            }
            .fullScreenCover(item: $presentedSheet) { sheet in
                switch sheet.content {
                case .favorites:
                    GoFlyFavoritesView(
                        candidate: activeSearch.candidate?.place,
                        onSelect: { selectSearchPlace($0); presentedSheet = nil },
                        onSearch: { showingSearch = true; presentedSheet = nil },
                        onDismiss: { presentedSheet = nil }
                    )
                case .details(let place):
                    GoFlyPlaceDetailsView(place: place, onDismiss: { presentedSheet = nil })
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { (showingSearch || route.picker != nil) && !isMapPicking },
            set: { shown in
                if !shown {
                    showingSearch = false
                    if isMapPicking { isMapPicking = false }
                }
            }
        )) { searchScreen.interactiveDismissDisabled() }
        .tint(GoFlyStyle.primary)
    }

    private var searchScreen: some View {
        Group {
            if let picker = route.picker {
                GoFlySearchPanel(
                    search: picker.candidates,
                    focusRequest: searchFocusRequest,
                    placeholderOverride: routePickerPlaceholder(picker.role),
                    roleTitle: routePickerPlaceholder(picker.role),
                    onBack: { route.cancelPicker(id: picker.id) },
                    onFavorites: { searchFavorites = true },
                    recentPlaces: recentPlaces,
                    onClearRecentPlaces: clearRecentPlaces,
                    onSelect: { place in
                        recordRecentPlace(place)
                        _ = route.confirmPicker(id: picker.id)
                    },
                    onUseCurrentLocation: picker.allowsCurrent
                        ? { _ = route.confirmPicker(id: picker.id, useCurrentLocation: true) } : nil,
                    onChooseOnMap: {
                        isMapPicking = true
                        sheetDetent = .collapsed
                        if let candidate = picker.candidates.candidate {
                            activeSearch.select(candidate.place)
                        } else if let firstResult = picker.candidates.results.first {
                            activeSearch.select(firstResult)
                        } else if let coordinate = service.positionMarker?.coordinate {
                            let place = MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
                            activeSearch.select(place)
                        }
                    }
                )
            } else {
                GoFlySearchPanel(
                    search: activeSearch,
                    focusRequest: searchFocusRequest,
                    onBack: { showingSearch = false },
                    onFavorites: { searchFavorites = true },
                    recentPlaces: recentPlaces,
                    onClearRecentPlaces: clearRecentPlaces,
                    onSelect: selectSearchPlace)
            }
        }
        .background(GoFlyStyle.surface)
        .fullScreenCover(isPresented: $searchFavorites) {
            GoFlyFavoritesView(candidate: activeSearch.candidate?.place,
                onSelect: { place in
                    activeSearch.select(place)
                    searchFavorites = false
                    if let picker = route.picker { _ = route.confirmPicker(id: picker.id) }
                    else { selectSearchPlace(place) }
                }, onSearch: { searchFavorites = false }, onDismiss: { searchFavorites = false })
        }
    }

    private func routePickerPlaceholder(_ role: RouteNodeRole) -> String {
        switch role {
        case .start: goFlyString("route.chooseOrigin")
        case .destination: goFlyString("route.chooseDestination")
        case .waypoint(let number):
            goFlyLocalizedFormat(goFlyString("route.chooseWaypoint"), number)
        }
    }

    @ViewBuilder
    private func mapContent(in geometry: GeometryProxy) -> some View {
        let viewport = visibleViewport(in: geometry)
        ZStack(alignment: .topLeading) {
            mapCanvas(viewport: viewport, size: geometry.size)
            mapPins(viewport: viewport)
            if isExecutionMode {
                GoFlyExecutionHeader(
                    title: executionTitle,
                    detail: executionDetail,
                    symbol: executionSymbol,
                    onTrailingAction: joystick.wanderEnabled && joystick.canRandomizeWanderTarget ? { _ = joystick.randomizeWanderTarget() } : nil
                )
                    .padding(.horizontal, 16).padding(.top, 8)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { topFrame = $0 }
            } else { topBar }
            floatingSystemToast
                .padding(.horizontal, 16)
                .padding(.top, (topFrame.maxY > 0 ? topFrame.maxY : 116) + 8)
                .frame(maxWidth: .infinity)
                .zIndex(50)
            if showsMapControls { mapControls(bottomInset: geometry.safeAreaInsets.bottom) }
            bottomChrome(in: geometry)
        }
        .goFlySnackbar($snackbar, bottomPadding: snackbarBottomOffset(in: geometry))
        .onChange(of: service.error) { _, newError in
            if newError != nil { serviceNoticeDismissed = false }
        }
        .onChange(of: joystick.error) { _, newError in
            if newError != nil { joystickErrorDismissed = false }
        }
        .onChange(of: route.error) { _, newError in
            if newError != nil { routeErrorDismissed = false }
        }
        .onChange(of: recovery.noticeKey) { _, newKey in
            if newKey != nil { recoveryNoticeDismissed = false }
        }
        .onChange(of: continuation.noticeKey) { _, newKey in
            if newKey != nil { continuationNoticeDismissed = false }
        }
    }

    private func snackbarBottomOffset(in geometry: GeometryProxy) -> CGFloat {
        if mode == .teleport {
            let top = activeCandidate != nil && teleportCardFrame.height > 0
                ? teleportCardFrame.minY : panelFrame.minY
            return max(0, geometry.size.height - top) + 6
        }
        if activeCandidate != nil || wanderCardPlace != nil {
            let cardBottom = geometry.safeAreaInsets.bottom + 12
            let cardTop = cardBottom + 188
            return cardTop + 12
        } else {
            let panelTop = (showsBottomBar ? bottomBarHeight : geometry.safeAreaInsets.bottom) + max(currentCollapsedHeight, sheetHeight)
            return panelTop + 12
        }
    }

    /// Mark the actual road entrances; selected POIs remain in the editing fields.
    private var manualRouteWaypoints: [GeoCoordinate] {
        route.plannedRoute?.waypoints ?? []
    }

    private func mapCanvas(viewport: CGRect, size: CGSize) -> some View {
        let cameraViewport = activeCandidate == nil
            ? viewport
            : CGRect(origin: .zero, size: size)
        return GoFlyMapCanvas(
            marker: movement.presentation.marker, candidate: activeCandidate,
            viewport: cameraViewport, cameraIntent: cameraIntent,
            route: mode == .route ? route.plannedRoute : nil,
            routeWaypoints: mode == .route && route.draft.gpxSource == nil ? manualRouteWaypoints : nil,
            wanderTarget: isWanderMap ? joystick.wanderTarget?.place : nil,
            markerBearingDegrees: activeMarkerBearing,
            markerRoute: movement.presentation.route,
            markerRouteDistance: movement.presentation.routeDistance,
            adjustsFocusForViewportChanges: false,
            onMapTap: { coordinate in
                if let picker = route.picker {
                    picker.candidates.selectMapCoordinate(coordinate, resolver: mapPlaces)
                } else if isWanderMap {
                    wanderSearch.selectMapCoordinate(coordinate, resolver: mapPlaces)
                } else if mode == .teleport, route.canEdit {
                    search.selectMapCoordinate(coordinate, resolver: mapPlaces)
                    cameraIntent = GoFlyCameraIntent(coordinate: coordinate, ensureVisibleOnly: true)
                    sheetDetent = .collapsed
                }
            },
            onProjection: {
                MapKitSearchRegionContext.current = $0.searchRegion
                if projection != $0 { projection = $0 }
            }
        )
    }

    @ViewBuilder
    private func mapPins(viewport: CGRect) -> some View {
        if isWanderMap, let target = joystick.wanderTarget,
           let point = projection?.wanderTargetPoint, viewport.contains(point) {
            wanderPinOverlay(at: point, size: CGSize(width: 44, height: 44), viewport: viewport) {
                wanderTargetPin(target.place)
            }
        }
        if let candidate = activeCandidate, let point = projection?.candidatePoint {
            if isWanderMap {
                if viewport.contains(point) {
                    wanderPinOverlay(at: point, size: CGSize(width: max(84, goWidth), height: candidateHeight),
                                     viewport: viewport, avoiding: projection?.wanderTargetPoint) {
                        candidatePin(candidate)
                    }
                }
            } else {
                candidatePin(candidate)
                    .position(x: point.x, y: point.y - candidateHeight / 2)
            }
        }
    }

    private func captureCheckpoint() {
        let snapshot = recovery.snapshot(mode: mode)
        guard snapshot != lastCapturedSnapshot else { return }
        lastCapturedSnapshot = snapshot
        _ = recoveryStore.capture(snapshot)
    }

    /// A finite save window, independent of movement runtime and native cleanup.
    private func beginCheckpointFlush() {
        guard !checkpointWindowStarted else { return }
        checkpointWindowStarted = true
        guard recoveryStore.isSaving || recoveryStore.hasUnsavedChanges else { return }
        let id = UUID()
        checkpointWindowID = id
        checkpointBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save GoFly session") {
            Task { @MainActor in finishCheckpointWindow(id: id) }
        }
        checkpointFlushTask = Task { @MainActor in
            _ = await recoveryStore.flush()
            finishCheckpointWindow(id: id)
        }
    }

    private func finishCheckpointWindow(id: UUID?) {
        guard let id, checkpointWindowID == id else { return }
        checkpointWindowID = nil
        checkpointFlushTask?.cancel()
        checkpointFlushTask = nil
        let task = checkpointBackgroundTask
        checkpointBackgroundTask = .invalid
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
    }

    private func bottomChrome(in geometry: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if isExecutionMode {
                    bottomPanelContent(in: geometry)
                        .padding(.bottom, geometry.safeAreaInsets.bottom)
                        .background(GoFlyStyle.cardSurface)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) {
                            panelFrame = $0; sheetHeight = $0.height
                        }
                } else {
                    GoFlyBottomSheet(
                        detent: $sheetDetent,
                        availableHeight: sheetAvailableHeight(in: geometry),
                        collapsedHeight: currentCollapsedHeight,
                        maximumHeight: sheetMaxHeight(in: geometry),
                        contentHeight: bottomContentHeight,
                        fitsContent: mode == .teleport,
                        onHeightChange: { sheetHeight = $0 }
                    ) {
                        sheetContent(in: geometry)
                    }
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { panelFrame = $0 }
                }
                if showsBottomBar {
                    GoFlyBottomBar(selection: Binding(get: { mode }, set: { selectMode($0) }),
                                     bottomInset: geometry.safeAreaInsets.bottom)
                        .disabled(!canSwitchMode)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { bottomBarHeight = $0 }
                }
            }
            if isWanderMap, let place = wanderCardPlace {
                wanderLocationCard(for: place)
                    .padding(.horizontal, 16)
                    .padding(.bottom, (showsBottomBar ? bottomBarHeight : geometry.safeAreaInsets.bottom) + 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
            if mode == .route, let candidate = activeCandidate {
                GoFlyLocationCard(
                    place: candidate.place,
                    primaryActionType: isMapPicking ? .confirm : .add,
                    primaryActionTitle: isMapPicking ? goFlyString("common.confirm") : goFlyString("common.add"),
                    onPrimaryAction: {
                        if isMapPicking {
                            if let picker = route.picker {
                                _ = route.confirmPicker(id: picker.id)
                            }
                            isMapPicking = false
                            activeSearch.resetSelection()
                            sheetDetent = .expanded
                        } else {
                            _ = route.appendDestination(candidate.place)
                            activeSearch.resetSelection()
                            sheetDetent = .expanded
                        }
                    },
                    onDismiss: {
                        activeSearch.resetSelection()
                        if isMapPicking {
                            isMapPicking = false
                        }
                        sheetDetent = .expanded
                    },
                    onCopy: {
                        snackbar = GoFlySnackbarMessage(text: goFlyString("placeDetails.copied"))
                    },
                    distanceFrom: service.positionMarker?.coordinate,
                    identifier: isMapPicking ? "map.route.confirmCard" : "map.route.addCard"
                )
                .padding(.horizontal, 16)
                .padding(.bottom, (showsBottomBar ? bottomBarHeight : geometry.safeAreaInsets.bottom) + 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
            if mode == .teleport, let candidate = activeCandidate {
                GoFlyLocationCard(
                    place: candidate.place,
                    primaryActionType: .teleport,
                    primaryEnabled: !isGoButtonDisabled,
                    onPrimaryAction: {
                        performGo(candidate)
                    },
                    onDismiss: {
                        activeSearch.resetSelection()
                    },
                    onCopy: {
                        snackbar = GoFlySnackbarMessage(text: goFlyString("placeDetails.copied"))
                    },
                    distanceFrom: service.positionMarker?.coordinate,
                    identifier: "map.teleport.locationCard"
                )
                .padding(.horizontal, 16)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 12)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { frame in
                    // Exclude the outer bottom padding from the card bounds.
                    teleportCardFrame = CGRect(x: frame.minX, y: frame.minY,
                                              width: frame.width, height: frame.height - geometry.safeAreaInsets.bottom - 12)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: activeCandidate != nil) { _, hasCandidate in
            if hasCandidate {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    sheetDetent = .collapsed
                }
            }
        }
        .onChange(of: service.clearState) { _, state in
            guard state == .confirmed, service.coldClearPending else { return }
            Task {
                if await recoveryStore.clearMovementState() { service.finishColdClear() }
            }
        }
        .onChange(of: showsOperationPanel) { _, shown in
            if shown { sheetDetent = .expanded }
        }
        .onChange(of: route.picker?.id) { _, id in
            if id != nil { sheetDetent = .expanded }
        }
    }

    private func sheetContent(in geometry: GeometryProxy) -> some View {
        bottomPanelContent(in: geometry)
            .fixedSize(horizontal: false, vertical: mode == .teleport)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { bottomContentHeight = $0 }
            .frame(maxWidth: .infinity, alignment: .top)
    }

    private func sheetAvailableHeight(in geometry: GeometryProxy) -> CGFloat {
        max(200, geometry.size.height - (showsBottomBar ? 49 : 0))
    }

    private func bottomPanelContent(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            modePanel(in: geometry)
        }
    }

    private var isResumeState: Bool {
        if continuation.noticeKey != nil && !continuationNoticeDismissed { return true }
        if !route.canEdit, route.phase == .paused || route.phase == .interrupted { return true }
        if mode == .joystick, joystick.wanderEnabled,
           [.paused, .suspended, .interrupted].contains(joystick.phase) { return true }
        if mode == .teleport, positionHold.phase == .paused { return true }
        return false
    }

    private var currentCollapsedHeight: CGFloat {
        if isResumeState || mode == .route { return 76 }
        return 116
    }

    private func modePanel(in geometry: GeometryProxy) -> some View {
        Group {
            if mode == .joystick, route.canEdit, route.picker == nil {
                if isResumeState && [.paused, .suspended, .interrupted].contains(joystick.phase) {
                    GoFlyResumePanel(
                        title: goFlyString("joystick.wanderPaused"),
                        ctaTitle: goFlyString("wander.resumeShort"),
                        onResume: { _ = joystick.resume() },
                        isEnabled: joystick.canResume,
                        identifier: "joystick.resumePanel"
                    )
                } else {
                    ZStack(alignment: .bottom) {
                        GoFlyJoystickPanel(
                            controller: joystick, cameraHeadingDegrees: projection?.cameraHeadingDegrees ?? 0,
                            maximumHeight: isExecutionMode ? max(180, geometry.size.height - topFrame.maxY - 120) : contentMaximumHeight(in: geometry),
                            onRandomDestination: {
                                if joystick.randomizeWanderTarget() { wanderSearch.resetSelection() }
                            },
                            onSettings: { showingSettings = true }
                        )
                        // Keep an admitted finger alive through preparation; disappearance releases it.
                        .opacity(showsOperationPanel ? 0 : 1)
                        .accessibilityHidden(showsOperationPanel)
                        if showsOperationPanel { operationPanel(in: geometry) }
                    }
                }
            } else if showsOperationPanel {
                operationPanel(in: geometry)
            } else if mode == .route || !route.canEdit {
                if isResumeState && (route.phase == .paused || route.phase == .interrupted) {
                    GoFlyResumePanel(
                        title: goFlyString("background.routePaused"),
                        ctaTitle: goFlyString("route.resumeShort"),
                        onResume: { _ = route.resume() },
                        isEnabled: route.canResume,
                        identifier: "route.resumePanel"
                    )
                } else {
                    GoFlyRoutePanel(
                        controller: route, maximumHeight: isExecutionMode ? max(180, geometry.size.height - topFrame.maxY - 120) : contentMaximumHeight(in: geometry),
                        onEditNode: { _ = route.openPicker(for: $0) },
                        onSettings: { showingSettings = true },
                        onFocusPoint: { cameraIntent = GoFlyCameraIntent(coordinate: $0) },
                        currentLocationAvailable: service.currentRouteOrigin != nil,
                        currentRouteOrigin: { service.currentRouteOrigin },
                        isNarrow: sheetDetent == .collapsed || isMapPicking || (mode == .route && activeCandidate != nil),
                        onExpand: { sheetDetent = .expanded }
                    )
                }
            } else if isResumeState && mode == .teleport && (positionHold.phase == .paused || positionHold.phase == .completed) {
                GoFlyResumePanel(
                    title: goFlyString(hasFreshRealGPS ? "sheet.realPosition" : "sheet.lastSimulatedPosition"),
                    ctaTitle: goFlyString("teleport.resumeShort"),
                    onResume: { _ = positionHold.retry() },
                    isEnabled: positionHold.canRetry,
                    identifier: "teleport.resumePanel"
                )
            } else {
                teleportContent
            }
        }
    }

    private var isExecutionMode: Bool { !route.canEdit }

    private var executionTitle: String {
        if joystick.wanderEnabled { return joystick.wanderTarget?.place.title ?? goFlyString("joystick.wander") }
        if case .place(let place) = route.draft.destination?.value { return place.title }
        return goFlyString("mode.route")
    }

    private var executionSymbol: String {
        if joystick.wanderEnabled {
            return [.paused, .suspended, .interrupted].contains(joystick.phase) ? GoFlySymbols.pause : GoFlySymbols.heading
        }
        return [.paused, .interrupted].contains(route.phase) ? GoFlySymbols.pause : GoFlySymbols.heading
    }

    private var executionDetail: String {
        if joystick.wanderEnabled {
            return goFlyString("joystick.phase.\(joystick.phase.rawValue)") + " · "
                + goFlyLocalizedFormat(goFlyString("route.speedValue"), joystick.speed.kilometersPerHour)
        }
        let speed = goFlyLocalizedFormat(goFlyString("route.speedValue"), route.draft.speed.kilometersPerHour)
        guard !route.roundTripEnabled, let progress = route.progress else {
            return goFlyString("route.phase.\(route.phase.rawValue)") + " · " + speed
        }
        let remaining = max(0, route.heading == .reverse
            ? progress.committedDistanceMeters
            : progress.totalDistanceMeters - progress.committedDistanceMeters)
        let minutes = Int(ceil(Double(max(0, progress.estimatedRemaining.components.seconds)) / 60))
        return goFlyLocalizedFormat(goFlyString("route.distance"), remaining / 1_000) + " · "
            + goFlyLocalizedFormat(goFlyString("route.duration"), minutes) + " · " + speed
    }

    private func selectSearchPlace(_ place: MapPlace) {
        activeSearch.select(place)
        recordRecentPlace(place)
        cameraIntent = GoFlyCameraIntent(coordinate: place.coordinate)
        if mode == .teleport {
            sheetDetent = .collapsed
        } else {
            sheetDetent = .expanded
        }
        showingSearch = false
    }

    private func recordRecentPlace(_ place: MapPlace) {
        recentPlaces.removeAll { $0.coordinate == place.coordinate }
        recentPlaces.insert(place, at: 0)
        recentPlaces = Array(recentPlaces.prefix(8))
    }

    private func clearRecentPlaces() {
        withAnimation(.easeInOut(duration: 0.2)) {
            recentPlaces.removeAll()
        }
    }

    private func performGo(_ candidate: TeleportCandidate) {
        dismissKeyboard()
        if isWanderMap {
            if joystick.applyWanderTarget(candidate.place) { wanderSearch.clearCandidate(ifMatching: candidate.id) }
        } else if service.teleport(to: candidate), settingJoystickOrigin,
                  case .preparing(let intent) = service.pointState {
            joystickOriginIntentID = intent.id
        }
    }

    private func useCandidateInRoute(_ candidate: TeleportCandidate, asStart: Bool) {
        guard route.canEdit, route.draft.isManual else { return }
        // A destination always needs a start; use the same current-location
        // placeholder as a fresh route when the person removed every field.
        if !asStart, route.draft.nodes.isEmpty {
            guard route.openNewPicker(), let picker = route.picker,
                  route.confirmPicker(id: picker.id, useCurrentLocation: true) else { return }
        }
        let node = asStart ? route.draft.nodes.first : (route.draft.nodes.count > 1 ? route.draft.nodes.last : nil)
        if let node { _ = route.openPicker(for: node.id) }
        else { _ = route.openNewPicker() }
        if let picker = route.picker {
            picker.candidates.select(candidate.place)
            _ = route.confirmPicker(id: picker.id)
        }
        mode = .route
        sheetDetent = .expanded
    }

    private var teleportContent: some View {
        Group {
            if sheetDetent == .collapsed {
                collapsedPositionSummary
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            } else {
                expandedTeleportContent
            }
        }
    }

    /// Figma B1: the collapsed sheet is one row about the current simulated
    /// position, with the same favorite and copy actions as the place sheet.
    private var collapsedPositionSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(service.positionMarker?.source == .simulation ? goFlyString("sheet.currentPosition") : goFlyString("sheet.realPosition"))
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(currentPositionPlace?.title ?? goFlyString("sheet.noPosition"))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    if let coordinate = service.positionMarker?.coordinate {
                        Text(coordinate.displayText)
                            .font(.footnote)
                            .foregroundStyle(GoFlyStyle.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let coordinate = service.positionMarker?.coordinate {
                    let place = currentPositionPlace ?? MapPlace(id: .coordinate(coordinate), title: coordinate.displayText,
                                         coordinate: coordinate)
                    GoFlyFavoriteStar(place: place, identifier: "map.position.favorite")
                        .background(GoFlyStyle.secondarySurface, in: Circle())
                        .overlay { Circle().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                    Button {
                        UIPasteboard.general.string = coordinate.displayText
                        snackbar = GoFlySnackbarMessage(text: goFlyString("placeDetails.copied"))
                    } label: {
                        Image(systemName: "doc.on.doc").frame(width: 44, height: 44)
                            .background(GoFlyStyle.secondarySurface, in: Circle())
                            .overlay { Circle().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(goFlyString("placeDetails.copy"))
                    .accessibilityIdentifier("map.position.copy")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.collapsedPosition")
    }

    /// Reuse known place metadata; a visual summary never starts location work.
    private var currentPositionPlace: MapPlace? {
        guard let coordinate = service.positionMarker?.coordinate else { return nil }
        if let favorite = favorites.favorites.first(where: { $0.place.coordinate == coordinate }) {
            return MapPlace(id: .coordinate(coordinate), title: favorite.displayTitle,
                            coordinate: coordinate, address: favorite.place.address)
        }
        return recentPlaces.first(where: { $0.coordinate == coordinate })
            ?? MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
    }

    private var expandedTeleportContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsedPositionSummary
                .padding(.bottom, 12)
            Rectangle()
                .fill(GoFlyStyle.subtleBorder)
                .frame(height: 0.5)
            teleportSectionHeader("favorites.title", actionTitle: "search.viewAll") {
                presentedSheet = GoFlyMapSheet(content: .favorites)
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
            if favorites.favorites.isEmpty {
                Text(goFlyString("favorites.empty"))
                    .font(.footnote)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(favorites.favorites.prefix(2)) { favorite in
                        teleportPlaceRow(favorite.place, title: favorite.displayTitle,
                                         symbol: GoFlySymbols.favoriteSelected,
                                         identifier: "favorites.place.\(favorite.place.coordinate.displayText)")
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func teleportSectionHeader(_ key: String, actionTitle: String? = nil,
                                       action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(goFlyString(key))
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(goFlyString(actionTitle), action: action)
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("favorites.open")
            }
        }
    }

    private func teleportPlaceRow(_ place: MapPlace, title: String, symbol: String,
                                  identifier: String) -> some View {
        Button { selectSearchPlace(place) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(GoFlyStyle.secondarySurface, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GoFlyStyle.primary)
                        .lineLimit(1)
                    Text(place.address ?? place.coordinate.displayText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(GoFlyStyle.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: GoFlySymbols.disclosure)
                    .goFlyControlSymbol(size: 12, maximum: 16, weight: .semibold)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 64)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(GoFlyStyle.subtleBorder)
                    .frame(height: 0.5)
                    .padding(.leading, 48)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func operationPanel(in geometry: GeometryProxy) -> some View {
        GoFlyOperationPanel(
            operation: service.preparedOperation,
            unconfirmedFailure: unconfirmedFailure,
            nativeBusy: service.nativeBusy,
            maximumHeight: panelMaximumHeight(in: geometry),
            reasonIdentifier: "map.serviceError.message",
            cancelIdentifier: "map.serviceError.dismiss",
            onCancel: cancelPreparation,
            onRetry: { _ = service.retryPreparedOperation(id: $0) },
            onSettings: { showingSettings = true },
            onReturn: { returnedFromUnconfirmed = unconfirmedID }
        )
    }

    private func selectMode(_ value: GoFlyMapMode) {
        settingJoystickOrigin = false
        joystickOriginIntentID = nil
        mode = value
        if value == .joystick {
            service.warmupSession()
        }
        if value != .teleport { sheetDetent = .expanded }
    }

    private var activeMarkerBearing: Double? {
        if isWanderMap { return joystickMarkerBearing }
        if mode == .route || !route.canEdit {
            return routeMarkerBearing
        }
        if mode == .joystick {
            return joystickMarkerBearing
        }
        return nil
    }

    private var routeMarkerBearing: Double? {
        guard !route.canEdit, let planned = route.plannedRoute, let progress = route.progress else { return nil }
        let distance = progress.committedDistanceMeters
        let forward = route.heading == .forward
        let deltaDistance: Double = 3.0
        let lower = max(0, distance - deltaDistance)
        let upper = min(planned.totalDistanceMeters, distance + deltaDistance)
        guard let a = planned.coordinate(at: forward ? lower : upper),
              let b = planned.coordinate(at: forward ? upper : lower), a != b else { return nil }
        let latitudeA = a.latitude * .pi / 180
        let latitudeB = b.latitude * .pi / 180
        let delta = (b.longitude - a.longitude) * .pi / 180
        let y = sin(delta) * cos(latitudeB)
        let x = cos(latitudeA) * sin(latitudeB) - sin(latitudeA) * cos(latitudeB) * cos(delta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private var joystickMarkerBearing: Double? {
        guard let marker = service.positionMarker, marker.source == .simulation,
              marker.coordinate == joystick.lastAcknowledgedCoordinate else { return nil }
        return joystick.lastAcknowledgedBearingDegrees
    }

    /// Floating search entry and settings gear; execution mode supplies its own header.
    /// Floating search bar and status pill (plan 3). The gear and the clear
    /// control live inside the same rounded search field, as in Figma B1/B5.
    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                Button(action: beginSearch) {
                    HStack(spacing: 10) {
                        Image(systemName: GoFlySymbols.search)
                            .goFlyControlSymbol(size: 17, weight: .medium)
                            .foregroundStyle(GoFlyStyle.secondary)
                        Text(searchBarText)
                            .font(.body)
                            .foregroundStyle(hasSearchBarContent ? GoFlyStyle.primary : GoFlyStyle.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("search.placeholder"))
                .accessibilityValue(hasSearchBarContent ? searchBarText : "")
                .accessibilityHint(goFlyString("map.searchHint"))
                .accessibilityIdentifier("map.searchBar")

                if hasSearchBarContent {
                    Button(action: clearSearchBar) {
                        Image(systemName: GoFlySymbols.clearSearch)
                            .goFlyControlSymbol(size: 16, maximum: 18, weight: .medium)
                            .foregroundStyle(GoFlyStyle.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(goFlyString("search.clear"))
                    .accessibilityIdentifier("map.searchClear")
                }

                Button { showingSettings = true } label: {
                    Image(systemName: GoFlySymbols.settings)
                        .goFlyControlSymbol(size: 19, maximum: 22, weight: .medium)
                        .foregroundStyle(GoFlyStyle.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("settings.title"))
                .accessibilityIdentifier("map.settings")
                .padding(.trailing, 4)
            }
            .frame(minHeight: 50)
            .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 3)

            HStack {
                GoFlyStatusPill(text: pillText, tone: pillTone, action: expandSheet,
                                identifier: "map.statusPill")
                    .accessibilityValue(goFlyString(movement.status.textKey))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: .infinity, alignment: .top)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { topFrame = $0 }
    }

    private var searchBarText: String {
        if let candidate = activeCandidate { return candidate.place.title }
        if !search.query.isEmpty { return search.query }
        if isWanderMap, !wanderSearch.query.isEmpty { return wanderSearch.query }
        return goFlyString("search.placeholder")
    }

    private var hasSearchBarContent: Bool {
        if activeCandidate != nil { return true }
        if !search.query.isEmpty { return true }
        if isWanderMap, !wanderSearch.query.isEmpty { return true }
        return false
    }

    private func clearSearchBar() {
        settingJoystickOrigin = false
        joystickOriginIntentID = nil
        activeSearch.resetSelection()
    }

    /// The only map-side control: Figma `Recenter`. It also resets the map to north,
    /// so there is no separate compass or follow-heading button.
    private func mapControls(bottomInset: CGFloat) -> some View {
        Button { recenter() } label: {
            GoFlyRecenterIcon(size: 22)
        }
        .buttonStyle(GoFlyIconStyle(floating: true))
        .accessibilityLabel(goFlyString("map.recenter"))
        .accessibilityHint(goFlyString("map.recenterHint"))
        .accessibilityIdentifier("map.recenter")
        .padding(.trailing, 16)
        .padding(.bottom, max(0, sheetHeight + (showsBottomBar ? bottomBarHeight : 0) - bottomInset) + 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    /// Hidden while a place card, search or the route point picker covers the sheet.
    private var showsMapControls: Bool {
        activeCandidate == nil && wanderCardPlace == nil && !showingSearch && route.picker == nil
    }

    private var showsBottomBar: Bool {
        route.picker == nil && !showsOperationPanel && !isExecutionMode
    }

    private func beginSearch() {
        if !isWanderMap, canSwitchMode, mode != .teleport { selectMode(.teleport) }
        showingSearch = true
        searchFocusRequest = UUID()
    }

    private func expandSheet() {
        if mode == .teleport {
            sheetDetent = sheetDetent == .half ? .collapsed : .half
        } else {
            sheetDetent = sheetDetent == .expanded ? .half : .expanded
        }
    }

    private var pillText: String { goFlyString(movement.status.textKey) }

    private var pillTone: GoFlyStatusTone { movement.status.tone }

    private var hasFreshRealGPS: Bool {
        service.positionMarker?.source == .gps && service.positionMarker?.freshness == .fresh
    }

    private var displayStatusKey: String {
        if mode == .route, !route.canEdit {
            if route.usesPositionAxis, [.running, .pausing, .paused].contains(route.phase) {
                let prefix = route.roundTripEnabled ? "route.status.roundTrip" : "route.status"
                return "\(prefix).\(route.phase.rawValue).\(route.heading.rawValue)"
            }
            return "route.phase.\(route.phase.rawValue)"
        }
        if joystick.phase != .neutral { return "joystick.phase.\(joystick.phase.rawValue)" }
        switch service.pointState {
        case .sending: return "teleport.moving"
        case .unconfirmed: return "teleport.unconfirmed"
        default: return service.statusKey
        }
    }

    private func visibleViewport(in geometry: GeometryProxy) -> CGRect {
        let top = max(viewportGap, topFrame.maxY + viewportGap)
        let bottom = panelFrame.height > 0 ? panelFrame.minY - viewportGap : geometry.size.height - 92
        return CGRect(x: 16, y: top, width: max(1, geometry.size.width - 32), height: max(1, bottom - top))
    }

    private func sheetMaxHeight(in geometry: GeometryProxy) -> CGFloat {
        if mode == .teleport {
            return sheetAvailableHeight(in: geometry)
        }
        return max(132, geometry.size.height - max(topFrame.maxY, 96) - 96 - 49)
    }

    private func sheetRestingHeight(in geometry: GeometryProxy) -> CGFloat {
        if mode == .teleport {
            switch sheetDetent {
            case .collapsed: return currentCollapsedHeight
            case .half, .expanded:
                return min(sheetAvailableHeight(in: geometry), max(currentCollapsedHeight, bottomContentHeight + 24))
            }
        }
        let available = sheetAvailableHeight(in: geometry)
        let expanded = max(117, min(available * 0.88, sheetMaxHeight(in: geometry)))
        let half = min(expanded, max(116, available * 0.5))
        switch sheetDetent {
        case .collapsed: return currentCollapsedHeight
        case .half: return half
        case .expanded: return expanded
        }
    }

    private func panelMaximumHeight(in geometry: GeometryProxy) -> CGFloat {
        max(96, sheetRestingHeight(in: geometry) - 12)
    }

    private var minimumMapBand: CGFloat {
        // Two 44 pt map controls (plus spacing) must stay visible above the sheet.
        max(96, activeCandidate == nil ? (route.picker == nil ? 120 : 0)
                                       : candidateHeight * 2 + viewportGap * 2)
    }

    private func contentMaximumHeight(in geometry: GeometryProxy) -> CGFloat {
        max(96, sheetRestingHeight(in: geometry) - 20)
    }

    private var unconfirmedID: UUID? {
        if case .unconfirmed(let intent, _) = service.pointState { return intent.id }
        return nil
    }

    private var unconfirmedFailure: DeviceServiceFailure? {
        if case .unconfirmed(_, let failure) = service.pointState { return failure }
        return nil
    }

    private var showsOperationPanel: Bool {
        false
    }

    private var panelPresentsFailure: Bool {
        if case .failed = service.preparedOperation?.state { return true }
        if route.error != nil, !route.canEdit { return true }
        return showsOperationPanel && unconfirmedFailure != nil
    }

    private func cancelPreparation(_ id: UUID) {
        if service.cancelPreparation(id: id) { serviceNoticeDismissed = true }
    }

    private func candidatePin(_ candidate: TeleportCandidate) -> some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 4 : 0) {
            if route.picker == nil || isMapPicking { goButton(candidate) }
            pinButton(candidate)
        }
        .frame(width: max(84, goWidth))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { candidateHeight = $0 }
    }

    private func goButton(_ candidate: TeleportCandidate) -> some View {
        Button {
            if mode == .route {
                if isMapPicking {
                    if let picker = route.picker {
                        _ = route.confirmPicker(id: picker.id)
                    }
                    isMapPicking = false
                    activeSearch.resetSelection()
                    sheetDetent = .expanded
                } else {
                    _ = route.appendDestination(candidate.place)
                    activeSearch.resetSelection()
                    sheetDetent = .expanded
                }
            } else {
                performGo(candidate)
            }
        } label: {
            Text(goButtonTitle)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 28)
                .foregroundStyle(GoFlyStyle.surface)
                .background(GoFlyStyle.primary, in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isGoButtonDisabled)
        .accessibilityIdentifier("map.candidate.go")
    }

    private var goButtonTitle: String {
        if mode == .route {
            return isMapPicking ? goFlyString("common.confirm") : goFlyString("common.add")
        }
        return goFlyString("map.go")
    }

    private var isGoButtonDisabled: Bool {
        if mode == .route { return false }
        if isWanderMap {
            return !wanderSearch.canGo || !joystick.canApplyWanderTarget
        }
        return !search.canGo || !service.canTeleport
    }

    private func pinButton(_ candidate: TeleportCandidate) -> some View {
        Button {
            dismissKeyboard()
            if mode == .route {
                activeSearch.select(candidate.place)
                sheetDetent = .collapsed
            } else {
                sheetDetent = .half
            }
        } label: {
            GoFlyPlacePinIcon(kind: .candidate)
                .frame(width: 44, height: 44, alignment: .bottom)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(GoFlyStyle.primary)
        .accessibilityLabel(goFlyString("search.placeDetails"))
        .accessibilityValue(candidate.place.coordinate.displayText)
        .accessibilityIdentifier("map.candidate.pin")
    }

    private func wanderTargetPin(_ place: MapPlace) -> some View {
        Button {
            dismissKeyboard()
            selectedWanderPlace = place
        } label: {
            GoFlyPlacePinIcon(kind: .destination)
                .frame(width: 44, height: 44, alignment: .bottom)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(goFlyString("search.placeDetails"))
        .accessibilityValue(goFlyLocalizedFormat(goFlyString("joystick.currentTarget"), place.title))
        .accessibilityIdentifier("map.wander.target")
    }

    /// Move only the callout within the unobscured map. Its leader keeps the exact coordinate visible.
    private func wanderPinOverlay<Content: View>(at anchor: CGPoint, size: CGSize, viewport: CGRect,
                                                avoiding other: CGPoint? = nil,
                                                @ViewBuilder content: () -> Content) -> some View {
        let width = min(size.width, viewport.width)
        let height = min(size.height, viewport.height)
        let centerY = min(max(anchor.y - height / 2, viewport.minY + height / 2), viewport.maxY - height / 2)
        var centerX = min(max(anchor.x, viewport.minX + width / 2), viewport.maxX - width / 2)
        if let other, viewport.contains(other) {
            let otherX = min(max(other.x, viewport.minX + 22), viewport.maxX - 22)
            let otherY = min(max(other.y - 22, viewport.minY + 22), viewport.maxY - 22)
            if abs(centerX - otherX) < (width + 44) / 2,
               abs(centerY - otherY) < (height + 44) / 2 {
                let right = otherX + (width + 44) / 2 + 8
                let left = otherX - (width + 44) / 2 - 8
                centerX = right + width / 2 <= viewport.maxX ? right : max(viewport.minX + width / 2, left)
            }
        }
        let bottom = CGPoint(x: centerX, y: centerY + height / 2)
        return ZStack(alignment: .topLeading) {
            if hypot(bottom.x - anchor.x, bottom.y - anchor.y) > 1 {
                Path { path in path.move(to: anchor); path.addLine(to: bottom) }
                    .stroke(GoFlyStyle.primary, lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            content().position(x: centerX, y: centerY)
        }
    }

    private func recenter() {
        if let simulated = service.confirmedSimulatedLocation {
            cameraIntent = GoFlyCameraIntent(coordinate: simulated, headingDegrees: 0)
        } else {
            pendingGPSRecenter = true
            location.requestRecenter()
        }
    }

    private var wanderCardPlace: MapPlace? {
        selectedWanderPlace ?? (isWanderMap ? activeCandidate?.place : nil)
    }

    private func wanderLocationCard(for place: MapPlace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GoFlyPlaceDetailsView(
                place: place,
                onDismiss: {
                    selectedWanderPlace = nil
                    if isWanderMap {
                        wanderSearch.resetSelection()
                    }
                },
                embedded: true,
                distanceFrom: service.positionMarker?.coordinate,
                canGo: activeCandidate != nil ? (wanderSearch.canGo && joystick.canApplyWanderTarget) : joystick.canApplyWanderTarget,
                onGo: {
                    if let candidate = activeCandidate {
                        performGo(candidate)
                    } else if let wanderTarget = joystick.wanderTarget, wanderTarget.place == place {
                        _ = joystick.applyWanderTarget(place)
                    }
                    selectedWanderPlace = nil
                }
            )
        }
        .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 5)
        .accessibilityIdentifier("map.wander.locationCard")
    }

    @ViewBuilder
    private var floatingSystemToast: some View {
        if network.shouldShowWiFiError {
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyString("wifi.error.title"),
                message: goFlyString("wifi.error.message"),
                actionTitle: goFlyString("wifi.error.action"),
                onAction: { network.openWiFiSettings() },
                onDismiss: { network.dismissNotice() },
                identifier: "map.wifiError",
                isFloating: true
            )
        } else if let error = service.error, !serviceNoticeDismissed {
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyString(error.rawValue),
                message: goFlyString("status.repairGuidance"),
                onDismiss: { serviceNoticeDismissed = true },
                identifier: "map.serviceError",
                isFloating: true
            )
        } else if let failure = unconfirmedFailure, returnedFromUnconfirmed != unconfirmedID {
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyString(failure.rawValue),
                message: goFlyString("teleport.positionUnconfirmed") + " " + goFlyString("operation.failureGuidance"),
                actionTitle: goFlyString("operation.settings"),
                onAction: { showingSettings = true },
                onDismiss: { returnedFromUnconfirmed = unconfirmedID },
                identifier: "map.unconfirmedFailure",
                isFloating: true
            )
        } else if case .failed(let failure)? = service.preparedOperation?.state {
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyString(failure.rawValue),
                message: goFlyString("operation.failureGuidance"),
                actionTitle: goFlyString("operation.retry"),
                onAction: {
                    if let id = service.preparedOperation?.id { _ = service.retryPreparedOperation(id: id) }
                },
                onDismiss: {
                    if let id = service.preparedOperation?.id { _ = service.cancelPreparation(id: id) }
                },
                identifier: "map.operationFailure",
                isFloating: true
            )
        } else if let error = joystick.error, mode == .joystick, !joystickErrorDismissed {
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyString(error.localizationKey),
                message: goFlyString("status.repairGuidance"),
                actionTitle: goFlyString("operation.settings"),
                onAction: { showingSettings = true },
                onDismiss: { joystickErrorDismissed = true },
                identifier: "joystick.error",
                isFloating: true
            )
        } else if let error = joystick.wanderError, mode == .joystick {
            GoFlyStatusBanner(
                tone: .warning,
                title: goFlyString(error.localizationKey),
                message: goFlyString("status.repairGuidance"),
                actionTitle: joystick.canRetryWander ? goFlyString("operation.retry") : nil,
                onAction: joystick.canRetryWander ? { _ = joystick.retryWander() } : nil,
                onDismiss: { joystick.clearWanderError() },
                identifier: "joystick.wanderError",
                isFloating: true
            )
        } else if let error = route.error, mode == .route, !routeErrorDismissed {
            GoFlyStatusBanner(
                tone: .warning,
                title: goFlyString("route.error.shortTitle"),
                message: goFlyString(error.localizationKey),
                actionTitle: goFlyString("operation.retry"),
                onAction: { _ = route.retryPlanning() },
                onDismiss: { routeErrorDismissed = true },
                identifier: "route.error",
                isFloating: true
            )
        } else if let key = location.noticeKey, key != "location.noFix" {
            GoFlyStatusBanner(
                tone: .warning,
                title: goFlyString(key),
                onDismiss: { location.dismissNotice() },
                identifier: "map.locationNotice",
                isFloating: true
            )
        } else if let key = recovery.noticeKey, !recoveryNoticeDismissed {
            let cold = recovery.requiresColdConfirmation
            let tone: GoFlyStatusTone = key == "recovery.connectionRecovered" ? .success : .warning
            GoFlyStatusBanner(
                tone: tone,
                title: goFlyString(key),
                message: goFlyString("recovery.connectionGuidance"),
                actionTitle: goFlyString(cold ? "service.restoreGPS" : recovery.canRetryAutomaticRepair ? "common.retry" : "onboarding.vpn.check"),
                onAction: {
                    if cold { _ = service.restoreGPS() }
                    else { recovery.checkConnection() }
                },
                onDismiss: { recoveryNoticeDismissed = true },
                identifier: "recovery.connectionBanner",
                actionEnabled: cold ? service.canRestoreGPS : recovery.canCheck,
                actionIdentifier: cold ? "recovery.restoreGPS" : "recovery.checkConnection",
                titleIdentifier: "recovery.notice",
                isFloating: true
            )
        } else if (continuation.noticeKey != nil && !continuationNoticeDismissed) || isResumeState {
            let routePaused = mode == .route && (route.phase == .paused || route.phase == .interrupted)
            let holdPaused = positionHold.phase == .paused || positionHold.phase == .completed
            let wanderPaused = mode == .joystick && joystick.wanderEnabled && [.paused, .suspended, .interrupted].contains(joystick.phase)

            let title: String = routePaused ? goFlyString("background.routePaused")
                : (holdPaused ? goFlyString("background.positionPaused")
                : (wanderPaused ? goFlyString("joystick.wanderPaused") : goFlyString(continuation.noticeKey ?? "background.positionPaused")))

            let message: String = routePaused ? goFlyString("background.routePaused.message")
                : (holdPaused ? goFlyString("background.positionPaused.message") : goFlyString("status.repairGuidance"))

            GoFlyStatusBanner(
                tone: .warning,
                title: title,
                message: message,
                actionTitle: goFlyString("common.retry"),
                onAction: {
                    if routePaused { _ = route.resume() }
                    else if holdPaused { _ = positionHold.retry() }
                    else if wanderPaused { _ = joystick.resume() }
                    else { showingSettings = true }
                },
                onDismiss: { continuationNoticeDismissed = true },
                identifier: "map.continuationNotice",
                actionEnabled: routePaused ? route.canResume : (holdPaused ? positionHold.canRetry : true),
                isFloating: true
            )
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }


}

private struct GoFlyMapSheet: Identifiable {
    enum Content {
        case favorites
        case details(MapPlace)
    }
    let id = UUID()
    let content: Content
}

private typealias GoFlyMapMode = SessionMapMode

private extension SessionMapMode {
    var localizationKey: String { "mode.\(rawValue)" }
}

/// A compact map notice for a concrete continuation reason. The map decides
/// whether to show it after higher-priority recovery and cold-state notices.
struct GoFlyContinuationNotice: View {
    @ObservedObject var continuation: MovementContinuationController
    var onSettings: () -> Void = { }

    var hasContent: Bool {
        continuation.noticeKey != nil
    }

    var body: some View {
        if let key = continuation.noticeKey {
            GoFlyStatusBanner(tone: .warning, title: goFlyString(key),
                message: goFlyString("status.repairGuidance"),
                actionTitle: goFlyString("operation.settings"), onAction: onSettings,
                identifier: "background.notice", actionIdentifier: "background.settings")
        }
    }
}
