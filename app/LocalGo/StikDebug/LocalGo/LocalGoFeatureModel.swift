import Combine
import Foundation
import MapKit

enum LocalGoMode: String, CaseIterable, Identifiable {
    case teleport = "瞬移"
    case route = "路線"
    case joystick = "搖桿"
    var id: Self { self }
}

struct LocalGoSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let point: GeoPoint
}

struct LocalGoCameraFocus: Equatable {
    let id = UUID()
    let point: GeoPoint
}

@MainActor
final class LocalGoFeatureModel: ObservableObject {
    let setup: LocalGoProofModel
    let motion: MovementController
    @Published private(set) var selectedPoint: GeoPoint?
    @Published private(set) var cameraFocus: LocalGoCameraFocus?
    @Published private(set) var selectedName = "選擇一個地點"
    @Published private(set) var mode: LocalGoMode = .teleport
    @Published private(set) var waypoints: [GeoPoint] = []
    @Published private(set) var routePoints: [GeoPoint] = []
    @Published var speed: Double = 20.0 / 3.6 {
        didSet {
            speed = min(28, max(0.5, speed.isFinite ? speed : 20.0 / 3.6))
            motion.speed = speed
        }
    }
    @Published var repeatRoute = false { didSet { motion.repeats = repeatRoute } }
    @Published var useRoads = false {
        didSet {
            guard oldValue != useRoads else { return }
            invalidateRoadRoute()
            stopIfNeeded()
        }
    }
    @Published var query = ""
    @Published private(set) var searchResults: [LocalGoSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var status = "可先搜尋、選點與規劃；裝置尚未連線"
    @Published private(set) var favorites: [SavedPlace] = []
    @Published private(set) var history: [SavedPlace] = []

    private var subscriptions = Set<AnyCancellable>()
    private var store: LocalPlaceStore?
    private var storageHealthy = false
    private var searchTask: Task<Void, Never>?
    private var roadTask: Task<Void, Never>?
    private var currentSearch: MKLocalSearch?
    private var currentDirections: MKDirections?
    private var searchGeneration: UInt64 = 0
    private var roadGeneration: UInt64 = 0
    private var roadRouteReady = false
    private var pendingHistory: SavedPlace?
    private var awaitingClear = false
    private var resetServiceAfterClear = false

    init() {
        let setup = LocalGoProofModel()
        self.setup = setup
        motion = MovementController(commands: setup.commands) { [weak setup] in
            setup?.canSend ?? false
        }
        setup.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        motion.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        setup.commands.$phase.sink { [weak self] phase in self?.received(phase) }
            .store(in: &subscriptions)
        setup.$readiness.sink { [weak self] readiness in
            if readiness == .ready { self?.status = "已啟動；選點後即可設定位置" }
        }.store(in: &subscriptions)
        do {
            let store = try LocalPlaceStore()
            let archive = try store.load()
            self.store = store
            favorites = archive.favorites
            history = archive.history
            storageHealthy = true
        } catch {
            status = "本機收藏資料無法讀取；為保護原檔，暫停儲存"
        }
    }

    var canRun: Bool {
        setup.canSend && (setup.commands.phase == .idle || setup.commands.phase == .accepted)
    }
    var hasActiveMotion: Bool { motion.isActive }
    var routeDistanceMeters: Double {
        (try? RoutePath(points: routePoints.count >= 2 ? routePoints : waypoints).lengthMeters) ?? 0
    }

    func setMode(_ newMode: LocalGoMode) {
        guard mode != newMode else { return }
        stopIfNeeded()
        mode = newMode
        pendingHistory = nil
        status = "\(newMode.rawValue)模式；選點只更新預覽"
    }

    func select(point: GeoPoint, name: String = "地圖選點", focusMap: Bool = true) {
        if motion.isActive || motion.state == .paused { stopIfNeeded() }
        selectedPoint = point
        selectedName = String(name.prefix(120))
        if focusMap { cameraFocus = LocalGoCameraFocus(point: point) }
        if mode == .route {
            guard waypoints.count < 25 else {
                status = "手動路線最多 25 個途經點"
                return
            }
            invalidateRoadRoute()
            waypoints.append(point)
        }
        status = "已選擇 \(selectedName)；尚未送出定位"
    }

    func search() {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        currentSearch?.cancel()
        searchResults = []
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { isSearching = false; return }
        let numbers = text.components(separatedBy: CharacterSet(charactersIn: ",， "))
            .filter { !$0.isEmpty }
        if numbers.count == 2, let lat = Double(numbers[0]), let lon = Double(numbers[1]) {
            isSearching = false
            guard let point = try? GeoPoint(latitude: lat, longitude: lon) else {
                status = "請輸入有效座標：緯度 -90…90，經度 -180…180"
                return
            }
            select(point: point, name: "座標搜尋")
            return
        }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let point = selectedPoint {
            request.region = MKCoordinateRegion(center: point.mapCoordinate,
                latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        let search = MKLocalSearch(request: request)
        currentSearch = search
        searchTask = Task { @MainActor [weak self] in
            do {
                let response = try await search.start()
                guard let self, !Task.isCancelled, generation == self.searchGeneration else { return }
                self.searchResults = response.mapItems.prefix(12).compactMap { item in
                    let coordinate = item.location.coordinate
                    guard let point = try? GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude) else { return nil }
                    return LocalGoSearchResult(title: item.name ?? "搜尋地點",
                        subtitle: item.address?.fullAddress ?? "", point: point)
                }
                self.isSearching = false
                if self.searchResults.isEmpty { self.status = "找不到符合的地點" }
            } catch {
                guard let self, !Task.isCancelled, generation == self.searchGeneration else { return }
                self.isSearching = false
                self.status = "搜尋未完成；請檢查網路或改用經緯度"
            }
        }
    }

    func teleport() {
        let hadMotion = motion.isActive || motion.state == .paused
        motion.cancelMotion()
        if hadMotion {
            stop(resetService: false)
            status = "已停止移動；清除完成後可再次套用選點"
            return
        }
        guard canRun, let selectedPoint else {
            status = "請先選點並完成裝置連線準備"
            return
        }
        pendingHistory = SavedPlace(name: selectedName, point: selectedPoint)
        setup.commands.apply(latitude: selectedPoint.latitude, longitude: selectedPoint.longitude)
    }

    func planRoadRoute() {
        guard waypoints.count >= 2, waypoints.count <= 25 else {
            status = "請先選擇 2 至 25 個途經點"
            return
        }
        stopIfNeeded()
        if !useRoads { useRoads = true }
        invalidateRoadRoute()
        let generation = roadGeneration
        let points = waypoints
        status = "正在以 Apple 地圖計算步行道路…"
        roadTask = Task { @MainActor [weak self] in
            do {
                var collected: [GeoPoint] = []
                for index in 0..<(points.count - 1) {
                    guard let self, !Task.isCancelled, generation == self.roadGeneration else { return }
                    let request = MKDirections.Request()
                    request.source = MKMapItem(location: CLLocation(latitude: points[index].latitude,
                        longitude: points[index].longitude), address: nil)
                    request.destination = MKMapItem(location: CLLocation(latitude: points[index + 1].latitude,
                        longitude: points[index + 1].longitude), address: nil)
                    request.transportType = .walking
                    let directions = MKDirections(request: request)
                    self.currentDirections = directions
                    let response = try await directions.calculate()
                    guard !Task.isCancelled, generation == self.roadGeneration else { return }
                    guard let line = response.routes.first?.polyline, line.pointCount <= 10_000 else { throw FeatureFailure.noRoute }
                    var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: line.pointCount)
                    line.getCoordinates(&coordinates, range: NSRange(location: 0, length: line.pointCount))
                    for coordinate in coordinates {
                        let point = try GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        if collected.last != point { collected.append(point) }
                        guard collected.count <= 10_000 else { throw FeatureFailure.tooLarge }
                    }
                }
                guard let self, !Task.isCancelled, generation == self.roadGeneration else { return }
                _ = try RoutePath(points: collected)
                self.routePoints = collected
                self.roadRouteReady = true
                self.status = "步行道路已完成；按開始才會送出定位"
            } catch {
                guard let self, !Task.isCancelled, generation == self.roadGeneration else { return }
                self.roadRouteReady = false
                self.status = "無法計算道路；請重試，或關閉道路選項以明確使用直線路線"
            }
        }
    }

    func startRoute() {
        guard canRun else { status = "請先完成裝置連線準備，並等候前一個位置更新完成"; return }
        guard !useRoads || roadRouteReady else { status = "請先計算道路路線"; return }
        do {
            let path = try RoutePath(points: routePoints.count >= 2 ? routePoints : waypoints)
            motion.speed = speed
            motion.repeats = repeatRoute
            pendingHistory = SavedPlace(name: "路線起點", point: path.points[0])
            if motion.start(path) { status = "開始送出路線位置；切到背景會暫停移動" }
        } catch { status = "路線需要至少兩個不同位置" }
    }

    func pauseRoute() {
        motion.pause()
        status = "已暫停；最後一個位置可能仍在更新，模擬位置保留"
    }

    func resumeRoute() {
        if motion.resume() { status = "已繼續路線" }
        else { status = "目前無法繼續；請核對連線與位置狀態" }
    }

    func stop(resetService: Bool = true, forceClear: Bool = false) {
        pendingHistory = nil
        awaitingClear = true
        resetServiceAfterClear = resetServiceAfterClear || resetService
        motion.stop(forceClear: forceClear)
        status = "已停止更新，正在清除模擬位置"
    }

    func joystickChanged(x: Double, y: Double) {
        let last = setup.commands.latestAcceptedCoordinate
        let origin = last.flatMap { try? GeoPoint(latitude: $0.latitude, longitude: $0.longitude) } ?? selectedPoint
        guard let origin else { status = "請先在地圖選擇搖桿起點"; return }
        motion.speed = speed
        if !motion.updateJoystick(origin: origin, x: x, y: y) { status = "請先完成連線，並等候前一個位置更新完成" }
    }

    func joystickEnded() {
        motion.endJoystick()
        status = "搖桿已放開；停止送出新位置，按停止可清除模擬定位"
    }

    func clearWaypoints() {
        stopIfNeeded()
        invalidateRoadRoute()
        waypoints = []
    }

    func removeWaypoint(at index: Int) {
        guard waypoints.indices.contains(index) else { return }
        stopIfNeeded()
        invalidateRoadRoute()
        waypoints.remove(at: index)
    }

    func importGPX(from url: URL) {
        stopIfNeeded()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > GPXCodec.maximumBytes { throw FeatureFailure.tooLarge }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: GPXCodec.maximumBytes + 1) ?? Data()
            guard data.count <= GPXCodec.maximumBytes else { throw FeatureFailure.tooLarge }
            let points = try GPXCodec.decode(data)
            _ = try RoutePath(points: points)
            invalidateRoadRoute()
            useRoads = false
            mode = .route
            waypoints = [points[0], points[points.count - 1]]
            routePoints = points
            selectedPoint = points[0]
            cameraFocus = LocalGoCameraFocus(point: points[0])
            selectedName = "GPX 起點"
            status = "已匯入 \(points.count) 個路線點；尚未送出定位"
        } catch { status = "無法匯入 GPX：限 2 MiB、10,000 點，且須有有效路線座標" }
    }

    func exportGPX() throws -> Data {
        let points = routePoints.count >= 2 ? routePoints : waypoints
        return try GPXCodec.encode(points: points.isEmpty ? selectedPoint.map { [$0] } ?? [] : points, name: selectedName)
    }

    func saveFavorite() {
        guard let point = selectedPoint else { status = "請先選擇地點"; return }
        guard favorites.count < 100 else { status = "收藏最多 100 筆；請先刪除一筆"; return }
        persist(favorites: favorites + [SavedPlace(name: selectedName, point: point)], history: history)
    }

    func selectSaved(_ place: SavedPlace) { select(point: place.point, name: place.name) }
    func removeFavorite(_ id: UUID) { persist(favorites: favorites.filter { $0.id != id }, history: history) }
    func removeHistory(_ id: UUID) { persist(favorites: favorites, history: history.filter { $0.id != id }) }

    func backgrounded() {
        searchGeneration &+= 1
        searchTask?.cancel()
        currentSearch?.cancel()
        isSearching = false
        roadGeneration &+= 1
        roadTask?.cancel()
        currentDirections?.cancel()
        motion.backgrounded()
        status = "背景中停止移動；保留最後送出位置，返回後需手動繼續或清除"
    }

    private func invalidateRoadRoute() {
        roadGeneration &+= 1
        roadTask?.cancel()
        currentDirections?.cancel()
        roadRouteReady = false
        routePoints = []
    }

    private func stopIfNeeded() {
        if motion.isActive || motion.state == .paused || setup.commands.phase != .idle ||
           setup.commands.latestAcceptedCoordinate != nil {
            stop(resetService: false)
        } else { motion.cancelMotion() }
    }

    private func received(_ phase: LocationCommandPhase) {
        switch phase {
        case .accepted:
            status = "位置已送出；可在其他 App 查看目前位置"
            if let place = pendingHistory, let accepted = setup.commands.latestAcceptedCoordinate,
               accepted.latitude == place.point.latitude, accepted.longitude == place.point.longitude {
                pendingHistory = nil
                persist(favorites: favorites, history: Array(([place] + history).prefix(100)), showStatus: false)
            }
        case .unknownFailure:
            pendingHistory = nil
            if awaitingClear {
                status = "尚未清除，請重試"
            } else {
                setup.runtimeConnectionFailed()
                status = "定位狀態未知；請先停止清除，再重新啟動"
            }
        case .idle:
            if awaitingClear {
                awaitingClear = false
                if resetServiceAfterClear {
                    resetServiceAfterClear = false
                    setup.completeStop()
                    status = "已送出清除；請確認真實定位，未恢復可再次清除"
                } else {
                    status = "已送出清除；請確認真實定位，未恢復可再次清除"
                }
            }
        case .preparing, .applying: status = "正在更新位置…"
        case .clearing: status = "正在清除模擬位置…"
        }
    }

    private func persist(favorites: [SavedPlace], history: [SavedPlace], showStatus: Bool = true) {
        guard storageHealthy, let store else { status = "本機資料無法儲存；原檔保持不變"; return }
        do {
            try store.save(PlaceArchive(favorites: favorites, history: history))
            self.favorites = favorites
            self.history = history
            if showStatus { status = "已儲存在本機" }
        } catch { status = "儲存失敗；沒有更新畫面中的收藏資料" }
    }

    private enum FeatureFailure: Error { case noRoute, tooLarge }
}

extension GeoPoint {
    var mapCoordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
