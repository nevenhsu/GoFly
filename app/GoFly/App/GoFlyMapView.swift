import GoFlyCore
import MapKit
import SwiftUI
import UIKit

struct GoFlyMapView: View {
    @ObservedObject var service: ServiceController
    @StateObject private var route: RouteExecutionController
    @State private var mode: GoFlyMapMode = .teleport
    @State private var modeHeaderHeight: CGFloat = 44
    @StateObject private var location = GoFlyRealLocation()
    @StateObject private var search = CandidateController(search: MapKitPlaceSearch())
    @State private var cameraIntent: GoFlyCameraIntent?
    private let mapPlaces = MapKitPlaceResolver()
    @State private var pendingGPSRecenter = false
    @State private var projection: GoFlyMapProjection?
    @State private var topFrame = CGRect.zero
    @State private var panelFrame = CGRect.zero
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(service: ServiceController) {
        _service = ObservedObject(wrappedValue: service)
        _route = StateObject(wrappedValue: RouteExecutionController(
            draft: Self.routeDraft(), planner: Self.routePlanner(), commands: service, search: MapKitPlaceSearch()
        ))
    }

    private static func routeDraft() -> RouteDraft {
        #if DEBUG && targetEnvironment(simulator)
        return initialRouteUITestDraft() ?? RouteDraft()
        #else
        return RouteDraft()
        #endif
    }

