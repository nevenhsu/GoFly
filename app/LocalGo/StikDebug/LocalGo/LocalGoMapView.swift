import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The map-first control surface for LocalGo.
///
/// The view deliberately delegates location work, validation, persistence, and
/// device acknowledgement to `LocalGoFeatureModel`. It only presents state and
/// forwards user intent to that model.
struct LocalGoMapView: View {
    @ObservedObject private var model: LocalGoFeatureModel
    @StateObject private var tunnelMonitor = LocalGoTunnelMonitor(host: DeviceConnectionContext.targetIPAddress)
    @StateObject private var currentLocation = LocalGoCurrentLocation()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )
    )
    @State private var showingSetup = false
    @State private var showingPlaces = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument = LocalGoGPXDocument(data: Data())
    @State private var transferMessage: String?
    @State private var visibleSpan = MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
    @State private var renderedCameraHeading: CLLocationDirection = 0
    @State private var isPanelCollapsed = false
    @FocusState private var isSearchFocused: Bool

    init(model: LocalGoFeatureModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if tunnelMonitor.state == .unreachable { tunnelWarning }
                startupFailureNotice
                Spacer(minLength: 0)
                currentLocationControl
                controlPanel
            }
        }
        .background(LocalGoStyle.paper)
        .foregroundStyle(LocalGoStyle.ink)
        .tint(LocalGoStyle.accent)
        .onAppear {
            if scenePhase == .active {
                tunnelMonitor.start()
                currentLocation.start()
            }
        }
        .onDisappear {
            tunnelMonitor.stop()
            currentLocation.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.setup.consumeMacSetup()
                tunnelMonitor.start()
                currentLocation.start()
            }
            guard phase == .inactive || phase == .background else { return }
            tunnelMonitor.stop()
            currentLocation.stop()
            model.backgrounded()
        }
        .onChange(of: currentLocation.recenterGeneration) { _, _ in
            guard model.setup.commands.latestAcceptedCoordinate == nil,
                  let coordinate = currentLocation.coordinate else { return }
            recenterMap(to: coordinate)
        }
        .onChange(of: model.cameraFocus) { _, request in
            guard let point = request?.point else { return }
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: point.clLocation,
                    span: visibleSpan
                )
            )
        }
        .sheet(isPresented: $showingSetup) {
            LocalGoProofView(model: model.setup, stop: { model.stop() })
        }
        .sheet(isPresented: $showingPlaces) {
            LocalGoPlacesSheet(model: model)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: LocalGoGPXDocument.contentTypes
        ) { result in
            guard case .success(let url) = result else { return }
            model.importGPX(from: url)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: LocalGoGPXDocument.gpxType,
            defaultFilename: "LocalGo-route",
            onCompletion: { result in
                if case .failure = result {
                    transferMessage = "匯出失敗，請稍後再試。"
                }
            }
        )
    }

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if let selectedPoint = model.selectedPoint {
                    Annotation(model.selectedName, coordinate: selectedPoint.clLocation) {
                        Image(systemName: "mappin")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(LocalGoStyle.muted)
                            .accessibilityLabel("已選位置：\(model.selectedName)")
                    }
                }

                if let currentCoordinate {
                    Annotation("目前位置", coordinate: currentCoordinate) {
                        Image(systemName: "location.north.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(LocalGoStyle.accent)
                            .rotationEffect(.degrees(mapArrowRotation))
                            .accessibilityLabel("目前位置")
                    }
                }

                ForEach(Array(model.waypoints.prefix(25).enumerated()), id: \.offset) { item in
                    Marker("路點 \(item.offset + 1)", coordinate: item.element.clLocation)
                        .tint(LocalGoStyle.accent)
                }

                if routeDisplayPoints.count >= 2 {
                    MapPolyline(coordinates: routeDisplayPoints.map(\.clLocation))
                        .stroke(LocalGoStyle.accent, lineWidth: 5)
                }
            }
            .mapStyle(.standard)
            .onMapCameraChange(frequency: .continuous) { context in
                visibleSpan = context.region.span
                renderedCameraHeading = context.camera.heading
            }
            .onTapGesture { screenPoint in
                guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                do {
                    let point = try GeoPoint(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                    model.select(point: point, focusMap: false)
                } catch {
                    // MapKit should only produce finite, in-range coordinates;
                    // the domain model remains the final validation boundary.
                }
            }
            .accessibilityLabel("地圖。點一下選取位置")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LocalGoStyle.accent)
                .frame(width: 36, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(currentLocationTitle)
                    .font(.system(.headline, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 6) {
                    Circle().fill(serviceIsActive ? LocalGoStyle.accent : LocalGoStyle.muted)
                        .frame(width: 5, height: 5)
                    Text(previewStatus).font(.caption)
                        .foregroundStyle(LocalGoStyle.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            serviceButton
            Button { showingSetup = true } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(LocalGoIconButtonStyle())
                .accessibilityLabel("開啟設定")
        }
        .padding(12)
        .background(LocalGoStyle.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: LocalGoStyle.ink.opacity(0.08), radius: 16, y: 5)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var serviceIsActive: Bool {
        model.setup.canSend || model.setup.commands.phase != .idle
    }

    private var tunnelWarning: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(LocalGoStyle.warning)
                VStack(alignment: .leading, spacing: 5) {
                    Text("本機 VPN 通道無法連通")
                        .font(.subheadline.weight(.semibold))
                    Text("請開啟 LocalDevVPN；若已 Connected，請先 Disconnect 再 Connect。回來後重試停止，確認清除後再啟動。")
                        .font(.footnote)
                        .foregroundStyle(LocalGoStyle.muted)
                }
                Spacer(minLength: 0)
                Button { tunnelMonitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(LocalGoIconButtonStyle())
                    .accessibilityLabel("重新檢查連線")
            }
            LocalGoVPNButton()
        }
        .padding(16)
        .background(LocalGoStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var startupFailureNotice: some View {
        if tunnelMonitor.state != .unreachable,
           model.setup.readiness == .failed || model.setup.commands.phase == .unknownFailure {
            Text(model.setup.setupStatus)
                .font(.footnote)
                .foregroundStyle(LocalGoStyle.danger)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
    }

    private var currentLocationControl: some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: recenterCurrentLocation) {
                Image(systemName: "location.north.fill")
                    .rotationEffect(.degrees(mapArrowRotation))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(LocalGoIconButtonStyle())
            .accessibilityLabel("回到目前位置")
            .accessibilityHint("將地圖移到已送出的模擬位置，或目前的位置讀值")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var currentCoordinate: CLLocationCoordinate2D? {
        if let accepted = model.setup.commands.latestAcceptedCoordinate {
            return CLLocationCoordinate2D(latitude: accepted.latitude, longitude: accepted.longitude)
        }
        return currentLocation.coordinate
    }

    private var mapArrowHeading: CLLocationDirection {
        if model.setup.commands.latestAcceptedCoordinate != nil || model.motion.isActive {
            return model.motion.headingDegrees
        }
        return currentLocation.courseDegrees ?? 0
    }

    private var mapArrowRotation: Double {
        mapArrowHeading - renderedCameraHeading
    }

    private func recenterCurrentLocation() {
        if let accepted = model.setup.commands.latestAcceptedCoordinate {
            recenterMap(to: CLLocationCoordinate2D(latitude: accepted.latitude, longitude: accepted.longitude))
            return
        }

        switch currentLocation.requestRecenter() {
        case .available:
            if let coordinate = currentLocation.coordinate {
                recenterMap(to: coordinate)
            }
        case .waitingForPermission:
            break
        case .openSettings:
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                openURL(settingsURL)
            }
        }
    }

    private func recenterMap(to coordinate: CLLocationCoordinate2D) {
        cameraPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: visibleSpan
            )
        )
    }

    private var currentLocationTitle: String {
        if model.setup.commands.phase == .unknownFailure { return "定位狀態未知" }
        guard let coordinate = currentCoordinate else { return "尚未設定位置" }
        if model.setup.commands.latestAcceptedCoordinate != nil, let point = model.selectedPoint,
           point.latitude == coordinate.latitude, point.longitude == coordinate.longitude,
           !["地圖選點", "座標搜尋", "GPX 起點", "目前位置"].contains(model.selectedName) {
            return model.selectedName
        }
        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private func startService() {
        if model.setup.pairingImported { model.setup.prepare() }
        else { showingSetup = true }
    }

    private var serviceButton: some View {
        Button {
            if serviceIsActive { model.stop() }
            else { startService() }
        } label: {
            Group {
                if model.setup.isPreparing || isClearing {
                    ProgressView().tint(serviceIsActive ? LocalGoStyle.danger : LocalGoStyle.paper)
                } else {
                    Image(systemName: serviceIsActive ? "stop.fill" : "play.fill")
                }
            }
        }
        .buttonStyle(LocalGoIconButtonStyle(active: !serviceIsActive, destructive: serviceIsActive))
        .disabled(model.setup.isPreparing || isClearing)
        .accessibilityLabel(serviceIsActive ? "停止並自動清除模擬位置" : "啟動")
    }

    private var collapseButton: some View {
        Button {
            isSearchFocused = false
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { isPanelCollapsed = true }
        } label: { Image(systemName: "chevron.down") }
        .buttonStyle(LocalGoIconButtonStyle())
        .accessibilityLabel("收合控制面板")
    }

    private var controlPanel: some View {
        Group {
            if !model.setup.canSend {
                VStack(spacing: 10) {
                    Button("啟動") { startService() }
                        .accessibilityIdentifier("localgo.start")
                        .buttonStyle(LocalGoButtonStyle(.primary))
                        .frame(maxWidth: .infinity)
                        .disabled(model.setup.isPreparing || !model.setup.canConfigure)
                    if model.setup.pairingImported {
                        Button("恢復真實定位") { model.stop(forceClear: true) }
                            .accessibilityIdentifier("localgo.restore")
                            .buttonStyle(LocalGoButtonStyle(.secondary))
                            .frame(maxWidth: .infinity)
                            .disabled(model.setup.isPreparing || isClearing)
                        Text("重新開啟 App 不代表已清除先前的模擬位置。")
                            .font(.caption)
                            .foregroundStyle(LocalGoStyle.muted)
                    }
                    statusSection
                }
                .padding(16)
                .background(LocalGoStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                VStack(spacing: 0) {
                    if isPanelCollapsed {
                        compactSearchBar
                    } else {
                        HStack(spacing: 8) {
                            modePicker
                            collapseButton
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 12)

                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 18) {
                                switch model.mode {
                                case .teleport:
                                    searchSection
                                    Button { showingPlaces = true } label: {
                                        HStack {
                                            Image(systemName: "bookmark")
                                            Text("儲存的地點")
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                        }
                                    }
                                    .buttonStyle(LocalGoButtonStyle(.quiet))
                                    selectedPointSection
                                    teleportSection
                                case .route:
                                    selectedPointSection
                                    routeSection
                                case .joystick:
                                    selectedPointSection
                                    joystickSection
                                }
                                motionControls
                                statusSection
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                    }
                }
                .frame(maxHeight: isPanelCollapsed ? 64 : 430)
                .background(LocalGoStyle.surface)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: LocalGoStyle.ink.opacity(0.1), radius: 22, y: 8)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("localgo.controls")
            }
        }
    }

    private var compactSearchBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { isPanelCollapsed = false }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.setup.canSend && model.mode == .teleport ? "magnifyingglass" : "slider.horizontal.3")
                    Text(!model.setup.canSend ? "啟動定位" : (model.mode == .teleport ? (model.query.isEmpty ? "搜尋地址或地點" : model.query) : "\(model.mode.rawValue)控制"))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up").font(.caption.weight(.semibold))
                }
                .frame(minHeight: 44)
                .font(.subheadline.weight(.medium))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展開控制面板")

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LocalGoStyle.muted)
                TextField("搜尋地址或地點", text: $model.query)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        model.search()
                    }
                if model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("搜尋") {
                    model.search()
                }
                .buttonStyle(LocalGoButtonStyle(.primary))
                .controlSize(.small)
                .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(LocalGoStyle.recessed)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !model.searchResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.searchResults) { result in
                            Button {
                                model.select(point: result.point, name: result.title)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(LocalGoStyle.muted)
                                        .lineLimit(1)
                                }
                                .frame(width: 180, alignment: .leading)
                                .padding(10)
                                .background(LocalGoStyle.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("選取\(result.title)，\(result.subtitle)")
                        }
                    }
                }
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(LocalGoMode.allCases) { mode in
                Button { model.setMode(mode) } label: {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(model.mode == mode ? LocalGoStyle.paper : LocalGoStyle.muted)
                        .background(model.mode == mode ? LocalGoStyle.accent : .clear,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.rawValue)
                .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(LocalGoStyle.recessed, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("操作模式")
    }

    @ViewBuilder
    private var selectedPointSection: some View {
        if let selectedPoint = model.selectedPoint {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(LocalGoStyle.accent)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(selectedPoint.coordinateText)
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(LocalGoStyle.muted)
                }
                Spacer(minLength: 4)
                if model.mode == .teleport {
                    Button {
                        model.saveFavorite()
                    } label: {
                        Label("收藏", systemImage: "star")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(LocalGoIconButtonStyle())
                    .accessibilityLabel("收藏選定位置")
                }
            }
            .padding(14)
            .background(LocalGoStyle.recessed)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var teleportSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("選好地點，即可瞬移。")
                .font(.caption)
                .foregroundStyle(LocalGoStyle.muted)
            actionButton("瞬移到這裡", systemImage: "location.fill", prominent: true) {
                model.teleport()
            }
            .disabled(!model.canRun)
        }
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("路線 \(model.waypoints.count)/25", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("匯入 GPX") {
                    showingImporter = true
                }
                .buttonStyle(LocalGoButtonStyle(.secondary))
                .controlSize(.small)
                Button("匯出") {
                    prepareExport()
                }
                .buttonStyle(LocalGoButtonStyle(.secondary))
                .controlSize(.small)
            }

            if model.waypoints.isEmpty {
                Text("在地圖上點選兩個以上位置建立路線")
                    .font(.caption)
                    .foregroundStyle(LocalGoStyle.muted)
            } else {
                ForEach(Array(model.waypoints.prefix(25).enumerated()), id: \.offset) { item in
                    HStack(spacing: 8) {
                        Text("\(item.offset + 1)")
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(LocalGoStyle.muted)
                            .frame(width: 22)
                        Text(item.element.coordinateText)
                            .font(.caption).monospacedDigit()
                        Spacer(minLength: 4)
                        Button(role: .destructive) {
                            model.removeWaypoint(at: item.offset)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(LocalGoIconButtonStyle(destructive: true))
                        .accessibilityLabel("移除路點 \(item.offset + 1)")
                    }
                }
            }

            HStack(spacing: 8) {
                Button("清除路點", role: .destructive) {
                    model.clearWaypoints()
                }
                .buttonStyle(LocalGoButtonStyle(.secondary))
                .disabled(model.waypoints.isEmpty)

                Spacer()

                Toggle("沿道路", isOn: $model.useRoads)
                    .toggleStyle(.switch)
                    .font(.caption)
                Toggle("往返", isOn: $model.repeatRoute)
                    .toggleStyle(.switch)
                    .font(.caption)
            }

            HStack(spacing: 8) {
                Button("規劃道路路線") {
                    model.planRoadRoute()
                }
                .buttonStyle(LocalGoButtonStyle(.secondary))
                .disabled(model.waypoints.count < 2 || model.isSearching)

                Text(routeDescription)
                    .font(.caption)
                    .foregroundStyle(LocalGoStyle.muted)
                    .lineLimit(2)
            }

            speedControl
        }
    }

    private var speedKilometersPerHour: Binding<Double> {
        Binding(get: { model.speed * 3.6 }, set: { model.speed = $0 / 3.6 })
    }

    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("時速").font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%.0f", model.speed * 3.6))
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("km/h").font(.footnote).foregroundStyle(LocalGoStyle.muted)
            }
            Slider(value: speedKilometersPerHour, in: 2...100, step: 1)
                .accessibilityLabel("移動速度")
                .accessibilityValue(String(format: "每小時 %.0f 公里", model.speed * 3.6))
            HStack(spacing: 8) {
                ForEach([5.0, 20.0, 60.0], id: \.self) { value in
                    Button(String(format: "%.0f", value)) { model.speed = value / 3.6 }
                        .buttonStyle(LocalGoButtonStyle(abs(model.speed * 3.6 - value) < 0.1 ? .primary : .secondary))
                        .accessibilityLabel("時速 \(String(format: "%.0f", value)) 公里")
                }
                Spacer(minLength: 0)
                Text("2–100").font(.caption).monospacedDigit().foregroundStyle(LocalGoStyle.muted)
            }
        }
        .padding(16)
        .background(LocalGoStyle.recessed, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var joystickSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("搖桿", systemImage: "gamecontroller.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("拖曳移動，放開停下")
                    .font(.caption)
                    .foregroundStyle(LocalGoStyle.muted)
            }

            LocalGoJoystickPad(isEnabled: joystickEnabled) { x, y in
                handleJoystickChange(x: x, y: y)
            } onEnded: {
                model.joystickEnded()
            }
            .frame(height: 154)
            .frame(maxWidth: .infinity)

            speedControl
        }
    }

    private func handleJoystickChange(x: Double, y: Double) {
        if model.mode == .joystick,
           model.setup.commands.latestAcceptedCoordinate == nil,
           model.selectedPoint == nil,
           let coordinate = currentLocation.coordinate,
           let point = try? GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude) {
            model.select(point: point, name: "目前位置", focusMap: false)
        }
        model.joystickChanged(x: x, y: y)
    }

    private var motionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if case .route = model.mode {
                    actionButton("開始路線", systemImage: "play.fill", prominent: true) {
                        model.startRoute()
                    }
                    .disabled(!model.canRun)
                }

                if isMotionRunning {
                    actionButton("暫停", systemImage: "pause.fill", prominent: false) {
                        model.pauseRoute()
                    }
                } else if isMotionPaused {
                    actionButton("繼續", systemImage: "play.fill", prominent: false) {
                        model.resumeRoute()
                    }
                }

                Spacer(minLength: 0)

            }

            if model.hasActiveMotion || isMotionCompleted || isMotionFailed {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(motionStateLabel)
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(String(format: "%.0f m", model.motion.distanceMeters))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(LocalGoStyle.muted)
                    }
                    ProgressView(value: model.motion.progress)
                        .tint(LocalGoStyle.accent)
                }
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(model.status)
                    .font(.footnote)
                    .lineLimit(3)
            }
            if let transferMessage {
                Text(transferMessage)
                    .font(.caption)
                    .foregroundStyle(LocalGoStyle.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("狀態：\(model.status)")
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LocalGoButtonStyle(.primary))
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LocalGoButtonStyle(.secondary))
        }
    }

    private func prepareExport() {
        do {
            exportDocument = LocalGoGPXDocument(data: try model.exportGPX())
            transferMessage = nil
            showingExporter = true
        } catch {
            transferMessage = "匯出失敗，請稍後再試。"
        }
    }

    private var routeDisplayPoints: [GeoPoint] {
        model.routePoints.isEmpty ? model.waypoints : model.routePoints
    }

    private var routeDescription: String {
        if model.waypoints.count < 2 {
            return "至少需要兩個路點"
        }
        if model.useRoads, !model.routePoints.isEmpty {
            return "道路規劃路線 · \(formattedDistance(model.routeDistanceMeters))"
        }
        if model.useRoads {
            return "尚未規劃道路路線"
        }
        if !model.routePoints.isEmpty {
            return "已載入路線 · \(formattedDistance(model.routeDistanceMeters))"
        }
        return "直線路線 · \(formattedDistance(model.routeDistanceMeters))"
    }

    private var previewStatus: String {
        if model.setup.isPreparing { return "啟動中…" }
        if isClearing { return "停止中…" }
        if model.setup.commands.phase == .unknownFailure { return "請按停止重試清除" }
        return model.setup.canSend ? "已啟動" : "尚未啟動"
    }

    private var joystickEnabled: Bool {
        model.canRun || isJoystickMotion
    }

    private var isMotionRunning: Bool {
        if case .running = model.motion.state { return true }
        return false
    }

    private var isMotionPaused: Bool {
        if case .paused = model.motion.state { return true }
        return false
    }

    private var isJoystickMotion: Bool {
        if case .joystick = model.motion.state { return true }
        return false
    }

    private var isMotionCompleted: Bool {
        if case .completed = model.motion.state { return true }
        return false
    }

    private var isMotionFailed: Bool {
        if case .failed = model.motion.state { return true }
        return false
    }

    private var isClearing: Bool {
        model.setup.commands.phase == .clearing
    }

    private var motionStateLabel: String {
        switch model.motion.state {
        case .idle: return "待命"
        case .running: return "移動中"
        case .paused: return "已暫停"
        case .joystick: return "搖桿控制中"
        case .completed: return "已完成"
        case .failed: return "移動失敗"
        }
    }

    private var statusColor: Color {
        if isMotionFailed || model.setup.commands.phase == .unknownFailure { return LocalGoStyle.danger }
        if isMotionRunning || isJoystickMotion { return LocalGoStyle.accent }
        return LocalGoStyle.muted
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km", meters / 1_000)
        }
        return String(format: "%.0f m", meters)
    }
}

