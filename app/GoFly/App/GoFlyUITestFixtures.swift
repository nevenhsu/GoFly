#if DEBUG && targetEnvironment(simulator)
import Foundation
import GoFlyCore

/// UI fault injection only: it creates an uncertain command state without
/// claiming a successful device write, GPS fix, or recipient-app observation.
struct UnconfirmedPointUITestService: DeviceService {
    private let unavailableDevice = NativeDeviceService()

    func prepare() async throws { try await unavailableDevice.prepare() }
    func clearLocation() async throws { try await unavailableDevice.clearLocation() }
    func resetClientConnection() async throws { try await unavailableDevice.resetClientConnection() }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        return .unconfirmed(.operationTimedOut)
    }
}

/// A deterministic planning failure; it neither supplies a path nor calls native code.
struct DelayedFailureRouteUITestPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        try await Task.sleep(for: .seconds(5))
        try Task.checkCancellation()
        throw RouteExecutionFailure.planningFailed
    }
}
/// Initial editable test data only; this does not create a task or device outcome.
@MainActor
func initialRouteUITestDraft() -> RouteDraft? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let flag = arguments.firstIndex(of: "-gofly-ui-route-draft-count"),
          arguments.indices.contains(flag + 1), let count = Int(arguments[flag + 1]),
          (0...RouteDraft.maximumNodeCount).contains(count) else { return nil }
    let values: [RouteNodeValue] = (0..<count).map { index in
        if index == 0 { return .current }
        let coordinate = GeoCoordinate(latitude: 25 + Double(index) * 0.002,
                                       longitude: 121.5 + Double(index) * 0.002)!
        return .place(MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate))
    }
    return RouteDraft(values: values)
}
#endif
