import GoFlyCore
import MapKit
import SwiftUI
import UIKit

struct GoFlyMapView: View {
    @ObservedObject var service: ServiceController
    @StateObject private var location = GoFlyRealLocation()
    @StateObject private var search = CandidateController(search: MapKitPlaceSearch())
    @State private var cameraIntent: GoFlyCameraIntent?
    @State private var pendingGPSRecenter = false
    @State private var projection: GoFlyMapProjection?
    @State private var topFrame = CGRect.zero
    @State private var panelFrame = CGRect.zero
    @State private var detailPlace: MapPlace?
    @State private var candidateHeight: CGFloat = 96
    @ScaledMetric(relativeTo: .body) private var goWidth: CGFloat = 68
    @State private var showingSettings = false
    @State private var serviceNoticeDismissed = false
    @State private var returnedFromUnconfirmed: UUID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var viewportGap: CGFloat { dynamicTypeSize.isAccessibilitySize ? 4 : 8 }
    private var bottomPadding: CGFloat { dynamicTypeSize.isAccessibilitySize ? 8 : 12 }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let viewport = visibleViewport(in: geometry)
                ZStack(alignment: .topLeading) {
                    GoFlyMapCanvas(
                        marker: service.positionMarker, candidate: search.candidate,
                        viewport: viewport, cameraIntent: cameraIntent,
                        onMapTap: { search.selectMapCoordinate($0) },
                        onProjection: { if projection != $0 { projection = $0 } }
                    )
                    if let candidate = search.candidate, let point = projection?.candidatePoint {
                        candidatePin(candidate)
                            .position(x: point.x, y: point.y - candidateHeight / 2)
                    }
                    VStack(spacing: 0) {
                        VStack(spacing: 8) {
                            statusCard
                            if let error = service.error, !serviceNoticeDismissed, !panelPresentsFailure {
                                serviceFailureNotice(error)
                            }
                            if case .unconfirmed = service.pointState, !showsOperationPanel {
                                locationNoticeText("teleport.positionUnconfirmed")
                            }
                            if let notice = location.noticeKey {
                                locationNotice(notice)
                            }
                        }
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { topFrame = $0 }
                        Spacer(minLength: search.candidate == nil ? 100 : max(100, candidateHeight * 2 - 52 + viewportGap * 2 + 4))
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
                        .padding(.bottom, 8)
                        Group {
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
                            } else {
                                GoFlySearchPanel(search: search, maximumHeight: panelMaximumHeight(in: geometry))
                            }
                        }
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("mapRoot")) }) { panelFrame = $0 }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 4 : 8)
                    .padding(.bottom, bottomPadding)
                    mapMetrics(origin: geometry.frame(in: .global).origin)
                }
                .coordinateSpace(name: "mapRoot")
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
                      search.candidate == nil || explicitlyRequested,
                      let coordinate = GeoCoordinate(latitude: accepted.latitude, longitude: accepted.longitude) else { return }
                cameraIntent = GoFlyCameraIntent(coordinate: coordinate)
            }
            .onChange(of: search.candidate?.id) { _, _ in
                guard let candidate = search.candidate else { return }
                pendingGPSRecenter = false
                cameraIntent = GoFlyCameraIntent(coordinate: candidate.place.coordinate)
            }
            .onChange(of: service.pointState) { _, state in
                guard case .acknowledged(let intent) = state else { return }
                search.clearCandidate(ifMatching: intent.candidate.id)
                if search.candidate == nil {
                    cameraIntent = GoFlyCameraIntent(coordinate: intent.candidate.place.coordinate)
                }
                dismissKeyboard()
            }
            .sheet(item: $detailPlace) { place in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(place.title).font(.title2.bold())
                            Text(place.coordinate.displayText).font(.body).textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                    }
                    .navigationTitle(goFlyString("search.placeDetails"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(goFlyString("common.dismiss")) { detailPlace = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .tint(GoFlyStyle.primary)
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(goFlyString(service.positionMarker?.source == .simulation ? "map.simulatedLocation" : "map.currentLocation"))
                    .font(.headline)
                Text(goFlyString(displayStatusKey))
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("map.positionStatus")

            Button {
                _ = service.start()
            } label: {
                if service.phase == .preparing {
                    ProgressView()
                } else {
                    Image(systemName: service.phase == .ready ? "pause.fill" : "play.fill")
                }
            }
            .disabled(!service.canStart)
            .buttonStyle(GoFlyIconStyle())
            .accessibilityLabel(goFlyString(
                service.nativeBusy ? service.statusKey : (service.phase == .ready ? "map.pause" : "service.start")
            ))
            .accessibilityHint(goFlyString(service.canStart ? "map.startServiceHint" : "map.noActiveTask"))
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

    private var displayStatusKey: String {
        switch service.pointState {
        case .sending: "teleport.moving"
        case .unconfirmed: "teleport.unconfirmed"
        default: service.statusKey
        }
    }

    private func visibleViewport(in geometry: GeometryProxy) -> CGRect {
        let top = max(viewportGap, topFrame.maxY + viewportGap)
        let bottom = panelFrame.height > 0 ? panelFrame.minY - viewportGap : geometry.size.height - 92
        return CGRect(x: 16, y: top, width: max(1, geometry.size.width - 32), height: max(1, bottom - top))
    }

    private func panelMaximumHeight(in geometry: GeometryProxy) -> CGFloat {
        max(76, geometry.size.height - topFrame.maxY
            - (search.candidate == nil ? 120 : candidateHeight * 2 + 4)
            - bottomPadding - viewportGap * 2)
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
        return showsOperationPanel && unconfirmedFailure != nil
    }

    private func cancelPreparation(_ id: UUID) {
        if service.cancelPreparation(id: id) { serviceNoticeDismissed = true }
    }

    private func candidatePin(_ candidate: TeleportCandidate) -> some View {
        VStack(spacing: 8) {
            goButton(candidate)
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
                detailPlace = candidate.place
            } label: {
                Image(systemName: "mappin")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 44, height: 44, alignment: .bottom)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(GoFlyStyle.primary)
            .accessibilityLabel(goFlyString("search.placeDetails"))
            .accessibilityValue(candidate.place.title)
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