private struct LocalGoJoystickPad: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isEnabled: Bool
    let onChanged: (Double, Double) -> Void
    let onEnded: () -> Void

    @State private var knobOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let knobRadius = max(22, side * 0.14)
            let travelRadius = max(1, side * 0.5 - knobRadius - 5)

            ZStack {
                Circle()
                    .fill(LocalGoStyle.recessed.opacity(0.96))
                    .overlay(Circle().stroke(LocalGoStyle.accent.opacity(0.12), lineWidth: 1))
                    .frame(width: side, height: side)
                Circle()
                    .fill(LocalGoStyle.accent.opacity(0.12))
                    .frame(width: knobRadius * 2.5, height: knobRadius * 2.5)
                Circle()
                    .fill(isEnabled ? LocalGoStyle.accent : LocalGoStyle.muted)
                    .frame(width: knobRadius * 2, height: knobRadius * 2)
                    .overlay {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(LocalGoStyle.paper)
                    }
                    .shadow(color: LocalGoStyle.ink.opacity(0.12), radius: 6, y: 3)
                    .offset(knobOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        let distance = hypot(dx, dy)
                        let scale = distance > travelRadius ? travelRadius / distance : 1
                        let clampedX = dx * scale
                        let clampedY = dy * scale
                        knobOffset = CGSize(width: clampedX, height: clampedY)
                        onChanged(
                            min(1, max(-1, clampedX / travelRadius)),
                            min(1, max(-1, -clampedY / travelRadius))
                        )
                    }
                    .onEnded { _ in
                        guard isEnabled else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                            knobOffset = .zero
                        }
                        onEnded()
                    }
            )
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { knobOffset = .zero }
            }
            .opacity(isEnabled ? 1 : 0.62)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("搖桿")
            .accessibilityHint(isEnabled ? "拖曳控制方向，放開停止" : "啟動後即可使用")
        }
    }
}

