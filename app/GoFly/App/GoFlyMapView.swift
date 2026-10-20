import GoFlyCore
import GoFlyTransport
import MapKit
import SwiftUI
import UIKit

/// One App-owned assembly, created before SwiftUI attaches its observers.
/// View reconstruction reuses these exact domain owners and cannot fence live work.
@MainActor
final class GoFlyMovementModel: ObservableObject {
    @Published private(set) var presentationMode: SessionMapMode
    let route: RouteExecutionController
    let joystick: JoystickMovementController
    let recovery: ConnectionRecoveryController
    let continuation: MovementContinuationController
    private var mapAdmission: (@MainActor () -> Bool)?

    init(service: ServiceController, recoveryStore: SessionRecoveryStore) {
        let snapshot = recoveryStore.initialSnapshot
        presentationMode = snapshot.mode
        route = RouteExecutionController(
            draft: Self.routeDraft(restoring: snapshot.draft), planner: Self.routePlanner(),
            commands: service, search: MapKitPlaceSearch()
        )
        _ = route.setRoundTripEnabled(snapshot.roundTripEnabled)
        joystick = JoystickMovementController(commands: service, speed: snapshot.joystickSpeed)
        recovery = ConnectionRecoveryController(
            service: service, route: route, joystick: joystick,
            probe: NetworkTunnelProbe(), retainedColdSnapshot: snapshot
        )
        continuation = MovementContinuationController(
            service: service, route: route, joystick: joystick, recovery: recovery,
            driver: GoFlyContinuedProcessingDriver.shared,
            presentation: { kind, progress in
                (title: goFlyString("background.activity.\(kind.rawValue)"),
                 subtitle: goFlyLocalizedFormat(
                    goFlyString("background.activity.progress"), progress.acknowledgedWrites))
            }
        )
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

    private static func routePlanner() -> any RoutePlanning { MapKitWalkingRoutePlanner() }

}

struct GoFlyMapView: View {
    @ObservedObject private var movement: GoFlyMovementModel
    @ObservedObject var service: ServiceController
    @ObservedObject var recoveryStore: SessionRecoveryStore
    let setupMetadata: GoFlySetupMetadata?
    @ObservedObject private var route: RouteExecutionController
    @ObservedObject private var joystick: JoystickMovementController
    @ObservedObject private var recovery: ConnectionRecoveryController
    @ObservedObject private var continuation: MovementContinuationController
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
    @State private var bottomContentHeight: CGFloat = 260
    @State private var sheetDetent: GoFlySheetDetent = .half
    @State private var sheetHeight: CGFloat = 320
    @State private var presentedSheet: GoFlyMapSheet?
    @State private var searchFocusRequest: UUID?
    @State private var focusAfterSheet = false
    @State private var candidateHeight: CGFloat = 96
    @ScaledMetric(relativeTo: .body) private var goWidth: CGFloat = 68
    @State private var showingSettings = false
    @State private var serviceNoticeDismissed = false
    @State private var returnedFromUnconfirmed: UUID?
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
                .accessibilityHidden(presentedSheet != nil)
            }
            .background(GoFlyStyle.canvas.ignoresSafeArea())
            .goFlyNativeBackTitle()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingSettings) {
                ServiceSettingsView(
                    service: service,
                    continuation: continuation,
                    recovery: recovery,
                    setupMetadata: setupMetadata
                )
            }
            .onAppear {
                movement.attachMapAdmission {
                    !showingSettings && presentedSheet == nil && route.picker == nil
                }
                if cameraIntent == nil {
                    if mode == .route, let planned = route.plannedRoute {
                        cameraIntent = GoFlyCameraIntent(route: planned)
                    } else if let position = service.positionMarker {
                        cameraIntent = GoFlyCameraIntent(coordinate: position.coordinate)
                    }
                }
                if scenePhase == .active { continuation.sceneDidBecomeActive() }
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
                cameraIntent = GoFlyCameraIntent(coordinate: coordinate)
            }
            .onChange(of: activeCandidate?.id, initial: true) { _, id in
                guard let candidate = activeCandidate, candidate.id == id else { return }
                pendingGPSRecenter = false
                guard !isWanderMap else { return }
                cameraIntent = GoFlyCameraIntent(coordinate: candidate.place.coordinate)
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
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                route.dismissCompletion(executionID: id)
            }
            .onChange(of: service.pointState) { _, state in
                guard case .acknowledged(let intent) = state else { return }
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
            .sheet(item: $presentedSheet, onDismiss: {
                if focusAfterSheet {
                    focusAfterSheet = false
                    searchFocusRequest = UUID()
                }
            }) { sheet in
                switch sheet.content {
                case .favorites:
                    GoFlyFavoritesView(
                        candidate: activeSearch.candidate?.place,
                        onSelect: { activeSearch.select($0); presentedSheet = nil },
                        onSearch: { focusAfterSheet = true; presentedSheet = nil },
                        onDismiss: { presentedSheet = nil }
                    )
                case .details(let place):
                    GoFlyPlaceDetailsView(place: place) { presentedSheet = nil }
                }
            }
        }
        .tint(GoFlyStyle.primary)
    }

    @ViewBuilder
    private func mapContent(in geometry: GeometryProxy) -> some View {
        let viewport = visibleViewport(in: geometry)
        ZStack(alignment: .topLeading) {
            mapCanvas(viewport: viewport)
            mapPins(viewport: viewport)
            topBar
            mapControls
            bottomChrome(in: geometry)
        }
    }

    private func mapCanvas(viewport: CGRect) -> some View {
        GoFlyMapCanvas(
            marker: service.positionMarker, candidate: activeCandidate,
            viewport: viewport, cameraIntent: cameraIntent,
            route: mode == .route ? route.plannedRoute : nil,
            wanderTarget: isWanderMap ? joystick.wanderTarget?.place : nil,
            markerBearingDegrees: joystickMarkerBearing,
            adjustsFocusForViewportChanges: mode != .joystick,
            onMapTap: { coordinate in
                if let picker = route.picker {
                    picker.candidates.selectMapCoordinate(coordinate, resolver: mapPlaces)
                } else if isWanderMap {
                    wanderSearch.selectMapCoordinate(coordinate, resolver: mapPlaces)
                } else if mode == .teleport, route.canEdit {
                    search.selectMapCoordinate(coordinate)
                }
            },
            onProjection: { if projection != $0 { projection = $0 } }
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
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            GoFlyBottomSheet(
                detent: $sheetDetent,
                availableHeight: sheetAvailableHeight(in: geometry),
                collapsedHeight: 96,
                onHeightChange: { sheetHeight = $0 }
            ) {
                sheetContent(in: geometry)
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { panelFrame = $0 }
            if showsBottomBar {
                GoFlyBottomBar(selection: Binding(get: { mode }, set: { selectMode($0) }))
                    .disabled(!canSwitchMode)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
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
        Group {
            if route.picker != nil {
                // The picker already owns its keyboard-adjusted scroll viewport.
                bottomPanelContent(in: geometry)
            } else {
                ScrollView {
                    bottomPanelContent(in: geometry)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { bottomContentHeight = $0 }
                }
                .scrollIndicators(.hidden)
                .frame(height: min(bottomContentHeight, max(96, sheetHeight - 44)))
                .accessibilityIdentifier("map.panels.scroll")
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func sheetAvailableHeight(in geometry: GeometryProxy) -> CGFloat {
        max(200, geometry.size.height - max(topFrame.maxY, 96) - minimumMapBand
            - (showsBottomBar ? 74 : 0) - bottomPadding)
    }

    private func bottomPanelContent(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            if route.picker == nil, !showsOperationPanel {
                let notice = GoFlyRecoveryView(
                    recovery: recovery, store: recoveryStore, service: service,
                    maximumHeight: .greatestFiniteMagnitude,
                    onSettings: { showingSettings = true }
                )
                if notice.hasContent { notice }
                if recovery.noticeKey == nil, !recovery.requiresColdConfirmation,
                   continuation.noticeKey != nil {
                    GoFlyContinuationNotice(continuation: continuation) { showingSettings = true }
                }
            }
            modePanel(in: geometry)
        }
    }

    private func modePanel(in geometry: GeometryProxy) -> some View {
        Group {
            if mode == .joystick, route.canEdit, route.picker == nil {
                ZStack(alignment: .bottom) {
                    GoFlyJoystickPanel(
                        controller: joystick, cameraHeadingDegrees: projection?.cameraHeadingDegrees ?? 0,
                        maximumHeight: contentMaximumHeight(in: geometry),
                        onSetOrigin: beginJoystickOriginSelection,
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
            } else if showsOperationPanel {
                operationPanel(in: geometry)
            } else if let picker = route.picker {
                GoFlyRoutePickerView(
                    session: picker, maximumHeight: contentMaximumHeight(in: geometry),
                    focusRequest: searchFocusRequest,
                    onFavorites: { presentedSheet = GoFlyMapSheet(content: .favorites) },
                    onConfirm: { id, useCurrent in _ = route.confirmPicker(id: id, useCurrentLocation: useCurrent) },
                    onCancel: { route.cancelPicker(id: $0) },
                    onStagedCurrentChange: { useCurrent in
                        if useCurrent, route.stagePickerCurrent(id: picker.id), let origin = service.currentRouteOrigin {
                            cameraIntent = GoFlyCameraIntent(coordinate: origin)
                        }
                    },
                    onClearPlace: { _ = route.clearPickerPlace(id: $0) }
                )
                .id(picker.id)
            } else if mode == .route || !route.canEdit {
                GoFlyRoutePanel(
                    controller: route, maximumHeight: contentMaximumHeight(in: geometry),
                    onEditNode: { _ = route.openPicker(for: $0) },
                    onSettings: { showingSettings = true },
                    currentLocationAvailable: service.currentRouteOrigin != nil,
                    currentRouteOrigin: { service.currentRouteOrigin }
                )
            } else {
                GoFlySearchPanel(
                    search: search, maximumHeight: contentMaximumHeight(in: geometry),
                    focusRequest: searchFocusRequest,
                    onFavorites: { presentedSheet = GoFlyMapSheet(content: .favorites) }
                )
            }
        }
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
    }

    private func beginJoystickOriginSelection() {
        settingJoystickOrigin = true
        joystickOriginIntentID = nil
        mode = .teleport
    }

    private var joystickMarkerBearing: Double? {
        guard let marker = service.positionMarker, marker.source == .simulation,
              marker.coordinate == joystick.lastAcknowledgedCoordinate else { return nil }
        return joystick.lastAcknowledgedBearingDegrees
    }

    private func modeButton(_ value: GoFlyMapMode, key: String) -> some View {
        Button { selectMode(value) } label: {
            Text(goFlyString(key))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 8)
                .foregroundStyle(mode == value ? GoFlyStyle.surface : GoFlyStyle.primary)
                .background(mode == value ? GoFlyStyle.primary : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(mode == value ? .isSelected : [])
        .accessibilityIdentifier(key)
    }

    /// Floating search bar with the settings gear (plan 3). Tapping it opens the
    /// search experience; until the full-screen page lands it focuses the
    /// teleport panel so search stays usable in every intermediate build.
    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: beginSearch) {
                    HStack(spacing: 10) {
                        Image(systemName: GoFlySymbols.search)
                            .goFlyControlSymbol(size: 17, weight: .semibold)
                            .foregroundStyle(GoFlyStyle.secondary)
                        Text(goFlyString("search.placeholder"))
                            .font(.body)
                            .foregroundStyle(GoFlyStyle.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(GoFlyStyle.surface, in: Capsule())
                    .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 3)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("search.placeholder"))
                .accessibilityHint(goFlyString("map.searchHint"))
                .accessibilityIdentifier("map.searchBar")

                Button { showingSettings = true } label: {
                    Image(systemName: GoFlySymbols.settings)
                }
                .buttonStyle(GoFlyIconStyle())
                .accessibilityLabel(goFlyString("settings.title"))
                .accessibilityIdentifier("map.settings")
            }
            HStack {
                GoFlyStatusPill(text: pillText, tone: pillTone, action: expandSheet,
                                identifier: "map.statusPill")
                    .accessibilityValue(goFlyString(displayStatusKey))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: .infinity, alignment: .top)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { topFrame = $0 }
    }

    private var mapControls: some View {
        VStack(spacing: 8) {
            if let heading = projection?.cameraHeadingDegrees,
               abs(heading.truncatingRemainder(dividingBy: 360)) > 1 {
                Button { recenter(resetHeading: true) } label: {
                    Image(systemName: GoFlySymbols.compass)
                }
                .buttonStyle(GoFlyIconStyle())
                .accessibilityLabel(goFlyString("map.north"))
                .accessibilityIdentifier("map.north")
            }
            Button { recenter() } label: {
                Image(systemName: GoFlySymbols.recenter)
            }
            .buttonStyle(GoFlyIconStyle())
            .accessibilityLabel(goFlyString("map.recenter"))
            .accessibilityHint(goFlyString("map.recenterHint"))
            .accessibilityIdentifier("map.recenter")
        }
        .padding(.trailing, 16)
        .padding(.bottom, sheetHeight + (showsBottomBar ? 74 : 0) + 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var showsBottomBar: Bool {
        route.picker == nil && !showsOperationPanel
    }

    private func beginSearch() {
        if canSwitchMode, mode != .teleport { selectMode(.teleport) }
        sheetDetent = .expanded
        searchFocusRequest = UUID()
    }

    private func expandSheet() {
        sheetDetent = sheetDetent == .expanded ? .half : .expanded
    }

    private var pillText: String {
        if service.error != nil || unconfirmedID != nil || service.phase == .repairRequired {
            return goFlyString("status.pill.error")
        }
        if case .preparing = service.pointState { return goFlyString("status.pill.preparing") }
        if !route.canEdit, [.running, .pausing].contains(route.phase) {
            return goFlyString("status.pill.running")
        }
        if !route.canEdit, route.phase == .paused { return goFlyString("status.pill.paused") }
        if [.moving].contains(joystick.phase) { return goFlyString("status.pill.running") }
        if joystick.phase == .paused { return goFlyString("status.pill.paused") }
        if service.positionMarker?.source == .simulation { return goFlyString("status.pill.simulating") }
        return goFlyString("status.pill.standby")
    }

    private var pillTone: GoFlyStatusTone {
        if service.error != nil || unconfirmedID != nil || service.phase == .repairRequired { return .danger }
        if !route.canEdit, route.phase == .running || joystick.phase == .moving { return .active }
        if service.positionMarker?.source == .simulation { return .active }
        return .neutral
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

    private func panelMaximumHeight(in geometry: GeometryProxy) -> CGFloat {
        max(96, sheetHeight - 44)
    }

    private var minimumMapBand: CGFloat {
        // Two 44 pt map controls (plus spacing) must stay visible above the sheet.
        max(96, activeCandidate == nil ? (route.picker == nil ? 120 : 0)
                                       : candidateHeight * 2 + viewportGap * 2)
    }

    private func contentMaximumHeight(in geometry: GeometryProxy) -> CGFloat {
        max(96, sheetHeight - 52)
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
        service.preparedOperation != nil || (unconfirmedID != nil && returnedFromUnconfirmed != unconfirmedID)
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
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 4 : 8) {
            if route.picker == nil { goButton(candidate) }
            pinButton(candidate)
        }
        .frame(width: max(84, goWidth))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { candidateHeight = $0 }
    }

    private func goButton(_ candidate: TeleportCandidate) -> some View {
        Button {
                dismissKeyboard()
                if isWanderMap {
                    if joystick.applyWanderTarget(candidate.place) {
                        wanderSearch.clearCandidate(ifMatching: candidate.id)
                    }
                } else if service.teleport(to: candidate), settingJoystickOrigin,
                          case .preparing(let intent) = service.pointState {
                    joystickOriginIntentID = intent.id
                }
            } label: {
                Text(goFlyString("map.go"))
            }
            .buttonStyle(GoFlyActionStyle(primary: true, compactAtAccessibilitySizes: true))
            .frame(width: goWidth)
            .disabled(isWanderMap ? (!wanderSearch.canGo || !joystick.canApplyWanderTarget) : (!search.canGo || !service.canTeleport))
            .accessibilityIdentifier("map.candidate.go")
    }

    private func pinButton(_ candidate: TeleportCandidate) -> some View {
        Button {
                dismissKeyboard()
                presentedSheet = GoFlyMapSheet(content: .details(candidate.place))
            } label: {
                GoFlyPlacePinIcon(kind: .candidate)
                .frame(width: 44, height: 44, alignment: .bottom)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(GoFlyStyle.primary)
            .accessibilityLabel(goFlyString("search.placeDetails"))
            .accessibilityValue(route.picker != nil ? candidate.place.coordinate.displayText : candidate.place.title)
            .accessibilityIdentifier("map.candidate.pin")
    }

    private func wanderTargetPin(_ place: MapPlace) -> some View {
        Button {
            dismissKeyboard()
            presentedSheet = GoFlyMapSheet(content: .details(place))
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

    private func recenter(resetHeading: Bool = false) {
        if resetHeading, let center = projection?.centerCoordinate {
            cameraIntent = GoFlyCameraIntent(coordinate: center, setsHeadingNorth: true)
            return
        }
        if let simulated = service.confirmedSimulatedLocation {
            cameraIntent = GoFlyCameraIntent(coordinate: simulated)
        } else {
            pendingGPSRecenter = true
            location.requestRecenter()
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func locationNoticeText(_ key: String) -> some View {
        Text(goFlyString(key))
            .font(.footnote)
            .foregroundStyle(GoFlyStyle.errorForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func locationNotice(_ key: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(goFlyString(key))
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            Button {
                location.dismissNotice()
            } label: {
                Image(systemName: GoFlySymbols.close)
                    .goFlyControlSymbol(size: 14, maximum: 18, weight: .semibold)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(goFlyString("common.dismiss"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("map.locationNotice")
    }

    private func serviceFailureNotice(_ error: DeviceServiceFailure) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: GoFlySymbols.warning)
                .padding(.top, 12)
                .accessibilityHidden(true)
            Text(goFlyString(error.rawValue))
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .accessibilityIdentifier("map.serviceError.message")
            Button {
                serviceNoticeDismissed = true
            } label: {
                Image(systemName: GoFlySymbols.close)
                    .goFlyControlSymbol(size: 14, maximum: 18, weight: .semibold)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(goFlyString("common.dismiss"))
            .accessibilityIdentifier("map.serviceError.dismiss")
        }
        .foregroundStyle(GoFlyStyle.errorForeground)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
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
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(goFlyString(key))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: GoFlySymbols.warning)
                }
                .font(.subheadline)
                .accessibilityIdentifier("background.notice")

                Button(action: onSettings) {
                    Text(goFlyString("operation.settings"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GoFlyActionStyle())
                .accessibilityIdentifier("background.settings")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .goFlyCard(floating: true)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("background.notice.panel")
        }
    }
}
