import Foundation
import GoFlyCore
import GoFlyTransport

/// Simulator-only launch-argument overrides. Release and device builds compile
/// the inert variant, so no production argument can select test state.
#if DEBUG && targetEnvironment(simulator)
enum GoFlyUITestOverrides {
    static func value(_ flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    static func contains(_ flag: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }

    static var frame: String? {
        value("-gofly-ui-frame")?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isFrameMode: Bool { frame != nil }

    static var frameNeedsMapRuntime: Bool {
        guard let first = frame?.first else { return false }
        return ["B", "C", "D", "E", "F"].contains(String(first)) || frame == "R04"
    }

    static var fixturePlaces: [MapPlace] {
        [
            MapPlace(id: .coordinate(GeoCoordinate(latitude: 25.04776, longitude: 121.51706)!),
                     title: "台北車站", coordinate: GeoCoordinate(latitude: 25.04776, longitude: 121.51706)!,
                     address: "台北市中正區北平西路 3 號"),
            MapPlace(id: .coordinate(GeoCoordinate(latitude: 25.03752, longitude: 121.56370)!),
                     title: "大安森林公園", coordinate: GeoCoordinate(latitude: 25.03752, longitude: 121.56370)!,
                     address: "台北市大安區新生南路二段 1 號"),
            MapPlace(id: .coordinate(GeoCoordinate(latitude: 25.03398, longitude: 121.56447)!),
                     title: "測試地點 A", coordinate: GeoCoordinate(latitude: 25.03398, longitude: 121.56447)!,
                     address: "台北市大安區"),
        ]
    }

    static func initialMode(for frame: String?) -> SessionMapMode? {
        guard let first = frame?.first else { return nil }
        return switch first {
        case "D": .route
        case "E": .joystick
        case "B", "C", "F": .teleport
        default: nil
        }
    }

    static func routeDraft(for frame: String?) -> RouteDraft? {
        guard let frame, frame.first == "D" else { return nil }
        let places = fixturePlaces
        let speed = RouteSpeed(kilometersPerHour: frame == "D7" ? 50 : 25)!
        if frame == "D11" || frame == "D15" {
            let points = (0..<(frame == "D15" ? 14 : 4)).compactMap { index in
                GeoCoordinate(latitude: 25.04776 + Double(index) * 0.001,
                              longitude: 121.51706 + Double(index) * 0.001)
            }
            guard let document = try? GPXDocument(content: .tracks([GPXTrack(segments: [points])])),
                  let source = try? GPXRouteSource(document: document, displayFilename: "GoFly fixture.gpx") else { return nil }
            return RouteDraft(gpx: source, speed: speed)
        }
        let values: [RouteNodeValue]
        switch frame {
        case "D1": return RouteDraft(speed: speed)
        case "D2", "D2.a": values = [.current, .place(places[0]), .place(places[1]), .empty]
        case "D3": values = [.place(places[0]), .place(places[1])]
        default: values = [.current, .place(places[1])]
        }
        return RouteDraft(values: values, speed: speed)
    }

    @MainActor
    static func onboardingController(for frame: String) -> OnboardingController {
        let location: LocationAuthorization = frame == "R03" ? .authorized : locationAuthorization
        return OnboardingController(
            probe: fixtureTunnelProbe(for: frame),
            location: fixtureLocationAuthorization(authorization: location)
        )
    }

    static func fixtureTunnelProbe(for frame: String? = nil) -> any TunnelProbing {
        GoFlyUITestTunnelProbe(isReachable: frame != "R04.a" && !contains("-gofly-ui-unreachable"))
    }

    static var routePlanOutcome: GoFlyUITestRoutePlanOutcome {
        GoFlyUITestRoutePlanOutcome(rawValue: value("-gofly-ui-route-outcome") ?? "success") ?? .success
    }

    static var locationAuthorization: LocationAuthorization {
        switch value("-gofly-ui-location-state") {
        case "authorized": .authorized
        case "denied": .denied
        default: .notDetermined
        }
    }

    @MainActor
    static func fixtureLocationAuthorization(
        authorization: LocationAuthorization = .notDetermined
    ) -> any LocationAuthorizing {
        GoFlyUITestLocationAuthorization(authorization: authorization)
    }

    static func namespace(_ flag: String, under root: URL, folder: String) -> URL? {
        let namespace = value(flag).flatMap(UUID.init(uuidString:)) ?? (isFrameMode ? UUID() : nil)
        guard let namespace else { return nil }
        return root.appendingPathComponent("UITests", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(namespace.uuidString, isDirectory: true)
    }

    static func preferencesDefaults() -> UserDefaults? {
        let namespace = value("-gofly-ui-preferences-store").flatMap(UUID.init(uuidString:))
            ?? (isFrameMode ? UUID() : nil)
        guard let namespace,
              let store = UserDefaults(suiteName: "gofly.ui.preferences.\(namespace.uuidString)") else {
            return nil
        }
        if store.object(forKey: "gofly.preferences.v1") == nil {
            store.set([
                "language": value("-gofly-ui-preferences-language") ?? "system",
                "appearance": value("-gofly-ui-appearance")
                    ?? value("-gofly-ui-preferences-appearance") ?? "system",
                "backgroundRunSeconds": Int(value("-gofly-ui-background-seconds") ?? "43200") ?? 43200,
                "movementSpeed": Int(value("-gofly-ui-speed") ?? "25") ?? 25
            ], forKey: "gofly.preferences.v1")
        }
        return store
    }

    static func tunnelProbe() -> (any TunnelProbing)? {
        if contains("-gofly-ui-unreachable") { return GoFlyUITestTunnelProbe(isReachable: false) }
        if contains("-gofly-ui-reachable") { return GoFlyUITestTunnelProbe(isReachable: true) }
        return nil
    }
}

@MainActor
private final class GoFlyUITestLocationAuthorization: LocationAuthorizing {
    let authorization: LocationAuthorization

    init(authorization: LocationAuthorization) {
        self.authorization = authorization
    }

    func requestAuthorization() async -> LocationAuthorization { authorization }
}

private struct GoFlyUITestTunnelProbe: TunnelProbing {
    let isReachable: Bool
    var lastFailureDetail: String? { nil }

    func check() async throws {
        if !isReachable { throw TunnelProbeFailure.unavailable }
    }
}

struct GoFlyUITestDeviceService: DeviceService {
    private var scenario: String { GoFlyUITestOverrides.value("-gofly-ui-device-state") ?? "normal" }

    func prepare() async throws {
        if scenario == "start-failure" { throw DeviceServiceFailure.serviceUnavailable }
    }
    func clearLocation() async throws {
        if scenario == "stop-failure" { throw DeviceServiceFailure.serviceUnavailable }
    }
    func resetClientConnection() async throws {
        if scenario == "reset-failure" { throw DeviceServiceFailure.serviceUnavailable }
    }
    func rebuildClientConnection() async throws {
        if scenario == "rebuild-failure" { throw DeviceServiceFailure.serviceUnavailable }
    }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        if scenario == "unconfirmed-point" { return .unconfirmed(.operationTimedOut) }
        return .acknowledged
    }
}

@MainActor
final class GoFlyUITestContinuedProcessingDriver: ContinuedProcessingDriving {
    func register() -> Bool { true }

    func submit(_ request: ContinuedProcessingRequest,
                onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void) async throws {
        onEvent(.launched(ContinuedProcessingGrant(
            requestID: request.requestID, movementID: request.movementID, lease: request.lease)))
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {}

    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? {
        success ? .success : .failed
    }

    func cancel(requestID: UUID) {}
}

enum GoFlyUITestRoutePlanOutcome: String, Sendable {
    case success
    case planningFailed
    case reorderedSuccess
}

struct GoFlyUITestPlaceSearch: PlaceSearching {
    private let places = GoFlyUITestOverrides.fixturePlaces

    func search(query: String) async throws -> [MapPlace] {
        try Task.checkCancellation()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let matching = places.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.address?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
        return matching.isEmpty ? places : matching
    }
}

struct GoFlyUITestPlaceResolver: PlaceResolving {
    func resolve(at coordinate: GeoCoordinate) async throws -> MapPlace? {
        try Task.checkCancellation()
        if abs(coordinate.latitude - 25.04776) < 0.0001,
           abs(coordinate.longitude - 121.51706) < 0.0001 {
            return GoFlyUITestPlaceSearch().searchResult(named: "台北車站")
        }
        return MapPlace(id: .coordinate(coordinate), title: coordinate.displayText,
                        coordinate: coordinate, address: "fixture")
    }
}

extension GoFlyUITestPlaceSearch {
    fileprivate func searchResult(named title: String) -> MapPlace? {
        // Reuse the exact fixed record used by text search and the route picker.
        let coordinate = title == "台北車站"
            ? GeoCoordinate(latitude: 25.04776, longitude: 121.51706)!
            : GeoCoordinate(latitude: 25.03752, longitude: 121.56370)!
        return places.first { $0.coordinate == coordinate }
    }
}

struct GoFlyUITestRoutePlanner: RoutePlanning {
    let outcome: GoFlyUITestRoutePlanOutcome

    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        try Task.checkCancellation()
        if outcome == .planningFailed { throw RouteExecutionFailure.planningFailed }
        let midpoint = GeoCoordinate(latitude: (from.latitude + to.latitude) / 2,
                                     longitude: (from.longitude + to.longitude) / 2)!
        return [from, midpoint, to]
    }
}
#else
enum GoFlyUITestOverrides {
    static func value(_ flag: String) -> String? { nil }
    static func contains(_ flag: String) -> Bool { false }
    static var frame: String? { nil }
    static var isFrameMode: Bool { false }
    static func namespace(_ flag: String, under root: URL, folder: String) -> URL? { nil }
    static func preferencesDefaults() -> UserDefaults? { nil }
    static func tunnelProbe() -> (any TunnelProbing)? { nil }
}
#endif