private struct LocalGoPlacesSheet: View {
    @ObservedObject var model: LocalGoFeatureModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                savedSection(title: "收藏", places: model.favorites, isHistory: false, remove: model.removeFavorite)
                savedSection(title: "最近使用", places: model.history, isHistory: true, remove: model.removeHistory)
            }
            .scrollContentBackground(.hidden)
            .background(LocalGoStyle.paper)
            .foregroundStyle(LocalGoStyle.ink)
            .navigationTitle("儲存的地點")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(LocalGoIconButtonStyle())
                        .accessibilityLabel("關閉儲存的地點")
                }
            }
        }
        .tint(LocalGoStyle.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func savedSection(
        title: String,
        places: [SavedPlace],
        isHistory: Bool,
        remove: @escaping (UUID) -> Void
    ) -> some View {
        Section {
            if places.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: isHistory ? "clock" : "bookmark")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(LocalGoStyle.accent)
                        .padding(.bottom, 6)
                    Text(isHistory ? "還沒有最近使用的地點" : "把常去的地方留在這裡")
                        .font(.headline.weight(.medium))
                    Text(isHistory ? "使用過的地點會顯示在這裡。" : "在地圖選好位置，點星號即可收藏。")
                        .font(.subheadline)
                        .foregroundStyle(LocalGoStyle.muted)
                }
                .padding(.vertical, 20)
                .listRowBackground(LocalGoStyle.surface)
                .listRowSeparator(.hidden)
            } else {
                ForEach(places) { place in
                    HStack(spacing: 12) {
                        Image(systemName: isHistory ? "clock" : "mappin")
                            .font(.body.weight(.medium))
                            .foregroundStyle(LocalGoStyle.accent)
                        Button {
                            model.selectSaved(place)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(place.name).font(.body.weight(.medium)).lineLimit(2)
                                Text(place.point.coordinateText)
                                    .font(.caption).monospacedDigit()
                                    .foregroundStyle(LocalGoStyle.muted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("選取\(place.name)，\(place.point.coordinateText)")
                        Button(role: .destructive) { remove(place.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(LocalGoIconButtonStyle(destructive: true))
                            .accessibilityLabel("刪除\(place.name)")
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(LocalGoStyle.surface)
                    .listRowSeparator(.hidden)
                }
            }
        } header: {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(LocalGoStyle.muted)
                .textCase(nil)
        }
    }
}

private struct LocalGoGPXDocument: FileDocument {
    static let gpxType = UTType(filenameExtension: "gpx") ?? .xml
    static let contentTypes = [gpxType, .xml, .data]

    static var readableContentTypes: [UTType] { contentTypes }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private extension GeoPoint {
    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var coordinateText: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }
}
