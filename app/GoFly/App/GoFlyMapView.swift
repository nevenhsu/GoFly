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
    @State private var modeHeaderHeight: CGFloat = 44
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
    @State private var recenterHeight: CGFloat = 44
    @State private var normalStatusHeight: CGFloat = 0
    @State private var statusHeight: CGFloat = 0
    @State private var searchMinimumHeight: CGFloat = 76
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
                let viewport = visibleViewport(in: geometry)
                let compactStatus = usesCompactStatus(in: geometry)
                ZStack(alignment: .topLeading) {
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
                    VStack(spacing: 0) {
                        VStack(spacing: 8) {
                            statusCard(compact: compactStatus)
                                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                                    statusHeight = height
                                    if !compactStatus { normalStatusHeight = height }
                                }
                            if route.completion != nil {
                                Text(goFlyString("route.completed"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
                                    .accessibilityIdentifier("route.completed")
                            }
                            if let error = service.error, !serviceNoticeDismissed, !panelPresentsFailure {
                                serviceFailureNotice(error)
                            }
                            if case .unconfirmed = service.pointState, !showsOperationPanel {
                                locationNoticeText("teleport.positionUnconfirmed")
                            }
                            if let notice = location.noticeKey {
                                locationNotice(notice)
                            }
                            if presentedSheet == nil {
                                GoFlyFavoriteFailureNotice(maximumHeight: 120)
                            }
                        }
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { topFrame = $0 }
                        Spacer(minLength: max(viewportGap, minimumMapBand - recenterHeight - 8))
                        HStack {
                            Spacer()
                            Button(action: recenter) {
                                Image(systemName: GoFlySymbols.recenter)
                            }
                            .buttonStyle(GoFlyIconStyle())
                            .accessibilityLabel(goFlyString("map.recenter"))
                            .accessibilityHint(goFlyString("map.recenterHint"))
                            .accessibilityIdentifier("map.recenter")
                        }
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { recenterHeight = $0 }
                        .padding(.bottom, 8)
                        bottomPanel(in: geometry)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 4 : 8)
                    .padding(.bottom, bottomPadding)
                }
                .coordinateSpace(name: "mapRoot")
                .accessibilityHidden(presentedSheet != nil)
                .onChange(of: geometry.size.width) { _, _ in normalStatusHeight = 0 }
                .onChange(of: dynamicTypeSize) { _, _ in normalStatusHeight = 0 }
                .onChange(of: positionSourceTitle) { _, _ in normalStatusHeight = 0 }
                .onChange(of: displayStatusKey) { _, _ in normalStatusHeight = 0 }
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

    private func bottomPanel(in geometry: GeometryProxy) -> some View {
        Group {
            if route.picker != nil {
                // The picker already owns its keyboard-adjusted scroll viewport.
                // Keep that layout independent of the ordinary recovery panel.
                bottomPanelContent(in: geometry)
            } else {
                ScrollView {
                    bottomPanelContent(in: geometry)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { bottomContentHeight = $0 }
                }
                .frame(height: min(bottomContentHeight, panelMaximumHeight(in: geometry)))
                .accessibilityIdentifier("map.panels.scroll")
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { panelFrame = $0 }
        .onChange(of: service.clearState) { _, state in
            guard state == .confirmed, service.coldClearPending else { return }
            Task {
                if await recoveryStore.clearMovementState() { service.finishColdClear() }
            }
        }
    }

    private func bottomPanelContent(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            if canSwitchMode { modeSelector }
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
                    onFavorites: { presentedSheet = GoFlyMapSheet(content: .favorites) },
                    onMinimumHeightChange: { searchMinimumHeight = $0 }
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

    private var modeSelector: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                modeButton(.teleport, key: "mode.teleport")
                modeButton(.route, key: "mode.route")
                modeButton(.joystick, key: "mode.joystick")
            }
            .padding(4)
            .background(GoFlyStyle.secondarySurface, in: Capsule())
            .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5).allowsHitTesting(false) }
            Menu {
                ForEach(GoFlyMapMode.allCases, id: \.self) { value in
                    Button { selectMode(value) } label: {
                        if mode == value { Label(goFlyString(value.localizationKey), systemImage: GoFlySymbols.selected) }
                        else { Text(goFlyString(value.localizationKey)) }
                    }
                    .accessibilityIdentifier(value.localizationKey)
                }
            } label: {
                HStack {
                    Text(goFlyString(mode.localizationKey))
                    Spacer(minLength: 12)
                    Image(systemName: GoFlySymbols.expand)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(4)
            .background(GoFlyStyle.surface, in: Capsule())
            .accessibilityLabel(goFlyString("mode.title"))
            .accessibilityValue(goFlyString(mode.localizationKey))
            .accessibilityIdentifier("map.mode.menu")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(goFlyString("mode.title"))
        .accessibilityIdentifier("map.mode")
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { modeHeaderHeight = $0 }
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
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
                .foregroundStyle(mode == value ? GoFlyStyle.surface : GoFlyStyle.primary)
                .background(mode == value ? GoFlyStyle.primary : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? .isSelected : [])
        .accessibilityIdentifier(key)
    }

    private func statusCard(compact: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if !compact || service.positionMarker?.source == .simulation {
                    Text(positionSourceTitle).font(compact ? .caption : .headline)
                }
                Text(goFlyString(displayStatusKey))
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(positionSourceTitle), \(goFlyString(displayStatusKey))")
            .accessibilityIdentifier("map.positionStatus")

            Button {
                if route.canPause { _ = route.pause() }
                else if route.canResume { _ = route.resume() }
                else if joystick.canPause { _ = joystick.pause() }
                else if joystick.canResume { _ = joystick.resume() }
                else { _ = service.start() }
            } label: {
                if route.phase == .pausing || joystick.phase == .pausing || service.phase == .preparing {
                    ProgressView()
                } else {
                    Image(systemName: route.canPause || joystick.canPause ? GoFlySymbols.pause : GoFlySymbols.play)
                }
            }
            .disabled(!route.canPause && !route.canResume && !joystick.canPause && !joystick.canResume
                      && (!route.canEdit || !service.canStart))
            .buttonStyle(GoFlyIconStyle())
            .accessibilityLabel(goFlyString(
                route.canPause || joystick.canPause ? "map.pause" :
                    (route.canResume || joystick.canResume ? "route.resume" : (service.nativeBusy ? service.statusKey : "service.start"))
            ))
            .accessibilityHint(goFlyString(route.canPause ? "route.pauseHint" :
                (route.canResume ? "route.resumeHint" :
                    (joystick.canPause ? "joystick.pauseHint" :
                        (joystick.canResume ? (joystick.wanderEnabled ? "joystick.wanderResumeHint" : "joystick.resumeHint") :
                            (service.canStart ? "map.startServiceHint" : "map.noActiveTask"))))))
            .accessibilityIdentifier("map.serviceControl")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: GoFlySymbols.settings)
            }
            .buttonStyle(GoFlyIconStyle())
            .accessibilityLabel(goFlyString("settings.title"))
            .accessibilityIdentifier("map.settings")
        }
        .padding(dynamicTypeSize.isAccessibilitySize ? 8 : 16)
        .goFlyCard(floating: true)
    }

    private var positionSourceTitle: String {
        goFlyString(service.positionMarker?.source == .simulation ? "map.simulatedLocation" : "map.currentLocation")
    }

    private func usesCompactStatus(in geometry: GeometryProxy) -> Bool {
        guard normalStatusHeight > 0, mode == .teleport, canSwitchMode else { return false }
        let otherNotices = max(0, topFrame.height - statusHeight)
        // Keep the full-card measurement while compact, so fitting cannot toggle the layout back.
        let required = topFrame.minY + normalStatusHeight + otherNotices + minimumMapBand
            + modeHeaderHeight + 8 + searchMinimumHeight + bottomPadding
        return required > geometry.size.height
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
        max(76, geometry.size.height - topFrame.maxY - minimumMapBand - bottomPadding)
    }

    private var minimumMapBand: CGFloat {
        max(recenterHeight + 8 + viewportGap * 2,
            activeCandidate == nil ? (route.picker == nil ? 120 : 0) : candidateHeight * 2 + viewportGap * 2)
    }

    private func contentMaximumHeight(in geometry: GeometryProxy) -> CGFloat {
        max(76, panelMaximumHeight(in: geometry) - (canSwitchMode ? modeHeaderHeight + 8 : 0))
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

    private func recenter() {
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