    private static func routePlanner() -> any RoutePlanning {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-route-planning-delay") {
            return DelayedFailureRouteUITestPlanner()
        }
        #endif
        return MapKitWalkingRoutePlanner()
    }

    private var activeSearch: CandidateController { route.picker?.candidates ?? search }
    private var activeCandidate: TeleportCandidate? {
        if let picker = route.picker { return picker.candidates.candidate }
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
                        onMapTap: { coordinate in
                            if let picker = route.picker {
                                picker.candidates.selectMapCoordinate(coordinate, resolver: mapPlaces)
                            } else if mode == .teleport, route.canEdit {
                                search.selectMapCoordinate(coordinate)
                            }
                        },
                        onProjection: { if projection != $0 { projection = $0 } }
                    )
                    if let candidate = activeCandidate, let point = projection?.candidatePoint {
                        candidatePin(candidate)
                            .position(x: point.x, y: point.y - candidateHeight / 2)
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
                                Image(systemName: "location.viewfinder")
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
                    mapMetrics(origin: geometry.frame(in: .global).origin)
                }
                .coordinateSpace(name: "mapRoot")
                .accessibilityHidden(presentedSheet != nil)
                .onChange(of: geometry.size.width) { _, _ in normalStatusHeight = 0 }
                .onChange(of: dynamicTypeSize) { _, _ in normalStatusHeight = 0 }
                .onChange(of: positionSourceTitle) { _, _ in normalStatusHeight = 0 }
                .onChange(of: displayStatusKey) { _, _ in normalStatusHeight = 0 }
            }
            .background(GoFlyStyle.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingSettings) {
                ServiceSettingsView(service: service)
            }
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
                      mode == .teleport || route.plannedRoute == nil || explicitlyRequested,
                      (route.picker == nil ? activeCandidate == nil : activeSearch.candidate == nil) || explicitlyRequested,
                      let coordinate = GeoCoordinate(latitude: accepted.latitude, longitude: accepted.longitude) else { return }
                cameraIntent = GoFlyCameraIntent(coordinate: coordinate)
            }
            .onChange(of: activeCandidate?.id, initial: true) { _, id in
                guard let candidate = activeCandidate, candidate.id == id else { return }
                pendingGPSRecenter = false
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

    private func bottomPanel(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            if canSwitchMode {
                HStack(spacing: 8) {
                    modeButton(.teleport, key: "mode.teleport")
                    modeButton(.route, key: "mode.route")
                }
                .padding(4)
                .background(GoFlyStyle.surface, in: Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityLabel(goFlyString("mode.title"))
                .accessibilityIdentifier("map.mode")
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { modeHeaderHeight = $0 }
            }
            if showsOperationPanel {
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
                    currentLocationAvailable: service.currentRouteOrigin != nil
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
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { panelFrame = $0 }
    }

    private func modeButton(_ value: GoFlyMapMode, key: String) -> some View {
        Button { mode = value } label: {
            Text(goFlyString(key))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
                .foregroundStyle(mode == value ? GoFlyStyle.surface : GoFlyStyle.primary)
                .background(mode == value ? GoFlyStyle.primary : GoFlyStyle.surface, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(mode == value ? .clear : GoFlyStyle.border, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
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
                else { _ = service.start() }
            } label: {
                if route.phase == .pausing || service.phase == .preparing {
                    ProgressView()
                } else {
                    Image(systemName: route.canPause ? "pause.fill" : "play.fill")
                }
            }
            .disabled(!route.canPause && !route.canResume && (!route.canEdit || !service.canStart))
            .buttonStyle(GoFlyIconStyle())
            .accessibilityLabel(goFlyString(
                route.canPause ? "map.pause" : (route.canResume ? "route.resume" : (service.nativeBusy ? service.statusKey : "service.start"))
            ))
            .accessibilityHint(goFlyString(route.canPause ? "route.pauseHint" :
                (route.canResume ? "route.resumeHint" : (service.canStart ? "map.startServiceHint" : "map.noActiveTask"))))
            .accessibilityIdentifier("map.serviceControl")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(GoFlyIconStyle())
            .accessibilityLabel(goFlyString("settings.title"))
            .accessibilityIdentifier("map.settings")
        }
        .padding(dynamicTypeSize.isAccessibilitySize ? 8 : 16)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
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
        VStack(spacing: 8) {
            if route.picker == nil { goButton(candidate) }
            pinButton(candidate)
        }
        .frame(width: max(84, goWidth))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { candidateHeight = $0 }
    }

    private func goButton(_ candidate: TeleportCandidate) -> some View {
        Button {
                dismissKeyboard()
                _ = service.teleport(to: candidate)
            } label: {
                Text("Go")
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .frame(width: goWidth)
            .disabled(!search.canGo || !service.canTeleport)
            .accessibilityIdentifier("map.candidate.go")
    }

    private func pinButton(_ candidate: TeleportCandidate) -> some View {
        Button {
                dismissKeyboard()
                presentedSheet = GoFlyMapSheet(content: .details(candidate.place))
            } label: {
                Image(systemName: "mappin")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 44, height: 44, alignment: .bottom)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(GoFlyStyle.primary)
            .accessibilityLabel(goFlyString("search.placeDetails"))
            .accessibilityValue(route.picker != nil ? candidate.place.coordinate.displayText : candidate.place.title)
            .accessibilityIdentifier("map.candidate.pin")
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

    @ViewBuilder private func mapMetrics(origin: CGPoint) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics"), let projection {
            Text(String(projection.routePointCount))
                .font(.caption2).foregroundStyle(.clear).frame(width: 1, height: 1).allowsHitTesting(false)
                .accessibilityIdentifier("map.routePreview.points")
            Text(projection.routeIsVisible ? "true" : "false")
                .font(.caption2).foregroundStyle(.clear).frame(width: 1, height: 1).allowsHitTesting(false)
                .accessibilityIdentifier("map.routePreview.visible")
        }
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics"),
           let projection, let candidate = projection.candidatePoint {
            Text(String(format: "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f",
                        projection.viewport.midX + origin.x, projection.viewport.midY + origin.y,
                        candidate.x + origin.x, candidate.y + origin.y, projection.viewport.width, projection.viewport.height))
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityIdentifier("map.viewportMetrics")
            if let selection = activeCandidate?.id {
                Text(selection.uuidString)
                    .font(.caption2)
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("map.candidate.selectionID")
            }
        }
        #endif
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
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
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
            Image(systemName: "exclamationmark.triangle")
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
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
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

private enum GoFlyMapMode: Hashable { case teleport, route }
